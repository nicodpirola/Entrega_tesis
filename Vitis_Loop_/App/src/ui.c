#include "ui.h"
#include <stdio.h>
#include "params.h"
#include "xil_io.h"
#include "ipc.h"

#define FX_BASE 0x60000000

// LVGL objects
static lv_obj_t * header_cont;
static lv_obj_t * label_status;
static lv_obj_t * label_preset_msg;
static uint32_t preset_msg_timeout = 0;
static lv_obj_t * label_sd;
static lv_obj_t * bar_progress;

static lv_obj_t * col_left;
static lv_obj_t * col_right;

static lv_obj_t * fx_items[MAX_EFFECTS];
static lv_obj_t * param_items[MAX_FX_PARAMS];
static lv_obj_t * param_labels[MAX_FX_PARAMS];
static lv_obj_t * param_bars[MAX_FX_PARAMS];

//state
static int selected_fx_idx = 0;

// Presets en memoria local (Slots 0, 1, 2)
static int preset_slots[3][MAX_EFFECTS][MAX_FX_PARAMS];
static int presets_initialized = 0;

//efectos y parámetros iniciales
const int num_effects = 6;
effect_module_t effects_list[MAX_EFFECTS] = {
    {
        .name = "Synth",
        .param_count = 3,
        .params = {
            {"Status (0=OFF)", 0, 1, 1}, // 0:OFF, 1:ON
            {"Dry (0=Muted)", 0, 1, 1}, // 0:Muted (Synth Only), 1:Active (Synth+Dry)
            {"Patch", 0, 3, 0}, // 0:Saw, 1:Minimoog, 2:3 Saws, 3:Sub
            {"-", 0, 0, 0}
        }
    },
    {
        .name = "Delay",
        .param_count = 4,
        .params = {
            {"Status", 0, 1, 0},
            {"Time(ms)", 10, 680, 250},
            {"FB(%)", 0, 90, 35},
            {"Wet(%)", 0, 100, 25}
        }
    },
    {
        .name = "Chorus",
        .param_count = 4,
        .params = {
            {"Status", 0, 1, 0},
            {"Depth(ms)", 0, 20, 2},
            {"Rate(Hz*10)", 1, 50, 4},
            {"Wet(%)", 0, 100, 50}
        }
    },
    {
        .name = "Flanger",
        .param_count = 4,
        .params = {
            {"Status", 0, 1, 0},
            {"Depth(ms)", 0, 10, 2},
            {"Rate(Hz*10)", 1, 50, 4},
            {"FB(%)", 0, 90, 50}
        }
    },
    {
        .name = "Tremolo",
        .param_count = 3,
        .params = {
            {"Status", 0, 1, 0},
            {"Depth(%)", 0, 100, 50},
            {"Rate(Hz*10)", 1, 100, 50},
            {"-", 0, 0, 0}
        }
    },
    {
        .name = "Distorsion",
        .param_count = 4,
        .params = {
            {"Status", 0, 1, 0},
            {"Drive", 1, 20, 5},
            {"Tone(%)", 0, 100, 50},
            {"Level(%)", 0, 100, 20}
        }
    }
};

