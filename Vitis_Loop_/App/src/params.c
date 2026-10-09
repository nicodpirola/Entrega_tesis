#include "params.h"
#include "fx_regmap.h"
#include "xil_io.h"
#include "xil_printf.h"
#include <float.h>
#include <math.h>
#include <string.h>
#include <stdint.h>

#define CAB_IR_BANK_DATA
#include "cab_ir_bank.h"

/* -------------------------------------------------------------------------
 * Primitivas de comunicacion AXI-Lite (HAL de hardware)
 * ------------------------------------------------------------------------- */
static inline u32 fx_hw_read(UINTPTR base, u32 offset) {
    return Xil_In32(base + offset);
}

static inline void fx_hw_write(UINTPTR base, u32 offset, u32 value) {
    Xil_Out32(base + offset, value);
}

static inline void fx_hw_update_bits(UINTPTR base, u32 offset, u32 mask, u32 value) {
    u32 current = fx_hw_read(base, offset);
    fx_hw_write(base, offset, (current & ~mask) | (value & mask));
}

static inline void fx_hw_commit(UINTPTR base) {
    fx_hw_write(base, FX_REG_CORE_COMMAND, FX_COMMAND_COMMIT);
}

static inline int fx_hw_probe(UINTPTR base) {
    return (fx_hw_read(base, FX_REG_CORE_ID) == FX_CORE_ID_VALUE) &&
           (fx_hw_read(base, FX_REG_CORE_VERSION) == FX_CORE_VERSION_VALUE);
}

/* -------------------------------------------------------------------------
 * Simulador de gabinete (Cabsim / Respuestas al impulso BRAM)
 * ------------------------------------------------------------------------- */
static int cab_ir_loaded = -1;

void cab_load_ir(const int32_t *h, int n) {
    if (n > CAB_IR_TAPS) n = CAB_IR_TAPS;
    Xil_Out32(FX_BASE + FX_REG_CAB_COEF_ADDR, 0u);
    for (int i = 0; i < CAB_IR_TAPS; i++) {
        int32_t c = (i < n) ? h[i] : 0;
        if (c >  131071) c =  131071;
        if (c < -131072) c = -131072;
        Xil_Out32(FX_BASE + FX_REG_CAB_COEF_DATA, (uint32_t)c & 0x3FFFFu);
    }
}

void cab_select_ir(int idx) {
    if (idx < 0 || idx >= CAB_IR_COUNT || idx == cab_ir_loaded) return;
    cab_load_ir(CAB_IR_BANK[idx], CAB_IR_TAPS);
    cab_ir_loaded = idx;
}

int cab_ir_count(void) { return CAB_IR_COUNT; }

const char *cab_ir_name(int idx) {
    return (idx >= 0 && idx < CAB_IR_COUNT) ? CAB_IR_NAMES[idx] : "?";
}



static float clampf(float value, float low, float high) {
    return value < low ? low : (value > high ? high : value);
}

static u32 float_to_q16_16(float value) {
    if (value <= 0.0f) return 0u;
    if (value >= 65535.999f) return 0xFFFFFFFFu;
    return (u32)(value * 65536.0f + 0.5f);
}

static u32 float_to_q1_31(float value) {
    if (value >= 1.0f) return 0x7FFFFFFFu;
    if (value <= -1.0f) return 0x80000000u;
    return (u32)(s32)(value * 2147483648.0f);
}

static u32 double_to_q2_30(double value) {
    double scaled = value * 1073741824.0;
    if (scaled > 2147483647.0) scaled = 2147483647.0;
    if (scaled < -2147483648.0) scaled = -2147483648.0;
    return (u32)(s32)(scaled < 0.0 ? scaled - 0.5 : scaled + 0.5);
}

static u32 hz_to_phase_inc(float hz) {
    double inc;
    if (hz <= 0.0f) return 0u;
    inc = (double)hz * 4294967296.0 / (double)FS_HZ;
    if (inc >= 4294967295.0) return 0xFFFFFFFFu;
    return (u32)(inc + 0.5);
}

static u32 ms_to_samples_q16_16(float ms) {
    return float_to_q16_16(ms * ((float)FS_HZ / 1000.0f));
}

static u32 cents_to_q2_30(float cents) {
    return double_to_q2_30(pow(2.0, (double)cents / 1200.0));
}

