// Main perteneciente al nucleo 0

#include "xparameters.h"
#include "xgpio.h"
#include "sleep.h"
#include "xil_io.h"
#include "xiltimer.h"
#include "xil_mmu.h"
#include "xil_printf.h"
#include "ipc.h"
#include "params.h"

// LVGL & UI
#include "ili9341.h"
#include "lvgl/lvgl.h"
#include "lvgl/include/lvgl/core/lv_init.h"
#include "lvgl/include/lvgl/core/lv_timer.h"
#include "lvgl/include/lvgl/display/lv_display.h"
#include "lvgl/include/lvgl/tick/lv_tick.h"
#include "ui.h"

#define GPIO_SW_DEV_ID      XPAR_XGPIO_1_BASEADDR

#define PRESIONADO          1
#define SOLTADO             0

XGpio GpioPedal;    
static int gpio_ready = 0;

// Funciones para LVGL y Encoders
static int16_t enc_prev[6] = {0, 0, 0, 0, 0, 0};

static void encoders_init(void) {
    for (int n = 0; n < 6; n++) {
        enc_prev[n] = (int16_t)(Xil_In32(FX_BASE + FX_REG_ENCODER(n)) & 0xFFFFu);
    }
}

static int16_t enc_delta(int n) {
    if (n < 0 || n >= 6) return 0;
    int16_t now = (int16_t)(Xil_In32(FX_BASE + FX_REG_ENCODER(n)) & 0xFFFFu);
    int16_t d   = (int16_t)(now - enc_prev[n]);
    if (d > -2 && d < 2) return 0;
    enc_prev[n] = now;
    return (d / 2);
}

static int enc_button_clicked(int n, int switches) {
    static int btn_prev[6] = {0,0,0,0,0,0};
    static int btn_debounce[6] = {0,0,0,0,0,0};
    if (n < 0 || n >= 6) return 0;
    if (!gpio_ready) return 0;
    if (btn_debounce[n] > 0) {
        btn_debounce[n]--;
        return 0; 
    }
    int current = ((switches & (1 << (n + 1))) == 0) ? 1 : 0;
    int clicked = 0;
    if (current == 1 && btn_prev[n] == 0) {
        clicked = 1;
        btn_debounce[n] = 40; 
    }
    btn_prev[n] = current;
    return clicked;
}

// Diagnostico de stack: se pinta la zona libre al arrancar y se mide
// cuanto se llego a usar. Se informa por UART cada ~5 s.
#define STACK_PAINT 0xA5A5A5A5u
extern u8 _stack_end;   // limite inferior del stack (lscript.ld)
extern u8 _stack;       // tope del stack (lscript.ld)

static void stack_paint(void) {
    volatile u32 marker = 0;
    u32 *p   = (u32 *)&_stack_end;
    u32 *top = (u32 *)((((UINTPTR)&marker) - 512u) & ~3u);
    while (p < top) *p++ = STACK_PAINT;
}

static u32 stack_max_used(void) {
    u32 *p = (u32 *)&_stack_end;
    while (((u8 *)p < &_stack) && (*p == STACK_PAINT)) p++;
    return (u32)(&_stack - (u8 *)p);
}

uint32_t lvgl_time_get(void) {
    static uint32_t sw_ms = 0;
    XTime t = 0;
    XTime_GetTime(&t);
    uint32_t hw_ms = (uint32_t)((t * 1000ULL) / COUNTS_PER_SECOND);
    if (hw_ms > sw_ms) {
        sw_ms = hw_ms;
    } else {
        sw_ms += 5; // Fallback para garantizar que el tiempo NUNCA se congele en baremetal
    }
    return sw_ms;
}
//CorrecciÃ³n color y flush renderizado
void my_flush_cb(lv_display_t * display, const lv_area_t * area, uint8_t * px_map) { 
    uint32_t px_count = (area->x2 - area->x1 + 1) * (area->y2 - area->y1 + 1);
    uint16_t * buf16 = (uint16_t *)px_map;
    for(uint32_t i = 0; i < px_count; i++) {
        buf16[i] = (buf16[i] << 8) | (buf16[i] >> 8);
    }
    ili9341_flush_region(area->x1, area->y1, area->x2, area->y2, px_map);
    lv_display_flush_ready(display);
}