static void ui_apply_all_params(void) {
    uint32_t fx_en = 0;
    
    // Configurar bitmask de estados
    if (effects_list[0].params[0].current_val) fx_en |= FXB_SYNTH;
    if (effects_list[0].params[1].current_val == 0) fx_en |= FXB_SYNTH_ONLY;
    
    if (effects_list[1].params[0].current_val) fx_en |= FXB_DELAY;
    if (effects_list[2].params[0].current_val) fx_en |= FXB_CHORUS;
    if (effects_list[3].params[0].current_val) fx_en |= FXB_FLANG;
    if (effects_list[4].params[0].current_val) fx_en |= FXB_TREM;
    if (effects_list[5].params[0].current_val) fx_en |= FXB_DIST;
    
    // Mantener siempre prendido filtros escenciales
    fx_en |= FXB_DCB_IN | FXB_DCB_POST | FXB_CHO_LPF | FXB_BLEND | FXB_CAB;
    
    Xil_Out32(FX_BASE + FX_OFF_FX_EN, fx_en);
    
    // Cargar parametros base por defecto y sobreescribir con la pantalla
    params_t p;
    params_init(&p);
    
    // Synth
    int patch = effects_list[0].params[2].current_val;
    if (patch == 0)      { p.syn_w1=WAVE_SAW; p.syn_w2=WAVE_SAW; p.syn_w3=WAVE_SAW; p.syn_r1=0; p.syn_r2=0; p.syn_r3=0; p.syn_o2_cents=0; p.syn_o3_cents=0; }
    else if (patch == 1) { p.syn_w1=WAVE_TRISAW; p.syn_w2=WAVE_SAW; p.syn_w3=WAVE_SQUARE; p.syn_r1=-1; p.syn_r2=-1; p.syn_r3=0; p.syn_o2_cents=-5; p.syn_o3_cents=5; }
    else if (patch == 2) { p.syn_w1=WAVE_SAW; p.syn_w2=WAVE_SAW; p.syn_w3=WAVE_SAW; p.syn_r1=0; p.syn_r2=0; p.syn_r3=0; p.syn_o2_cents=-12; p.syn_o3_cents=12; }
    else                 { p.syn_w1=WAVE_SQUARE; p.syn_w2=WAVE_SQUARE; p.syn_w3=WAVE_SQUARE; p.syn_r1=-2; p.syn_r2=-1; p.syn_r3=0; p.syn_o2_cents=-2; p.syn_o3_cents=2; }
    
    // Delay
    p.dly_time = (float)effects_list[1].params[1].current_val;
    p.dly_fb = (float)effects_list[1].params[2].current_val / 100.0f;
    p.dly_wet = (float)effects_list[1].params[3].current_val / 100.0f;
    
    // Chorus
    p.cho_depth = (float)effects_list[2].params[1].current_val;
    p.cho_rate = (float)effects_list[2].params[2].current_val / 10.0f;
    p.cho_wet = (float)effects_list[2].params[3].current_val / 100.0f;
    
    // Flanger
    p.fl_depth = (float)effects_list[3].params[1].current_val;
    p.fl_rate = (float)effects_list[3].params[2].current_val / 10.0f;
    p.fl_fb = (float)effects_list[3].params[3].current_val / 100.0f;
    p.fl_wet = 0.5f; // Fijo para Flanger tipico
    
    // Tremolo
    p.trem_depth = (float)effects_list[4].params[1].current_val / 100.0f;
    p.trem_rate = (float)effects_list[4].params[2].current_val / 10.0f;
    
    // Distorsion
    p.dist_drive = (float)effects_list[5].params[1].current_val;
    p.dist_tone = (float)effects_list[5].params[2].current_val / 10.0f;
    p.dist_level = (float)effects_list[5].params[3].current_val / 100.0f;
    
    // Enviar a la FPGA
    params_push_to_pl(&p);
    params_push_synth(&p);
}

static void ui_refresh_selection(void) {
    lv_color_t color_bg_idle = lv_color_hex(0x222222);
    lv_color_t color_bg_active = lv_color_hex(0xFFFFFF);

    // refresh lista principal
    for(int i=0; i<num_effects; i++) {
        if (i == selected_fx_idx) {
            lv_obj_set_style_bg_color(fx_items[i], color_bg_active, 0);
            lv_obj_set_style_text_color(fx_items[i], lv_color_hex(0x000000), 0);
            // Obligar a la columna a scrollear para mostrar este elemento
            lv_obj_scroll_to_view(fx_items[i], LV_ANIM_ON);
        } else {
            lv_obj_set_style_bg_color(fx_items[i], color_bg_idle, 0);
            lv_obj_set_style_text_color(fx_items[i], lv_color_hex(0xFFFFFF), 0);
        }
    }
}

static void ui_refresh_param_panel(void) {
    int param_count = effects_list[selected_fx_idx].param_count;
    for(int i=0; i<MAX_FX_PARAMS; i++) {
        if (i < param_count) {
            lv_obj_clear_flag(param_items[i], LV_OBJ_FLAG_HIDDEN);
            char buf[64];
            sprintf(buf, "%s: %d", effects_list[selected_fx_idx].params[i].name, effects_list[selected_fx_idx].params[i].current_val);
            lv_label_set_text(param_labels[i], buf);
            
            lv_bar_set_range(param_bars[i], effects_list[selected_fx_idx].params[i].min_val, effects_list[selected_fx_idx].params[i].max_val);
            lv_bar_set_value(param_bars[i], effects_list[selected_fx_idx].params[i].current_val, LV_ANIM_OFF);
        } else {
            lv_obj_add_flag(param_items[i], LV_OBJ_FLAG_HIDDEN);
        }
    }
}

