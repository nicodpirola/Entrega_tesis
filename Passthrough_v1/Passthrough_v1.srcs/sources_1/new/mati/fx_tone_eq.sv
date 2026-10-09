`timescale 1ns/1ps

// =============================================================================
// fx_tone_eq.sv
//
// Seccion de shaping:
//
//   in -> tone blend -> EQ biquad -> out
//
// Tone y EQ tienen enables independientes.
//
// enable_tone=0:
//   tone blend hace bypass.
//
// enable_eq=0:
//   biquad EQ hace bypass.
// =============================================================================

module fx_tone_eq(
    input  logic               clk,
    input  logic               rst_n,

    input  logic               enable_tone,
    input  logic               enable_eq,

    input  logic               in_valid,
    output logic               in_ready,
    input  logic signed [31:0] in_data,

    output logic               out_valid,
    input  logic               out_ready,
    output logic signed [31:0] out_data,

    input  fx_ctrl_pkg::tone_cfg_t tone_cfg,
    input  fx_ctrl_pkg::eq_cfg_t   eq_cfg
);

// =============================================================================
// TONE -> EQ STREAM
// =============================================================================

logic               tone_valid;
logic               tone_ready;
logic signed [31:0] tone_data;

// =============================================================================
// TONE BLEND
// =============================================================================

fx_tone_blend u_tone(
    .clk          (clk),
    .rst_n        (rst_n),

    .enable       (enable_tone),

    .in_valid     (in_valid),
    .in_ready     (in_ready),
    .in_data      (in_data),

    .out_valid    (tone_valid),
    .out_ready    (tone_ready),
    .out_data     (tone_data),

    .lpf_b0       (tone_cfg.l_b0),
    .lpf_b1       (tone_cfg.l_b1),
    .lpf_b2       (tone_cfg.l_b2),
    .lpf_a1       (tone_cfg.l_a1),
    .lpf_a2       (tone_cfg.l_a2),

    .hpf_b0       (tone_cfg.h_b0),
    .hpf_b1       (tone_cfg.h_b1),
    .hpf_b2       (tone_cfg.h_b2),
    .hpf_a1       (tone_cfg.h_a1),
    .hpf_a2       (tone_cfg.h_a2),

    .blend_q1_31  ($signed(tone_cfg.blend_q1_31))
);

// =============================================================================
// EQ
//
// Actualmente un peak biquad configurable.
//
// eq_cfg.ctrl queda reservado para futuros modos / clear.
// El propio fx_biquad limpia estado en el flanco de enable.
// =============================================================================

fx_biquad u_eq(
    .clk         (clk),
    .rst_n       (rst_n),

    .state_clear (1'b0),
    .enable      (enable_eq),

    .in_valid    (tone_valid),
    .in_ready    (tone_ready),
    .in_data     (tone_data),

    .out_valid   (out_valid),
    .out_ready   (out_ready),
    .out_data    (out_data),

    .b0_q2_30    (eq_cfg.b0),
    .b1_q2_30    (eq_cfg.b1),
    .b2_q2_30    (eq_cfg.b2),
    .a1_q2_30    (eq_cfg.a1),
    .a2_q2_30    (eq_cfg.a2)
);

endmodule