#ifndef PARAMS_H
#define PARAMS_H

#include "xil_types.h"
#include "xparameters.h"

// !! Copiar de tu params.h anterior la base AXI correcta !!
#define FX_BASE      0x60000000
#define FS_HZ        48000
#define NUM_ENCODERS 6

// ================= MAPA DE REGISTROS (FINAL-2) =================
#define FX_OFF_CTRL       0x00
#define FX_OFF_FX_EN      0x04
#define FX_OFF_SNOOP      0x08

#define FX_OFF_DIST_DRIVE 0x10
#define FX_OFF_DIST_LEVEL 0x14
#define FX_OFF_DIST_MIX   0x18
#define FX_OFF_WT_ADDR    0x1C
#define FX_OFF_WT_DATA    0x20
#define FX_OFF_DIST_TONE  0x24   // blend 0=oscuro 1=brillante
#define FX_OFF_TL_L_B0    0x28   // coefs LPF del tone (Q2.30)
#define FX_OFF_TL_L_B1    0x2C
#define FX_OFF_TL_L_B2    0x30
#define FX_OFF_TL_L_A1    0x34
#define FX_OFF_TL_L_A2    0x38
#define FX_OFF_TL_H_B0    0x3C   // coefs HPF del tone (Q2.30)
#define FX_OFF_TL_H_B1    0x40
#define FX_OFF_TL_H_B2    0x44
#define FX_OFF_TL_H_A1    0x48
#define FX_OFF_TL_H_A2    0x4C

#define FX_OFF_CHO_CENTER 0x50
#define FX_OFF_CHO_DEPTH  0x54
#define FX_OFF_CHO_RATE   0x58
#define FX_OFF_CHO_WET    0x5C
#define FX_OFF_CHO_LPF_G  0x60

#define FX_OFF_FL_DEPTH   0x70
#define FX_OFF_FL_RATE    0x74
#define FX_OFF_FL_FB      0x78
#define FX_OFF_FL_WET     0x7C

#define FX_OFF_TREM_RATE  0x90
#define FX_OFF_TREM_DEPTH 0x94

#define FX_OFF_DLY_TIME   0xB0
#define FX_OFF_DLY_FB     0xB4
#define FX_OFF_DLY_WET    0xB8

// -- SYNTH (Minimoog) 0xC0-0xFC --
#define FX_OFF_SYN_WAVES    0xC0   // [2:0]w1 [5:3]w2 [8:6]w3
#define FX_OFF_SYN_RANGES   0xC4   // [3:0]r1 [7:4]r2 [11:8]r3 (signed)
#define FX_OFF_SYN_O2_TUNE  0xC8   // Q2.30
#define FX_OFF_SYN_O3_TUNE  0xCC   // Q2.30
#define FX_OFF_SYN_O1_LVL   0xD0   // Q1.31
#define FX_OFF_SYN_O2_LVL   0xD4
#define FX_OFF_SYN_O3_LVL   0xD8
#define FX_OFF_SYN_NOISE    0xDC
#define FX_OFF_SYN_ENV_GAIN 0xE0
#define FX_OFF_SYN_LEVEL    0xE4   // nivel de salida del synth
#define FX_OFF_SYN_DRY_LVL  0xE8   // nivel del dry en la mezcla
#define FX_OFF_SYN_F_B0     0xEC   // filtro synth (off por defecto)
#define FX_OFF_SYN_F_B1     0xF0
#define FX_OFF_SYN_F_B2     0xF4
#define FX_OFF_SYN_F_A1     0xF8
#define FX_OFF_SYN_F_A2     0xFC

#define FX_OFF_ENC(n)     (0x100 + 4*(n))

// bits de FX_EN
#define FXB_DIST     (1u<<0)
#define FXB_CHORUS   (1u<<1)
#define FXB_FLANG    (1u<<2)
#define FXB_TREM     (1u<<3)
#define FXB_DELAY    (1u<<4)
#define FXB_BLEND    (1u<<5)
#define FXB_PEAK     (1u<<6)
#define FXB_HPF      (1u<<7)
#define FXB_DCB_IN   (1u<<8)
#define FXB_DCB_POST (1u<<9)
#define FXB_CHO_LPF  (1u<<10)
#define FXB_CAB      (1u<<11)       
#define FXB_PHASER   (1u<<12)
#define FXB_SYNTH    (1u<<13)   // activa tracking + voz sintetizada
#define FXB_SYNTH_ONLY (1u<<14) // 1=sólo synth; 0=mix 50/50 dry+synth
#define FXB_SYNTH_FILT (1u<<15) // filtro interno del synth