static u32 cutoff_to_tpt_g(float cutoff_hz) {
    double g = tan(M_PI * (double)cutoff_hz / (double)FS_HZ);
    return float_to_q1_31((float)(g / (1.0 + g)));
}

static void lpf1(double fc, double *b, double *a) {
    double g = tan(M_PI * fc / (double)FS_HZ);
    b[0] = g / (1.0 + g); b[1] = b[0]; b[2] = 0.0;
    a[0] = (g - 1.0) / (1.0 + g); a[1] = 0.0;
}

static void hpf1(double fc, double *b, double *a) {
    double g = tan(M_PI * fc / (double)FS_HZ);
    b[0] = 1.0 / (1.0 + g); b[1] = -b[0]; b[2] = 0.0;
    a[0] = (g - 1.0) / (1.0 + g); a[1] = 0.0;
}

static void write_tone(const params_t *p) {
    double b[3], a[2];
    lpf1((double)p->tone_lpf_hz, b, a);
    fx_hw_write(FX_BASE, FX_REG_TONE_L_B0, double_to_q2_30(b[0]));
    fx_hw_write(FX_BASE, FX_REG_TONE_L_B1, double_to_q2_30(b[1]));
    fx_hw_write(FX_BASE, FX_REG_TONE_L_B2, double_to_q2_30(b[2]));
    fx_hw_write(FX_BASE, FX_REG_TONE_L_A1, double_to_q2_30(a[0]));
    fx_hw_write(FX_BASE, FX_REG_TONE_L_A2, double_to_q2_30(a[1]));
    hpf1((double)p->tone_hpf_hz, b, a);
    fx_hw_write(FX_BASE, FX_REG_TONE_H_B0, double_to_q2_30(b[0]));
    fx_hw_write(FX_BASE, FX_REG_TONE_H_B1, double_to_q2_30(b[1]));
    fx_hw_write(FX_BASE, FX_REG_TONE_H_B2, double_to_q2_30(b[2]));
    fx_hw_write(FX_BASE, FX_REG_TONE_H_A1, double_to_q2_30(a[0]));
    fx_hw_write(FX_BASE, FX_REG_TONE_H_A2, double_to_q2_30(a[1]));
}

/* Shelf suave: graves sin realce y agudos ajustables, centro en 3 kHz. */
static void write_eq(const params_t *p) {
    static const u32 coef[7][5] = {
        { 0x40000000u, 0x00000000u, 0x00000000u, 0x00000000u, 0x00000000u }, /* +0 dB */
        { 0x46733CA8u, 0xCFD3662Eu, 0x00000000u, 0xD646A2D6u, 0x00000000u }, /* +1 dB */
        { 0x4D8C30FFu, 0xC9CEB16Eu, 0x00000000u, 0xD75AE26Cu, 0x00000000u }, /* +2 dB */
        { 0x555AA7BEu, 0xC31EC309u, 0x00000000u, 0xD8796AC7u, 0x00000000u }, /* +3 dB */
        { 0x5DEFC338u, 0xBBB28E22u, 0x00000000u, 0xD9A25159u, 0x00000000u }, /* +4 dB */
        { 0x675E146Fu, 0xB3778FA2u, 0x00000000u, 0xDAD5A411u, 0x00000000u }, /* +5 dB */
        { 0x71B9B2F8u, 0xAA59B5BDu, 0x00000000u, 0xDC1368B5u, 0x00000000u } /* +6 dB */
    };
    int db = p->eq_agudos_db;
    if (db < 0) db = 0;
    if (db > 6) db = 6;
    fx_hw_write(FX_BASE, FX_REG_EQ_B0, coef[db][0]);
    fx_hw_write(FX_BASE, FX_REG_EQ_B1, coef[db][1]);
    fx_hw_write(FX_BASE, FX_REG_EQ_B2, coef[db][2]);
    fx_hw_write(FX_BASE, FX_REG_EQ_A1, coef[db][3]);
    fx_hw_write(FX_BASE, FX_REG_EQ_A2, coef[db][4]);
}

/* Redondeo y limite antes de convertir a entero. */
static u32 synth_fixed(double value, unsigned fractional_bits) {
    double scaled = ldexp(value, (int)fractional_bits);
    scaled = scaled < 0.0 ? ceil(scaled - 0.5) : floor(scaled + 0.5);
    if (scaled > 2147483647.0) scaled = 2147483647.0;
    if (scaled < -2147483648.0) scaled = -2147483648.0;
    return (u32)(s32)scaled;
}

