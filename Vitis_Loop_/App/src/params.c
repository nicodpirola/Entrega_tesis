#include "params.h"
#include "xil_io.h"
#include "xil_printf.h"
#include <math.h>

// ============================================================
//  Definicion de Pantallas & Encoders
// ============================================================
static param_binding_t dist_params[3];
static param_binding_t tone_params[2];
static param_binding_t cho_params[4];
static param_binding_t fl_params[4];
static param_binding_t trem_params[2];
static param_binding_t dly_params[3];
static param_binding_t syn_mix_params[4];
static param_binding_t syn_tune_params[4];

static screen_def_t screens[] = {
    { "DIST",    dist_params, 3 },
    { "TONE",    tone_params, 2 },
    { "CHORUS",  cho_params,  4 },
    { "FLANGER", fl_params,   4 },
    { "TREMOLO", trem_params, 2 },
    { "DELAY",   dly_params,  3 },
    { "SYN-MIX", syn_mix_params, 4 },
    { "SYN-VOICE",syn_tune_params, 4 },
};
static const int NUM_SCREENS = sizeof(screens)/sizeof(screens[0]);
static int g_screen = 0;

static enc_map_t enc_map[NUM_ENCODERS] = {
    { ROLE_PARAM, 0 }, { ROLE_PARAM, 1 }, { ROLE_PARAM, 2 },
    { ROLE_PARAM, 3 }, { ROLE_PARAM, 4 }, { ROLE_PARAM, 5 },
};

// ============================================================
//  Conversiones a punto fijo
// ============================================================
// COnversión Q16.16 (16 bits para la parte entera, 16 para la parete decimal).
static uint32_t f_to_q16_16(float v){ if(v<0)v=0; return (uint32_t)(v*65536.0f); }
// Conversión Q1.31
static uint32_t f_to_q1_31(float v){
    if(v>= 1.0f) return 0x7FFFFFFF;
    if(v<=-1.0f) return 0x80000000;
    return (uint32_t)(v*2147483648.0f);
}
// Q2.30 (biquads)
static uint32_t d_to_q2_30(double v){
    double s = v * 1073741824.0;          // 2^30
    if (s >  2147483647.0) s =  2147483647.0;
    if (s < -2147483648.0) s = -2147483648.0;
    return (uint32_t)(int32_t)(s < 0 ? s - 0.5 : s + 0.5);
}
// Convierte frecuencia en Hz a incremento de fase para un oscilador de 32 bits a la frecuencia de muestreo FS_HZ
static uint32_t hz_to_phase_inc(float hz){
    if(hz<0)hz=0;
    double inc = (double)hz * 4294967296.0 / (double)FS_HZ;
    if(inc > 4294967295.0) inc = 4294967295.0;
    return (uint32_t)inc;
}
// LPF TPT de 1 polo (chorus): G = g/(1+g), g = tan(pi*fc/fs)
static uint32_t fc_to_tpt_G(float fc){
    double g = tan(M_PI * (double)fc / (double)FS_HZ);
    double G = g / (1.0 + g);
    return f_to_q1_31((float)G);
}
// Limita lo<float<hi
static float clampf(float v,float lo,float hi){ return v<lo?lo:(v>hi?hi:v); }

// ============================================================
//  Filtros de PRIMER ORDEN (6 dB/oct) por transformada bilineal
// ============================================================
// coeficientes biquad lpf 1 orden
static void lpf1(double fc, double *b, double *a){
    double g = tan(M_PI * fc / (double)FS_HZ);
    b[0] = g/(1.0+g);  b[1] = g/(1.0+g);  b[2] = 0.0;
    a[0] = (g-1.0)/(1.0+g);              a[1] = 0.0;
}
// coeficientes biquad hpf 1 orden
static void hpf1(double fc, double *b, double *a){
    double g = tan(M_PI * fc / (double)FS_HZ);
    b[0] = 1.0/(1.0+g);  b[1] = -1.0/(1.0+g);  b[2] = 0.0;
    a[0] = (g-1.0)/(1.0+g);                    a[1] = 0.0;
}

