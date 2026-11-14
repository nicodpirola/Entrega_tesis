#include "ili9341.h"
#include "xspi.h"
#include "xspi_l.h"
#include "xgpiops.h"
#include "sleep.h"
#include "xil_printf.h"

static XSpi    SpiInstance;
static XGpioPs GpioInstance;

// GPIO (DC y RST) 
static inline void gpio_sync(u32 pin, u32 val) {
    XGpioPs_WritePin(&GpioInstance, pin, val);
    // Pequeña barrera para asegurar que la señal EMIO se propaga
    for (volatile int i = 0; i < 200; i++) { }  
}

static inline void dc_cmd(void)  { gpio_sync(ILI9341_DC_PIN, 0); }
static inline void dc_data(void) { gpio_sync(ILI9341_DC_PIN, 1); }
static inline void rst_lo(void)  { gpio_sync(ILI9341_RST_PIN, 0); }
static inline void rst_hi(void)  { gpio_sync(ILI9341_RST_PIN, 1); }

void ili9341_test_gpio(void) {
    while(1) {
        gpio_sync(ILI9341_DC_PIN, 0);
        gpio_sync(ILI9341_RST_PIN, 0);
        usleep(500000);
        
        gpio_sync(ILI9341_DC_PIN, 1);
        gpio_sync(ILI9341_RST_PIN, 1);
        usleep(500000);
    }
}

// SPI (AXI Quad SPI) Control de Chip Select
static inline void cs_low(void) {
    // Escribir 0xFFFFFFFE selecciona el Slave 0 físicamente
    XSpi_WriteReg(SpiInstance.BaseAddr, XSP_SSR_OFFSET, ~0x01);
}

static inline void cs_high(void) {
    // Escribir 0xFFFFFFFF deselecciona todos los Slaves
    XSpi_WriteReg(SpiInstance.BaseAddr, XSP_SSR_OFFSET, 0xFFFFFFFF);
}

// ── Función core de envío de datos (Estilo Repositorio) ─────

#define SPI_STALL_LIMIT 1000000u

static void spi_send(const u8 *data, u32 len) {
    u32 sent = 0;
    u32 received = 0;
    u32 stalled = 0;
    u32 base = SpiInstance.BaseAddr;

    while (sent < len || received < len) {
        u32 sent_before = sent;
        u32 received_before = received;

        while (received < sent && !(XSpi_ReadReg(base, XSP_SR_OFFSET) & XSP_SR_RX_EMPTY_MASK)) {
            XSpi_ReadReg(base, XSP_DRR_OFFSET);
            received++;
        }

        while (sent < len &&
               !(XSpi_ReadReg(base, XSP_SR_OFFSET) & XSP_SR_TX_FULL_MASK) &&
               (sent - received < 128)) {
            XSpi_WriteReg(base, XSP_DTR_OFFSET, data[sent]);
            sent++;
        }

        if (sent != sent_before || received != received_before) {
            stalled = 0;
        } else if (++stalled >= SPI_STALL_LIMIT) {
            u32 control = XSpi_ReadReg(base, XSP_CR_OFFSET);
            control |= XSP_CR_TRANS_INHIBIT_MASK |
                       XSP_CR_TXFIFO_RESET_MASK |
                       XSP_CR_RXFIFO_RESET_MASK;
            XSpi_WriteReg(base, XSP_CR_OFFSET, control);
            control &= ~XSP_CR_TRANS_INHIBIT_MASK;
            XSpi_WriteReg(base, XSP_CR_OFFSET, control);
            xil_printf("[ILI9341] SPI timeout\r\n");
            return;
        }
    }
}

// ILI9341
static void ili9341_cmd(u8 cmd, const u8 *params, u32 nparams) {
    /* Keep CS asserted from the command byte through all its parameters.
       Some ILI9341 modules terminate the command when CS rises. */
    cs_low();
    dc_cmd();
    spi_send(&cmd, 1);

    if (nparams > 0) {
        dc_data();
        spi_send(params, nparams);
    }

    cs_high();
}