static u32 synth_pulse_width(float duty) {
    return (u32)((double)clampf(duty, 0.05f, 0.95f) * 4294967296.0 + 0.5);
}

static u32 synth_env_coefficient(float time_ms) {
    double tau = (double)clampf(time_ms, 1.0f, 2000.0f) * 0.001;
    return synth_fixed(exp(-1.0 / (tau * FS_HZ)), 31);
}

static void write_synth_filter(const params_t *p) {
    double fc = clampf(p->syn_cutoff_hz, 20.0f, 12000.0f);
    double q = clampf(p->syn_resonance_q, 0.50f, 10.0f);
    double g = tan(M_PI * fc / FS_HZ), k = 1.0 / q;
    double a1 = 1.0 / (1.0 + g * (g + k));
    u32 ctrl = p->syn_filter_mode >= 1 && p->syn_filter_mode <= 3
             ? 1u | ((u32)(p->syn_filter_mode - 1) << 1) : 0u;
    fx_hw_write(FX_BASE, FX_REG_SYNTH_SVF_CTRL, ctrl);
    fx_hw_write(FX_BASE, FX_REG_SYNTH_SVF_A1, synth_fixed(a1, 31));
    fx_hw_write(FX_BASE, FX_REG_SYNTH_SVF_A2, synth_fixed(g * a1, 31));
    fx_hw_write(FX_BASE, FX_REG_SYNTH_SVF_A3, synth_fixed(g * g * a1, 31));
    fx_hw_write(FX_BASE, FX_REG_SYNTH_SVF_K, synth_fixed(k, 29));
}

static void write_synth(const params_t *p) {
    fx_hw_write(FX_BASE, FX_REG_SYNTH_CTRL,
        FX_SYNTH_ENABLE | ((u32)(p->syn_output >= 0 && p->syn_output <= 2 ? p->syn_output : (int)FX_SYNTH_OUTPUT_MIX) << FX_SYNTH_OUTPUT_SHIFT));
    fx_hw_write(FX_BASE, FX_REG_OSC1_CTRL,
        FX_OSC1_CTRL(p->syn_osc1_mode, p->syn_osc1_range, p->syn_harmonics));
    fx_hw_write(FX_BASE, FX_REG_OSC1_PW, synth_pulse_width(p->syn_pw1));
    fx_hw_write(FX_BASE, FX_REG_OSC1_LEVEL, float_to_q1_31(p->syn_l1));
    fx_hw_write(FX_BASE, FX_REG_OSC2_CTRL,
        FX_OSC2_CTRL(p->syn_osc2_wave, p->syn_osc2_range));
    fx_hw_write(FX_BASE, FX_REG_OSC2_PW, synth_pulse_width(p->syn_pw2));
    fx_hw_write(FX_BASE, FX_REG_OSC2_DETUNE, cents_to_q2_30(p->syn_o2_cents));
    fx_hw_write(FX_BASE, FX_REG_OSC2_LEVEL, float_to_q1_31(p->syn_l2));
    fx_hw_write(FX_BASE, FX_REG_NOISE_CTRL, 0u);
    fx_hw_write(FX_BASE, FX_REG_NOISE_LEVEL, 0u);
    fx_hw_write(FX_BASE, FX_REG_SYNTH_BUS_TRIM, float_to_q1_31(p->syn_bus_trim));
    fx_hw_write(FX_BASE, FX_REG_ENV_GAIN, float_to_q1_31(p->syn_env_gain));
    fx_hw_write(FX_BASE, FX_REG_FRONTEND_CTRL, FX_FRONTEND_PITCH | FX_FRONTEND_ENVELOPE);
    fx_hw_write(FX_BASE, FX_REG_ENV_ATTACK, synth_env_coefficient(p->syn_attack_ms));
    fx_hw_write(FX_BASE, FX_REG_ENV_RELEASE, synth_env_coefficient(p->syn_release_ms));
    double gate_on = clampf(p->syn_gate_on, 0.001f, 0.100f);
    double gate_off = clampf(p->syn_gate_off, 0.0f, (float)(gate_on - 0.001));
    fx_hw_write(FX_BASE, FX_REG_GATE_ON_THR, synth_fixed(gate_on, 29));
    fx_hw_write(FX_BASE, FX_REG_GATE_OFF_THR, synth_fixed(gate_off, 29));
    fx_hw_write(FX_BASE, FX_REG_PITCH_CTRL,
                p->syn_instrumento == 1 ? FX_PITCH_CTRL_THEREMIN : FX_PITCH_CTRL_GUITARRA);
    fx_hw_write(FX_BASE, FX_REG_PITCH_CFG2, FX_PITCH_CFG2_DEFAULT);
    fx_hw_write(FX_BASE, FX_REG_GLIDE_CTRL, 0u);
    write_synth_filter(p);
    fx_hw_write(FX_BASE, FX_REG_SYNTH_OUT_CTRL, 0u);
    fx_hw_write(FX_BASE, FX_REG_SYNTH_MASTER, float_to_q1_31(p->syn_level));
}

