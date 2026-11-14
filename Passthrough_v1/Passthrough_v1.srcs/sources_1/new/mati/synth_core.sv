// synth_core.sv
// Motor del synth: osciladores, mezcla, filtro y VCA en cadena, una muestra por tick.
//
// osc1, osc2 -> synth_mixer -> synth_svf -> synth_vca (envolvente y master) -> salida
//
// En paralelo con los osciladores, synth_svf_coef calcula los coeficientes del pasabajos
// para esta muestra: corte = nota * corte(xnota) * (1 + contorno * envolvente).
// El filtro espera a tener los coeficientes nuevos antes de tomar la muestra del mezclador.
//
// Cada bloque tiene su propio mul32_seq (1 DSP48). La muestra recorre la cadena
// completa antes de aceptar el siguiente tick (synth_ready).

`timescale 1ns/1ps

module synth_core(
    input logic clk,
    input logic rst_n,

    input  logic               synth_tick,
    output logic               synth_valid,
    output logic signed [31:0] synth_sample,

    input logic [31:0] base_phase_inc,

    // OSC1
    input logic [1:0]  osc1_mode,
    input logic [2:0]  osc1_range,
    input logic [31:0] osc1_pulse_width,
    input logic [5:0]  osc1_n_harmonics,
    input logic               amp_we,
    input logic [4:0]         amp_addr,
    input logic signed [31:0] amp_wdata,

    // OSC2
    input logic [1:0]  osc2_waveform,
    input logic [2:0]  osc2_range,
    input logic [31:0] osc2_pulse_width,
    input logic [31:0] osc2_detune_q2_30,

    // Puertos sin uso (ruido y softclip): se conservan para no tocar fx_core
    // ni el regmap en este paso. Se sacan en la limpieza final.
    input logic [31:0] noise_ctrl,
    input logic [31:0] noise_seed,

    // Mixer
    input logic [31:0] osc1_level_q1_31,
    input logic [31:0] osc2_level_q1_31,
    input logic [31:0] noise_level_q1_31,
    input logic        mix_softclip_enable,
    input logic [31:0] mix_bus_trim_q1_31,
    input logic signed [31:0] mix_t1_q3_29,
    input logic signed [31:0] mix_t2_q3_29,
    input logic signed [31:0] mix_k1_q1_31,
    input logic signed [31:0] mix_k2_q1_31,

    // Filtro (bit 0 prende, bit 3 borra los integradores)
    input logic [31:0]        svf_ctrl,
    input logic signed [31:0] svf_track_q5_27,     //corte en multiplos de la nota (0 a 16)
    input logic signed [31:0] svf_contour_q3_29,   //cuanto abre el volumen el filtro (0 a 4)
    input logic signed [31:0] svf_k_q3_29,         //1/Q

    // VCA / master
    input logic signed [31:0] vca_gain_q1_31,
    input logic signed [31:0] synth_master_q1_31,

    input logic [1:0] output_sel,

    output logic synth_ready,
    output logic synth_busy,
    output logic mixer_overdrive,
    output logic mixer_clip
);

// =============================================================================
// OSCILLATORS
// =============================================================================

logic launch_fire;

logic bank_in_ready;
logic bank_out_valid;
logic bank_out_ready;

logic signed [31:0] osc1_sample;
logic signed [31:0] osc2_sample;

synth_oscillators u_oscillators(
    .clk               (clk),
    .rst_n             (rst_n),

    .in_valid          (launch_fire),
    .in_ready          (bank_in_ready),

    .base_phase_inc    (base_phase_inc),

    .osc1_mode         (osc1_mode),
    .osc1_range        (osc1_range),
    .osc1_pulse_width  (osc1_pulse_width),
    .osc1_n_harmonics  (osc1_n_harmonics),

    .amp_we            (amp_we),
    .amp_addr          (amp_addr),
    .amp_wdata         (amp_wdata),

    .osc2_waveform     (osc2_waveform),
    .osc2_range        (osc2_range),
    .osc2_pulse_width  (osc2_pulse_width),
    .osc2_detune_q2_30 (osc2_detune_q2_30),

    .out_valid         (bank_out_valid),
    .out_ready         (bank_out_ready),

    .osc1_sample_q3_29 (osc1_sample),
    .osc2_sample_q3_29 (osc2_sample)
);

// =============================================================================
// MIXER PARAMETER LATCH
// =============================================================================

logic [1:0] output_sel_r;

logic [31:0] osc1_level_r;
logic [31:0] osc2_level_r;

logic [31:0] mix_bus_trim_r;

logic signed [31:0] mix_t1_r;

always_ff @(posedge clk) begin
    if (!rst_n) begin
        output_sel_r <= 2'd0;

        osc1_level_r <= 32'd0;
        osc2_level_r <= 32'd0;

        mix_bus_trim_r <= 32'h0666_6666;

        mix_t1_r <= 32'sh1999_999A;
    end else if (launch_fire) begin
        output_sel_r <= output_sel;

        osc1_level_r <= osc1_level_q1_31;
        osc2_level_r <= osc2_level_q1_31;

        mix_bus_trim_r <= mix_bus_trim_q1_31;

        mix_t1_r <= mix_t1_q3_29;
    end
end

// =============================================================================
// ENTREGA DE LOS OSCILADORES AL MEZCLADOR
// =============================================================================

logic mix_in_valid;
logic mix_in_ready;
assign mix_in_valid = bank_out_valid;
assign bank_out_ready = mix_in_ready;

// =============================================================================
// SOURCE SELECT
// =============================================================================

logic signed [31:0] mix_osc1;
logic signed [31:0] mix_osc2;

always_comb begin
    mix_osc1 = 32'sd0;
    mix_osc2 = 32'sd0;

    case (output_sel_r)
        2'd0: mix_osc1 = osc1_sample;

        2'd1: mix_osc2 = osc2_sample;

        2'd2: begin
            mix_osc1 = osc1_sample;
            mix_osc2 = osc2_sample;
        end

        default: begin
            mix_osc1 = osc1_sample;
            mix_osc2 = osc2_sample;
        end
    endcase
end

// =============================================================================
// MIXER
// =============================================================================

logic mix_out_valid;
logic mix_out_ready;
logic signed [31:0] mix_sample;

synth_mixer u_mixer(
    .clk              (clk),
    .rst_n            (rst_n),

    .in_valid         (mix_in_valid),
    .in_ready         (mix_in_ready),
    .in_osc1          (mix_osc1),
    .in_osc2          (mix_osc2),

    .out_valid        (mix_out_valid),
    .out_ready        (mix_out_ready),
    .out_data         (mix_sample),

    .osc1_level_q1_31 (osc1_level_r),
    .osc2_level_q1_31 (osc2_level_r),
    .bus_trim_q1_31   (mix_bus_trim_r),
    .t1_q3_29         (mix_t1_r),

    .overdrive        (mixer_overdrive),
    .clip             (mixer_clip)
);

// =============================================================================
// COEFICIENTES DEL FILTRO (arrancan con el tick, en paralelo con los osciladores)
// =============================================================================

logic coef_ready;
logic coef_valid;

logic signed [31:0] svf_a1;
logic signed [31:0] svf_a2;
logic signed [31:0] svf_a3;

synth_svf_coef u_svf_coef(
    .clk            (clk),
    .rst_n          (rst_n),

    .start          (launch_fire),
    .ready          (coef_ready),
    .coef_valid     (coef_valid),
    .a1_q1_31       (svf_a1),
    .a2_q1_31       (svf_a2),
    .a3_q1_31       (svf_a3),

    .base_phase_inc (base_phase_inc),
    .env_q1_31      (vca_gain_q1_31),
    .track_q5_27    (svf_track_q5_27),
    .contour_q3_29  (svf_contour_q3_29),
    .k_q3_29        (svf_k_q3_29)
);

// =============================================================================
// SVF (pasabajos)
// =============================================================================

logic svf_in_valid;
logic svf_in_ready;
logic svf_out_valid;
logic svf_out_ready;

logic signed [31:0] svf_sample;

//la muestra del mezclador pasa al filtro recien cuando estan los coeficientes
assign svf_in_valid  = mix_out_valid && coef_valid;
assign mix_out_ready = svf_in_ready && coef_valid;

synth_svf u_svf(
    .clk         (clk),
    .rst_n       (rst_n),
    .clear_state (svf_ctrl[3]),

    .in_valid    (svf_in_valid),
    .in_ready    (svf_in_ready),
    .in_data     (mix_sample),

    .out_valid   (svf_out_valid),
    .out_ready   (svf_out_ready),
    .out_data    (svf_sample),

    .enable      (svf_ctrl[0]),
    .a1_q1_31    (svf_a1),
    .a2_q1_31    (svf_a2),
    .a3_q1_31    (svf_a3)
);

// =============================================================================
// VCA + MASTER (synth_vca: un solo mul32_seq para los dos productos)
// =============================================================================

logic vca_in_ready;
logic vca_out_valid;

logic signed [31:0] vca_sample;

assign svf_out_ready = vca_in_ready;

synth_vca u_vca(
    .clk            (clk),
    .rst_n          (rst_n),

    .in_valid       (svf_out_valid),
    .in_ready       (vca_in_ready),
    .in_data        (svf_sample),

    .out_valid      (vca_out_valid),
    .out_ready      (1'b1),
    .out_data       (vca_sample),

    .vca_gain_q1_31 (vca_gain_q1_31),
    .master_q1_31   (synth_master_q1_31)
);

// =============================================================================
// GLOBAL CONTROL
// =============================================================================

assign synth_ready =
    bank_in_ready &&
    coef_ready &&
    mix_in_ready &&
    svf_in_ready &&
    vca_in_ready;

assign synth_busy = !synth_ready;

assign launch_fire =
    synth_tick &&
    synth_ready;

// =============================================================================
// OUTPUT
// =============================================================================

assign synth_valid = vca_out_valid;
assign synth_sample = vca_sample;

// =============================================================================
// ASSERTIONS
// =============================================================================

`ifndef SYNTHESIS

always_ff @(posedge clk) begin
    if (rst_n && synth_tick) begin
        assert (synth_ready)
            else $error(
                "synth_core: synth_tick recibido estando busy"
            );
    end
end

`endif

endmodule