//Segundo orden (RBJ, 12 dB/oct)
//coeficientes biquad lpf 2 orden
static void lpf2(double fc, double *b, double *a){
    double w0 = 2.0*M_PI*fc/(double)FS_HZ;
    double c = cos(w0), s = sin(w0), al = s/(2.0*0.707);
    double a0 = 1.0 + al;
    b[0] = ((1.0-c)/2.0)/a0;  b[1] = (1.0-c)/a0;  b[2] = b[0];
    a[0] = (-2.0*c)/a0;       a[1] = (1.0-al)/a0;
}
//coeficientes biquad hpf 2 orden
static void hpf2(double fc, double *b, double *a){
    double w0 = 2.0*M_PI*fc/(double)FS_HZ;
    double c = cos(w0), s = sin(w0), al = s/(2.0*0.707);
    double a0 = 1.0 + al;
    b[0] = ((1.0+c)/2.0)/a0;  b[1] = (-(1.0+c))/a0;  b[2] = b[0];
    a[0] = (-2.0*c)/a0;       a[1] = (1.0-al)/a0;
}
int g_tone_order = 1;

// R & C -> Fc
float rc_to_fc(float R_ohm, float C_farad){
    return (float)(1.0 / (2.0*M_PI*(double)R_ohm*(double)C_farad));
}

// Baja los 10 coeficientes del tone blend al PL
void params_push_tone(const params_t *p){
    double b[3], a[2];

    if (g_tone_order == 2) lpf2((double)p->tone_lpf_hz, b, a);
    else                   lpf1((double)p->tone_lpf_hz, b, a);
    Xil_Out32(FX_BASE + FX_OFF_TL_L_B0, d_to_q2_30(b[0]));
    Xil_Out32(FX_BASE + FX_OFF_TL_L_B1, d_to_q2_30(b[1]));
    Xil_Out32(FX_BASE + FX_OFF_TL_L_B2, d_to_q2_30(b[2]));
    Xil_Out32(FX_BASE + FX_OFF_TL_L_A1, d_to_q2_30(a[0]));
    Xil_Out32(FX_BASE + FX_OFF_TL_L_A2, d_to_q2_30(a[1]));

    if (g_tone_order == 2) hpf2((double)p->tone_hpf_hz, b, a);
    else                   hpf1((double)p->tone_hpf_hz, b, a);
    Xil_Out32(FX_BASE + FX_OFF_TL_H_B0, d_to_q2_30(b[0]));
    Xil_Out32(FX_BASE + FX_OFF_TL_H_B1, d_to_q2_30(b[1]));
    Xil_Out32(FX_BASE + FX_OFF_TL_H_B2, d_to_q2_30(b[2]));
    Xil_Out32(FX_BASE + FX_OFF_TL_H_A1, d_to_q2_30(a[0]));
    Xil_Out32(FX_BASE + FX_OFF_TL_H_A2, d_to_q2_30(a[1]));
}

// ============================================================
//  Presets de tone stack
// ============================================================
static const char *preset_names[NUM_PRESETS_TONE] = {
    "BigMuff(scoop)", "TubeScreamer", "Fuzz", "Plano"
};
// Devuelve str preset 
const char *params_preset_name(int idx){
    if (idx < 0 || idx >= NUM_PRESETS_TONE) idx = 0;
    return preset_names[idx];
}
// envía al PL presets según idx.
void params_preset_tone(params_t *p, int idx){
    switch (idx){
        case 0:  // BIG MUFF: R=33k C=0.01uF (oscura) | R=33k C=0.004uF (brillante)
            p->tone_lpf_hz = rc_to_fc(33000.0f, 0.01e-6f);   // ~482 Hz
            p->tone_hpf_hz = rc_to_fc(33000.0f, 0.004e-6f);  // ~1206 Hz
            break;
        case 1:  // TUBE SCREAMER: scoop leve
            p->tone_lpf_hz = 760.0f;
            p->tone_hpf_hz = 1500.0f;
            break;
        case 2:  // FUZZ: esquinas iguales y altas (sin scoop, con cuerpo)
            p->tone_lpf_hz = 1200.0f;
            p->tone_hpf_hz = 1200.0f;
            break;
        default: // PLANO: misma esquina -> con blend 0.5 la respuesta es PLANA
            p->tone_lpf_hz = 900.0f;
            p->tone_hpf_hz = 900.0f;
            break;
    }
    params_push_tone(p);
}