//Window setup para writes a GRAM 
static void ili9341_begin_write(u16 x0, u16 y0, u16 x1, u16 y1) {
    u8 cmd;
    u8 buf[4];

    /* CASET, PASET, RAMWR and pixel data are one continuous transaction. */
    cs_low();

    dc_cmd();
    cmd = ILI9341_CASET;
    spi_send(&cmd, 1);
    dc_data();
    buf[0] = x0 >> 8; buf[1] = x0 & 0xFF;
    buf[2] = x1 >> 8; buf[3] = x1 & 0xFF;
    spi_send(buf, 4);

    dc_cmd();
    cmd = ILI9341_PASET;
    spi_send(&cmd, 1);
    dc_data();
    buf[0] = y0 >> 8; buf[1] = y0 & 0xFF;
    buf[2] = y1 >> 8; buf[3] = y1 & 0xFF;
    spi_send(buf, 4);

    dc_cmd();
    cmd = ILI9341_RAMWR;
    spi_send(&cmd, 1);
    dc_data();
}

// Init 
int ili9341_init(void) {
    int Status;
    XGpioPs_Config *GpioCfg;
    XSpi_Config    *SpiCfg;

    // 1. Init GPIO
    GpioCfg = XGpioPs_LookupConfig(ILI9341_GPIO_DEVICE_ID);
    if (!GpioCfg) return XST_FAILURE;
    Status = XGpioPs_CfgInitialize(&GpioInstance, GpioCfg, GpioCfg->BaseAddr);
    if (Status != XST_SUCCESS) return XST_FAILURE;

    XGpioPs_SetDirectionPin(&GpioInstance, ILI9341_DC_PIN, 1);
    XGpioPs_SetOutputEnablePin(&GpioInstance, ILI9341_DC_PIN, 1);
    XGpioPs_SetDirectionPin(&GpioInstance, ILI9341_RST_PIN, 1);
    XGpioPs_SetOutputEnablePin(&GpioInstance, ILI9341_RST_PIN, 1);

    // 2. Init SPI
    SpiCfg = XSpi_LookupConfig(ILI9341_SPI_BASEADDR);
    if (!SpiCfg) return XST_FAILURE;
    Status = XSpi_CfgInitialize(&SpiInstance, SpiCfg, SpiCfg->BaseAddress);
    if (Status != XST_SUCCESS) return XST_FAILURE;

    Status = XSpi_SetOptions(&SpiInstance, XSP_MASTER_OPTION | XSP_MANUAL_SSELECT_OPTION);
    if (Status != XST_SUCCESS) return XST_FAILURE;

    XSpi_Start(&SpiInstance);
    XSpi_IntrGlobalDisable(&SpiInstance);

    // --- LA MODIFICACIÓN CLAVE DEL REPOSITORIO ---
    // Cancelar inhibición del transmisor. Permite que la transferencia
    // comience tan pronto como se escriba en la FIFO de DTR.
    u32 ControlReg = XSpi_ReadReg(SpiInstance.BaseAddr, XSP_CR_OFFSET);
    ControlReg &= ~XSP_CR_TRANS_INHIBIT_MASK;
    XSpi_WriteReg(SpiInstance.BaseAddr, XSP_CR_OFFSET, ControlReg);

    // CS idle alto
    cs_high();

    xil_printf("[ILI9341] AXI Quad SPI Low-Level Driver Ready\r\n");

    // Reset HW
    rst_hi(); usleep(10000);
    rst_lo(); usleep(20000);
    rst_hi(); usleep(150000);

    // Secuencia de inicialización ILI9341
    ili9341_cmd(ILI9341_SWRESET, NULL, 0); usleep(120000);
    ili9341_cmd(ILI9341_SLPOUT,  NULL, 0); usleep(120000);

    ili9341_cmd(0xCF, (u8[]){0x00, 0xC1, 0x30}, 3);
    ili9341_cmd(0xED, (u8[]){0x64, 0x03, 0x12, 0x81}, 4);
    ili9341_cmd(0xE8, (u8[]){0x85, 0x00, 0x78}, 3);
    ili9341_cmd(0xCB, (u8[]){0x39, 0x2C, 0x00, 0x34, 0x02}, 5);
    ili9341_cmd(0xF7, (u8[]){0x20}, 1);
    ili9341_cmd(0xEA, (u8[]){0x00, 0x00}, 2);
    ili9341_cmd(0xC0, (u8[]){0x23}, 1);
    ili9341_cmd(0xC1, (u8[]){0x10}, 1);
    ili9341_cmd(0xC5, (u8[]){0x3E, 0x28}, 2);
    ili9341_cmd(0xC7, (u8[]){0x86}, 1);
    
    // MADCTL: landscape scan direction plus BGR color order.
    ili9341_cmd(ILI9341_MADCTL, (u8[]){ILI9341_MADCTL_VALUE}, 1);
    
    ili9341_cmd(ILI9341_PIXFMT, (u8[]){0x55}, 1);
    ili9341_cmd(0xB1, (u8[]){0x00, 0x18}, 2);
    ili9341_cmd(ILI9341_DFUNCTR, (u8[]){0x08, 0x82, 0x27}, 3);
    ili9341_cmd(0xF2, (u8[]){0x00}, 1);
    ili9341_cmd(0x26, (u8[]){0x01}, 1);
    ili9341_cmd(0xE0, (u8[]){0x0F,0x31,0x2B,0x0C,0x0E,0x08,0x4E,0xF1,0x37,0x07,0x10,0x03,0x0E,0x09,0x00}, 15);
    ili9341_cmd(0xE1, (u8[]){0x00,0x0E,0x14,0x03,0x11,0x07,0x31,0xC1,0x48,0x08,0x0F,0x0C,0x31,0x36,0x0F}, 15);
    ili9341_cmd(0x13, NULL, 0); usleep(10000);
    ili9341_cmd(ILI9341_DISPON, NULL, 0); usleep(10000);
    
    return XST_SUCCESS;
}

