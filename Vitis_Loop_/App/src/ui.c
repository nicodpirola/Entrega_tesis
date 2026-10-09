#include "ui.h"
#include <stdio.h>
#include <string.h>
#include "xil_printf.h"
#include "params.h"
#include "xil_io.h"
#include "ipc.h"
#include "fx_regmap.h"

// LVGL objects
static lv_obj_t * header_cont;
static lv_obj_t * label_status;
static lv_obj_t * label_preset_msg;
static uint32_t   preset_msg_timeout = 0;
static lv_obj_t * label_sd;
static lv_obj_t * bar_progress;

static lv_obj_t * col_left;
static lv_obj_t * col_right;
static lv_obj_t * label_page_info;

static lv_obj_t * fx_items[MAX_EFFECTS];
static lv_obj_t * fx_labels[MAX_EFFECTS];
static lv_obj_t * param_items[PARAMS_PER_PAGE];
static lv_obj_t * param_labels[PARAMS_PER_PAGE];
static lv_obj_t * param_bars[PARAMS_PER_PAGE];

// State
static int selected_fx_idx = 0;

// Presets en memoria local (Slots 0, 1, 2)
static int preset_slots_enabled[3][MAX_EFFECTS];
static int preset_slots_params[3][MAX_EFFECTS][MAX_FX_PARAMS];
static int presets_initialized = 0;

enum {
    UI_SYNTH = 0,
    UI_DISTORTION,
    UI_EQ,
    UI_CHORUS,
    UI_FLANGER,
    UI_TREMOLO,
    UI_PHASER,
    UI_DELAY,
    UI_CAB,
    UI_OUTPUT
};

const int num_effects = MAX_EFFECTS;
effect_module_t effects_list[MAX_EFFECTS] = {
    {
        .name = "Synth",
        .enabled = 0,
        .param_count = 12,
        .current_page = 0,
        .params = {
            // Pagina 0: Osciladores & Modo Pitch (Theremin / Guitarra)
            {"Osc1 Wave",   0, 3,     1},
            {"Osc2 Wave",   0, 2,     0},
            {"Tune2(cnt)", -100, 100, 0},
            {"Modo Pitch",  0, 1,     0},

            // Pagina 1: Filtro SVF
            {"Filtro",      0, 3,     1},
            {"Cutoff(Hz)",  20, 12000, 1000},
            {"Reson(Q*10)", 5, 50,    10},
            {"Salida Osc",  0, 2,     2},

            // Pagina 2: Envolvente & Dinamica
            {"Ataque(ms)",  1, 200,   5},
            {"Release(ms)", 5, 1000,  80},
            {"Balance(%)",  0, 100,   60},
            {"Nivel(%)",    0, 100,   90}
        }
    },
    {
        .name = "Dist",
        .enabled = 0,
        .param_count = 3,
        .params = {
            {"Drive(%)", 0, 100, 50},
            {"Tone(%)",  0, 100, 50},
            {"Level(%)", 0, 100, 100},
            {"-",        0, 0,   0}
        }
    },
    {
        .name = "EQ",
        .enabled = 0,
        .param_count = 1,
        .params = {
            {"Agudos(dB)", 0, 6, 0},
            {"-",          0, 0, 0},
            {"-",          0, 0, 0},
            {"-",          0, 0, 0}
        }
    },
    {
        .name = "Chorus",
        .enabled = 0,
        .param_count = 3,
        .params = {
            {"Depth(ms)",   0, 20,  2},
            {"Rate(Hz*10)", 1, 50,  4},
            {"Wet(%)",      0, 100, 50},
            {"-",           0, 0,   0}
        }
    },
    {
        .name = "Flanger",
        .enabled = 0,
        .param_count = 3,
        .params = {
            {"Depth(ms)",   0, 10, 2},
            {"Rate(Hz*10)", 1, 50, 4},
            {"FB(%)",       0, 90, 50},
            {"-",           0, 0,  0}
        }
    },
    {
        .name = "Tremolo",
        .enabled = 0,
        .param_count = 2,
        .params = {
            {"Depth(%)",     0, 100, 50},
            {"Rate(Hz*10)",  1, 100, 50},
            {"-",            0, 0,   0},
            {"-",            0, 0,   0}
        }
    },
    {
        .name = "Phaser",
        .enabled = 0,
        .param_count = 3,
        .params = {
            {"Rate(Hz*10)", 1, 50,  10},
            {"Depth(%)",    0, 100, 50},
            {"FB(%)",       0, 90,  30},
            {"-",           0, 0,   0}
        }
    },
    {
        .name = "Delay",
        .enabled = 0,
        .param_count = 3,
        .params = {
            {"Time(ms)", 10, 680, 250},
            {"FB(%)",    0, 90,  35},
            {"Wet(%)",   0, 100, 25},
            {"-",        0, 0,   0}
        }
    },
    {
        .name = "Cab",
        .enabled = 1,
        .param_count = 2,
        .params = {
            {"Level(%)", 0, 100,              100},
            {"IR",       0, CAB_IR_COUNT - 1, 0},
            {"-",        0, 0,                0},
            {"-",        0, 0,                0}
        }
    },
    {
        .name = "Output",
        .enabled = 1,
        .param_count = 1,
        .params = {
            {"Level(%)", 0, 100, 100},
            {"-",        0, 0,   0},
            {"-",        0, 0,   0},
            {"-",        0, 0,   0}
        }
    }
};