// DESPERTADOR DEL NÚCLEO 1 
#define A9_CPU1_START_ADDR 0xFFFFFFF0
static int WakeUpCore1(void) {
    xil_printf("[BOOT] Despertando Core 1...\r\n");

    // PARCHE QSPI: 
    // El FSBL deja al nucleo 1 en un bucle en 0xFFFFFF00
    // Sobrescribimos ese bucle con un salto directo a 0x10000000
    // 0xE51FF004 = 'ldr pc, [pc, #-4]' (Carga el PC con el valor que esta en 0xFFFFFF04)
    Xil_Out32(0xFFFFFF00, 0xE51FF004); 
    Xil_Out32(0xFFFFFF04, 0x10000000); 

    // Mantenemos el buzon original para cuando arrancamos por JTAG
    Xil_Out32(A9_CPU1_START_ADDR, 0x10000000);  
    dmb();
    __asm__("sev"); // Instrucción en ensamblador SEV (Send Event)
    
    uint32_t wait_ms = 0;
    while(IPC->core1_ready == 0 && wait_ms < 3000) {
        usleep(1000);
        wait_ms++;
    }
    xil_printf("[BOOT] Core 1 status: %s (IPC->core1_ready=%u, esperó %u ms)\r\n",
               (IPC->core1_ready != 0) ? "LISTO" : "TIMEOUT",
               (unsigned int)IPC->core1_ready, (unsigned int)wait_ms);
    return IPC->core1_ready != 0;
}