// ============================================================
//  Init
// ===========================================================
void params_init(params_t *p){
    p->dist_drive = 20.0f;   // arranca con mordida (senal de entrada ~0.05-0.2)
    p->dist_level = 0.25f;    // gain staging: la dist. comprime a full-scale
    p->dist_tone  = 0.5f;
    p->tone_lpf_hz = 482.0f;  // Big Muff por defecto
    p->tone_hpf_hz = 1206.0f;

    p->cho_center = 15.0f;  p->cho_depth = 1.5f;  p->cho_rate = 0.4f;  p->cho_wet = 0.5f;
    p->fl_depth   = 2.0f;   p->fl_rate   = 0.4f;  p->fl_fb    = 0.5f;  p->fl_wet  = 0.5f;
    p->trem_rate  = 5.0f;   p->trem_depth = 0.5f;
    p->dly_time   = 300.0f; p->dly_fb    = 0.4f;  p->dly_wet  = 0.5f;

    dist_params[0] = (param_binding_t){ "Drive", &p->dist_drive, 5.0f, 100.0f, 5.0f };
    dist_params[1] = (param_binding_t){ "Level", &p->dist_level, 0.0f, 1.0f,  0.05f };
    dist_params[2] = (param_binding_t){ "Tone",  &p->dist_tone,  0.0f, 1.0f,  0.05f };

    tone_params[0] = (param_binding_t){ "fLPF", &p->tone_lpf_hz, 200.0f, 7000.0f, 50.0f };
    tone_params[1] = (param_binding_t){ "fHPF", &p->tone_hpf_hz, 300.0f, 5000.0f, 50.0f };

    cho_params[0] = (param_binding_t){ "Center", &p->cho_center, 5.0f, 30.0f, 1.0f  };
    cho_params[1] = (param_binding_t){ "Depth",  &p->cho_depth,  0.0f, 8.0f,  0.5f  };
    cho_params[2] = (param_binding_t){ "Rate",   &p->cho_rate,   0.05f,5.0f,  0.1f  };
    cho_params[3] = (param_binding_t){ "Wet",    &p->cho_wet,    0.0f, 1.0f,  0.05f };

    fl_params[0] = (param_binding_t){ "Depth", &p->fl_depth, 0.5f, 2.5f, 0.25f };
    fl_params[1] = (param_binding_t){ "Rate",  &p->fl_rate,  0.05f,3.0f, 0.1f  };
    fl_params[2] = (param_binding_t){ "FB",    &p->fl_fb,    0.0f, 0.9f, 0.05f };
    fl_params[3] = (param_binding_t){ "Wet",   &p->fl_wet,   0.0f, 1.0f, 0.05f };

    trem_params[0] = (param_binding_t){ "Rate",  &p->trem_rate,  0.5f, 15.0f, 0.5f  };
    trem_params[1] = (param_binding_t){ "Depth", &p->trem_depth, 0.0f, 1.0f,  0.05f };

    dly_params[0] = (param_binding_t){ "Time", &p->dly_time, 20.0f, 600.0f, 10.0f };
    dly_params[1] = (param_binding_t){ "FB",   &p->dly_fb,   0.0f,  0.95f,  0.05f };
    dly_params[2] = (param_binding_t){ "Wet",  &p->dly_wet,  0.0f,  1.0f,   0.05f };

    // Synth: patch Minimoog inicial (2 saws + square)
    p->syn_w1 = WAVE_SAW;  p->syn_w2 = WAVE_SAW;  p->syn_w3 = WAVE_SQUARE;
    p->syn_r1 = 0;  p->syn_r2 = 0;  p->syn_r3 = -1;
    p->syn_o2_cents = 7.0f;  p->syn_o3_cents = 0.0f;
    p->syn_l1 = 0.45f;  p->syn_l2 = 0.30f;  p->syn_l3 = 0.20f;
    p->syn_noise = 0.0f;
    p->syn_env_gain = 0.5f;  p->syn_level = 0.9f;  p->syn_dry = 0.5f;

    syn_mix_params[0] = (param_binding_t){ "O1", &p->syn_l1,    0.0f, 1.0f, 0.05f };
    syn_mix_params[1] = (param_binding_t){ "O2", &p->syn_l2,    0.0f, 1.0f, 0.05f };
    syn_mix_params[2] = (param_binding_t){ "O3", &p->syn_l3,    0.0f, 1.0f, 0.05f };
    syn_mix_params[3] = (param_binding_t){ "Nz", &p->syn_noise, 0.0f, 1.0f, 0.05f };

    syn_tune_params[0] = (param_binding_t){ "Tun2", &p->syn_o2_cents, -50.0f, 50.0f, 1.0f };
    syn_tune_params[1] = (param_binding_t){ "Tun3", &p->syn_o3_cents, -1200.0f, 1200.0f, 10.0f };
    syn_tune_params[2] = (param_binding_t){ "EnvG", &p->syn_env_gain, 0.0f, 1.0f, 0.05f };
    syn_tune_params[3] = (param_binding_t){ "Dry",  &p->syn_dry,      0.0f, 1.0f, 0.05f };
}