static void ui_apply_all_params(void) {
    uint32_t fx_en = 0;

    if (effects_list[UI_DISTORTION].enabled) fx_en |= FX_EN_DIST;
    if (effects_list[UI_EQ].enabled)         fx_en |= FX_EN_EQ;
    if (effects_list[UI_CHORUS].enabled)     fx_en |= FX_EN_CHORUS;
    if (effects_list[UI_FLANGER].enabled)    fx_en |= FX_EN_FLANGER;
    if (effects_list[UI_TREMOLO].enabled)    fx_en |= FX_EN_TREMOLO;
    if (effects_list[UI_PHASER].enabled)     fx_en |= FX_EN_PHASER;
    if (effects_list[UI_DELAY].enabled)      fx_en |= FX_EN_DELAY;
    if (effects_list[UI_CAB].enabled)        fx_en |= FX_EN_CAB;

    Xil_Out32(FX_BASE + FX_REG_FX_ENABLE, fx_en);
    Xil_Out32(FX_BASE + FX_REG_SOURCE_CTRL, effects_list[UI_SYNTH].enabled ? FX_SOURCE_SYNTH : 0u);

    params_t p;
    params_init(&p);

    // Synth - Mapeo completo de las 3 paginas
    p.syn_osc1_mode   = effects_list[UI_SYNTH].params[0].current_val;
    p.syn_osc2_wave   = effects_list[UI_SYNTH].params[1].current_val;
    p.syn_o2_cents    = (float)effects_list[UI_SYNTH].params[2].current_val;
    p.syn_instrumento = effects_list[UI_SYNTH].params[3].current_val; // 0=Guitarra, 1=Theremin

    p.syn_filter_mode = effects_list[UI_SYNTH].params[4].current_val;
    p.syn_cutoff_hz   = (float)effects_list[UI_SYNTH].params[5].current_val;
    p.syn_resonance_q = (float)effects_list[UI_SYNTH].params[6].current_val / 10.0f;
    p.syn_output      = effects_list[UI_SYNTH].params[7].current_val;

    p.syn_attack_ms   = (float)effects_list[UI_SYNTH].params[8].current_val;
    p.syn_release_ms  = (float)effects_list[UI_SYNTH].params[9].current_val;
    float synth_bal   = (float)effects_list[UI_SYNTH].params[10].current_val / 100.0f;
    p.syn_l1          = synth_bal;
    p.syn_l2          = 1.0f - synth_bal;
    p.syn_level       = (float)effects_list[UI_SYNTH].params[11].current_val / 100.0f;

    // Distortion
    p.dist_drive = (float)effects_list[UI_DISTORTION].params[0].current_val;
    p.dist_tone  = (float)effects_list[UI_DISTORTION].params[1].current_val / 100.0f;
    p.dist_level = (float)effects_list[UI_DISTORTION].params[2].current_val / 100.0f;

    // EQ
    p.eq_agudos_db = effects_list[UI_EQ].params[0].current_val;

    // Chorus
    p.cho_depth = (float)effects_list[UI_CHORUS].params[0].current_val;
    p.cho_rate  = (float)effects_list[UI_CHORUS].params[1].current_val / 10.0f;
    p.cho_wet   = (float)effects_list[UI_CHORUS].params[2].current_val / 100.0f;

    // Flanger
    p.fl_depth = (float)effects_list[UI_FLANGER].params[0].current_val;
    p.fl_rate  = (float)effects_list[UI_FLANGER].params[1].current_val / 10.0f;
    p.fl_fb    = (float)effects_list[UI_FLANGER].params[2].current_val / 100.0f;
    p.fl_wet   = 0.5f;

    // Tremolo
    p.trem_depth = (float)effects_list[UI_TREMOLO].params[0].current_val / 100.0f;
    p.trem_rate  = (float)effects_list[UI_TREMOLO].params[1].current_val / 10.0f;

    // Phaser
    p.ph_rate = (float)effects_list[UI_PHASER].params[0].current_val / 10.0f;
    p.ph_fmin = 300.0f;
    p.ph_fmax = 300.0f + 2700.0f * (float)effects_list[UI_PHASER].params[1].current_val / 100.0f;
    p.ph_fb   = (float)effects_list[UI_PHASER].params[2].current_val / 100.0f;

    // Delay
    p.dly_time = (float)effects_list[UI_DELAY].params[0].current_val;
    p.dly_fb   = (float)effects_list[UI_DELAY].params[1].current_val / 100.0f;
    p.dly_wet  = (float)effects_list[UI_DELAY].params[2].current_val / 100.0f;

    // Cab
    uint32_t cab_q1_31 = (uint32_t)(((uint64_t)effects_list[UI_CAB].params[0].current_val * 0x7FFFFFFFu) / 100u);
    Xil_Out32(FX_BASE + FX_REG_CAB_LEVEL, cab_q1_31);
    cab_select_ir(effects_list[UI_CAB].params[1].current_val);

    // Output
    int output_level_pct = effects_list[UI_OUTPUT].params[0].current_val;
    uint32_t output_q1_31 = (uint32_t)(((uint64_t)output_level_pct * 0x7FFFFFFFu) / 100u);
    Xil_Out32(FX_BASE + FX_REG_OUTPUT_LEVEL, output_q1_31);
    Xil_Out32(FX_BASE + FX_REG_OUTPUT_CTRL, effects_list[UI_OUTPUT].enabled ? 0u : 1u);

    // Push to PL
    params_push_to_pl(&p);
}