// ── Funciones de dibujado ───────────────────────────────────
static u8 fill_line[ILI9341_WIDTH * 2];

void ili9341_fill_rect(u16 x, u16 y, u16 w, u16 h, u16 color) {
    if (x >= ILI9341_WIDTH || y >= ILI9341_HEIGHT || w == 0 || h == 0) return;
    if (x + w > ILI9341_WIDTH)  w = ILI9341_WIDTH  - x;
    if (y + h > ILI9341_HEIGHT) h = ILI9341_HEIGHT - y;

    const u32 row_bytes = (u32)w * 2u;
    const u8 color_hi = (u8)(color >> 8);
    const u8 color_lo = (u8)(color & 0xFF);

    for (u32 i = 0; i < w; i++) {
        fill_line[i * 2]     = color_hi;
        fill_line[i * 2 + 1] = color_lo;
    }

    ili9341_begin_write(x, y, x + w - 1, y + h - 1);
    for (u32 row = 0; row < h; row++) {
        spi_send(fill_line, row_bytes);
    }
    cs_high();
}

void ili9341_fill_screen(u16 color) {
    ili9341_fill_rect(0, 0, ILI9341_WIDTH, ILI9341_HEIGHT, color);
}

void ili9341_test_pattern(void) {
    const u16 half_w = ILI9341_WIDTH / 2;
    const u16 half_h = ILI9341_HEIGHT / 2;

    ili9341_fill_rect(0,      0,      half_w, half_h, COLOR_RED);
    ili9341_fill_rect(half_w, 0,      half_w, half_h, COLOR_GREEN);
    ili9341_fill_rect(0,      half_h, half_w, half_h, COLOR_BLUE);
    ili9341_fill_rect(half_w, half_h, half_w, half_h, COLOR_WHITE);
}

void ili9341_draw_pixel(u16 x, u16 y, u16 color) {
    if (x >= ILI9341_WIDTH || y >= ILI9341_HEIGHT) return;
    u8 px[2] = { color >> 8, color & 0xFF };
    ili9341_begin_write(x, y, x, y);
    spi_send(px, 2);
    cs_high();
}

void ili9341_flush_region(u16 x1, u16 y1, u16 x2, u16 y2, const u8 *data){
    uint32_t size = (x2 - x1 + 1) * (y2 - y1 + 1) * 2;
    ili9341_begin_write(x1, y1, x2, y2);

    spi_send(data, size);
    cs_high();
}