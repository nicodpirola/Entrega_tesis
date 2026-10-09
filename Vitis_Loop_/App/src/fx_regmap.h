#ifndef FX_REGMAP_H
#define FX_REGMAP_H

#include "xil_types.h"

#define FX_CORE_ID_VALUE       0x46585448u
#define FX_CORE_VERSION_VALUE  0x00010300u

/* Global */
#define FX_REG_CORE_CTRL        0x000u
#define FX_REG_SOURCE_CTRL      0x004u
#define FX_REG_FX_ENABLE        0x008u
#define FX_REG_CORE_STATUS      0x00Cu
#define FX_REG_AUDIO_SNOOP      0x010u
#define FX_REG_PERF_STATUS      0x014u
#define FX_REG_CORE_ID          0x018u
#define FX_REG_CORE_VERSION     0x01Cu
#define FX_REG_CORE_COMMAND     0x020u

/* Theremin frontend */
#define FX_REG_FRONTEND_CTRL    0x040u
#define FX_REG_ENV_GAIN         0x044u
#define FX_REG_ZC_HYST          0x048u
#define FX_REG_GLIDE_CTRL       0x04Cu
#define FX_REG_FRONTEND_STATUS  0x050u
#define FX_REG_ENV_VALUE        0x054u
#define FX_REG_PITCH_PERIOD     0x058u
#define FX_REG_PITCH_PHASE_INC  0x05Cu
#define FX_REG_ENV_ATTACK       0x060u
#define FX_REG_ENV_RELEASE      0x064u
#define FX_REG_GATE_ON_THR      0x068u
#define FX_REG_GATE_OFF_THR     0x06Cu
#define FX_REG_PITCH_CTRL       0x070u   /* perfil del detector de pitch (YIN 48 kHz + post) */
#define FX_REG_PITCH_CFG2       0x074u   /* [7:0] ms de nota estable para la memoria de nota */

/* Perfiles (ver fx_synth_frontend.sv para el detalle de los campos) */
#define FX_PITCH_CTRL_GUITARRA  0x3185BA6Eu  /* memoria + confianza + re-ataque + estabilidad K=12 */
#define FX_PITCH_CTRL_THEREMIN  0x0860B007u  /* prefiltro 8,5 kHz, memoria, K=3, sin re-ataque */
#define FX_PITCH_CFG2_DEFAULT   100u

/* Synth */
#define FX_REG_SYNTH_CTRL        0x100u
#define FX_REG_SYNTH_BASE_INC    0x104u
#define FX_REG_SYNTH_STATUS      0x108u
#define FX_REG_OSC1_CTRL         0x140u
#define FX_REG_OSC1_PW           0x144u
#define FX_REG_OSC1_LEVEL        0x148u
#define FX_REG_OSC2_CTRL         0x180u
#define FX_REG_OSC2_PW           0x184u
#define FX_REG_OSC2_DETUNE       0x188u
#define FX_REG_OSC2_LEVEL        0x18Cu
#define FX_REG_ADD_AMP_BASE      0x1C0u
#define FX_REG_ADD_AMP_LAST      0x23Cu
#define FX_REG_NOISE_CTRL        0x240u
#define FX_REG_NOISE_SEED        0x244u
#define FX_REG_NOISE_LEVEL       0x248u
#define FX_REG_SYNTH_BUS_TRIM    0x24Cu
#define FX_REG_SYNTH_MIX_STATUS  0x250u
#define FX_REG_SYNTH_SVF_CTRL    0x280u
#define FX_REG_SYNTH_SVF_A1      0x284u
#define FX_REG_SYNTH_SVF_A2      0x288u
#define FX_REG_SYNTH_SVF_A3      0x28Cu
#define FX_REG_SYNTH_SVF_K       0x290u
#define FX_REG_SYNTH_SVF_DRIVE   0x294u
#define FX_REG_SYNTH_OUT_CTRL    0x2C0u
#define FX_REG_SYNTH_MASTER      0x2C4u