static void ui_refresh_effect_label(int idx) {
    if (idx >= 0 && idx < num_effects && fx_labels[idx]) {
        char buf[32];
        snprintf(buf, sizeof(buf), "%s %s", effects_list[idx].name, effects_list[idx].enabled ? "ON" : "OFF");
        lv_label_set_text(fx_labels[idx], buf);
    }
}

static void ui_refresh_selection(void) {
    for (int i = 0; i < num_effects; i++) {
        int is_on = effects_list[i].enabled;

        if (i == selected_fx_idx) {
            lv_color_t bg_col = is_on ? lv_color_hex(0x694598) : lv_color_hex(0x3B3B48);
            lv_obj_set_style_bg_color(fx_items[i], bg_col, 0);
            if (fx_labels[i]) {
                lv_obj_set_style_text_color(fx_labels[i], lv_color_hex(0xFFFFFF), 0);
            }
            lv_obj_scroll_to_view(fx_items[i], LV_ANIM_OFF);
        } else {
            lv_color_t bg_col = lv_color_hex(0x1C1C24);
            lv_color_t txt_col = is_on ? lv_color_hex(0x55FF88) : lv_color_hex(0x777788);
            lv_obj_set_style_bg_color(fx_items[i], bg_col, 0);
            if (fx_labels[i]) {
                lv_obj_set_style_text_color(fx_labels[i], txt_col, 0);
            }
        }
    }
}