void ui_presets_init(void) {
    for (int s = 0; s < 3; s++) {
        for (int i = 0; i < MAX_EFFECTS; i++) {
            for (int j = 0; j < MAX_FX_PARAMS; j++) {
                preset_slots[s][i][j] = effects_list[i].params[j].current_val;
            }
        }
    }
    presets_initialized = 1;
}

void ui_save_preset(int slot) {
    if (slot < 0 || slot >= 3) return;
    if (!presets_initialized) ui_presets_init();
    
    // Guardar en RAM local
    for (int i = 0; i < MAX_EFFECTS; i++) {
        for (int j = 0; j < MAX_FX_PARAMS; j++) {
            preset_slots[slot][i][j] = effects_list[i].params[j].current_val;
            IPC->preset_data[i][j] = effects_list[i].params[j].current_val;
        }
    }
    
    // Mostrar feedback en pantalla (centro superior)
    if (label_preset_msg) {
        char buf[32];
        sprintf(buf, "GUARDANDO P%d", slot + 1);
        lv_label_set_text(label_preset_msg, buf);
        lv_obj_set_style_text_color(label_preset_msg, lv_color_hex(0xFFCC00), 0);
        preset_msg_timeout = lv_tick_get() + 2500;
    }
    
    // Mandar a Core 1 para guardar en SD
    IPC->preset_cmd = slot + 1; // 1, 2, 3
}

void ui_load_preset(int slot) {
    if (slot < 0 || slot >= 3) return;
    if (!presets_initialized) ui_presets_init();
    
    for (int i = 0; i < MAX_EFFECTS; i++) {
        for (int j = 0; j < MAX_FX_PARAMS; j++) {
            effects_list[i].params[j].current_val = preset_slots[slot][i][j];
        }
    }
    
    ui_refresh_param_panel();
    ui_refresh_selection();
    ui_apply_all_params();

    // Mostrar feedback en pantalla (centro superior)
    if (label_preset_msg) {
        char buf[32];
        sprintf(buf, "CARGADO P%d", slot + 1);
        lv_label_set_text(label_preset_msg, buf);
        lv_obj_set_style_text_color(label_preset_msg, lv_color_hex(0x00E5FF), 0);
        preset_msg_timeout = lv_tick_get() + 2500;
    }
}

void ui_handle_presets(int switches, uint32_t now) {
    static const int preset_bits[3] = {12, 8, 10};
    static int sw_slot_pressed[3] = {0, 0, 0};
    static uint32_t sw_slot_press_time[3] = {0, 0, 0};
    static int sw_slot_action_saved[3] = {0, 0, 0};

    for (int k = 0; k < 3; k++) {
        int bit = preset_bits[k];
        int raw = ((switches & (1 << bit)) == 0) ? 1 : 0;
        
        if (raw == 1) {
            if (!sw_slot_pressed[k]) {
                sw_slot_pressed[k] = 1;
                sw_slot_press_time[k] = now;
                sw_slot_action_saved[k] = 0;
            } else if (!sw_slot_action_saved[k] && (now - sw_slot_press_time[k] >= 1200)) {
                sw_slot_action_saved[k] = 1;
                ui_save_preset(k);
            }
        } else if (sw_slot_pressed[k]) {
            if (!sw_slot_action_saved[k] && (now - sw_slot_press_time[k] >= 50)) {
                ui_load_preset(k);
            }
            sw_slot_pressed[k] = 0;
        }
    }
}