int params_hw_compatible(void) { return fx_hw_probe(FX_BASE); }

void params_init(params_t *p) {
    p->dist_drive = 50.0f; p->dist_level = 1.0f; p->dist_tone = 0.5f;
    p->eq_agudos_db = 0;
    p->tone_lpf_hz = 482.0f; p->tone_hpf_hz = 1206.0f;
    p->cho_center = 15.0f; p->cho_depth = 1.5f; p->cho_rate = 0.4f; p->cho_wet = 0.5f;
    p->fl_center = 3.0f; p->fl_depth = 2.0f; p->fl_rate = 0.4f; p->fl_fb = 0.5f; p->fl_wet = 0.5f;
    p->trem_rate = 5.0f; p->trem_depth = 0.5f;
    p->dly_time = 300.0f; p->dly_fb = 0.4f; p->dly_wet = 0.5f;
    /* Phaser: mismos valores que el reset del RTL (1 Hz, 300-1600 Hz, FB 0.3) */
    p->ph_rate = 1.0f; p->ph_fmin = 300.0f; p->ph_fmax = 1600.0f; p->ph_fb = 0.3f;
    p->syn_osc1_mode = FX_OSC1_SAW_UP; p->syn_osc2_wave = FX_OSC2_SAW_UP;
    p->syn_osc1_range = FX_RANGE_8; p->syn_osc2_range = FX_RANGE_8; p->syn_harmonics = 1;
    p->syn_o2_cents = 0.0f;
    p->syn_l1 = 0.55f; p->syn_l2 = 0.30f;
    p->syn_bus_trim = 0.35f; p->syn_env_gain = 0.5f; p->syn_level = 0.9f;
    p->syn_pw1 = 0.5f; p->syn_pw2 = 0.5f;
    p->syn_output = FX_SYNTH_OUTPUT_MIX;
    p->syn_filter_mode = 0; p->syn_cutoff_hz = 1000.0f; p->syn_resonance_q = 0.71f;
    p->syn_attack_ms = 1.0f; p->syn_release_ms = 20.0f;
    p->syn_gate_on = 0.010f; p->syn_gate_off = 0.001f;
    p->syn_instrumento = 0;
}

void params_push_tone(const params_t *p) { write_tone(p); fx_hw_commit(FX_BASE); }
void params_push_synth(const params_t *p) { write_synth(p); fx_hw_commit(FX_BASE); }

