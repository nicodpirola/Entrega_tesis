#ifndef PARAMS_H
#define PARAMS_H

#include "xil_types.h"
#include "fx_regmap.h"

#define FX_BASE      0x60000000u
#define FS_HZ        48000u
#define NUM_ENCODERS 6

typedef struct {
    float dist_drive;    // porcentaje 0..100
    float dist_level;
    float dist_tone;
    int eq_agudos_db;    // realce de agudos, 0..6 dB
    float tone_lpf_hz;
    float tone_hpf_hz;
    float cho_center;
    float cho_depth;
    float cho_rate;
    float cho_wet;
    float fl_center;
    float fl_depth;
    float fl_rate;
    float fl_fb;
    float fl_wet;
    float trem_rate;
    float trem_depth;
    float dly_time;
    float dly_fb;
    float dly_wet;
    float dly_tone_hz;
    int dly_lpf_on;     // pasabajos en el feedback del delay
    float ph_rate;      // Hz del LFO
    float ph_fmin;      // Hz, extremo inferior del barrido
    float ph_fmax;      // Hz, extremo superior del barrido
    float ph_fb;        // realimentacion, -1..1
    int syn_osc1_mode;
    int syn_osc2_wave;
    int syn_osc1_range;
    int syn_osc2_range;
    int syn_harmonics;
    float syn_o2_cents;
    float syn_l1;
    float syn_l2;
    float syn_bus_trim;
    float syn_env_gain;
    float syn_level;
    float syn_pw1, syn_pw2;
    int syn_output; // OSC1, OSC2 o mezcla
    int syn_corte_mult;           // 0: filtro apagado, 1..16: corte = nota x mult
    float syn_contorno;           // 0..1: el volumen abre el filtro hasta x5
    float syn_resonance_q;
    float syn_attack_ms, syn_release_ms;
    float syn_gate_on, syn_gate_off;
    int syn_instrumento;          // detector de pitch: 0 guitarra, 1 theremin
} params_t;

typedef struct {
    const char *name;
    float *value;
    float min;
    float max;
    float step;
} param_binding_t;

typedef struct {
    const char *title;
    param_binding_t *params;
    int n;
} screen_def_t;

typedef enum { ROLE_PARAM, ROLE_NAV_NEXT, ROLE_NAV_PREV } enc_role_t;
typedef struct { enc_role_t role; int param_idx; } enc_map_t;

#define NUM_PRESETS_TONE 4

/* -------------------------------------------------------------------------
 * HAL de hardware AXI-Lite (fx_hw)
 * ------------------------------------------------------------------------- */
u32  fx_hw_read(UINTPTR base, u32 offset);
void fx_hw_write(UINTPTR base, u32 offset, u32 value);
void fx_hw_update_bits(UINTPTR base, u32 offset, u32 mask, u32 value);
void fx_hw_commit(UINTPTR base);
int  fx_hw_probe(UINTPTR base);
void fx_hw_frontend_clear(UINTPTR base);

/* -------------------------------------------------------------------------
 * Generacion de tabla de diodos del overdrive (fx_od)
 * ------------------------------------------------------------------------- */
/* Sensibilidad del modelo, todavia no medida en el codec. */
#define FX_OD_INPUT_SENSITIVITY 1.7

void fx_od_init(void);
void fx_od_request(float drive_percent, float tone, float level);
void fx_od_service(UINTPTR base, u32 now_ms);
int  fx_od_coefficients(double drive, double tone, double level, unsigned factor,
                        double sensitivity, u32 words[12]);
int  fx_od_table_word(u32 index, double drive, double sensitivity, u32 *word);

/* -------------------------------------------------------------------------
 * IRs de gabinete para fx_cabsim (cab_ir)
 * ------------------------------------------------------------------------- */
#define CAB_IR_TAPS 1024

void        cab_load_ir(const int32_t *h, int n);
void        cab_select_ir(int idx);
int         cab_ir_count(void);
const char *cab_ir_name(int idx);

/* -------------------------------------------------------------------------
 * API de parametros DSP
 * ------------------------------------------------------------------------- */
int params_hw_compatible(void);
void params_master_enable(int on);
void params_set_mode(int synth_on, int tracking_on, int delay_on);
void params_load_wavetables(void);
void params_init(params_t *p);
void params_push_to_pl(const params_t *p);
void params_service(u32 now_ms);
void params_push_synth(const params_t *p);
void params_push_tone(const params_t *p);
void params_preset_tone(params_t *p, int idx);
const char *params_preset_name(int idx);
void params_screen_next(void);
void params_screen_prev(void);
const char *params_screen_title(void);
void params_handle_encoder(params_t *p, int enc, int delta);
void params_print(const params_t *p);
void synth_cycle_wave(params_t *p, int osc);
void synth_cycle_range(params_t *p, int osc);
const char *synth_wave_name(int osc, int wave);

#endif