int main() {
    int Status;

    stack_paint();

    // Deshabilitar cache para la región OCM (0xFFFF0000)
    Xil_SetTlbAttributes(0xFFFF0000, 0x14de2);

    // Init IPC
    IPC->hw_mode = 0;
    IPC->sd_recording = 0;
    IPC->loop_index = 0;
    IPC->loop_length = 0;
    IPC->core1_ready = 0;
    IPC->preset_cmd = 0;
    IPC->preset_status = 0;

    // Init GPIO
    Status = XGpio_Initialize(&GpioPedal, GPIO_SW_DEV_ID);
    if (Status == XST_SUCCESS) {
        XGpio_SetDataDirection(&GpioPedal, 1, 0xFFFFFFFF);
        gpio_ready = 1;
    }
    xil_printf("[BOOT] GPIO listo=%d (Status=%d)\r\n", gpio_ready, Status);

    // Init Pantalla ILI9341
    if (ili9341_init() != 0) return XST_FAILURE;

    // Despertar Núcleo 1 ANTES de inicializar LVGL (orden probado de Entrega_Tesis)
    WakeUpCore1();

    // Init LVGL y Display
    lv_init();
    lv_tick_set_cb(lvgl_time_get);

    lv_display_t * disp = lv_display_create(ILI9341_WIDTH, ILI9341_HEIGHT);
    lv_display_set_color_format(disp, LV_COLOR_FORMAT_RGB565);
    lv_display_set_flush_cb(disp, my_flush_cb);

    static uint8_t buf1[ILI9341_WIDTH * 10 * 2] __attribute__((aligned(32)));
    lv_display_set_buffers(disp, buf1, NULL, sizeof(buf1), LV_DISPLAY_RENDER_MODE_PARTIAL);

    u32 core_id = Xil_In32(FX_BASE + FX_REG_CORE_ID);
    u32 core_version = Xil_In32(FX_BASE + FX_REG_CORE_VERSION);
    xil_printf("FX core: ID=0x%08x VERSION=0x%08x\r\n",
               (unsigned int)core_id, (unsigned int)core_version);

    xil_printf("[BOOT] Creando UI...\r\n");
    fx_od_init();
    ui_init();

    // Hardware params y encoders
    params_master_enable(1);
    params_load_wavetables();
    params_set_mode(0, 1, 0);
    encoders_init();

    u32 last_diag_sequence = IPC->diag_sequence;

    int switches_init = gpio_ready ? XGpio_DiscreteRead(&GpioPedal, 1) : 0xFFFFFFFF;
    int last_pedal = ((switches_init & 0x01) != 0) ? PRESIONADO : SOLTADO;
    xil_printf("[BOOT] Switches iniciales: 0x%04x (pedal=%s)\r\n",
               (unsigned int)switches_init, (last_pedal == PRESIONADO) ? "PRESIONADO" : "SOLTADO");
    
    static uint32_t pedal_debounce_time = 0;
    uint32_t record_command_start_ms = 0;
    uint32_t record_command_elapsed_ms = 0;
    
    // Control grabado SD (SW1 en IO37 / Bit 7)
    static int sw1_prev = 0;
    static uint32_t sw1_debounce_time = 0;

    xil_printf("[BOOT] ENTRANDO AL BUCLE PRINCIPAL (while 1)\r\n");

    while (1) {
        uint32_t now = lvgl_time_get();

        // Core 1 publica una captura al cerrar REC u OVERDUB. Core 0 es el
        // unico que la imprime para no mezclar mensajes de ambos nucleos.
        u32 diag_sequence = IPC->diag_sequence;
        if (diag_sequence != last_diag_sequence) {
            __asm__ volatile("dmb sy" ::: "memory");
            if (IPC->diag_event == 1) {
                xil_printf("LOOPER,REC,cmdMs=%u,us=%u,words=%u,rate=%u,seamL=%u,seamR=%u,sat=%u,same2=%u,compared=%u,rxErr=%u,txErr=%u,startErr=%u,startRx=%u,startTx=%u,resync=%u\r\n",
                           (unsigned int)record_command_elapsed_ms,
                           (unsigned int)IPC->diag_record_us,
                           (unsigned int)IPC->diag_recorded_words,
                           (unsigned int)IPC->diag_stream_word_rate,
                           (unsigned int)IPC->diag_seam_left,
                           (unsigned int)IPC->diag_seam_right,
                           (unsigned int)IPC->diag_record_saturated,
                           (unsigned int)IPC->diag_record_same_prev2,
                           (unsigned int)IPC->diag_record_compared,
                           (unsigned int)IPC->diag_dma_rx_errors,
                           (unsigned int)IPC->diag_dma_tx_errors,
                           (unsigned int)IPC->diag_transfer_errors,
                           (unsigned int)IPC->diag_start_rx_errors,
                           (unsigned int)IPC->diag_start_tx_errors,
                           (unsigned int)IPC->diag_resyncs);
            } else if (IPC->diag_event == 2) {
                xil_printf("LOOPER,OD,words=%u,changed=%u,meanDelta=%u,maxDelta=%u,large=%u,start=%u,end=%u,maxAt=%u,sat=%u,rxErr=%u,txErr=%u,startErr=%u,startRx=%u,startTx=%u,resync=%u\r\n",
                           (unsigned int)IPC->diag_overdub_words,
                           (unsigned int)IPC->diag_overdub_changed,
                           (unsigned int)IPC->diag_overdub_mean_delta,
                           (unsigned int)IPC->diag_overdub_max_delta,
                           (unsigned int)IPC->diag_overdub_large_delta,
                           (unsigned int)IPC->diag_overdub_start_index,
                           (unsigned int)IPC->diag_overdub_end_index,
                           (unsigned int)IPC->diag_overdub_max_index,
                           (unsigned int)IPC->diag_overdub_saturated,
                           (unsigned int)IPC->diag_dma_rx_errors,
                           (unsigned int)IPC->diag_dma_tx_errors,
                           (unsigned int)IPC->diag_transfer_errors,
                           (unsigned int)IPC->diag_start_rx_errors,
                           (unsigned int)IPC->diag_start_tx_errors,
                           (unsigned int)IPC->diag_resyncs);
            }
            last_diag_sequence = diag_sequence;
        }

        int switches = gpio_ready ? XGpio_DiscreteRead(&GpioPedal, 1) : 0xFFFFFFFF;
        
        int pedal = ((switches & 0x01) != 0) ? PRESIONADO : SOLTADO;
        int sw1_raw = ((switches & (1 << 7)) == 0) ? 1 : 0;

        // Control del loop por pulsaciones.
        if (pedal != last_pedal && (now - pedal_debounce_time > 200)) {
            pedal_debounce_time = now;
            if (pedal == PRESIONADO) {
                if (IPC->hw_mode == 0) {
                    IPC->hw_mode = 1; // primera pulsacion: record
                    record_command_start_ms = now;
                    record_command_elapsed_ms = 0;
                } else if (IPC->hw_mode == 1) {
                    IPC->hw_mode = 2; // segunda pulsacion: play
                    record_command_elapsed_ms = now - record_command_start_ms;
                } else if (IPC->hw_mode == 2) {
                    IPC->hw_mode = 3; // tercera pulsacion: overdub
                } else if (IPC->hw_mode == 3) {
                    IPC->hw_mode = 2; // cuarta pulsacion: play
                }
            }
            last_pedal = pedal;
        }

        // Grabar a SD con SW1 (IO37)
        if (sw1_raw == 1 && sw1_prev == 0 && (now - sw1_debounce_time > 200)) {
            sw1_debounce_time = now;
            if (IPC->sd_recording == 0) {
                IPC->sd_recording = 1;
            } else {
                IPC->sd_recording = 0;
            }
        }
        sw1_prev = sw1_raw;

        // Reset / Parado de loop (Bit 11 / IO33)
        int loop_stop_raw = ((switches & (1 << 11)) == 0) ? 1 : 0;
        static int loop_stop_prev = 0;
        static uint32_t loop_stop_debounce_time = 0;
        if (loop_stop_raw == 1 && loop_stop_prev == 0 && (now - loop_stop_debounce_time > 200)) {
            loop_stop_debounce_time = now;
            IPC->hw_mode = 0;   // Core 1 hace el fade-out y limpia largo/indice
        }
        loop_stop_prev = loop_stop_raw;

        ui_handle_presets(switches, now); // perfiles de efectos
        ui_update_status(IPC->hw_mode, (IPC->sd_recording == 1)); // estado loop y SD
        
        uint32_t progress_length = (IPC->hw_mode == 1) ? LOOP_MAX_SAMPLES : IPC->loop_length;
        ui_update_progress(IPC->loop_index, progress_length); // progreso del loop

        // lectura encoders
        int e0_d = enc_delta(0);
        int e1_d = enc_delta(1);
        int e2_d = enc_delta(2);
        int e3_d = enc_delta(3);
        int e4_d = enc_delta(4);
        int e5_d = enc_delta(5);

        unsigned param_clicked = 0;
        for (int n = 0; n < 4; n++)
            if (enc_button_clicked(n, switches)) param_clicked |= 1u << n;
        int e4_clicked = enc_button_clicked(4, switches);
        int e5_clicked = enc_button_clicked(5, switches);
        int nav_clicked = e4_clicked | e5_clicked;

        ui_handle_buttons(param_clicked);
        ui_handle_encoders(e0_d, e1_d, e2_d, e3_d, e4_d, nav_clicked, e5_d);

        params_service(now);
        lv_timer_handler();

        static uint32_t last_hb = 0;
        static uint32_t loop_cycles = 0;
        loop_cycles++;
        if (loop_cycles == 1 || (now - last_hb >= 1000)) {
            last_hb = now;
            xil_printf("[HB] t=%u ms, loops=%u, sw=0x%04X, c1_rdy=%u\r\n",
                       (unsigned int)now, (unsigned int)loop_cycles,
                       (unsigned int)switches, (unsigned int)IPC->core1_ready);
        }

        static uint32_t stack_report_time = 0;
        if (now - stack_report_time > 5000) {
            stack_report_time = now;
            xil_printf("[STACK] Core0 max usado: %u / %u bytes\r\n",
                       (unsigned int)stack_max_used(),
                       (unsigned int)(&_stack - &_stack_end));
        }

        usleep(5000);
    }
    return XST_SUCCESS;
}