void params_push_to_pl(const params_t *p) {
    fx_od_request(p->dist_drive, p->dist_tone, p->dist_level);
    write_eq(p);
    write_tone(p);
    fx_hw_write(FX_BASE, FX_REG_CHORUS_CTRL, 1u);
    fx_hw_write(FX_BASE, FX_REG_CHORUS_CENTER, ms_to_samples_q16_16(p->cho_center));
    fx_hw_write(FX_BASE, FX_REG_CHORUS_DEPTH, ms_to_samples_q16_16(p->cho_depth));
    fx_hw_write(FX_BASE, FX_REG_CHORUS_RATE, hz_to_phase_inc(p->cho_rate));
    fx_hw_write(FX_BASE, FX_REG_CHORUS_WET, float_to_q1_31(p->cho_wet));
    fx_hw_write(FX_BASE, FX_REG_CHORUS_LPF_G, cutoff_to_tpt_g(5000.0f));
    fx_hw_write(FX_BASE, FX_REG_FLANGER_CTRL, 0u);
    fx_hw_write(FX_BASE, FX_REG_FLANGER_CENTER, ms_to_samples_q16_16(p->fl_center));
    fx_hw_write(FX_BASE, FX_REG_FLANGER_DEPTH, ms_to_samples_q16_16(p->fl_depth));
    fx_hw_write(FX_BASE, FX_REG_FLANGER_RATE, hz_to_phase_inc(p->fl_rate));
    fx_hw_write(FX_BASE, FX_REG_FLANGER_FB, float_to_q1_31(p->fl_fb));
    fx_hw_write(FX_BASE, FX_REG_FLANGER_WET, float_to_q1_31(p->fl_wet));
    fx_hw_write(FX_BASE, FX_REG_TREMOLO_CTRL, 0u);
    fx_hw_write(FX_BASE, FX_REG_TREMOLO_RATE, hz_to_phase_inc(p->trem_rate));
    fx_hw_write(FX_BASE, FX_REG_TREMOLO_DEPTH, float_to_q1_31(p->trem_depth));
    /* Phaser: G = g/(1+g), g = tan(pi*fc/fs) (TPT, ver fx_phaser.sv) */
    fx_hw_write(FX_BASE, FX_REG_PHASER_CTRL, 0u);
    fx_hw_write(FX_BASE, FX_REG_PHASER_RATE, hz_to_phase_inc(p->ph_rate));
    fx_hw_write(FX_BASE, FX_REG_PHASER_GMIN, cutoff_to_tpt_g(p->ph_fmin));
    fx_hw_write(FX_BASE, FX_REG_PHASER_GMAX, cutoff_to_tpt_g(p->ph_fmax));
    fx_hw_write(FX_BASE, FX_REG_PHASER_FB, float_to_q1_31(p->ph_fb));
    fx_hw_write(FX_BASE, FX_REG_DELAY_CTRL, 0u);
    fx_hw_write(FX_BASE, FX_REG_DELAY_TIME, ms_to_samples_q16_16(p->dly_time));
    fx_hw_write(FX_BASE, FX_REG_DELAY_FB, float_to_q1_31(p->dly_fb));
    fx_hw_write(FX_BASE, FX_REG_DELAY_WET, float_to_q1_31(p->dly_wet));
    write_synth(p);
    fx_hw_commit(FX_BASE);
}

void params_master_enable(int on) {
    fx_hw_update_bits(FX_BASE, FX_REG_CORE_CTRL, FX_CORE_ENABLE, on ? FX_CORE_ENABLE : 0u);
    fx_hw_commit(FX_BASE);
}

void params_set_mode(int synth_on, int tracking_on, int delay_on) {
    u32 fx_enable = fx_hw_read(FX_BASE, FX_REG_FX_ENABLE);
    (void)tracking_on; // La voz siempre sigue pitch y envolvente.
    u32 frontend = FX_FRONTEND_PITCH | FX_FRONTEND_ENVELOPE;
    fx_hw_write(FX_BASE, FX_REG_SOURCE_CTRL, synth_on ? FX_SOURCE_SYNTH : 0u);
    fx_hw_write(FX_BASE, FX_REG_FRONTEND_CTRL, frontend);
    fx_hw_write(FX_BASE, FX_REG_SYNTH_CTRL,
        synth_on ? FX_SYNTH_ENABLE | (FX_SYNTH_OUTPUT_MIX << FX_SYNTH_OUTPUT_SHIFT) : 0u);
    fx_enable &= ~FX_EN_DELAY;
    if (delay_on) fx_enable |= FX_EN_DELAY;
    fx_hw_write(FX_BASE, FX_REG_FX_ENABLE, fx_enable);
    fx_hw_commit(FX_BASE);
}

void params_load_wavetables(void) {
    int i;
    for (i = 0; i < 32; ++i)
        fx_hw_write(FX_BASE, FX_REG_ADD_AMP_BASE + (u32)(4 * i), i == 0 ? 0x7FFFFFFFu : 0u);
}

static const char *preset_names[NUM_PRESETS_TONE] = {
    "BigMuff(scoop)", "TubeScreamer", "Fuzz", "Plano"
};

const char *params_preset_name(int idx) {
    return preset_names[(idx >= 0 && idx < NUM_PRESETS_TONE) ? idx : 0];
}

