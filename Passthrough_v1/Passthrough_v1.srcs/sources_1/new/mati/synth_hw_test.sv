`timescale 1ns/1ps

module synth_hw_test(
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

    // Puertos reservados para compatibilidad; no hay generador de ruido.
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

    // SVF
    input logic [31:0]        svf_ctrl,
    input logic signed [31:0] svf_a1_q1_31,
    input logic signed [31:0] svf_a2_q1_31,
    input logic signed [31:0] svf_a3_q1_31,
    input logic signed [31:0] svf_k_q3_29,

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

logic        mix_softclip_enable_r;
logic [31:0] mix_bus_trim_r;

logic signed [31:0] mix_t1_r;
logic signed [31:0] mix_t2_r;
logic signed [31:0] mix_k1_r;
logic signed [31:0] mix_k2_r;

always_ff @(posedge clk) begin
    if (!rst_n) begin
        output_sel_r <= 2'd0;

        osc1_level_r <= 32'd0;
        osc2_level_r <= 32'd0;

        mix_softclip_enable_r <= 1'b0;
        mix_bus_trim_r <= 32'h0666_6666;

        mix_t1_r <= 32'sh1999_999A;
        mix_t2_r <= 32'sh2666_6666;
        mix_k1_r <= 32'sh4000_0000;
        mix_k2_r <= 32'sh0000_0000;
    end else if (launch_fire) begin
        output_sel_r <= output_sel;

        osc1_level_r <= osc1_level_q1_31;
        osc2_level_r <= osc2_level_q1_31;

        mix_softclip_enable_r <= mix_softclip_enable;
        mix_bus_trim_r <= mix_bus_trim_q1_31;

        mix_t1_r <= mix_t1_q3_29;
        mix_t2_r <= mix_t2_q3_29;
        mix_k1_r <= mix_k1_q1_31;
        mix_k2_r <= mix_k2_q1_31;
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
    .clk                 (clk),
    .rst_n               (rst_n),

    .in_valid            (mix_in_valid),
    .in_ready            (mix_in_ready),

    .osc1_sample_q3_29   (mix_osc1),
    .osc2_sample_q3_29   (mix_osc2),
    .noise_sample_q3_29  (32'sd0),

    .osc1_level_q1_31    (osc1_level_r),
    .osc2_level_q1_31    (osc2_level_r),
    .noise_level_q1_31   (32'd0),

    .softclip_enable     (mix_softclip_enable_r),
    .bus_trim_q1_31      (mix_bus_trim_r),

    .softclip_t1_q3_29   (mix_t1_r),
    .softclip_t2_q3_29   (mix_t2_r),
    .softclip_k1_q1_31   (mix_k1_r),
    .softclip_k2_q1_31   (mix_k2_r),

    .out_valid           (mix_out_valid),
    .out_ready           (mix_out_ready),

    .sample_q3_29        (mix_sample),

    .overdrive           (mixer_overdrive),
    .clip                (mixer_clip)
);

// =============================================================================
// SVF
// =============================================================================

logic [1:0] svf_mode;

logic svf_in_ready;
logic svf_out_valid;
logic svf_out_ready;
logic svf_busy;

logic signed [31:0] svf_sample;
logic signed [31:0] svf_lp;
logic signed [31:0] svf_bp;
logic signed [31:0] svf_hp;

always_comb begin
    if (svf_ctrl[0])
        svf_mode = svf_ctrl[2:1];
    else
        svf_mode = 2'd3;
end

assign mix_out_ready = svf_in_ready;

synth_svf u_svf(
    .clk               (clk),
    .rst_n             (rst_n),
    .clear_state       (svf_ctrl[3]),

    .in_valid          (mix_out_valid),
    .in_ready          (svf_in_ready),
    .sample_in_q3_29   (mix_sample),

    .filter_mode       (svf_mode),
    .a1_q1_31          (svf_a1_q1_31),
    .a2_q1_31          (svf_a2_q1_31),
    .a3_q1_31          (svf_a3_q1_31),
    .k_q3_29           (svf_k_q3_29),

    .out_valid         (svf_out_valid),
    .out_ready         (svf_out_ready),
    .sample_out_q3_29  (svf_sample),

    .lp_q3_29          (svf_lp),
    .bp_q3_29          (svf_bp),
    .hp_q3_29          (svf_hp),

    .busy              (svf_busy)
);

// =============================================================================
// VCA
// =============================================================================

logic vca_in_ready;
logic vca_out_valid;
logic vca_out_ready;
logic vca_busy;

logic signed [31:0] vca_sample;

assign svf_out_ready = vca_in_ready;

synth_gain u_vca(
    .clk               (clk),
    .rst_n             (rst_n),

    .in_valid          (svf_out_valid),
    .in_ready          (vca_in_ready),

    .sample_in_q3_29   (svf_sample),
    .gain_q1_31        (vca_gain_q1_31),

    .out_valid         (vca_out_valid),
    .out_ready         (vca_out_ready),

    .sample_out_q3_29  (vca_sample),
    .busy              (vca_busy)
);

// =============================================================================
// MASTER
// =============================================================================

logic master_in_ready;
logic master_out_valid;
logic master_busy;

logic signed [31:0] master_sample;

assign vca_out_ready = master_in_ready;

synth_gain u_master(
    .clk               (clk),
    .rst_n             (rst_n),

    .in_valid          (vca_out_valid),
    .in_ready          (master_in_ready),

    .sample_in_q3_29   (vca_sample),
    .gain_q1_31        (synth_master_q1_31),

    .out_valid         (master_out_valid),
    .out_ready         (1'b1),

    .sample_out_q3_29  (master_sample),
    .busy              (master_busy)
);

// =============================================================================
// GLOBAL CONTROL
// =============================================================================

assign synth_ready =
    bank_in_ready &&
    mix_in_ready &&
    svf_in_ready &&
    vca_in_ready &&
    master_in_ready;

assign synth_busy = !synth_ready;

assign launch_fire =
    synth_tick &&
    synth_ready;

// =============================================================================
// OUTPUT
// =============================================================================

assign synth_valid = master_out_valid;
assign synth_sample = master_sample;

// =============================================================================
// ASSERTIONS
// =============================================================================

`ifndef SYNTHESIS

always_ff @(posedge clk) begin
    if (rst_n && synth_tick) begin
        assert (synth_ready)
            else $error(
                "synth_hw_test: synth_tick recibido estando busy"
            );
    end
end

`endif

endmodule