// ============================================================
//  SYNTH (Minimoog)
// ============================================================
static const char *wave_names[NUM_WAVES] = {
    "tri", "tri-saw", "saw", "square", "pulse-W", "pulse-N"
};
// Devuelve str synth
const char *synth_wave_name(int w){
    if (w < 0 || w >= NUM_WAVES) w = 0;
    return wave_names[w];
}

// ratio de detune desde cents -> Q2.30 (1.0 = 0x40000000)
// Convierte un valor de desafinación en cents (1/100 de semitono) a una relación de frecuencias en  Q2.30
static uint32_t cents_to_q2_30(float cents){
    double ratio = pow(2.0, (double)cents / 1200.0);
    return d_to_q2_30(ratio);
}

// TX config osciladores, mezclas y filtros del synth a memoria FPGA.
void params_push_synth(const params_t *p){
    Xil_Out32(FX_BASE + FX_OFF_SYN_WAVES,  SYN_PACK_WAVES(p->syn_w1, p->syn_w2, p->syn_w3));
    Xil_Out32(FX_BASE + FX_OFF_SYN_RANGES, SYN_PACK_RANGES(p->syn_r1, p->syn_r2, p->syn_r3));
    Xil_Out32(FX_BASE + FX_OFF_SYN_O2_TUNE, cents_to_q2_30(p->syn_o2_cents));
    Xil_Out32(FX_BASE + FX_OFF_SYN_O3_TUNE, cents_to_q2_30(p->syn_o3_cents));
    Xil_Out32(FX_BASE + FX_OFF_SYN_O1_LVL, f_to_q1_31(p->syn_l1));
    Xil_Out32(FX_BASE + FX_OFF_SYN_O2_LVL, f_to_q1_31(p->syn_l2));
    Xil_Out32(FX_BASE + FX_OFF_SYN_O3_LVL, f_to_q1_31(p->syn_l3));
    Xil_Out32(FX_BASE + FX_OFF_SYN_NOISE,  f_to_q1_31(p->syn_noise));
    Xil_Out32(FX_BASE + FX_OFF_SYN_ENV_GAIN, f_to_q1_31(p->syn_env_gain));
    Xil_Out32(FX_BASE + FX_OFF_SYN_LEVEL,  f_to_q1_31(p->syn_level));
    Xil_Out32(FX_BASE + FX_OFF_SYN_DRY_LVL, f_to_q1_31(p->syn_dry));
    // filtro del synth: passthrough (off) por ahora
    Xil_Out32(FX_BASE + FX_OFF_SYN_F_B0, 0x40000000);
    Xil_Out32(FX_BASE + FX_OFF_SYN_F_B1, 0);
    Xil_Out32(FX_BASE + FX_OFF_SYN_F_B2, 0);
    Xil_Out32(FX_BASE + FX_OFF_SYN_F_A1, 0);
    Xil_Out32(FX_BASE + FX_OFF_SYN_F_A2, 0);
}