void ui_init(void) {
    ui_presets_init();

    lv_obj_t * screen = lv_screen_active();
    lv_obj_set_style_bg_color(screen, lv_color_hex(0x000000), 0); // Fondo negro total

    //header
    header_cont = lv_obj_create(screen);
    lv_obj_set_size(header_cont, 320, 36);
    lv_obj_set_pos(header_cont, 0, 0);
    lv_obj_set_style_bg_color(header_cont, lv_color_hex(0x111111), 0);
    lv_obj_set_style_border_width(header_cont, 0, 0);
    lv_obj_set_style_radius(header_cont, 0, 0);
    lv_obj_set_style_pad_all(header_cont, 0, 0);
    
    label_status = lv_label_create(header_cont);
    lv_obj_align(label_status, LV_ALIGN_TOP_LEFT, 5, 2);
    lv_label_set_text(label_status, "IDLE");
    lv_obj_set_style_text_color(label_status, lv_color_hex(0xAAAAAA), 0);

    label_preset_msg = lv_label_create(header_cont);
    lv_obj_align(label_preset_msg, LV_ALIGN_TOP_MID, 0, 2);
    lv_label_set_text(label_preset_msg, "");
    lv_obj_set_style_text_color(label_preset_msg, lv_color_hex(0x00E5FF), 0);
    
    label_sd = lv_label_create(header_cont);
    lv_obj_align(label_sd, LV_ALIGN_TOP_RIGHT, -5, 2);
    lv_label_set_text(label_sd, "SD: LISTA");
    lv_obj_set_style_text_color(label_sd, lv_color_hex(0x555555), 0);
    
    bar_progress = lv_bar_create(header_cont);
    lv_obj_set_size(bar_progress, 310, 10);
    lv_obj_align(bar_progress, LV_ALIGN_BOTTOM_MID, 0, -2);
    lv_bar_set_range(bar_progress, 0, 100);
    lv_bar_set_value(bar_progress, 0, LV_ANIM_OFF);
    lv_obj_set_style_bg_color(bar_progress, lv_color_hex(0x333333), LV_PART_MAIN); // Fondo oscuro
    lv_obj_set_style_bg_color(bar_progress, lv_color_hex(0xFFFFFF), LV_PART_INDICATOR); // Progreso blanco
    
    // colu,mna izquierda (MENU)
    col_left = lv_obj_create(screen);
    lv_obj_set_size(col_left, 110, 204);
    lv_obj_set_pos(col_left, 0, 36);
    lv_obj_set_style_bg_color(col_left, lv_color_hex(0x1A1A1A), 0);
    lv_obj_set_style_border_width(col_left, 0, 0);
    lv_obj_set_style_radius(col_left, 0, 0);
    lv_obj_set_style_pad_all(col_left, 5, 0);
    
    for(int i=0; i<MAX_EFFECTS; i++) {
        fx_items[i] = lv_obj_create(col_left);
        lv_obj_set_size(fx_items[i], 100, 34);
        lv_obj_set_pos(fx_items[i], 0, i * 38);
        lv_obj_set_style_border_width(fx_items[i], 0, 0);
        lv_obj_set_style_radius(fx_items[i], 4, 0);
        lv_obj_set_style_pad_all(fx_items[i], 0, 0);
        
        lv_obj_t * lbl = lv_label_create(fx_items[i]);
        if (i < num_effects) {
            lv_label_set_text(lbl, effects_list[i].name);
        }
        //lv_obj_center(lbl);
        lv_obj_align(lbl, LV_ALIGN_LEFT_MID, 5, 0);
        if (i >= num_effects) {
            lv_obj_add_flag(fx_items[i], LV_OBJ_FLAG_HIDDEN);
        }
    }
    
    // Columna derecha (parámetros)
    col_right = lv_obj_create(screen);
    lv_obj_set_size(col_right, 210, 204);
    lv_obj_set_pos(col_right, 110, 36);
    lv_obj_set_style_bg_color(col_right, lv_color_hex(0x0A0A0A), 0);
    lv_obj_set_style_border_width(col_right, 0, 0);
    lv_obj_set_style_radius(col_right, 0, 0);
    lv_obj_set_style_pad_all(col_right, 5, 0);
    
    for(int i=0; i<MAX_FX_PARAMS; i++) {
        param_items[i] = lv_obj_create(col_right);
        lv_obj_set_size(param_items[i], 200, 36);
        lv_obj_set_pos(param_items[i], 0, i * 40);
        lv_obj_set_style_bg_color(param_items[i], lv_color_hex(0x222222), 0);
        lv_obj_set_style_border_width(param_items[i], 0, 0);
        lv_obj_set_style_radius(param_items[i], 4, 0);
        lv_obj_set_style_pad_all(param_items[i], 0, 0);
        
        param_labels[i] = lv_label_create(param_items[i]);
        lv_obj_align(param_labels[i], LV_ALIGN_TOP_LEFT, 5, 2);
        lv_obj_set_style_text_color(param_labels[i], lv_color_hex(0xFFFFFF), 0);
        
        param_bars[i] = lv_bar_create(param_items[i]);
        lv_obj_set_size(param_bars[i], 190, 8);
        lv_obj_align(param_bars[i], LV_ALIGN_BOTTOM_MID, 0, -4);
        lv_obj_set_style_bg_color(param_bars[i], lv_color_hex(0x444444), LV_PART_MAIN);
        lv_obj_set_style_bg_color(param_bars[i], lv_color_hex(0xFFFFFF), LV_PART_INDICATOR);
    }
    
    ui_refresh_param_panel();
    ui_refresh_selection();
    ui_apply_all_params();
}