/* Effects */
#define FX_REG_OCT_CTRL          0x400u
#define FX_REG_OCT_MODE          0x404u
#define FX_REG_OCT_MIX           0x408u
#define FX_REG_OCT_LEVEL         0x40Cu
#define FX_REG_WAH_CTRL          0x440u
#define FX_REG_WAH_POSITION      0x444u
#define FX_REG_WAH_RESONANCE     0x448u
#define FX_REG_WAH_MIX           0x44Cu
#define FX_REG_WAH_MIN_FREQ      0x450u
#define FX_REG_WAH_MAX_FREQ      0x454u
#define FX_REG_DIST_CTRL         0x480u
#define FX_REG_DIST_DRIVE        0x484u
#define FX_REG_DIST_LEVEL        0x488u
#define FX_REG_DIST_MIX          0x48Cu
#define FX_REG_DIST_WT_ADDR      0x490u
#define FX_REG_DIST_WT_DATA      0x494u
#define FX_REG_DIST_WT_CMD       0x498u
#define FX_REG_TONE_BLEND        0x4C0u
#define FX_REG_TONE_L_B0         0x4C4u
#define FX_REG_TONE_L_B1         0x4C8u
#define FX_REG_TONE_L_B2         0x4CCu
#define FX_REG_TONE_L_A1         0x4D0u
#define FX_REG_TONE_L_A2         0x4D4u
#define FX_REG_TONE_H_B0         0x4D8u
#define FX_REG_TONE_H_B1         0x4DCu
#define FX_REG_TONE_H_B2         0x4E0u
#define FX_REG_TONE_H_A1         0x4E4u
#define FX_REG_TONE_H_A2         0x4E8u
#define FX_REG_EQ_CTRL           0x500u
#define FX_REG_EQ_B0             0x504u
#define FX_REG_EQ_B1             0x508u
#define FX_REG_EQ_B2             0x50Cu
#define FX_REG_EQ_A1             0x510u
#define FX_REG_EQ_A2             0x514u
#define FX_REG_CHORUS_CTRL       0x540u
#define FX_REG_CHORUS_CENTER     0x544u
#define FX_REG_CHORUS_DEPTH      0x548u
#define FX_REG_CHORUS_RATE       0x54Cu
#define FX_REG_CHORUS_WET        0x550u
#define FX_REG_CHORUS_LPF_G      0x554u
#define FX_REG_FLANGER_CTRL      0x580u
#define FX_REG_FLANGER_CENTER    0x584u
#define FX_REG_FLANGER_DEPTH     0x588u
#define FX_REG_FLANGER_RATE      0x58Cu
#define FX_REG_FLANGER_FB        0x590u
#define FX_REG_FLANGER_WET       0x594u
#define FX_REG_TREMOLO_CTRL      0x5C0u
#define FX_REG_TREMOLO_RATE      0x5C4u
#define FX_REG_TREMOLO_DEPTH     0x5C8u
#define FX_REG_PHASER_CTRL       0x600u
#define FX_REG_PHASER_RATE       0x604u
#define FX_REG_PHASER_GMIN       0x608u
#define FX_REG_PHASER_GMAX       0x60Cu
#define FX_REG_PHASER_FB         0x610u
#define FX_REG_DELAY_CTRL        0x640u
#define FX_REG_DELAY_TIME        0x644u
#define FX_REG_DELAY_FB          0x648u
#define FX_REG_DELAY_WET         0x64Cu
#define FX_REG_REVERB_CTRL       0x680u
#define FX_REG_REVERB_MIX        0x684u
#define FX_REG_REVERB_DECAY      0x688u
#define FX_REG_REVERB_DAMPING    0x68Cu
#define FX_REG_REVERB_SIZE       0x690u
#define FX_REG_REVERB_PREDELAY   0x694u
#define FX_REG_REVERB_DIFFUSION  0x698u
#define FX_REG_REVERB_MOD_DEPTH  0x69Cu
#define FX_REG_REVERB_MOD_RATE   0x6A0u
#define FX_REG_CAB_CTRL          0x6C0u
#define FX_REG_CAB_LEVEL         0x6C4u
#define FX_REG_CAB_COEF_ADDR     0x6C8u   /* tap 0..1023, auto-incrementa */
#define FX_REG_CAB_COEF_DATA     0x6CCu   /* coef Q1.17 en bits [17:0] */
#define FX_REG_OUTPUT_CTRL       0x700u
#define FX_REG_OUTPUT_LEVEL      0x704u
#define FX_REG_LIMITER_THRESH    0x708u
#define FX_REG_OUTPUT_STATUS     0x70Cu


