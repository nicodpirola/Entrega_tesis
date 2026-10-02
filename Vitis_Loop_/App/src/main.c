// Main perteneciente al nucleo 0

#include "xparameters.h"
#include "xgpio.h"
#include "sleep.h"
#include "xil_io.h"
#include "xiltimer.h"
#include "xil_mmu.h"
#include "ipc.h"
#include "params.h"

#define FX_BASE 0x60000000

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

// Funciones para LVGL y Encoders
static int16_t enc_prev[6] = {0, 0, 0, 0, 0, 0};
static int16_t enc_delta(int n) {
    if (n < 0 || n >= 6) return 0;
    int16_t now = (int16_t)(Xil_In32(0x60000000 + 0x100 + (n)*4) & 0xFFFF);
    int16_t d   = (int16_t)(now - enc_prev[n]);
    enc_prev[n] = now;
    return d;
}

static int enc_button_clicked(int n) {
    static int btn_prev[6] = {0,0,0,0,0,0};
    static int btn_debounce[6] = {0,0,0,0,0,0};
    if (n < 0 || n >= 6) return 0;
    if (btn_debounce[n] > 0) {
        btn_debounce[n]--;
        return 0; 
    }
    int switches = XGpio_DiscreteRead(&GpioPedal, 1);
    int current = ((switches & (1 << (n + 1))) == 0) ? 1 : 0;
    int clicked = 0;
    if (current == 1 && btn_prev[n] == 0) {
        clicked = 1;
        btn_debounce[n] = 40; 
    }
    btn_prev[n] = current;
    return clicked;
}

uint32_t lvgl_time_get(void){
    XTime t;
    XTime_GetTime(&t);
    return (uint32_t)((t * 1000)/ COUNTS_PER_SECOND); 
}
//Corrección color y flush renderizado
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
void WakeUpCore1() {

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
    while(IPC->core1_ready == 0) { // Esperar a que el Núcleo 1 avise por OCM que ya terminó de encender
        usleep(1000);
    }
}

int main() {
    int Status;

    //Deshabilitar cache para la región OCM (0xFFFF0000)
    Xil_SetTlbAttributes(0xFFFF0000, 0x14de2);

    //Init IPC
    IPC->hw_mode = 0;
    IPC->sd_recording = 0;
    IPC->loop_index = 0;
    IPC->loop_length = 0;
    IPC->core1_ready = 0;

    //Init GPIO
    Status = XGpio_Initialize(&GpioPedal, GPIO_SW_DEV_ID);
    if (Status != XST_SUCCESS) {
        return XST_FAILURE;
    }
    XGpio_SetDataDirection(&GpioPedal, 1, 0xFFFFFFFF);

    //Init Pantalla
    if (ili9341_init() != 0) return XST_FAILURE;

    //Despertar nucleo 1
    WakeUpCore1();

    //Init LVGL y UI
    lv_init();
    lv_tick_set_cb(lvgl_time_get);

    lv_display_t * disp = lv_display_create(240, 320); //resolución (vertical)
    lv_display_set_flush_cb(disp, my_flush_cb);
    lv_display_set_rotation(disp, LV_DISPLAY_ROTATION_270); //se cambia a orientación horizontal

    static uint8_t buf1[240 * 10 * 2] __attribute__((aligned(32))); 
    lv_display_set_buffers(disp, buf1, NULL, sizeof(buf1), LV_DISPLAY_RENDER_MODE_PARTIAL);

    ui_init();

    //Init Synth
    params_master_enable(1);
    params_load_wavetables();
    params_set_mode(1, 0, 0); // Arranca en modo Synth + Dry (Coincide con UI)

    int switches_init = XGpio_DiscreteRead(&GpioPedal, 1);
    int last_pedal = ((switches_init & 0x01) == 0) ? PRESIONADO : SOLTADO;
    
    static uint32_t pedal_debounce_time = 0;
    
    // Control grabado SD (SW1 en IO37 / Bit 7)
    static int sw1_prev = 0;
    static uint32_t sw1_debounce_time = 0;

    while (1) {
        uint32_t now = lvgl_time_get();

        // Lectura botones (0 = presionado, 1 = suelto)
        int switches = XGpio_DiscreteRead(&GpioPedal, 1);
        
        int pedal = ((switches & 0x01) == 0) ? PRESIONADO : SOLTADO;
        int sw1_raw = ((switches & (1 << 7)) == 0) ? 1 : 0;

        // Maquina de estados del pedal con retencion (IPC)
        if (pedal != last_pedal && (now - pedal_debounce_time > 200)) { 
            pedal_debounce_time = now;
            
            if (pedal == PRESIONADO) {
                if (IPC->hw_mode == 0) {
                    IPC->hw_mode = 1; // record
                } else if (IPC->hw_mode == 2) {
                    IPC->hw_mode = 3; // overdub
                }
            } else {
                if (IPC->hw_mode == 1 || IPC->hw_mode == 3) {
                    IPC->hw_mode = 2; // play
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
            IPC->hw_mode = 0;
            IPC->loop_length = 0;
            IPC->loop_index = 0;
        }
        loop_stop_prev = loop_stop_raw;

        ui_handle_presets(switches, now); // perfiles de efectos
        ui_update_status(IPC->hw_mode, (IPC->sd_recording == 1)); // estado loop y SD
        ui_update_progress(IPC->loop_index, IPC->loop_length); // progreso del loop

        // lectura encoders
        int e0_d = enc_delta(0);
        int e1_d = enc_delta(1);
        int e2_d = enc_delta(2);
        int e3_d = enc_delta(3);
        int e4_d = enc_delta(4); 
        ui_handle_encoders(e0_d, e1_d, e2_d, e3_d, e4_d);

        lv_timer_handler();
        usleep(5000);
    }
    return XST_SUCCESS;
}