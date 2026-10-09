`timescale 1ns/1ps

// =============================================================================
// fx_mod_section.sv
//
// Seccion completa de modulacion:
//
//   in
//    -> chorus
//    -> flanger
//    -> tremolo
//    -> phaser
//    -> out
//
// Cada efecto tiene enable independiente.
//
// chorus_cfg.ctrl[0]:
//   0 = wet sin LPF
//   1 = LPF interno del wet activado
//
// Los demas campos ctrl quedan reservados.
// =============================================================================

module fx_mod_section(
    input  logic               clk,
    input  logic               rst_n,

    input  logic               enable_chorus,
    input  logic               enable_flanger,
    input  logic               enable_tremolo,
    input  logic               enable_phaser,

    input  logic               in_valid,
    output logic               in_ready,
    input  logic signed [31:0] in_data,

    output logic               out_valid,
    input  logic               out_ready,
    output logic signed [31:0] out_data,

    input  fx_ctrl_pkg::chorus_cfg_t  chorus_cfg,
    input  fx_ctrl_pkg::flanger_cfg_t flanger_cfg,
    input  fx_ctrl_pkg::tremolo_cfg_t tremolo_cfg,
    input  fx_ctrl_pkg::phaser_cfg_t  phaser_cfg
);

// =============================================================================
// INTERNAL STREAMS
// =============================================================================

// Chorus -> Flanger
logic               chorus_valid;
logic               chorus_ready;
logic signed [31:0] chorus_data;

// Flanger -> Tremolo
logic               flanger_valid;
logic               flanger_ready;
logic signed [31:0] flanger_data;

// Tremolo -> Phaser
logic               tremolo_valid;
logic               tremolo_ready;
logic signed [31:0] tremolo_data;

// =============================================================================
// CHORUS
// =============================================================================

fx_chorus #(
    .ADDR_W(11)
) u_chorus(
    .clk               (clk),
    .rst_n             (rst_n),

    .enable            (enable_chorus),

    .in_valid          (in_valid),
    .in_ready          (in_ready),
    .in_data           (in_data),

    .out_valid         (chorus_valid),
    .out_ready         (chorus_ready),
    .out_data          (chorus_data),

    .D_center_16_16    (chorus_cfg.center_16_16),
    .D_depth_16_16     (chorus_cfg.depth_16_16),

    .wet_q1_31         ($signed(chorus_cfg.wet_q1_31)),
    .lfo_phase_inc_u32 (chorus_cfg.rate_inc_u32),

    .lpf_on            (chorus_cfg.ctrl[0]),
    .lpf_G_q1_31       ($signed(chorus_cfg.lpf_g_q1_31))
);

// =============================================================================
// FLANGER
// =============================================================================

fx_flanger #(
    .ADDR_W(11)
) u_flanger(
    .clk               (clk),
    .rst_n             (rst_n),

    .enable            (enable_flanger),

    .in_valid          (chorus_valid),
    .in_ready          (chorus_ready),
    .in_data           (chorus_data),

    .out_valid         (flanger_valid),
    .out_ready         (flanger_ready),
    .out_data          (flanger_data),

    .D_center_16_16    (flanger_cfg.center_16_16),
    .D_depth_16_16     (flanger_cfg.depth_16_16),

    .wet_q1_31         ($signed(flanger_cfg.wet_q1_31)),
    .fb_q1_31          ($signed(flanger_cfg.fb_q1_31)),

    .lfo_phase_inc_u32 (flanger_cfg.rate_inc_u32)
);

// =============================================================================
// TREMOLO
// =============================================================================

fx_tremolo u_tremolo(
    .clk               (clk),
    .rst_n             (rst_n),

    .enable            (enable_tremolo),

    .in_valid          (flanger_valid),
    .in_ready          (flanger_ready),
    .in_data           (flanger_data),

    .out_valid         (tremolo_valid),
    .out_ready         (tremolo_ready),
    .out_data          (tremolo_data),

    .depth_q1_31       ($signed(tremolo_cfg.depth_q1_31)),
    .lfo_phase_inc_u32 (tremolo_cfg.rate_inc_u32)
);

// =============================================================================
// PHASER
// =============================================================================

fx_phaser u_phaser(
    .clk              (clk),
    .rst_n            (rst_n),

    .enable           (enable_phaser),

    .in_valid         (tremolo_valid),
    .in_ready         (tremolo_ready),
    .in_data          (tremolo_data),

    .out_valid        (out_valid),
    .out_ready        (out_ready),
    .out_data         (out_data),

    .lfo_phase_inc    (phaser_cfg.rate_inc_u32),

    .g_min_q1_31      (phaser_cfg.g_min_q1_31),
    .g_max_q1_31      (phaser_cfg.g_max_q1_31),
    .fb_q1_31         (phaser_cfg.fb_q1_31)
);

endmodule