// Cambio entre forma de onda para un oscilador  (SYNTH++)
void synth_cycle_wave(params_t *p, int osc){
    int *w = (osc==1)?&p->syn_w1 : (osc==2)?&p->syn_w2 : &p->syn_w3;
    *w = (*w + 1) % NUM_WAVES;
    params_push_synth(p);
}

// Cambio transposición de octavas del oscilador (SYNTH++)
void synth_cycle_range(params_t *p, int osc){
    int *r = (osc==1)?&p->syn_r1 : (osc==2)?&p->syn_r2 : &p->syn_r3;
    *r = (*r >= 2) ? -2 : (*r + 1);
    params_push_synth(p);
}

// ============================================================
//  Push completo
// ============================================================
// Envía los valores actuales de todos los parámetros de efectos y sintetizador a los registros del hardware (FPGA).
void params_push_to_pl(const params_t *p){
    // DIST
    Xil_Out32(FX_BASE + FX_OFF_DIST_DRIVE, f_to_q16_16(p->dist_drive));
    Xil_Out32(FX_BASE + FX_OFF_DIST_LEVEL, f_to_q1_31 (p->dist_level));
    Xil_Out32(FX_BASE + FX_OFF_DIST_TONE,  f_to_q1_31 (p->dist_tone));
    params_push_tone(p);
    // CHORUS (ms -> muestras)
    Xil_Out32(FX_BASE + FX_OFF_CHO_CENTER, f_to_q16_16(p->cho_center * 48.0f));
    Xil_Out32(FX_BASE + FX_OFF_CHO_DEPTH,  f_to_q16_16(p->cho_depth  * 48.0f));
    Xil_Out32(FX_BASE + FX_OFF_CHO_RATE,   hz_to_phase_inc(p->cho_rate));
    Xil_Out32(FX_BASE + FX_OFF_CHO_WET,    f_to_q1_31 (p->cho_wet));
    Xil_Out32(FX_BASE + FX_OFF_CHO_LPF_G,  fc_to_tpt_G(5000.0f));
    // FLANGER
    Xil_Out32(FX_BASE + FX_OFF_FL_DEPTH,   f_to_q16_16(p->fl_depth * 48.0f));
    Xil_Out32(FX_BASE + FX_OFF_FL_RATE,    hz_to_phase_inc(p->fl_rate));
    Xil_Out32(FX_BASE + FX_OFF_FL_FB,      f_to_q1_31 (p->fl_fb));
    Xil_Out32(FX_BASE + FX_OFF_FL_WET,     f_to_q1_31 (p->fl_wet));
    // TREMOLO
    Xil_Out32(FX_BASE + FX_OFF_TREM_RATE,  hz_to_phase_inc(p->trem_rate));
    Xil_Out32(FX_BASE + FX_OFF_TREM_DEPTH, f_to_q1_31 (p->trem_depth));
    // DELAY (ms -> muestras)
    Xil_Out32(FX_BASE + FX_OFF_DLY_TIME,   f_to_q16_16(p->dly_time * 48.0f));
    Xil_Out32(FX_BASE + FX_OFF_DLY_FB,     f_to_q1_31 (p->dly_fb));
    Xil_Out32(FX_BASE + FX_OFF_DLY_WET,    f_to_q1_31 (p->dly_wet));
    params_push_synth(p);
}

// ============================================================
//  Navegacion / encoders / print
// ===========================================================
// Avanza a la siguiente página o pantalla de parámetros en el menú
void params_screen_next(void){ g_screen=(g_screen+1)%NUM_SCREENS; }
// Retrocede a la página o pantalla de parámetros anterior en el menú
void params_screen_prev(void){ g_screen=(g_screen-1+NUM_SCREENS)%NUM_SCREENS; }
// Obtiene el título de la pantalla actual para mostrarlo en el display
const char *params_screen_title(void){ return screens[g_screen].title; }