/* Overdrive Yeh: shadow, aplicar con FX_COMMAND_COMMIT. */
#define FX_REG_OD_CTRL           0x900u
#define FX_REG_OD_INPUT1_G       0x904u
#define FX_REG_OD_INPUT2_G       0x908u
#define FX_REG_OD_BRANCH_HP_G    0x90Cu
#define FX_REG_OD_BRANCH_LP_G    0x910u
#define FX_REG_OD_BRANCH_GAIN    0x914u
#define FX_REG_OD_TONE_B0        0x918u
#define FX_REG_OD_TONE_B1        0x91Cu
#define FX_REG_OD_TONE_B2        0x920u
#define FX_REG_OD_TONE_A1        0x924u
#define FX_REG_OD_TONE_A2        0x928u
#define FX_REG_OD_OUTPUT_G       0x92Cu
#define FX_REG_OD_LEVEL_Q3_29    0x930u
#define FX_REG_OD_STATUS         0x934u
#define FX_REG_OD_COMMAND        0x938u
#define FX_REG_OD_INFO           0x93Cu
#define FX_OD_CTRL_BANK          (1u << 0)
#define FX_OD_CTRL_CLEAR         (1u << 1)
#define FX_OD_COMMAND_CLEAR      (1u << 0)
#define FX_OD_STATUS_WR_READY    (1u << 0)
#define FX_OD_STATUS_BANK        (1u << 1)
#define FX_OD_STATUS_REJECTED    (1u << 2)
#define FX_OD_STATUS_LOADED0     (1u << 3)
#define FX_OD_STATUS_LOADED1     (1u << 4)
#define FX_OD_STATUS_CFG_READY   (1u << 5)
#define FX_OD_TABLE_DEPTH        2561u
#define FX_OD_WT_ADDR(bank, addr) ((((u32)(bank) & 1u) << 12) | ((u32)(addr) & 0xFFFu))
/* FX_REG_OD_INFO: factor en bits [7:0], profundidad de tabla en [31:16]. */

/* Front panel */
#define FX_REG_ENCODER(n)        (0x800u + 4u * (u32)(n))
#define FX_RESERVED_PANEL_BASE   0x840u

/* Control bits */
#define FX_CORE_ENABLE           (1u << 0)
#define FX_CORE_TONE_TEST        (1u << 3)
#define FX_SOURCE_SYNTH          (1u << 0)
#define FX_COMMAND_COMMIT        (1u << 0)

#define FX_FRONTEND_PITCH        (1u << 0)
#define FX_FRONTEND_ENVELOPE     (1u << 1)
#define FX_FRONTEND_CLEAR        (1u << 2)

#define FX_FRONTEND_GATE         (1u << 0)
#define FX_FRONTEND_PITCH_LOCKED (1u << 1)
#define FX_FRONTEND_PERIOD_VALID (1u << 2)
#define FX_FRONTEND_INC_VALID    (1u << 3)

#define FX_EN_OCTAVER            (1u << 0)
#define FX_EN_WAH                (1u << 1)
#define FX_EN_DIST               (1u << 2)
#define FX_EN_TONE               (1u << 3)
#define FX_EN_EQ                 (1u << 4)
#define FX_EN_CHORUS             (1u << 5)
#define FX_EN_FLANGER            (1u << 6)
#define FX_EN_TREMOLO            (1u << 7)
#define FX_EN_PHASER             (1u << 8)
#define FX_EN_DELAY              (1u << 9)
#define FX_EN_REVERB             (1u << 10)
#define FX_EN_CAB                (1u << 11)

/* Synth fields */
#define FX_SYNTH_ENABLE          (1u << 0)
#define FX_SYNTH_OUTPUT_SHIFT    1u
#define FX_SYNTH_OUTPUT_MASK     (3u << FX_SYNTH_OUTPUT_SHIFT)
#define FX_SYNTH_OUTPUT_OSC1     0u
#define FX_SYNTH_OUTPUT_OSC2     1u
#define FX_SYNTH_OUTPUT_MIX      2u

#define FX_OSC1_ADDITIVE         0u
#define FX_OSC1_SAW_UP           1u
#define FX_OSC1_SAW_DOWN         2u
#define FX_OSC1_PULSE            3u
#define FX_OSC2_SAW_UP           0u
#define FX_OSC2_SAW_DOWN         1u
#define FX_OSC2_PULSE            2u

#define FX_RANGE_32              0u
#define FX_RANGE_16              1u
#define FX_RANGE_8               2u
#define FX_RANGE_4               3u
#define FX_RANGE_2               4u

#define FX_OSC1_CTRL(mode, range, harmonics) \
    (((u32)(mode) & 3u) | (((u32)(range) & 7u) << 2) | \
     (((u32)(harmonics) & 0x3Fu) << 5))

#define FX_OSC2_CTRL(wave, range) \
    (((u32)(wave) & 3u) | (((u32)(range) & 7u) << 2))

#endif