void params_preset_tone(params_t *p, int idx) {
    switch (idx) {
        case 0: p->tone_lpf_hz = 482.0f; p->tone_hpf_hz = 1206.0f; break;
        case 1: p->tone_lpf_hz = 760.0f; p->tone_hpf_hz = 1500.0f; break;
        case 2: p->tone_lpf_hz = 1200.0f; p->tone_hpf_hz = 1200.0f; break;
        default: p->tone_lpf_hz = 900.0f; p->tone_hpf_hz = 900.0f; break;
    }
    params_push_tone(p);
}


void synth_cycle_wave(params_t *p, int osc) {
    if (osc == 1) p->syn_osc1_mode = (p->syn_osc1_mode + 1) % 4;
    else if (osc == 2) p->syn_osc2_wave = (p->syn_osc2_wave + 1) % 3;
    params_push_synth(p);
}

void synth_cycle_range(params_t *p, int osc) {
    int *range;
    if (osc != 1 && osc != 2) return;
    range = osc == 1 ? &p->syn_osc1_range : &p->syn_osc2_range;
    *range = (*range + 1) % 5;
    params_push_synth(p);
}

const char *synth_wave_name(int osc, int wave) {
    static const char *osc1_names[] = { "additive", "saw up", "saw down", "pulse" };
    static const char *osc2_names[] = { "saw up", "saw down", "pulse" };
    if (osc == 1 && wave >= 0 && wave < 4) return osc1_names[wave];
    if (osc == 2 && wave >= 0 && wave < 3) return osc2_names[wave];
    return "invalid";
}

/* -------------------------------------------------------------------------
 * Driver de Overdrive / Distorsion (modelado no lineal Yeh y filtros TPT)
 * ------------------------------------------------------------------------- */
#define FX_OD_INPUT_SENSITIVITY 1.7
#define OD_PI 3.14159265358979323846
#define OD_FS 48000.0
#define OD_TABLE_CHUNK 128u
#define OD_DRIVE_SETTLE_MS 60u
#define OD_COMMIT_TIMEOUT_MS 1000u

enum { OD_IDLE, OD_LOADING, OD_COMMIT };
typedef struct { double drive, tone, level; } od_parameters_t;
static od_parameters_t wanted;
static u32 revision, applied_revision, pending_revision;
static u32 load_index, load_bank, pending_bank, commit_ms, drive_changed_ms;
static unsigned factor;
static double load_drive, seen_drive, bank_drive[2];
static int state, checked, failed, bank_valid[2], have_applied;

static double limit(double x, double low, double high) {
    return x < low ? low : (x > high ? high : x);
}

static int quantize(double x, int fractional_bits, u32 *word) {
    double scaled = ldexp(x, fractional_bits);
    double rounded;
    if (!isfinite(scaled)) return -1;
    rounded = scaled < 0.0 ? -floor(-scaled + 0.5) : floor(scaled + 0.5);
    if (rounded < -2147483648.0 || rounded > 2147483647.0) return -1;
    *word = (u32)(s32)rounded;
    return 0;
}