// formas de onda del synth (Minimoog)
#define WAVE_TRI     0
#define WAVE_TRISAW  1
#define WAVE_SAW     2
#define WAVE_SQUARE  3
#define WAVE_PULSEW  4
#define WAVE_PULSEN  5
#define NUM_WAVES    6
#define SYN_PACK_WAVES(w1,w2,w3)  (((w1)&7)|(((w2)&7)<<3)|(((w3)&7)<<6))
#define SYN_PACK_RANGES(r1,r2,r3) (((r1)&0xF)|(((r2)&0xF)<<4)|(((r3)&0xF)<<8))

// bits de CTRL
#define CTRLB_ENABLE (1u<<0)
#define CTRLB_TONO   (1u<<3)


// ================= Modelo =================
typedef struct {
    // Distorsion
    float dist_drive;   // 1..20
    float dist_level;   // 0..1
    float dist_tone;    // 0=oscuro .. 1=brillante (blend)
    // Tone stack (frecuencias de las dos ramas; el PS calcula los coefs)
    float tone_lpf_hz;  // rama oscura
    float tone_hpf_hz;  // rama brillante
    // Chorus
    float cho_center, cho_depth, cho_rate, cho_wet;   // ms, ms, Hz, 0..1
    // Flanger
    float fl_depth, fl_rate, fl_fb, fl_wet;
    // Tremolo
    float trem_rate, trem_depth;
    // Delay
    float dly_time, dly_fb, dly_wet;                  // ms, 0..1, 0..1
    // Synth (Minimoog): formas y octavas discretas (por tecla), resto continuo
    int   syn_w1, syn_w2, syn_w3;      // forma de onda por oscilador (0..5)
    int   syn_r1, syn_r2, syn_r3;      // octava (RANGE) por oscilador (-2..+2)
    float syn_o2_cents, syn_o3_cents;  // detune OSC2/OSC3 (cents)
    float syn_l1, syn_l2, syn_l3;      // niveles 0..1
    float syn_noise;                   // nivel de ruido 0..1
    float syn_env_gain;                // volumen del synth segun señal 0..1
    float syn_level;                   // nivel salida synth 0..1
    float syn_dry;                     // nivel dry en la mezcla 0..1
} params_t;

typedef struct {
    const char *name;
    float      *value;
    float       min, max, step;
} param_binding_t;

typedef struct {
    const char      *title;
    param_binding_t *params;
    int              n;
} screen_def_t;

typedef enum { ROLE_PARAM, ROLE_NAV_NEXT, ROLE_NAV_PREV } enc_role_t;
typedef struct { enc_role_t role; int param_idx; } enc_map_t;

// ============================================================
// Funciones maestras (Setup)
// ============================================================
void params_master_enable(int on);
void params_set_mode(int synth_on, int synth_only, int delay_on);
void params_load_wavetables(void);

// ============================================================
// Funciones publicas
// ============================================================
void params_init(params_t *p);
void params_push_to_pl(const params_t *p);
void params_push_tone(const params_t *p);     // recalcula y baja los 10 coefs
void params_preset_tone(params_t *p, int idx);// presets de pedal (BigMuff, TS...)
const char *params_preset_name(int idx);
#define NUM_PRESETS_TONE 4

void params_screen_next(void);
void params_screen_prev(void);
const char *params_screen_title(void);
void params_handle_encoder(params_t *p, int enc, int delta);
void params_print(const params_t *p);

// --- Synth ---
void params_push_synth(const params_t *p);        // baja todos los params del synth
void synth_cycle_wave(params_t *p, int osc);      // rota la forma de un oscilador (1..3)
void synth_cycle_range(params_t *p, int osc);     // rota la octava de un oscilador
const char *synth_wave_name(int w);

#endif