static void ui_refresh_param_panel(void) {
    int total_params = effects_list[selected_fx_idx].param_count;
    int current_page = effects_list[selected_fx_idx].current_page;
    int offset = current_page * 4;

    // Indicador de pagina para efectos multi-pagina (Synth)
    if (label_page_info) {
        if (total_params > 4) {
            lv_obj_clear_flag(label_page_info, LV_OBJ_FLAG_HIDDEN);
            char p_buf[32];
            const char *page_titles[] = { "OSC", "FILTRO", "ENV" };
            const char *t = (current_page >= 0 && current_page < 3) ? page_titles[current_page] : "";
            snprintf(p_buf, sizeof(p_buf), "[%d/3] %s (E5)", current_page + 1, t);
            lv_label_set_text(label_page_info, p_buf);
        } else {
            lv_obj_add_flag(label_page_info, LV_OBJ_FLAG_HIDDEN);
        }
    }

    for (int i = 0; i < PARAMS_PER_PAGE; i++) {
        int p_idx = offset + i;
        if (p_idx < total_params) {
            lv_obj_clear_flag(param_items[i], LV_OBJ_FLAG_HIDDEN);
            char buf[64];
            int val = effects_list[selected_fx_idx].params[p_idx].current_val;
            const char *pname = effects_list[selected_fx_idx].params[p_idx].name;

            // Texto especial para IR de Cab
            if (selected_fx_idx == UI_CAB && p_idx == 1) {
                snprintf(buf, sizeof(buf), "%s: %s", pname, cab_ir_name(val));
            } else if (selected_fx_idx == UI_SYNTH) {
                switch (p_idx) {
                    case 0: snprintf(buf, sizeof(buf), "%s: %s", pname, synth_wave_name(1, val)); break;
                    case 1: snprintf(buf, sizeof(buf), "%s: %s", pname, synth_wave_name(2, val)); break;
                    case 2: snprintf(buf, sizeof(buf), "%s: %d cnt", pname, val); break;
                    case 3: snprintf(buf, sizeof(buf), "%s: %s", pname, val ? "Theremin" : "Guitarra"); break;
                    case 4: {
                        const char *f_names[] = { "Bypass", "LowPass", "BandPass", "HighPass" };
                        const char *fn = (val >= 0 && val < 4) ? f_names[val] : "Bypass";
                        snprintf(buf, sizeof(buf), "%s: %s", pname, fn);
                        break;
                    }
                    case 5: snprintf(buf, sizeof(buf), "%s: %d Hz", pname, val); break;
                    case 6: snprintf(buf, sizeof(buf), "%s: %d.%d", pname, val / 10, val % 10); break;
                    case 7: {
                        const char *o_names[] = { "Solo Osc1", "Solo Osc2", "Mezcla" };
                        const char *on = (val >= 0 && val < 3) ? o_names[val] : "Mezcla";
                        snprintf(buf, sizeof(buf), "%s: %s", pname, on);
                        break;
                    }
                    case 8: snprintf(buf, sizeof(buf), "%s: %d ms", pname, val); break;
                    case 9: snprintf(buf, sizeof(buf), "%s: %d ms", pname, val); break;
                    case 10: snprintf(buf, sizeof(buf), "%s: %d%% O1", pname, val); break;
                    case 11: snprintf(buf, sizeof(buf), "%s: %d%%", pname, val); break;
                    default: snprintf(buf, sizeof(buf), "%s: %d", pname, val); break;
                }
            } else {
                snprintf(buf, sizeof(buf), "%s: %d", pname, val);
            }
            lv_label_set_text(param_labels[i], buf);

            lv_bar_set_range(param_bars[i], effects_list[selected_fx_idx].params[p_idx].min_val,
                                             effects_list[selected_fx_idx].params[p_idx].max_val);
            lv_bar_set_value(param_bars[i], val, LV_ANIM_OFF);
        } else {
            lv_obj_add_flag(param_items[i], LV_OBJ_FLAG_HIDDEN);
        }
    }
}

void ui_presets_init(void) {
    for (int s = 0; s < 3; s++) {
        for (int i = 0; i < MAX_EFFECTS; i++) {
            preset_slots_enabled[s][i] = effects_list[i].enabled;
            for (int j = 0; j < MAX_FX_PARAMS; j++) {
                preset_slots_params[s][i][j] = effects_list[i].params[j].current_val;
            }
        }
    }
    presets_initialized = 1;
}

void ui_save_preset(int slot) {
    if (slot < 0 || slot >= 3) return;
    if (!presets_initialized) ui_presets_init();
    
    for (int i = 0; i < MAX_EFFECTS; i++) {
        preset_slots_enabled[slot][i] = effects_list[i].enabled;
        for (int j = 0; j < MAX_FX_PARAMS; j++) {
            preset_slots_params[slot][i][j] = effects_list[i].params[j].current_val;
            if (i < 6) IPC->preset_data[i][j] = effects_list[i].params[j].current_val;
        }
    }
    
    if (label_preset_msg) {
        char buf[32];
        snprintf(buf, sizeof(buf), "GUARDANDO P%d", slot + 1);
        lv_label_set_text(label_preset_msg, buf);
        lv_obj_set_style_text_color(label_preset_msg, lv_color_hex(0xFFCC00), 0);
        preset_msg_timeout = lv_tick_get() + 2500;
    }
    
    IPC->preset_cmd = slot + 1;
}