// Modifica el valor de un parámetro, limitándolo entre min y max
static void edit_param(int idx,int delta){
    screen_def_t *s=&screens[g_screen];
    if(idx<0||idx>=s->n) return;
    param_binding_t *b=&s->params[idx];
    *(b->value)=clampf(*(b->value)+delta*b->step, b->min, b->max);
}

// Procesa los encodersy actualiza el hardware
void params_handle_encoder(params_t *p,int enc,int delta){
    if(delta==0||enc<0||enc>=NUM_ENCODERS) return;
    enc_map_t m=enc_map[enc];
    switch(m.role){
        case ROLE_PARAM:    edit_param(m.param_idx,delta); break;
        case ROLE_NAV_NEXT: (delta>0)?params_screen_next():params_screen_prev(); break;
        case ROLE_NAV_PREV: (delta>0)?params_screen_prev():params_screen_next(); break;
    }
    params_push_to_pl(p);
}

// Imprime los parámetros de la pantalla actual vía puerto serie (UART) para depuración.
void params_print(const params_t *p){
    (void)p;
    screen_def_t *s=&screens[g_screen];
    xil_printf("[%s]", s->title);
    for (int i=0;i<s->n;i++){
        param_binding_t *b=&s->params[i];
        int ent = (int)(*b->value);
        int dec = (int)(((*b->value) - (float)ent) * 100.0f);
        if (dec<0) dec=-dec;
        xil_printf(" %s=%d.%02d", b->name, ent, dec);
    }
    xil_printf("\r\n");
}

// ============================================================
//  Funciones Maestras (Setup)
// ============================================================
// Enable global efectos
void params_master_enable(int on) {
    uint32_t ctrl = Xil_In32(FX_BASE + FX_OFF_CTRL);
    if (on) ctrl |= 1u;
    else    ctrl &= ~1u;
    Xil_Out32(FX_BASE + FX_OFF_CTRL, ctrl);
}

// Configuración conjunta delay-synth
void params_set_mode(int synth_on, int synth_only, int delay_on) {
    uint32_t fxen = Xil_In32(FX_BASE + FX_OFF_FX_EN);
    fxen &= ~(FXB_SYNTH | FXB_SYNTH_ONLY | FXB_DELAY);
    
    if (synth_on) fxen |= FXB_SYNTH;
    if (synth_on && synth_only) fxen |= FXB_SYNTH_ONLY;
    if (delay_on) fxen |= FXB_DELAY;
    
    Xil_Out32(FX_BASE + FX_OFF_FX_EN, fxen);
}

// Carga default del synth
void params_load_wavetables(void) {
    // OSC1
    Xil_Out32(FX_BASE + FX_OFF_SYN_WAVES, (WAVE_SAW & 0x7u) | ((WAVE_SAW & 0x7u) << 3) | ((WAVE_SAW & 0x7u) << 6));
    Xil_Out32(FX_BASE + FX_OFF_SYN_RANGES, (0 & 0xFu) | ((0 & 0xFu) << 4) | ((0 & 0xFu) << 8));
    Xil_Out32(FX_BASE + FX_OFF_SYN_O1_LVL, f_to_q1_31(0.70f));
    
    // OSC2
    Xil_Out32(FX_BASE + FX_OFF_SYN_O2_TUNE, d_to_q2_30(1.0)); // +0 cents
    Xil_Out32(FX_BASE + FX_OFF_SYN_O2_LVL, f_to_q1_31(0.00f));
    
    // OSC3
    Xil_Out32(FX_BASE + FX_OFF_SYN_O3_TUNE, d_to_q2_30(1.0)); // +0 cents
    Xil_Out32(FX_BASE + FX_OFF_SYN_O3_LVL, f_to_q1_31(0.00f));
    
    // Noise
    Xil_Out32(FX_BASE + FX_OFF_SYN_NOISE, f_to_q1_31(0.0f));
}