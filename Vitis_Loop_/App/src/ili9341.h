#ifndef ILI9341_H
#define ILI9341_H

#include "xil_types.h"
#include "xparameters.h"

// ── Hardware ────────────────────────────────────────────────
#define ILI9341_SPI_BASEADDR    XPAR_AXI_QUAD_SPI_0_BASEADDR
#define ILI9341_GPIO_DEVICE_ID  0

// EMIO GPIO pins (Intercambiados para probar si los cables están invertidos)
#define ILI9341_DC_PIN          54   // Era 55, ahora prueba con EMIO[0] (Pin IO3)
#define ILI9341_RST_PIN         55   // Era 54, ahora prueba con EMIO[1] (Pin IO2)

// ── Dimensiones ─────────────────────────────────────────────
#define ILI9341_WIDTH           320
#define ILI9341_HEIGHT          240

// ── Colores RGB565 ──────────────────────────────────────────
#define COLOR_BLACK             0x0000
#define COLOR_WHITE             0xFFFF
#define COLOR_RED               0xF800
#define COLOR_GREEN             0x07E0
#define COLOR_BLUE              0x001F
#define COLOR_YELLOW            0xFFE0
#define COLOR_CYAN              0x07FF
#define COLOR_MAGENTA           0xF81F
#define RGB565(r,g,b) (((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3))

// ── Comandos ILI9341 ────────────────────────────────────────
#define ILI9341_SWRESET         0x01
#define ILI9341_SLPOUT          0x11
#define ILI9341_DISPON          0x29
#define ILI9341_CASET           0x2A
#define ILI9341_PASET           0x2B
#define ILI9341_RAMWR           0x2C
#define ILI9341_MADCTL          0x36
#define ILI9341_PIXFMT          0x3A
#define ILI9341_DFUNCTR         0xB6

// ── API ─────────────────────────────────────────────────────
int  ili9341_init(void);
void ili9341_test_gpio(void);
void ili9341_fill_screen(u16 color);
void ili9341_fill_rect(u16 x, u16 y, u16 w, u16 h, u16 color);
void ili9341_draw_pixel(u16 x, u16 y, u16 color);
void ili9341_flush_region(u16 x1, u16 y1, u16 x2, u16 y2, const u8 *data);



#endif