static int fx_od_coefficients(double drive, double tone, double level, unsigned os_factor,
                              double sensitivity, u32 words[12]) {
    double fs, r2, wz, wc, rl, rr, parallel, y, w, wp, x, k;
    double b1, b0, a1, a0, c, den;
    double coeff[12];
    static const int bits[12] = {31,31,31,31,23,30,30,30,30,30,31,29};
    if (!words || !isfinite(drive) || !isfinite(tone) || !isfinite(level) ||
        !isfinite(sensitivity) || drive < 0.0 || drive > 1.0 ||
        tone < 0.0 || tone > 1.0 || level < 0.0 || level >= 4.0 ||
        sensitivity <= 0.0 || (os_factor != 2 && os_factor != 4 && os_factor != 8)) return -1;
    fs = OD_FS * os_factor;
    r2 = 51000.0 + 500000.0 * drive;
    wz = 1.0 / (4700.0 * 47e-9);
    wc = 1.0 / (r2 * 51e-12);
    coeff[0] = (2.0 * OD_PI * 15.9) / (2.0 * OD_FS + 2.0 * OD_PI * 15.9);
    coeff[1] = (2.0 * OD_PI * 15.6) / (2.0 * OD_FS + 2.0 * OD_PI * 15.6);
    coeff[2] = wz / (2.0 * fs + wz);
    coeff[3] = wc / (2.0 * fs + wc);
    coeff[4] = (r2 / 4700.0) * sensitivity;

    rl = 20000.0 * tone; rr = 20000.0 * (1.0 - tone);
    parallel = rl * rr / (rl + rr);
    y = (rl + rr) * (220.0 + parallel);
    w = y / (rl * 1000.0 + y);
    wz = 1.0 / (0.22e-6 * (220.0 + parallel));
    wp = 1.0 / (0.22e-6 * (1000.0 * 10000.0 / 11000.0));
    x = rr / (rl + rr) * wz;
    k = (rl * 1000.0 + y) / (y * 1000.0 * 0.22e-6);
    b1 = k; b0 = k * w * wz; a1 = wp + wz + x; a0 = wp * wz;
    c = 2.0 * fs; den = a0 + a1 * c + c * c;
    coeff[5] = (b0 + b1 * c) / den;
    coeff[6] = 2.0 * b0 / den;
    coeff[7] = (b0 - b1 * c) / den;
    coeff[8] = (2.0 * a0 - 2.0 * c * c) / den;
    coeff[9] = (a0 - a1 * c + c * c) / den;
    wc = 1.0 / 0.101;
    coeff[10] = wc / (2.0 * fs + wc);
    coeff[11] = level;
    for (unsigned i = 0; i < 12; ++i)
        if (quantize(coeff[i], bits[i], &words[i]) != 0) return -1;
    a1 = (double)(s32)words[8] / 1073741824.0;
    a0 = (double)(s32)words[9] / 1073741824.0;
    if (fabs(a0) >= 1.0 || 1.0 + a1 + a0 <= 0.0 || 1.0 - a1 + a0 <= 0.0) return -1;
    return 0;
}

static int fx_od_table_word(u32 index, double drive, double sensitivity, u32 *word) {
    double u, r2, diode_c, lo, hi, v, f, candidate, exponential, inv;
    const double vt = 1.752 * 0.02585;
    u32 node;
    if (!word || index >= FX_OD_TABLE_DEPTH || !isfinite(drive) ||
        !isfinite(sensitivity) || drive < 0.0 || drive > 1.0 || sensitivity <= 0.0) return -1;
    if (index < 128u) node = index << 5;
    else if (index == 2560u) node = 0x80000000u;
    else {
        unsigned exponent = 12u + (index - 128u) / 128u;
        node = (1u << exponent) + ((index & 127u) << (exponent - 7u));
    }
    u = (double)node / 1048576.0;
    if (u == 0.0) { *word = 0; return 0; }
    r2 = 51000.0 + 500000.0 * drive;
    diode_c = 2.0 * r2 * 2.52e-9;
    lo = 0.0; hi = fmin(u, vt * asinh(u / diode_c)); v = hi;
    for (unsigned i = 0; i < 80; ++i) {
        exponential = exp(v / vt); inv = 1.0 / exponential;
        f = v + 0.5 * diode_c * (exponential - inv) - u;
        if (fabs(f) <= 1e-12 + 16.0 * DBL_EPSILON * u)
            return quantize(v / sensitivity, 29, word);
        if (f < 0.0) lo = v; else hi = v;
        candidate = v - f / (1.0 + 0.5 * diode_c / vt * (exponential + inv));
        v = candidate >= lo && candidate <= hi ? candidate : 0.5 * (lo + hi);
    }
    return -1;
}

void fx_od_init(void) {
    memset(&wanted, 0, sizeof(wanted));
    revision = applied_revision = pending_revision = 0;
    load_index = load_bank = pending_bank = commit_ms = drive_changed_ms = 0;
    factor = 0; seen_drive = -1.0; load_drive = 0.0;
    state = OD_IDLE; checked = failed = have_applied = 0;
    bank_valid[0] = bank_valid[1] = 0;
}

void fx_od_request(float drive_percent, float tone, float level) {
    od_parameters_t next;
    if (!isfinite(drive_percent) || !isfinite(tone) || !isfinite(level)) return;
    next.drive = limit((double)drive_percent / 100.0, 0.0, 1.0);
    next.tone = limit((double)tone, 0.0, 1.0);
    next.level = limit((double)level, 0.0, 1.0);
    if (revision && wanted.drive == next.drive && wanted.tone == next.tone && wanted.level == next.level) return;
    wanted = next; ++revision;
}

static void od_fail(int code) {
    failed = 1;
    xil_printf("[OD] Error %d: revisar VERSION, OD_STATUS y commit.\r\n", code);
}

