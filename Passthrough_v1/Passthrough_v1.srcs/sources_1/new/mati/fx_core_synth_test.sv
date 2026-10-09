`timescale 1ns/1ps

module fx_core_synth_test(
    input logic clk,
    input logic rst_n,
    input logic fx_enable,

    // AXI4-Lite
    input  logic [31:0] s_axi_awaddr,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,

    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,

    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,

    input  logic [31:0] s_axi_araddr,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,

    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    // AXIS RX
    input  logic [31:0] s_axis_tdata,
    input  logic [2:0]  s_axis_tid,
    input  logic        s_axis_tvalid,
    output logic        s_axis_tready,

    // AXIS TX
    output logic [31:0] m_axis_tdata,
    output logic [2:0]  m_axis_tid,
    output logic        m_axis_tvalid,
    input  logic        m_axis_tready,

    input logic [5:0] enc_a,
    input logic [5:0] enc_b
);

// =============================================================================
// REGMAP SIGNALS
// =============================================================================

logic        reg_enable;
logic [1:0]  reg_output_sel;
logic [31:0] reg_base_phase_inc;

// OSC1
logic [1:0]  reg_osc1_mode;
logic [2:0]  reg_osc1_range;
logic [31:0] reg_osc1_pw;
logic [5:0]  reg_osc1_nharm;

// OSC2
logic [1:0]  reg_osc2_waveform;
logic [2:0]  reg_osc2_range;
logic [31:0] reg_osc2_pw;
logic [31:0] reg_osc2_detune;

// Additive amplitudes
logic               reg_amp_we;
logic [4:0]         reg_amp_addr;
logic signed [31:0] reg_amp_wdata;

// Mixer
logic [31:0] reg_osc1_level;
logic [31:0] reg_osc2_level;
logic [31:0] reg_noise_level;

logic        reg_mix_softclip_enable;
logic [31:0] reg_mix_bus_trim;

logic signed [31:0] reg_mix_t1;
logic signed [31:0] reg_mix_t2;
logic signed [31:0] reg_mix_k1;
logic signed [31:0] reg_mix_k2;

// Noise
logic [31:0] reg_noise_ctrl;
logic [31:0] reg_noise_seed;

// SVF
logic [31:0]        reg_svf_ctrl;
logic signed [31:0] reg_svf_a1;
logic signed [31:0] reg_svf_a2;
logic signed [31:0] reg_svf_a3;
logic signed [31:0] reg_svf_k;
logic [31:0]        reg_svf_drive;

// VCA / envelope / master
logic [31:0] reg_vca_ctrl;
logic [31:0] reg_env_gain;
logic [31:0] reg_synth_master;

// LFO
logic [31:0] reg_lfo_ctrl;
logic [31:0] reg_lfo_rate;
logic [31:0] reg_lfo_depth;

// Status
logic synth_ready;
logic synth_busy;
logic mixer_overdrive;
logic mixer_clip;

// =============================================================================
// REGMAP
// =============================================================================

fx_regmap_synth u_regmap(
    .clk                    (clk),
    .rst_n                  (rst_n),

    .s_axi_awaddr           (s_axi_awaddr),
    .s_axi_awvalid          (s_axi_awvalid),
    .s_axi_awready          (s_axi_awready),

    .s_axi_wdata            (s_axi_wdata),
    .s_axi_wstrb            (s_axi_wstrb),
    .s_axi_wvalid           (s_axi_wvalid),
    .s_axi_wready           (s_axi_wready),

    .s_axi_bresp            (s_axi_bresp),
    .s_axi_bvalid           (s_axi_bvalid),
    .s_axi_bready           (s_axi_bready),

    .s_axi_araddr           (s_axi_araddr),
    .s_axi_arvalid          (s_axi_arvalid),
    .s_axi_arready          (s_axi_arready),

    .s_axi_rdata            (s_axi_rdata),
    .s_axi_rresp            (s_axi_rresp),
    .s_axi_rvalid           (s_axi_rvalid),
    .s_axi_rready           (s_axi_rready),

    .o_enable               (reg_enable),
    .o_output_sel           (reg_output_sel),
    .o_base_phase_inc       (reg_base_phase_inc),

    .o_osc1_mode            (reg_osc1_mode),
    .o_osc1_range           (reg_osc1_range),
    .o_osc1_pulse_width     (reg_osc1_pw),
    .o_osc1_n_harmonics     (reg_osc1_nharm),

    .o_osc2_waveform        (reg_osc2_waveform),
    .o_osc2_range           (reg_osc2_range),
    .o_osc2_pulse_width     (reg_osc2_pw),
    .o_osc2_detune_q2_30    (reg_osc2_detune),

    .o_amp_we               (reg_amp_we),
    .o_amp_addr             (reg_amp_addr),
    .o_amp_wdata            (reg_amp_wdata),

    .o_osc1_level_q1_31     (reg_osc1_level),
    .o_osc2_level_q1_31     (reg_osc2_level),
    .o_noise_level_q1_31    (reg_noise_level),

    .o_mix_softclip_enable  (reg_mix_softclip_enable),
    .o_mix_bus_trim_q1_31   (reg_mix_bus_trim),

    .o_mix_t1_q3_29         (reg_mix_t1),
    .o_mix_t2_q3_29         (reg_mix_t2),
    .o_mix_k1_q1_31         (reg_mix_k1),
    .o_mix_k2_q1_31         (reg_mix_k2),

    .o_noise_ctrl           (reg_noise_ctrl),
    .o_noise_seed           (reg_noise_seed),

    .o_svf_ctrl             (reg_svf_ctrl),
    .o_svf_a1_q1_31         (reg_svf_a1),
    .o_svf_a2_q1_31         (reg_svf_a2),
    .o_svf_a3_q1_31         (reg_svf_a3),
    .o_svf_k_q3_29          (reg_svf_k),
    .o_svf_drive            (reg_svf_drive),

    .o_vca_ctrl             (reg_vca_ctrl),
    .o_env_gain_q1_31       (reg_env_gain),
    .o_synth_master_q1_31   (reg_synth_master),

    .o_lfo_ctrl             (reg_lfo_ctrl),
    .o_lfo_rate             (reg_lfo_rate),
    .o_lfo_depth            (reg_lfo_depth),

    .i_synth_ready          (synth_ready),
    .i_synth_busy           (synth_busy),
    .i_mixer_overdrive      (mixer_overdrive),
    .i_mixer_clip           (mixer_clip)
);

// =============================================================================
// AXIS MONO ADAPTER
// =============================================================================

logic               mono_valid;
logic               mono_ready;
logic signed [31:0] mono_data;

logic               ret_valid;
logic               ret_ready;
logic signed [31:0] ret_data;

logic adapter_idle;

logic mono_fire;
logic ret_fire;

fx_axis_mono_adapter u_adapter(
    .clk           (clk),
    .rst_n         (rst_n),

    .s_axis_tdata  (s_axis_tdata),
    .s_axis_tid    (s_axis_tid),
    .s_axis_tvalid (s_axis_tvalid),
    .s_axis_tready (s_axis_tready),

    .m_axis_tdata  (m_axis_tdata),
    .m_axis_tid    (m_axis_tid),
    .m_axis_tvalid (m_axis_tvalid),
    .m_axis_tready (m_axis_tready),

    .in_valid      (mono_valid),
    .in_data       (mono_data),
    .in_ready      (mono_ready),

    .out_valid     (ret_valid),
    .out_data      (ret_data),
    .out_ready     (ret_ready),

    .idle          (adapter_idle)
);

// =============================================================================
// STREAM BRIDGE
// =============================================================================

logic               bridge_in_valid;
logic               bridge_in_ready;

logic               bridge_out_valid;
logic               bridge_out_ready;
logic signed [31:0] bridge_out_data;

logic               synth_tick;
logic               synth_valid;
logic signed [31:0] synth_sample;

synth_stream_bridge u_bridge(
    .clk          (clk),
    .rst_n        (rst_n),

    .in_valid     (bridge_in_valid),
    .in_data      (mono_data),
    .in_ready     (bridge_in_ready),

    .out_valid    (bridge_out_valid),
    .out_data     (bridge_out_data),
    .out_ready    (bridge_out_ready),

    .synth_tick   (synth_tick),
    .synth_sample (synth_sample),
    .synth_valid  (synth_valid)
);

// =============================================================================
// THEREMIN FRONTEND
// =============================================================================

logic signed [31:0] frontend_env;
logic signed [31:0] frontend_env_vca;

logic frontend_gate;
logic frontend_pitch_locked;

logic [31:0] frontend_period;
logic        frontend_period_valid;

logic [31:0] frontend_phase_inc;
logic        frontend_inc_valid;

// Selecciones finales hacia el synth
logic signed [31:0] synth_vca_gain;
logic        [31:0] synth_phase_inc;

fx_synth_frontend #(
    .ENV_VCA_SHIFT(4)
) u_synth_frontend(
    .clk               (clk),
    .rst_n             (rst_n),

    .sample_valid      (mono_fire),
    .sample_data_q3_29 (mono_data),

    .env_gain_q1_31    ($signed(reg_env_gain)),
    .env_attack_q1_31  (32'sh7F77_C02F),
    .env_release_q1_31 (32'sh7FFB_72FF),
    .gate_on_thr_q3_29 (32'sh0051_EB85),
    .gate_off_thr_q3_29(32'sh0028_F5C3),
    .zc_hyst_q3_29     (32'sh0008_3127),
    .glide_shift       (5'd8),
    .pitch_ctrl        (fx_ctrl_pkg::PITCH_CTRL_GUITARRA),
    .pitch_cfg2        (fx_ctrl_pkg::PITCH_CFG2_DEFAULT),

    .env_q3_29         (frontend_env),
    .env_vca_q1_31     (frontend_env_vca),

    .gate              (frontend_gate),
    .pitch_locked      (frontend_pitch_locked),

    .period_16_16      (frontend_period),
    .period_valid      (frontend_period_valid),

    .base_phase_inc    (frontend_phase_inc),
    .inc_valid         (frontend_inc_valid),

    .pitch_ataque      (),
    .pitch_overrun     ()
);

// =============================================================================
// VCA / PITCH SELECT
//
// REG_VCA_CTRL
//
// bit0:
//   0 = VCA abierto / unity
//   1 = VCA controlado por envelope
//
// bit1:
//   0 = pitch fijo escrito por PS
//   1 = pitch detectado desde ADC
//
// Mientras no exista pitch lock, se conserva el pitch del PS.
// Cuando gate cae, pitch_locked vuelve a 0.
// =============================================================================

assign synth_vca_gain =
    reg_vca_ctrl[0]
        ? frontend_env_vca
        : 32'sh7FFF_FFFF;

assign synth_phase_inc =
    (reg_vca_ctrl[1] && frontend_pitch_locked)
        ? frontend_phase_inc
        : reg_base_phase_inc;

// =============================================================================
// SYNTH
// =============================================================================

synth_hw_test u_synth_hw(
    .clk                  (clk),
    .rst_n                (rst_n),

    .synth_tick           (synth_tick),
    .synth_valid          (synth_valid),
    .synth_sample         (synth_sample),

    .base_phase_inc       (synth_phase_inc),

    .osc1_mode            (reg_osc1_mode),
    .osc1_range           (reg_osc1_range),
    .osc1_pulse_width     (reg_osc1_pw),
    .osc1_n_harmonics     (reg_osc1_nharm),

    .amp_we               (reg_amp_we),
    .amp_addr             (reg_amp_addr),
    .amp_wdata            (reg_amp_wdata),

    .osc2_waveform        (reg_osc2_waveform),
    .osc2_range           (reg_osc2_range),
    .osc2_pulse_width     (reg_osc2_pw),
    .osc2_detune_q2_30    (reg_osc2_detune),

    .noise_ctrl           (reg_noise_ctrl),
    .noise_seed           (reg_noise_seed),

    .osc1_level_q1_31     (reg_osc1_level),
    .osc2_level_q1_31     (reg_osc2_level),
    .noise_level_q1_31    (reg_noise_level),

    .mix_softclip_enable  (reg_mix_softclip_enable),
    .mix_bus_trim_q1_31   (reg_mix_bus_trim),

    .mix_t1_q3_29         (reg_mix_t1),
    .mix_t2_q3_29         (reg_mix_t2),
    .mix_k1_q1_31         (reg_mix_k1),
    .mix_k2_q1_31         (reg_mix_k2),

    .svf_ctrl             (reg_svf_ctrl),
    .svf_a1_q1_31         (reg_svf_a1),
    .svf_a2_q1_31         (reg_svf_a2),
    .svf_a3_q1_31         (reg_svf_a3),
    .svf_k_q3_29          (reg_svf_k),

    .vca_gain_q1_31       (synth_vca_gain),
    .synth_master_q1_31   ($signed(reg_synth_master)),

    .output_sel           (reg_output_sel),

    .synth_ready          (synth_ready),
    .synth_busy           (synth_busy),

    .mixer_overdrive      (mixer_overdrive),
    .mixer_clip           (mixer_clip)
);

// =============================================================================
// BYPASS / SYNTH ROUTING
// =============================================================================

logic synth_enable;

logic route_active;
logic route_synth_r;

logic               bypass_valid;
logic signed [31:0] bypass_data;

assign synth_enable = reg_enable;

always_comb begin
    if (route_active) begin
        mono_ready = 1'b0;
    end else if (synth_enable) begin
        mono_ready =
            bridge_in_ready &&
            synth_ready;
    end else begin
        mono_ready = 1'b1;
    end
end

assign mono_fire =
    mono_valid &&
    mono_ready;

assign bridge_in_valid =
    mono_valid &&
    mono_ready &&
    synth_enable;

assign bridge_out_ready =
    route_active &&
    route_synth_r &&
    ret_ready;

always_comb begin
    ret_valid = 1'b0;
    ret_data = 32'sd0;

    if (route_active) begin
        if (route_synth_r) begin
            ret_valid = bridge_out_valid;
            ret_data = bridge_out_data;
        end else begin
            ret_valid = bypass_valid;
            ret_data = bypass_data;
        end
    end
end

assign ret_fire =
    ret_valid &&
    ret_ready;

// =============================================================================
// ROUTE STATE
// =============================================================================

always_ff @(posedge clk) begin
    if (!rst_n) begin
        route_active <= 1'b0;
        route_synth_r <= 1'b0;

        bypass_valid <= 1'b0;
        bypass_data <= 32'sd0;
    end else begin
        if (mono_fire) begin
            route_active <= 1'b1;
            route_synth_r <= synth_enable;

            if (!synth_enable) begin
                bypass_data <= mono_data;
                bypass_valid <= 1'b1;
            end
        end

        if (ret_fire) begin
            route_active <= 1'b0;

            if (!route_synth_r)
                bypass_valid <= 1'b0;
        end
    end
end

// =============================================================================
// UNUSED / FUTURE
// =============================================================================

logic unused_inputs;

always_comb begin
    unused_inputs =
        fx_enable ^
        ^enc_a ^
        ^enc_b ^
        adapter_idle ^
        ^reg_svf_drive ^
        ^reg_lfo_ctrl ^
        ^reg_lfo_rate ^
        ^reg_lfo_depth ^
        frontend_period_valid ^
        frontend_inc_valid ^
        ^frontend_env ^
        frontend_gate ^
        ^frontend_period;
end

// =============================================================================
// ASSERTIONS
// =============================================================================

`ifndef SYNTHESIS

always_ff @(posedge clk) begin
    if (
        rst_n &&
        bridge_in_valid &&
        bridge_in_ready
    ) begin
        assert (synth_ready)
            else $error(
                "fx_core_synth_test: synth iniciado estando busy"
            );
    end
end

`endif

endmodule
