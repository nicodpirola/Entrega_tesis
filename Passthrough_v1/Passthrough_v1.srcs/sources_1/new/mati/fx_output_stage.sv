`timescale 1ns/1ps

// =============================================================================
// fx_output_stage.sv
//
// Etapa final de salida.
//
// Actualmente:
//   in -> output gain -> out
//
// ctrl:
//   bit0 = mute
//   bit1 = limiter enable [reservado, no implementado todavia]
//
// limiter_threshold_q3_29 queda reservado para el futuro limiter.
//
// El hard clip final de seguridad continua existiendo en
// fx_axis_mono_adapter al convertir Q3.29 -> PCM24.
// =============================================================================

module fx_output_stage(
    input  logic               clk,
    input  logic               rst_n,

    input  logic               in_valid,
    output logic               in_ready,
    input  logic signed [31:0] in_data,

    output logic               out_valid,
    input  logic               out_ready,
    output logic signed [31:0] out_data,

    input  logic [31:0]        ctrl,
    input  logic signed [31:0] level_q1_31,

    input  logic signed [31:0] limiter_threshold_q3_29,

    output logic               busy
);

// =============================================================================
// EFFECTIVE GAIN
//
// ctrl[0] = mute
// =============================================================================

logic signed [31:0] effective_gain_q1_31;

always_comb begin
    if (ctrl[0])
        effective_gain_q1_31 = 32'sd0;
    else
        effective_gain_q1_31 = level_q1_31;
end

// =============================================================================
// OUTPUT GAIN
// =============================================================================

synth_gain u_output_gain(
    .clk               (clk),
    .rst_n             (rst_n),

    .in_valid          (in_valid),
    .in_ready          (in_ready),

    .sample_in_q3_29   (in_data),
    .gain_q1_31        (effective_gain_q1_31),

    .out_valid         (out_valid),
    .out_ready         (out_ready),

    .sample_out_q3_29  (out_data),

    .busy              (busy)
);

// =============================================================================
// RESERVED
//
// ctrl[1] y limiter_threshold_q3_29 se usaran cuando implementemos
// la proteccion/limiter de salida.
// =============================================================================

logic unused_limiter;

always_comb begin
    unused_limiter =
        ctrl[1] ^
        ^limiter_threshold_q3_29;
end

endmodule