static void od_apply(UINTPTR base, u32 bank, u32 now_ms) {
    u32 words[12];
    if (fx_od_coefficients(wanted.drive, wanted.tone, wanted.level, factor,
                           FX_OD_INPUT_SENSITIVITY, words) != 0) { od_fail(4); return; }
    for (u32 i = 0; i < 12; ++i) fx_hw_write(base, FX_REG_OD_INPUT1_G + 4u * i, words[i]);
    fx_hw_write(base, FX_REG_OD_CTRL, bank);
    pending_bank = bank; pending_revision = revision; commit_ms = now_ms;
    fx_hw_commit(base); state = OD_COMMIT;
}

void fx_od_service(UINTPTR base, u32 now_ms) {
    u32 status, active, info, word, count;
    if (!revision || failed) return;
    if (!checked) {
        info = fx_hw_read(base, FX_REG_OD_INFO);
        factor = info & 0xFFu;
        if (!fx_hw_probe(base) || (info >> 16) != FX_OD_TABLE_DEPTH ||
            (factor != 2 && factor != 4 && factor != 8)) { od_fail(1); return; }
        checked = 1;
    }
    if (wanted.drive != seen_drive) { seen_drive = wanted.drive; drive_changed_ms = now_ms; }
    if (state == OD_COMMIT) {
        if (fx_hw_read(base, FX_REG_CORE_STATUS) & 2u) {
            if ((u32)(now_ms - commit_ms) > OD_COMMIT_TIMEOUT_MS) od_fail(2);
            return;
        }
        status = fx_hw_read(base, FX_REG_OD_STATUS);
        if (((status >> 1) & 1u) != pending_bank || !(status & (FX_OD_STATUS_LOADED0 << pending_bank))) {
            od_fail(3); return;
        }
        applied_revision = pending_revision;
        state = OD_IDLE;
        if (!have_applied) xil_printf("[OD] Listo: Yeh, %ux, tabla %u puntos.\r\n", factor, FX_OD_TABLE_DEPTH);
        have_applied = 1;
        return;
    }
    if (state == OD_LOADING && load_drive != wanted.drive) state = OD_IDLE;
    if (fx_hw_read(base, FX_REG_CORE_STATUS) & 2u) return;
    if (state == OD_IDLE) {
        if (applied_revision == revision) return;
        status = fx_hw_read(base, FX_REG_OD_STATUS);
        active = (status >> 1) & 1u;
        for (u32 i = 0; i < 2; ++i)
            if (!(status & (FX_OD_STATUS_LOADED0 << i))) bank_valid[i] = 0;
        if (bank_valid[active] && bank_drive[active] == wanted.drive) { od_apply(base, active, now_ms); return; }
        if (have_applied && (u32)(now_ms - drive_changed_ms) < OD_DRIVE_SETTLE_MS) return;
        load_bank = active ^ 1u;
        if (bank_valid[load_bank] && bank_drive[load_bank] == wanted.drive) { od_apply(base, load_bank, now_ms); return; }
        load_drive = wanted.drive; load_index = 0; bank_valid[load_bank] = 0;
        fx_hw_write(base, FX_REG_OD_COMMAND, FX_OD_COMMAND_CLEAR);
        fx_hw_write(base, FX_REG_DIST_WT_ADDR, FX_OD_WT_ADDR(load_bank, 0));
        state = OD_LOADING;
    }
    if (state != OD_LOADING) return;
    for (count = 0; count < OD_TABLE_CHUNK && load_index < FX_OD_TABLE_DEPTH; ++count, ++load_index) {
        if (fx_od_table_word(load_index, load_drive, FX_OD_INPUT_SENSITIVITY, &word) != 0) { od_fail(5); return; }
        fx_hw_write(base, FX_REG_DIST_WT_DATA, word);
    }
    status = fx_hw_read(base, FX_REG_OD_STATUS);
    if (status & FX_OD_STATUS_REJECTED) { od_fail(6); return; }
    if (load_index == FX_OD_TABLE_DEPTH) {
        if (!(status & (FX_OD_STATUS_LOADED0 << load_bank))) { od_fail(7); return; }
        bank_valid[load_bank] = 1; bank_drive[load_bank] = load_drive;
        od_apply(base, load_bank, now_ms);
    }
}

void params_service(u32 now_ms) {
    fx_od_service(FX_BASE, now_ms);
}

