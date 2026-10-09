#ifndef UI_H
#define UI_H

#include "lvgl/lvgl.h"
#include <stdint.h>

#define MAX_FX_PARAMS 12
#define PARAMS_PER_PAGE 4
#define MAX_EFFECTS   10

typedef struct {
    const char * name;
    int min_val;
    int max_val;
    int current_val;
} fx_param_t;

typedef struct {
    const char * name;
    int enabled;              // 1 = ON, 0 = BYPASS
    int param_count;          // Total de parametros del modulo (ej. 12 para Synth)
    int current_page;         // Pagina activa (0..2 para Synth, 0 para los demas)
    fx_param_t params[MAX_FX_PARAMS];
} effect_module_t;

extern effect_module_t effects_list[MAX_EFFECTS];
extern const int num_effects;

// API de Inicializacion
void ui_init(void);
void ui_presets_init(void);

// API de Actualizacion del Sistema
void ui_update_status(int hw_mode, int sd_recording);
void ui_update_progress(uint32_t loop_index, uint32_t loop_length);

// API de Manejo de Hardware (Encoders y botones)
void ui_handle_encoders(int e0_d, int e1_d, int e2_d, int e3_d, int e4_d, int e4_click, int e5_d);
void ui_handle_buttons(unsigned param_clicked);

// API de Presets
void ui_save_preset(int slot);
void ui_load_preset(int slot);
void ui_handle_presets(int switches, uint32_t now);

#endif