void ui_load_preset(int slot) {
    if (slot < 0 || slot >= 3) return;
    if (!presets_initialized) ui_presets_init();
    
    for (int i = 0; i < MAX_EFFECTS; i++) {
        effects_list[i].enabled = preset_slots_enabled[slot][i];
        for (int j = 0; j < MAX_FX_PARAMS; j++) {
            effects_list[i].params[j].current_val = preset_slots_params[slot][i][j];
        }
        ui_refresh_effect_label(i);
    }
    
    ui_refresh_param_panel();
    ui_refresh_selection();
    ui_apply_all_params();

    if (label_preset_msg) {
        char buf[32];
        snprintf(buf, sizeof(buf), "CARGADO P%d", slot + 1);
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
    lv_obj_set_style_bg_color(screen, lv_color_hex(0x101018), 0);

    // Header superior
    header_cont = lv_obj_create(screen);
    lv_obj_set_size(header_cont, 320, 36);
    lv_obj_set_pos(header_cont, 0, 0);
    lv_obj_set_style_bg_color(header_cont, lv_color_hex(0x181824), 0);
    lv_obj_set_style_border_width(header_cont, 0, 0);
    lv_obj_set_style_radius(header_cont, 0, 0);
    lv_obj_set_style_pad_all(header_cont, 0, 0);
    
    label_status = lv_label_create(header_cont);
    lv_obj_align(label_status, LV_ALIGN_TOP_LEFT, 6, 3);
    lv_label_set_text(label_status, "IDLE");
    lv_obj_set_style_text_color(label_status, lv_color_hex(0xAAAAAA), 0);

    label_preset_msg = lv_label_create(header_cont);
    lv_obj_align(label_preset_msg, LV_ALIGN_TOP_MID, 0, 3);
    lv_label_set_text(label_preset_msg, "");
    lv_obj_set_style_text_color(label_preset_msg, lv_color_hex(0x00E5FF), 0);
    
    label_sd = lv_label_create(header_cont);
    lv_obj_align(label_sd, LV_ALIGN_TOP_RIGHT, -6, 3);
    lv_label_set_text(label_sd, "SD: LISTA");
    lv_obj_set_style_text_color(label_sd, lv_color_hex(0x888888), 0);
    
    bar_progress = lv_bar_create(header_cont);
    lv_obj_set_size(bar_progress, 308, 6);
    lv_obj_align(bar_progress, LV_ALIGN_BOTTOM_MID, 0, -3);
    lv_bar_set_range(bar_progress, 0, 100);
    lv_bar_set_value(bar_progress, 0, LV_ANIM_OFF);
    lv_obj_set_style_bg_color(bar_progress, lv_color_hex(0x282838), LV_PART_MAIN);
    lv_obj_set_style_bg_color(bar_progress, lv_color_hex(0x694598), LV_PART_INDICATOR);
    
    // Columna izquierda (Lista de Efectos desplazable)
    col_left = lv_obj_create(screen);
    lv_obj_set_size(col_left, 114, 204);
    lv_obj_set_pos(col_left, 0, 36);
    lv_obj_set_style_bg_color(col_left, lv_color_hex(0x181820), 0);
    lv_obj_set_style_border_width(col_left, 0, 0);
    lv_obj_set_style_radius(col_left, 0, 0);
    lv_obj_set_style_pad_all(col_left, 3, 0);
    
    for (int i = 0; i < MAX_EFFECTS; i++) {
        fx_items[i] = lv_obj_create(col_left);
        lv_obj_set_size(fx_items[i], 106, 32);
        lv_obj_set_pos(fx_items[i], 0, i * 35);
        lv_obj_set_style_border_width(fx_items[i], 0, 0);
        lv_obj_set_style_radius(fx_items[i], 3, 0);
        lv_obj_set_style_pad_all(fx_items[i], 0, 0);
        
        fx_labels[i] = lv_label_create(fx_items[i]);
        if (i < num_effects) {
            char buf[32];
            snprintf(buf, sizeof(buf), "%s %s", effects_list[i].name, effects_list[i].enabled ? "ON" : "OFF");
            lv_label_set_text(fx_labels[i], buf);
        }
        lv_obj_align(fx_labels[i], LV_ALIGN_LEFT_MID, 6, 0);
        if (i >= num_effects) {
            lv_obj_add_flag(fx_items[i], LV_OBJ_FLAG_HIDDEN);
        }
    }
    
    // Columna derecha (Controles del Efecto Seleccionado)
    col_right = lv_obj_create(screen);
    lv_obj_set_size(col_right, 206, 204);
    lv_obj_set_pos(col_right, 114, 36);
    lv_obj_set_style_bg_color(col_right, lv_color_hex(0x101018), 0);
    lv_obj_set_style_border_width(col_right, 0, 0);
    lv_obj_set_style_radius(col_right, 0, 0);
    lv_obj_set_style_pad_all(col_right, 4, 0);

    label_page_info = lv_label_create(col_right);
    lv_obj_align(label_page_info, LV_ALIGN_TOP_LEFT, 6, 2);
    lv_label_set_text(label_page_info, "");
    lv_obj_set_style_text_color(label_page_info, lv_color_hex(0x00E5FF), 0);
    lv_obj_add_flag(label_page_info, LV_OBJ_FLAG_HIDDEN);
    
    for (int i = 0; i < PARAMS_PER_PAGE; i++) {
        param_items[i] = lv_obj_create(col_right);
        lv_obj_set_size(param_items[i], 198, 42);
        lv_obj_set_pos(param_items[i], 0, 18 + i * 46);
        lv_obj_set_style_bg_color(param_items[i], lv_color_hex(0x242430), 0);
        lv_obj_set_style_border_width(param_items[i], 0, 0);
        lv_obj_set_style_radius(param_items[i], 4, 0);
        lv_obj_set_style_pad_all(param_items[i], 0, 0);
        
        param_labels[i] = lv_label_create(param_items[i]);
        lv_obj_align(param_labels[i], LV_ALIGN_TOP_LEFT, 6, 3);
        lv_obj_set_style_text_color(param_labels[i], lv_color_hex(0xEEEAF6), 0);
        
        param_bars[i] = lv_bar_create(param_items[i]);
        lv_obj_set_size(param_bars[i], 186, 6);
        lv_obj_align(param_bars[i], LV_ALIGN_BOTTOM_MID, 0, -5);
        lv_obj_set_style_bg_color(param_bars[i], lv_color_hex(0x363642), LV_PART_MAIN);
        lv_obj_set_style_bg_color(param_bars[i], lv_color_hex(0x694598), LV_PART_INDICATOR);
    }
    
    ui_refresh_param_panel();
    ui_refresh_selection();
    ui_apply_all_params();
}

void ui_update_status(int hw_mode, int sd_recording) { 
    static int last_hw_mode = -1;
    static int last_sd_recording = -1;

    if (hw_mode != last_hw_mode) {
        last_hw_mode = hw_mode;
        if (hw_mode == 0) {
            lv_label_set_text(label_status, "IDLE");
            lv_obj_set_style_text_color(label_status, lv_color_hex(0xAAAAAA), 0);
        } else if (hw_mode == 1) {
            lv_label_set_text(label_status, "REC");
            lv_obj_set_style_text_color(label_status, lv_color_hex(0xFF3333), 0);
        } else if (hw_mode == 2) {
            lv_label_set_text(label_status, "PLAY");
            lv_obj_set_style_text_color(label_status, lv_color_hex(0x33FF66), 0);
        } else if (hw_mode == 3) {
            lv_label_set_text(label_status, "OVERDUB");
            lv_obj_set_style_text_color(label_status, lv_color_hex(0xFF9900), 0);
        }
    }

    if (sd_recording != last_sd_recording) {
        last_sd_recording = sd_recording;
        if (sd_recording) {
            lv_label_set_text(label_sd, "SD: REC...");
            lv_obj_set_style_text_color(label_sd, lv_color_hex(0xFFFFFF), 0);
        } else {
            lv_label_set_text(label_sd, "SD: LISTA");
            lv_obj_set_style_text_color(label_sd, lv_color_hex(0x888888), 0);
        }
    }

    if (preset_msg_timeout > 0 && lv_tick_get() >= preset_msg_timeout) {
        if (label_preset_msg) lv_label_set_text(label_preset_msg, "");
        preset_msg_timeout = 0;
    }
}

void ui_update_progress(uint32_t loop_index, uint32_t loop_length) {
    static uint32_t last_pct = 0xFFFFFFFF;
    uint32_t pct = 0;
    if (loop_length > 0) {
        pct = (loop_index * 100) / loop_length;
        if (pct > 100) pct = 100;
    }
    if (pct != last_pct) {
        last_pct = pct;
        lv_bar_set_value(bar_progress, pct, LV_ANIM_OFF);
    }
}

void ui_handle_buttons(unsigned param_clicked) {
    if (!param_clicked) return;
    int offset = effects_list[selected_fx_idx].current_page * 4;
    int total_params = effects_list[selected_fx_idx].param_count;
    int changed = 0;

    for (int i = 0; i < 4; i++) {
        int p_idx = offset + i;
        if (p_idx < total_params && (param_clicked & (1u << i))) {
            // Ciclo de seleccion rapida en parametros discretos
            int min_val = effects_list[selected_fx_idx].params[p_idx].min_val;
            int max_val = effects_list[selected_fx_idx].params[p_idx].max_val;
            int span = max_val - min_val + 1;
            if (span <= 6) {
                int val = effects_list[selected_fx_idx].params[p_idx].current_val + 1;
                if (val > max_val) val = min_val;
                effects_list[selected_fx_idx].params[p_idx].current_val = val;
                changed = 1;
            }
        }
    }
    if (changed) {
        ui_refresh_param_panel();
        ui_apply_all_params();
    }
}

void ui_handle_encoders(int e0_d, int e1_d, int e2_d, int e3_d, int e4_d, int nav_click, int e5_d) {
    int changed = 0;

    // E4: Navegacion entre efectos
    if (e4_d != 0) {
        selected_fx_idx += (e4_d > 0 ? 1 : -1);
        if (selected_fx_idx < 0) selected_fx_idx = 0;
        if (selected_fx_idx >= num_effects) selected_fx_idx = num_effects - 1;
        ui_refresh_param_panel();
        ui_refresh_selection();
    }

    // Boton del encoder de seleccion: Activar / Bypass del efecto actual
    if (nav_click) {
        effects_list[selected_fx_idx].enabled ^= 1;
        ui_refresh_effect_label(selected_fx_idx);
        ui_refresh_selection();
        changed = 1;
    }

    // E5: Si el efecto tiene multiples paginas (> 4 parametros, como Synth), cambia de pagina!
    if (e5_d != 0) {
        if (effects_list[selected_fx_idx].param_count > 4) {
            int total_pages = (effects_list[selected_fx_idx].param_count + 3) / 4;
            int next_page = effects_list[selected_fx_idx].current_page + (e5_d > 0 ? 1 : -1);
            if (next_page < 0) next_page = total_pages - 1;
            if (next_page >= total_pages) next_page = 0;
            effects_list[selected_fx_idx].current_page = next_page;
            ui_refresh_param_panel();
        } else {
            // En efectos de 1 sola pagina, E5 controla el Master Output
            int val = effects_list[UI_OUTPUT].params[0].current_val + e5_d;
            if (val < 0) val = 0;
            if (val > 100) val = 100;
            if (val != effects_list[UI_OUTPUT].params[0].current_val) {
                effects_list[UI_OUTPUT].params[0].current_val = val;
                changed = 1;
            }
        }
    }

    // E0..E3: Modificar los parametros visibles de la pagina activa
    int deltas[4] = {e0_d, e1_d, e2_d, e3_d};
    int offset = effects_list[selected_fx_idx].current_page * 4;
    int total_params = effects_list[selected_fx_idx].param_count;

    for (int i = 0; i < 4; i++) {
        int p_idx = offset + i;
        if (p_idx < total_params && deltas[i] != 0) {
            int min_val = effects_list[selected_fx_idx].params[p_idx].min_val;
            int max_val = effects_list[selected_fx_idx].params[p_idx].max_val;
            int span = max_val - min_val;
            int step = 1;
            if (span > 500) step = 50;
            else if (span > 50) step = 5;

            int val = effects_list[selected_fx_idx].params[p_idx].current_val + deltas[i] * step;
            if (val < min_val) val = min_val;
            if (val > max_val) val = max_val;

            if (val != effects_list[selected_fx_idx].params[p_idx].current_val) {
                effects_list[selected_fx_idx].params[p_idx].current_val = val;
                changed = 1;
            }
        }
    }

    if (changed) {
        ui_refresh_param_panel();
        ui_apply_all_params();
    }
}
