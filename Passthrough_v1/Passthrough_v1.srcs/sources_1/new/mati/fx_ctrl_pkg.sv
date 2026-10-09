`timescale 1ns/1ps

package fx_ctrl_pkg;

// =============================================================================
// GLOBAL CONSTANTS
// =============================================================================

localparam logic [31:0] FX_CORE_ID      = 32'h4658_5448; // "FXTH"
localparam logic [31:0] FX_CORE_VERSION = 32'h0001_0300; // v1.3.0: pitch YIN 48 kHz + post-procesado (perfil guitarra/theremin)

localparam int FX_EN_OCTAVER = 0;
localparam int FX_EN_WAH     = 1;
localparam int FX_EN_DIST    = 2;
localparam int FX_EN_TONE    = 3;
localparam int FX_EN_EQ      = 4;
localparam int FX_EN_CHORUS  = 5;
localparam int FX_EN_FLANGER = 6;
localparam int FX_EN_TREMOLO = 7;
localparam int FX_EN_PHASER  = 8;
localparam int FX_EN_DELAY   = 9;
localparam int FX_EN_REVERB  = 10;
localparam int FX_EN_CAB     = 11;

localparam int CORE_CTRL_ENABLE_BIT    = 0;
localparam int CORE_CTRL_TONE_TEST_BIT = 3;

localparam int SOURCE_CTRL_SYNTH_BIT = 0;

localparam int FRONTEND_CTRL_PITCH_BIT = 0;
localparam int FRONTEND_CTRL_ENV_BIT   = 1;
localparam int FRONTEND_CTRL_CLEAR_BIT = 2;

// =============================================================================
// BYTE OFFSETS
// =============================================================================

// Global
localparam logic [11:0] REG_CORE_CTRL       = 12'h000;
localparam logic [11:0] REG_SOURCE_CTRL     = 12'h004;
localparam logic [11:0] REG_FX_ENABLE       = 12'h008;
localparam logic [11:0] REG_CORE_STATUS     = 12'h00C;
localparam logic [11:0] REG_AUDIO_SNOOP     = 12'h010;
localparam logic [11:0] REG_PERF_STATUS     = 12'h014;
localparam logic [11:0] REG_CORE_ID         = 12'h018;
localparam logic [11:0] REG_CORE_VERSION    = 12'h01C;
localparam logic [11:0] REG_CORE_COMMAND    = 12'h020;

// Overdrive: factor fijo de hardware, consultable en REG_OD_INFO.
localparam int FX_OD_OS_FACTOR = 8;

// Theremin frontend
localparam logic [11:0] REG_FRONTEND_CTRL   = 12'h040;
localparam logic [11:0] REG_ENV_GAIN        = 12'h044;
localparam logic [11:0] REG_ZC_HYST         = 12'h048;
localparam logic [11:0] REG_GLIDE_CTRL      = 12'h04C;
localparam logic [11:0] REG_FRONTEND_STATUS = 12'h050;
localparam logic [11:0] REG_ENV_VALUE       = 12'h054;
localparam logic [11:0] REG_PITCH_PERIOD    = 12'h058;
localparam logic [11:0] REG_PITCH_PHASE_INC = 12'h05C;
localparam logic [11:0] REG_ENV_ATTACK      = 12'h060;
localparam logic [11:0] REG_ENV_RELEASE     = 12'h064;
localparam logic [11:0] REG_GATE_ON_THR     = 12'h068;
localparam logic [11:0] REG_GATE_OFF_THR    = 12'h06C;
localparam logic [11:0] REG_PITCH_CTRL      = 12'h070;   // perfil del detector de pitch (ver fx_synth_frontend)
localparam logic [11:0] REG_PITCH_CFG2      = 12'h074;   // [7:0] ms de nota estable para la memoria

// Perfiles del detector (valores de reset y referencia para el PS)
localparam logic [31:0] PITCH_CTRL_GUITARRA = 32'h3185_BA6E;
localparam logic [31:0] PITCH_CTRL_THEREMIN = 32'h0860_B007;
localparam logic [31:0] PITCH_CFG2_DEFAULT  = 32'd100;

// 0x078-0x0FC reservado para futuras mejoras del frontend.

// Synth global
localparam logic [11:0] REG_SYNTH_CTRL       = 12'h100;
localparam logic [11:0] REG_SYNTH_BASE_INC   = 12'h104;
localparam logic [11:0] REG_SYNTH_STATUS     = 12'h108;

// OSC1
localparam logic [11:0] REG_OSC1_CTRL        = 12'h140;
localparam logic [11:0] REG_OSC1_PW          = 12'h144;
localparam logic [11:0] REG_OSC1_LEVEL       = 12'h148;

// OSC2
localparam logic [11:0] REG_OSC2_CTRL        = 12'h180;
localparam logic [11:0] REG_OSC2_PW          = 12'h184;
localparam logic [11:0] REG_OSC2_DETUNE      = 12'h188;
localparam logic [11:0] REG_OSC2_LEVEL       = 12'h18C;

// Additive amplitudes: 32 words, H1..H32
localparam logic [11:0] REG_ADD_AMP_BASE     = 12'h1C0;
localparam logic [11:0] REG_ADD_AMP_LAST     = 12'h23C;

// Synth mixer / noise
localparam logic [11:0] REG_NOISE_CTRL       = 12'h240;
localparam logic [11:0] REG_NOISE_SEED       = 12'h244;
localparam logic [11:0] REG_NOISE_LEVEL      = 12'h248;
localparam logic [11:0] REG_SYNTH_BUS_TRIM   = 12'h24C;
localparam logic [11:0] REG_SYNTH_MIX_STATUS = 12'h250;

// Synth SVF
localparam logic [11:0] REG_SYNTH_SVF_CTRL   = 12'h280;
localparam logic [11:0] REG_SYNTH_SVF_A1     = 12'h284;
localparam logic [11:0] REG_SYNTH_SVF_A2     = 12'h288;
localparam logic [11:0] REG_SYNTH_SVF_A3     = 12'h28C;
localparam logic [11:0] REG_SYNTH_SVF_K      = 12'h290;
localparam logic [11:0] REG_SYNTH_SVF_DRIVE  = 12'h294;

// Synth output
localparam logic [11:0] REG_SYNTH_OUT_CTRL   = 12'h2C0;
localparam logic [11:0] REG_SYNTH_MASTER     = 12'h2C4;

// 0x300-0x3FC reservado para envolventes, LFO y control de nota/MIDI.

// Octaver
localparam logic [11:0] REG_OCT_CTRL         = 12'h400;
localparam logic [11:0] REG_OCT_MODE         = 12'h404;
localparam logic [11:0] REG_OCT_MIX          = 12'h408;
localparam logic [11:0] REG_OCT_LEVEL        = 12'h40C;

// Wah
localparam logic [11:0] REG_WAH_CTRL         = 12'h440;
localparam logic [11:0] REG_WAH_POSITION     = 12'h444;
localparam logic [11:0] REG_WAH_RESONANCE    = 12'h448;
localparam logic [11:0] REG_WAH_MIX          = 12'h44C;
localparam logic [11:0] REG_WAH_MIN_FREQ     = 12'h450;
localparam logic [11:0] REG_WAH_MAX_FREQ     = 12'h454;

// Distortion
localparam logic [11:0] REG_DIST_CTRL        = 12'h480;
localparam logic [11:0] REG_DIST_DRIVE       = 12'h484;
localparam logic [11:0] REG_DIST_LEVEL       = 12'h488;
localparam logic [11:0] REG_DIST_MIX         = 12'h48C;
localparam logic [11:0] REG_DIST_WT_ADDR     = 12'h490;
localparam logic [11:0] REG_DIST_WT_DATA     = 12'h494;
localparam logic [11:0] REG_DIST_WT_CMD      = 12'h498;

// Tone blend
localparam logic [11:0] REG_TONE_BLEND       = 12'h4C0;
localparam logic [11:0] REG_TONE_L_B0        = 12'h4C4;
localparam logic [11:0] REG_TONE_L_B1        = 12'h4C8;
localparam logic [11:0] REG_TONE_L_B2        = 12'h4CC;
localparam logic [11:0] REG_TONE_L_A1        = 12'h4D0;
localparam logic [11:0] REG_TONE_L_A2        = 12'h4D4;
localparam logic [11:0] REG_TONE_H_B0        = 12'h4D8;
localparam logic [11:0] REG_TONE_H_B1        = 12'h4DC;
localparam logic [11:0] REG_TONE_H_B2        = 12'h4E0;
localparam logic [11:0] REG_TONE_H_A1        = 12'h4E4;
localparam logic [11:0] REG_TONE_H_A2        = 12'h4E8;

// EQ
localparam logic [11:0] REG_EQ_CTRL          = 12'h500;
localparam logic [11:0] REG_EQ_B0            = 12'h504;
localparam logic [11:0] REG_EQ_B1            = 12'h508;
localparam logic [11:0] REG_EQ_B2            = 12'h50C;
localparam logic [11:0] REG_EQ_A1            = 12'h510;
localparam logic [11:0] REG_EQ_A2            = 12'h514;

// Chorus
localparam logic [11:0] REG_CHORUS_CTRL      = 12'h540;
localparam logic [11:0] REG_CHORUS_CENTER    = 12'h544;
localparam logic [11:0] REG_CHORUS_DEPTH     = 12'h548;
localparam logic [11:0] REG_CHORUS_RATE      = 12'h54C;
localparam logic [11:0] REG_CHORUS_WET       = 12'h550;
localparam logic [11:0] REG_CHORUS_LPF_G     = 12'h554;

// Flanger
localparam logic [11:0] REG_FLANGER_CTRL     = 12'h580;
localparam logic [11:0] REG_FLANGER_CENTER   = 12'h584;
localparam logic [11:0] REG_FLANGER_DEPTH    = 12'h588;
localparam logic [11:0] REG_FLANGER_RATE     = 12'h58C;
localparam logic [11:0] REG_FLANGER_FB       = 12'h590;
localparam logic [11:0] REG_FLANGER_WET      = 12'h594;

// Tremolo
localparam logic [11:0] REG_TREMOLO_CTRL     = 12'h5C0;
localparam logic [11:0] REG_TREMOLO_RATE     = 12'h5C4;
localparam logic [11:0] REG_TREMOLO_DEPTH    = 12'h5C8;

// Phaser
localparam logic [11:0] REG_PHASER_CTRL      = 12'h600;
localparam logic [11:0] REG_PHASER_RATE      = 12'h604;
localparam logic [11:0] REG_PHASER_GMIN      = 12'h608;
localparam logic [11:0] REG_PHASER_GMAX      = 12'h60C;
localparam logic [11:0] REG_PHASER_FB        = 12'h610;

// Delay
localparam logic [11:0] REG_DELAY_CTRL       = 12'h640;
localparam logic [11:0] REG_DELAY_TIME       = 12'h644;
localparam logic [11:0] REG_DELAY_FB         = 12'h648;
localparam logic [11:0] REG_DELAY_WET        = 12'h64C;

// Reverb
localparam logic [11:0] REG_REVERB_CTRL      = 12'h680;
localparam logic [11:0] REG_REVERB_MIX       = 12'h684;
localparam logic [11:0] REG_REVERB_DECAY     = 12'h688;
localparam logic [11:0] REG_REVERB_DAMPING   = 12'h68C;
localparam logic [11:0] REG_REVERB_SIZE      = 12'h690;
localparam logic [11:0] REG_REVERB_PREDELAY  = 12'h694;
localparam logic [11:0] REG_REVERB_DIFFUSION = 12'h698;
localparam logic [11:0] REG_REVERB_MOD_DEPTH = 12'h69C;
localparam logic [11:0] REG_REVERB_MOD_RATE  = 12'h6A0;

// Cab
localparam logic [11:0] REG_CAB_CTRL         = 12'h6C0;
localparam logic [11:0] REG_CAB_LEVEL        = 12'h6C4;
localparam logic [11:0] REG_CAB_COEF_ADDR    = 12'h6C8; // tap 0..1023 (auto-incrementa)
localparam logic [11:0] REG_CAB_COEF_DATA    = 12'h6CC; // coef Q1.17 en bits [17:0]

// Output
localparam logic [11:0] REG_OUTPUT_CTRL      = 12'h700;
localparam logic [11:0] REG_OUTPUT_LEVEL     = 12'h704;
localparam logic [11:0] REG_LIMITER_THRESH   = 12'h708;
localparam logic [11:0] REG_OUTPUT_STATUS    = 12'h70C;

// Front-panel encoders (read-only signed counters)
localparam logic [11:0] REG_ENCODER_1        = 12'h800;
localparam logic [11:0] REG_ENCODER_2        = 12'h804;
localparam logic [11:0] REG_ENCODER_3        = 12'h808;
localparam logic [11:0] REG_ENCODER_4        = 12'h80C;
localparam logic [11:0] REG_ENCODER_5        = 12'h810;
localparam logic [11:0] REG_ENCODER_6        = 12'h814;

// 0x840-0x87C reservado para switches, pulsadores y footswitches.


// Overdrive Yeh, extension sin desplazar los registros existentes.
localparam logic [11:0] REG_OD_CTRL           = 12'h900;
localparam logic [11:0] REG_OD_INPUT1_G       = 12'h904;
localparam logic [11:0] REG_OD_INPUT2_G       = 12'h908;
localparam logic [11:0] REG_OD_BRANCH_HP_G    = 12'h90C;
localparam logic [11:0] REG_OD_BRANCH_LP_G    = 12'h910;
localparam logic [11:0] REG_OD_BRANCH_GAIN    = 12'h914;
localparam logic [11:0] REG_OD_TONE_B0        = 12'h918;
localparam logic [11:0] REG_OD_TONE_B1        = 12'h91C;
localparam logic [11:0] REG_OD_TONE_B2        = 12'h920;
localparam logic [11:0] REG_OD_TONE_A1        = 12'h924;
localparam logic [11:0] REG_OD_TONE_A2        = 12'h928;
localparam logic [11:0] REG_OD_OUTPUT_G       = 12'h92C;
localparam logic [11:0] REG_OD_LEVEL_Q3_29    = 12'h930;
localparam logic [11:0] REG_OD_STATUS         = 12'h934;
localparam logic [11:0] REG_OD_COMMAND        = 12'h938;
localparam logic [11:0] REG_OD_INFO           = 12'h93C;

// =============================================================================
// CONFIGURATION TYPES
// =============================================================================

typedef struct packed {
    logic [31:0] core_ctrl;
    logic [31:0] source_ctrl;
    logic [31:0] fx_enable;
} global_cfg_t;

typedef struct packed {
    logic [31:0] ctrl;
    logic [31:0] env_gain_q1_31;
    logic signed [31:0] zc_hyst_q3_29;
    logic [31:0] glide_ctrl;
    logic signed [31:0] env_attack_q1_31;
    logic signed [31:0] env_release_q1_31;
    logic signed [31:0] gate_on_thr_q3_29;
    logic signed [31:0] gate_off_thr_q3_29;
    logic [31:0] pitch_ctrl;
    logic [31:0] pitch_cfg2;
} frontend_cfg_t;

typedef struct packed {
    logic [31:0] ctrl;
    logic [31:0] base_phase_inc;
} synth_cfg_t;

typedef struct packed {
    logic [31:0] ctrl;
    logic [31:0] pulse_width;
    logic [31:0] level_q1_31;
} osc1_cfg_t;

typedef struct packed {
    logic [31:0] ctrl;
    logic [31:0] pulse_width;
    logic [31:0] detune_q2_30;
    logic [31:0] level_q1_31;
} osc2_cfg_t;

typedef struct packed {
    logic [31:0] noise_ctrl;
    logic [31:0] noise_seed;
    logic [31:0] noise_level_q1_31;
    logic [31:0] bus_trim_q1_31;
} synth_mix_cfg_t;

typedef struct packed {
    logic [31:0] ctrl;
    logic signed [31:0] a1_q1_31;
    logic signed [31:0] a2_q1_31;
    logic signed [31:0] a3_q1_31;
    logic signed [31:0] k_q3_29;
    logic [31:0] drive;
} synth_svf_cfg_t;

typedef struct packed {
    logic [31:0] ctrl;
    logic [31:0] master_q1_31;
} synth_out_cfg_t;

typedef struct packed {
    logic [31:0] ctrl;
    logic [31:0] mode;
    logic [31:0] mix_q1_31;
    logic [31:0] level_q1_31;
} octaver_cfg_t;

typedef struct packed {
    logic [31:0] ctrl;
    logic [31:0] position_q1_31;
    logic [31:0] resonance_q1_31;
    logic [31:0] mix_q1_31;
    logic [31:0] min_freq_16_16;
    logic [31:0] max_freq_16_16;
} wah_cfg_t;

typedef struct packed {
    logic [31:0] ctrl;
    logic [31:0] drive_16_16;
    logic [31:0] level_q1_31;
    logic [31:0] mix_q1_31;
} dist_cfg_t;

typedef struct packed {
    logic [31:0] ctrl; // bit0: banco; bit1: limpiar estados al aplicar
    logic signed [31:0] input1_g;
    logic signed [31:0] input2_g;
    logic signed [31:0] branch_hp_g;
    logic signed [31:0] branch_lp_g;
    logic signed [31:0] branch_gain;
    logic signed [31:0] tone_b0;
    logic signed [31:0] tone_b1;
    logic signed [31:0] tone_b2;
    logic signed [31:0] tone_a1;
    logic signed [31:0] tone_a2;
    logic signed [31:0] output_g;
    logic signed [31:0] level_q3_29;
} overdrive_cfg_t;

typedef struct packed {
    logic [31:0] blend_q1_31;
    logic signed [31:0] l_b0;
    logic signed [31:0] l_b1;
    logic signed [31:0] l_b2;
    logic signed [31:0] l_a1;
    logic signed [31:0] l_a2;
    logic signed [31:0] h_b0;
    logic signed [31:0] h_b1;
    logic signed [31:0] h_b2;
    logic signed [31:0] h_a1;
    logic signed [31:0] h_a2;
} tone_cfg_t;

typedef struct packed {
    logic [31:0] ctrl;
    logic signed [31:0] b0;
    logic signed [31:0] b1;
    logic signed [31:0] b2;
    logic signed [31:0] a1;
    logic signed [31:0] a2;
} eq_cfg_t;

typedef struct packed {
    logic [31:0] ctrl;
    logic [31:0] center_16_16;
    logic [31:0] depth_16_16;
    logic [31:0] rate_inc_u32;
    logic [31:0] wet_q1_31;
    logic [31:0] lpf_g_q1_31;
} chorus_cfg_t;

typedef struct packed {
    logic [31:0] ctrl;
    logic [31:0] center_16_16;
    logic [31:0] depth_16_16;
    logic [31:0] rate_inc_u32;
    logic [31:0] fb_q1_31;
    logic [31:0] wet_q1_31;
} flanger_cfg_t;

typedef struct packed {
    logic [31:0] ctrl;
    logic [31:0] rate_inc_u32;
    logic [31:0] depth_q1_31;
} tremolo_cfg_t;

typedef struct packed {
    logic [31:0] ctrl;
    logic [31:0] rate_inc_u32;
    logic signed [31:0] g_min_q1_31;
    logic signed [31:0] g_max_q1_31;
    logic signed [31:0] fb_q1_31;
} phaser_cfg_t;

typedef struct packed {
    logic [31:0] ctrl;
    logic [31:0] time_16_16;
    logic [31:0] fb_q1_31;
    logic [31:0] wet_q1_31;
} delay_cfg_t;

typedef struct packed {
    logic [31:0] ctrl;
    logic [31:0] mix_q1_31;
    logic [31:0] decay_q1_31;
    logic [31:0] damping_q1_31;
    logic [31:0] size_q1_31;
    logic [31:0] predelay_16_16;
    logic [31:0] diffusion_q1_31;
    logic [31:0] mod_depth_q1_31;
    logic [31:0] mod_rate_inc_u32;
} reverb_cfg_t;

typedef struct packed {
    logic [31:0] ctrl;
    logic [31:0] level_q1_31;
} cab_cfg_t;

typedef struct packed {
    logic [31:0] ctrl;
    logic [31:0] level_q1_31;
    logic signed [31:0] limiter_threshold_q3_29;
} output_cfg_t;

endpackage
