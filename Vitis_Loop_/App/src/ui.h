#ifndef UI_H
#define UI_H

#include "lvgl/lvgl.h"

// API de Inicializacion
void ui_init(void);
void ui_presets_init(void);

// API de Actualizacion del Sistema (Llamados desde el while de main.c)
// hw_mode: 0=IDLE, 1=RECORD, 2=PLAY, 3=OVERDUB
void ui_update_status(int hw_mode, int sd_recording);
void ui_update_progress(uint32_t loop_index, uint32_t loop_length);

// API de Manejo de Hardware (Encoders)
void ui_handle_encoders(int e1_delta, int e2_delta, int e3_delta, int e4_delta, int e5_delta);

// API de Presets
void ui_save_preset(int slot);
void ui_load_preset(int slot);
void ui_handle_presets(int switches, uint32_t now);

// --- ESTRUCTURAS DE DATOS DE EFECTOS ---
#define MAX_FX_PARAMS 4
#define MAX_EFFECTS 6

typedef struct {
    const char * name;
    int min_val;
    int max_val;
    int current_val;
} fx_param_t;

typedef struct {
    const char * name;
    int param_count;
    fx_param_t params[MAX_FX_PARAMS];
} effect_module_t;

// Exponemos el arreglo para que el main.c pueda aplicar el DSP de audio leyendo estos valores en tiempo real
extern effect_module_t effects_list[MAX_EFFECTS];
extern const int num_effects;

#endif