void ui_update_status(int hw_mode, int sd_recording) { 
    if (hw_mode == 0) {
        lv_label_set_text(label_status, "BYPASS");
        lv_obj_set_style_text_color(label_status, lv_color_hex(0xAAAAAA), 0);
    } else if (hw_mode == 1) {
        lv_label_set_text(label_status, "RECORDING");
        lv_obj_set_style_text_color(label_status, lv_color_hex(0xFF0000), 0); // Rojo
    } else if (hw_mode == 2) {
        lv_label_set_text(label_status, "PLAYING");
        lv_obj_set_style_text_color(label_status, lv_color_hex(0x00FF00), 0); // Verde
    } else if (hw_mode == 3) {
        lv_label_set_text(label_status, "OVERDUB");
        lv_obj_set_style_text_color(label_status, lv_color_hex(0xFF9900), 0); // Naranja
    }

    if (sd_recording) {
        lv_label_set_text(label_sd, "SD: REC...");
        lv_obj_set_style_text_color(label_sd, lv_color_hex(0xFFFFFF), 0);
    } else {
        lv_label_set_text(label_sd, "SD: LISTA");
        lv_obj_set_style_text_color(label_sd, lv_color_hex(0xFFFFFF), 0);
    }

    if (preset_msg_timeout > 0 && lv_tick_get() >= preset_msg_timeout) {
        if (label_preset_msg) lv_label_set_text(label_preset_msg, "");
        preset_msg_timeout = 0;
    }
}

void ui_update_progress(uint32_t loop_index, uint32_t loop_length) {
    if (loop_length > 0) {
        // Calcular porcentaje
        uint32_t pct = (loop_index * 100) / loop_length;
        if (pct > 100) pct = 100;
        lv_bar_set_value(bar_progress, pct, LV_ANIM_OFF);
    } else {
        lv_bar_set_value(bar_progress, 0, LV_ANIM_OFF);
    }
}

void ui_handle_encoders(int e1_delta, int e2_delta, int e3_delta, int e4_delta, int e5_delta) {
    if (e5_delta != 0) {
        selected_fx_idx += e5_delta;
        if (selected_fx_idx < 0) selected_fx_idx = 0;
        if (selected_fx_idx >= num_effects) selected_fx_idx = num_effects - 1;
        ui_refresh_param_panel();
        ui_refresh_selection();
    }
    
    int deltas[4] = {e1_delta, e2_delta, e3_delta, e4_delta};
    int param_count = effects_list[selected_fx_idx].param_count;
    int any_param_changed = 0;
    
    for (int i = 0; i < 4; i++) {
        if (deltas[i] != 0 && i < param_count) {
            int min_val = effects_list[selected_fx_idx].params[i].min_val;
            int max_val = effects_list[selected_fx_idx].params[i].max_val;
            
            // Adaptar salto según el rango
            int step = ((max_val - min_val) <= 10) ? 1 : 5;
            
            int val = effects_list[selected_fx_idx].params[i].current_val;
            val += deltas[i] * step;
            
            if (val < min_val) val = min_val;
            if (val > max_val) val = max_val;
            effects_list[selected_fx_idx].params[i].current_val = val;
            
            // refresh especial solo del label y la barra seleccionada
            char buf[64];
            sprintf(buf, "%s: %d", effects_list[selected_fx_idx].params[i].name, val);
            lv_label_set_text(param_labels[i], buf);
            lv_bar_set_value(param_bars[i], val, LV_ANIM_OFF);
            
            any_param_changed = 1;
        }
    }
    
    if (any_param_changed) {
        ui_apply_all_params();
    }
}