`timescale 1ns/1ps

module fx_core(
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

import fx_ctrl_pkg::*;

// =============================================================================
// REGMAP CONFIGURATION
// =============================================================================

global_cfg_t      global_cfg;
frontend_cfg_t    frontend_cfg;

synth_cfg_t       synth_cfg;
osc1_cfg_t        osc1_cfg;
osc2_cfg_t        osc2_cfg;
synth_mix_cfg_t   synth_mix_cfg;
synth_svf_cfg_t   synth_svf_cfg;
synth_out_cfg_t   synth_out_cfg;

octaver_cfg_t     octaver_cfg;
wah_cfg_t         wah_cfg;
dist_cfg_t        dist_cfg;
overdrive_cfg_t   od_cfg;
overdrive_cfg_t   od_cfg_active;
tone_cfg_t        tone_cfg;
eq_cfg_t          eq_cfg;
chorus_cfg_t      chorus_cfg;
flanger_cfg_t     flanger_cfg;
tremolo_cfg_t     tremolo_cfg;
phaser_cfg_t      phaser_cfg;
delay_cfg_t       delay_cfg;
reverb_cfg_t      reverb_cfg;
cab_cfg_t         cab_cfg;
output_cfg_t      output_cfg;

// Regmap commands
logic config_commit;
logic frontend_clear;
logic synth_svf_clear;

// Additive write
logic               amp_we;
logic [4:0]         amp_addr;
logic signed [31:0] amp_wdata;

// Distortion wavetable write
logic        dist_wt_we;
logic [11:0] dist_wt_addr;
logic        dist_wt_bank, dist_wt_ready, dist_status_clear;
logic        dist_apply_ready;
logic [31:0] dist_status;
logic [31:0] dist_wt_data;

// Cab IR coefficient write
logic        cab_coef_we;
logic [9:0]  cab_coef_addr;
logic [17:0] cab_coef_data;

// =============================================================================
// STATUS
// =============================================================================

logic [31:0] audio_snoop;
logic [31:0] perf_status;
logic [31:0] output_status;

logic adapter_idle;

logic synth_ready;
logic synth_busy;

logic mixer_overdrive;
logic mixer_clip;

// =============================================================================
// FRONT-PANEL ENCODERS
// =============================================================================

logic               encoder_sample_tick;
logic signed [31:0] encoder_count [0:5];

tick_gen #(
    .DIV(2500)
) u_encoder_tick (
    .clk   (clk),
    .rst_n (rst_n),
    .tick  (encoder_sample_tick)
);

generate
    for (genvar encoder_index = 0; encoder_index < 6; encoder_index++) begin : g_encoder
        quad_decoder #(
            .CNT_W(32),
            .DB_N (8)
        ) u_decoder (
            .clk   (clk),
            .rst_n (rst_n),
            .tick  (encoder_sample_tick),
            .a_raw (enc_a[encoder_index]),
            .b_raw (enc_b[encoder_index]),
            .count (encoder_count[encoder_index]),
            .step  ()
        );
    end
endgenerate

// =============================================================================
// FRONTEND STATUS
// =============================================================================

logic signed [31:0] frontend_env;
logic signed [31:0] frontend_env_vca;

logic frontend_gate;
logic frontend_pitch_locked;

logic [31:0] frontend_period;
logic        frontend_period_valid;

logic [31:0] frontend_phase_inc;
logic        frontend_inc_valid;

// =============================================================================
// CONFIGURATION COMMIT
//
// Los registros del regmap son shadow.
//
// Algunos parametros numericos se usan directamente y pueden cambiar en vivo.
// Los controles estructurales se copian a *_active solamente mediante commit.
//
// RUN:
//   acepta muestras normalmente.
//
// DRAIN:
//   el adapter sigue recibiendo I2S en su FIFO, pero no se dejan entrar nuevas
//   muestras al DSP. Las que ya estan en la cadena terminan.
//
// APPLY:
//   cuando core_inflight_count llega a cero se cambian todos los controles
//   estructurales de forma atomica.
//
// Esto evita cambiar un bypass/source/mode con una muestra en medio del bloque.
// =============================================================================

typedef enum logic [1:0] {
    CFG_RUN,
    CFG_DRAIN,
    CFG_APPLY
} cfg_state_t;

cfg_state_t cfg_state;

logic [1:0] fx_enable_sync;
logic       fx_enable_hw_active;
logic       commit_pending;

logic [31:0] core_ctrl_active;
logic [31:0] source_ctrl_active;
logic [31:0] fx_enable_active;

logic [31:0] frontend_ctrl_active;
logic [31:0] synth_ctrl_active;
logic [31:0] osc1_ctrl_active;
logic [31:0] osc2_ctrl_active;
logic [31:0] synth_svf_ctrl_active;
logic [31:0] chorus_ctrl_active;

logic [7:0] core_inflight_count;

logic sample_enter_core;
logic sample_leave_core;

logic core_cfg_ready;
logic core_cfg_busy;

// Synchronizer for external global enable
always_ff @(posedge clk) begin
    if (!rst_n) begin
        fx_enable_sync <= 2'b00;
    end else begin
        fx_enable_sync <= {
            fx_enable_sync[0],
            fx_enable
        };
    end
end

// Number of samples currently inside the DSP datapath
always_ff @(posedge clk) begin
    if (!rst_n) begin
        core_inflight_count <= 8'd0;
    end else begin
        case ({sample_enter_core, sample_leave_core})

            2'b10:
                core_inflight_count <=
                    core_inflight_count + 1'b1;

            2'b01: begin
                if (core_inflight_count != 0)
                    core_inflight_count <=
                        core_inflight_count - 1'b1;
            end

            default:
                core_inflight_count <=
                    core_inflight_count;
        endcase
    end
end

// Structural configuration FSM
always_ff @(posedge clk) begin
    if (!rst_n) begin

        cfg_state <= CFG_RUN;

        fx_enable_hw_active <= 1'b0;
        commit_pending      <= 1'b0;

        core_ctrl_active   <= 32'h0000_0001;
        source_ctrl_active <= 32'h0000_0000;
        fx_enable_active   <= 32'h0000_0000;

        frontend_ctrl_active  <= 32'd0;
        synth_ctrl_active     <= 32'h0000_0001;
        osc1_ctrl_active      <= 32'h0000_0028;
        osc2_ctrl_active      <= 32'h0000_0008;
        synth_svf_ctrl_active <= 32'h0000_0000;
        chorus_ctrl_active    <= 32'h0000_0000;
        od_cfg_active         <= '0;

    end else begin

        case (cfg_state)

            CFG_RUN: begin

                // Software structural commit
                if (config_commit) begin
                    commit_pending <= 1'b1;
                    cfg_state      <= CFG_DRAIN;

                // Physical global enable also changes safely.
                end else if (
                    fx_enable_sync[1] !=
                    fx_enable_hw_active
                ) begin
                    commit_pending <= 1'b0;
                    cfg_state      <= CFG_DRAIN;
                end
            end

            CFG_DRAIN: begin

                // If software writes another commit while draining,
                // keep it pending and apply the latest shadow values.
                if (config_commit)
                    commit_pending <= 1'b1;

                if (core_inflight_count == 0)
                    cfg_state <= CFG_APPLY;
            end

            CFG_APPLY: begin
                // El drenado local espera tambien el ultimo descarte de los FIR.
                if (dist_apply_ready) begin

                // External enable always follows its synchronized target,
                // but only after the old pipeline has drained.
                fx_enable_hw_active <=
                    fx_enable_sync[1];

                if (commit_pending) begin
                    od_cfg_active <= od_cfg;

                    core_ctrl_active <=
                        global_cfg.core_ctrl;

                    source_ctrl_active <=
                        global_cfg.source_ctrl;

                    fx_enable_active <=
                        global_cfg.fx_enable;

                    frontend_ctrl_active <= frontend_cfg.ctrl;

                    synth_ctrl_active <=
                        synth_cfg.ctrl;

                    osc1_ctrl_active <=
                        osc1_cfg.ctrl;

                    osc2_ctrl_active <=
                        osc2_cfg.ctrl;

                    synth_svf_ctrl_active <=
                        synth_svf_cfg.ctrl;

                    chorus_ctrl_active <=
                        chorus_cfg.ctrl;
                end

                commit_pending <= 1'b0;
                cfg_state      <= CFG_RUN;
                end
            end

            default: begin
                cfg_state <= CFG_RUN;
            end

        endcase
    end
end

assign core_cfg_ready =
    (cfg_state == CFG_RUN);

assign core_cfg_busy =
    (cfg_state != CFG_RUN);

// =============================================================================
// REGMAP
// =============================================================================

fx_regmap u_regmap(
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

    .o_global_cfg           (global_cfg),
    .o_frontend_cfg         (frontend_cfg),

    .o_synth_cfg            (synth_cfg),
    .o_osc1_cfg             (osc1_cfg),
    .o_osc2_cfg             (osc2_cfg),
    .o_synth_mix_cfg        (synth_mix_cfg),
    .o_synth_svf_cfg        (synth_svf_cfg),
    .o_synth_out_cfg        (synth_out_cfg),

    .o_octaver_cfg          (octaver_cfg),
    .o_wah_cfg              (wah_cfg),
    .o_dist_cfg             (dist_cfg),
    .o_od_cfg               (od_cfg),
    .o_tone_cfg             (tone_cfg),
    .o_eq_cfg               (eq_cfg),

    .o_chorus_cfg           (chorus_cfg),
    .o_flanger_cfg          (flanger_cfg),
    .o_tremolo_cfg          (tremolo_cfg),
    .o_phaser_cfg           (phaser_cfg),

    .o_delay_cfg            (delay_cfg),
    .o_reverb_cfg           (reverb_cfg),
    .o_cab_cfg              (cab_cfg),
    .o_output_cfg           (output_cfg),

    .o_config_commit        (config_commit),
    .o_frontend_clear       (frontend_clear),
    .o_synth_svf_clear      (synth_svf_clear),

    .o_amp_we               (amp_we),
    .o_amp_addr             (amp_addr),
    .o_amp_wdata            (amp_wdata),

    .o_dist_wt_we           (dist_wt_we),
    .o_dist_wt_addr         (dist_wt_addr),
    .o_dist_wt_bank         (dist_wt_bank),
    .o_dist_status_clear    (dist_status_clear),
    .o_dist_wt_data         (dist_wt_data),

    .o_cab_coef_we          (cab_coef_we),
    .o_cab_coef_addr        (cab_coef_addr),
    .o_cab_coef_data        (cab_coef_data),

    .i_core_ready           (core_cfg_ready),
    .i_core_busy            (core_cfg_busy),

    .i_audio_snoop          (audio_snoop),
    .i_perf_status          (perf_status),

    .i_frontend_gate        (frontend_gate),
    .i_pitch_locked         (frontend_pitch_locked),
    .i_period_valid         (frontend_period_valid),
    .i_inc_valid            (frontend_inc_valid),

    .i_env_q3_29            (frontend_env),
    .i_period_16_16         (frontend_period),
    .i_pitch_phase_inc      (frontend_phase_inc),

    .i_synth_ready          (synth_ready),
    .i_synth_busy           (synth_busy),

    .i_mixer_overdrive      (mixer_overdrive),
    .i_mixer_clip           (mixer_clip),

    .i_output_status        (output_status),
    .i_dist_status          (dist_status),
    .i_enc_count            (encoder_count)
);

// =============================================================================
// GLOBAL CONTROL
// =============================================================================

logic core_active;
logic source_synth_active;
logic tone_test_active;

assign core_active =
    fx_enable_hw_active &&
    core_ctrl_active[CORE_CTRL_ENABLE_BIT];

assign source_synth_active =
    core_active &&
    source_ctrl_active[SOURCE_CTRL_SYNTH_BIT];

assign tone_test_active =
    core_ctrl_active[CORE_CTRL_TONE_TEST_BIT];

// =============================================================================
// EFFECT ENABLES
// =============================================================================

logic en_dist;
logic en_tone;
logic en_eq;

logic en_chorus;
logic en_flanger;
logic en_tremolo;
logic en_phaser;

logic en_delay;
logic en_cab;

assign en_dist =
    core_active &&
    fx_enable_active[FX_EN_DIST];

assign en_tone =
    core_active &&
    fx_enable_active[FX_EN_TONE];

assign en_eq =
    core_active &&
    fx_enable_active[FX_EN_EQ];

assign en_chorus =
    core_active &&
    fx_enable_active[FX_EN_CHORUS];

assign en_flanger =
    core_active &&
    fx_enable_active[FX_EN_FLANGER];

assign en_tremolo =
    core_active &&
    fx_enable_active[FX_EN_TREMOLO];

assign en_phaser =
    core_active &&
    fx_enable_active[FX_EN_PHASER];

assign en_delay =
    core_active &&
    fx_enable_active[FX_EN_DELAY];

assign en_cab =
    core_active &&
    fx_enable_active[FX_EN_CAB];

// =============================================================================
// AXIS MONO ADAPTER
// =============================================================================

logic               mono_valid;
logic               mono_ready;
logic               mono_dsp_ready;
logic               core_input_valid;
logic signed [31:0] mono_data;

logic               return_valid;
logic               return_ready;
logic signed [31:0] return_data;

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

    .out_valid     (return_valid),
    .out_data      (return_data),
    .out_ready     (return_ready),

    .idle          (adapter_idle)
);

// During DRAIN the adapter keeps receiving I2S into its input FIFO,
// but it is not allowed to hand another sample to the DSP.
//
// IMPORTANT:
// Gate VALID and READY together. If only READY were gated, the downstream
// DCB could still consume a sample that the adapter did not pop.
assign core_input_valid =
    mono_valid &&
    (cfg_state == CFG_RUN);

assign mono_ready =
    (cfg_state == CFG_RUN)
        ? mono_dsp_ready
        : 1'b0;

assign sample_enter_core =
    core_input_valid &&
    mono_dsp_ready;

assign sample_leave_core =
    return_valid &&
    return_ready;

// =============================================================================
// AUDIO SNOOP
// =============================================================================

always_ff @(posedge clk) begin
    if (!rst_n)
        audio_snoop <= 32'd0;
    else if (sample_enter_core)
        audio_snoop <= mono_data;
end

// =============================================================================
// INPUT DCB
// =============================================================================

logic               input_valid;
logic               input_ready;
logic signed [31:0] input_data;

fx_dcb_byp u_input_dcb(
    .clk       (clk),
    .rst_n     (rst_n),

    .enable    (core_active),

    .in_valid  (core_input_valid),
    .in_ready  (mono_dsp_ready),
    .in_data   (mono_data),

    .out_valid (input_valid),
    .out_ready (input_ready),
    .out_data  (input_data)
);

// =============================================================================
// THEREMIN FRONTEND
// =============================================================================

logic frontend_sample_valid;
logic frontend_rst_n;

assign frontend_sample_valid =
    input_valid &&
    input_ready;

assign frontend_rst_n =
    rst_n &&
    !frontend_clear;

fx_synth_frontend #(
    .ENV_VCA_SHIFT(4),
    .PITCH_YIN(1'b1)
) u_synth_frontend(
    .clk               (clk),
    .rst_n             (frontend_rst_n),

    .sample_valid      (frontend_sample_valid),
    .sample_data_q3_29 (input_data),

    .env_gain_q1_31    (
        $signed(frontend_cfg.env_gain_q1_31)
    ),
    .env_attack_q1_31  (frontend_cfg.env_attack_q1_31),
    .env_release_q1_31 (frontend_cfg.env_release_q1_31),
    .gate_on_thr_q3_29 (frontend_cfg.gate_on_thr_q3_29),
    .gate_off_thr_q3_29(frontend_cfg.gate_off_thr_q3_29),
    .zc_hyst_q3_29     (frontend_cfg.zc_hyst_q3_29),
    .glide_shift       (5'd0),
    .pitch_ctrl        (frontend_cfg.pitch_ctrl),
    .pitch_cfg2        (frontend_cfg.pitch_cfg2),

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
// SYNTH REALTIME CONTROL
//
// Numeric parameters remain live:
// - phase_inc
// - pulse width
// - detune
// - levels
// - bus trim
// - coefficients
// - VCA/master
//
// Structural CTRL fields use the committed *_active versions.
// =============================================================================

logic [31:0] synth_phase_inc;

logic signed [31:0] synth_vca_gain;
logic signed [31:0] synth_master_gain;

logic [31:0] synth_svf_ctrl_effective;

// YIN fija la frecuencia; la envolvente de entrada controla el volumen.
// Se conserva la ultima afinacion al cerrar, sin recurrir a una nota manual.
assign synth_phase_inc = frontend_phase_inc;
// >>> VCA_RAMPA
// VCA del synth: min(envolvente, rampa).
//
// La afinacion valida llega 8-30 ms despues del ataque (latencia de YIN).
// Hasta entonces el VCA esta en 0, pero la envolvente ya subio al pico de la
// pua: usar la envolvente directa produciria un escalon 0 -> pico (golpe).
// Con min(envolvente, rampa) la voz entra en ~4 ms (205 muestras) y despues
// sigue a la envolvente. Al perder la afinacion (gate cerrado) el nivel baja
// linealmente a 0 en vez de cortar. Solo comparadores y sumas: sin DSP.
localparam logic signed [31:0] SYNTH_VCA_MAX     = 32'sh7FFF_FFFF;
localparam logic signed [31:0] SYNTH_VCA_RAMP_UP = 32'sh00A0_0000;  // 0 -> max en ~205 muestras (4,3 ms)
localparam logic signed [31:0] SYNTH_VCA_RAMP_DN = 32'sh00A0_0000;  // max -> 0 en ~205 muestras

logic signed [31:0] synth_vca_ramp;
logic signed [31:0] synth_vca_level;

always_ff @(posedge clk) begin
    if (!rst_n) begin
        synth_vca_ramp  <= 32'sd0;
        synth_vca_level <= 32'sd0;
    end else if (frontend_sample_valid) begin
        if (frontend_pitch_locked) begin
            if (synth_vca_ramp >= SYNTH_VCA_MAX - SYNTH_VCA_RAMP_UP)
                synth_vca_ramp <= SYNTH_VCA_MAX;
            else
                synth_vca_ramp <= synth_vca_ramp + SYNTH_VCA_RAMP_UP;

            if (frontend_env_vca <= 32'sd0)
                synth_vca_level <= 32'sd0;
            else if (frontend_env_vca < synth_vca_ramp)
                synth_vca_level <= frontend_env_vca;
            else
                synth_vca_level <= synth_vca_ramp;
        end else begin
            synth_vca_ramp <= 32'sd0;
            if (synth_vca_level <= SYNTH_VCA_RAMP_DN)
                synth_vca_level <= 32'sd0;
            else
                synth_vca_level <= synth_vca_level - SYNTH_VCA_RAMP_DN;
        end
    end
end

assign synth_vca_gain = synth_vca_level;
// <<< VCA_RAMPA

assign synth_master_gain =
    (
        !synth_ctrl_active[0] ||
        synth_out_cfg.ctrl[0]
    )
        ? 32'sd0
        : $signed(synth_out_cfg.master_q1_31);

assign synth_svf_ctrl_effective =
    synth_svf_ctrl_active |
    (
        synth_svf_clear
            ? 32'h0000_0008
            : 32'h0000_0000
    );

// =============================================================================
// SYNTH ENGINE
// =============================================================================

logic synth_tick;
logic synth_valid;

logic signed [31:0] synth_sample;

synth_hw_test u_synth(
    .clk                  (clk),
    .rst_n                (rst_n),

    .synth_tick           (synth_tick),
    .synth_valid          (synth_valid),
    .synth_sample         (synth_sample),

    .base_phase_inc       (synth_phase_inc),

    .osc1_mode            (osc1_ctrl_active[1:0]),
    .osc1_range           (osc1_ctrl_active[4:2]),
    .osc1_pulse_width     (osc1_cfg.pulse_width),
    .osc1_n_harmonics     (osc1_ctrl_active[10:5]),

    .amp_we               (amp_we),
    .amp_addr             (amp_addr),
    .amp_wdata            (amp_wdata),

    .osc2_waveform        (osc2_ctrl_active[1:0]),
    .osc2_range           (osc2_ctrl_active[4:2]),
    .osc2_pulse_width     (osc2_cfg.pulse_width),
    .osc2_detune_q2_30    (osc2_cfg.detune_q2_30),

    .noise_ctrl           (32'd0),
    .noise_seed           (32'd0),

    .osc1_level_q1_31     (osc1_cfg.level_q1_31),
    .osc2_level_q1_31     (osc2_cfg.level_q1_31),
    .noise_level_q1_31    (
        32'd0
    ),

    .mix_softclip_enable  (1'b0),

    .mix_bus_trim_q1_31   (
        synth_mix_cfg.bus_trim_q1_31
    ),

    .mix_t1_q3_29         (32'sh1999_999A),
    .mix_t2_q3_29         (32'sh2666_6666),
    .mix_k1_q1_31         (32'sh4000_0000),
    .mix_k2_q1_31         (32'sh0000_0000),

    .svf_ctrl             (synth_svf_ctrl_effective),
    .svf_a1_q1_31         (synth_svf_cfg.a1_q1_31),
    .svf_a2_q1_31         (synth_svf_cfg.a2_q1_31),
    .svf_a3_q1_31         (synth_svf_cfg.a3_q1_31),
    .svf_k_q3_29          (synth_svf_cfg.k_q3_29),

    .vca_gain_q1_31       (synth_vca_gain),
    .synth_master_q1_31   (synth_master_gain),

    .output_sel           (synth_ctrl_active[2:1]),

    .synth_ready          (synth_ready),
    .synth_busy           (synth_busy),

    .mixer_overdrive      (mixer_overdrive),
    .mixer_clip           (mixer_clip)
);

// =============================================================================
// SOURCE ROUTER
// =============================================================================

logic               source_valid;
logic               source_ready;
logic signed [31:0] source_data;

fx_source_router u_source_router(
    .clk           (clk),
    .rst_n         (rst_n),

    .source_select (source_synth_active),

    .audio_valid   (input_valid),
    .audio_ready   (input_ready),
    .audio_data    (input_data),

    .synth_tick    (synth_tick),
    .synth_ready   (synth_ready),
    .synth_valid   (synth_valid),
    .synth_data    (synth_sample),

    .out_valid     (source_valid),
    .out_ready     (source_ready),
    .out_data      (source_data)
);

// =============================================================================
// OCTAVER PLACEHOLDER
// =============================================================================

logic               oct_valid;
logic               oct_ready;
logic signed [31:0] oct_data;

assign oct_valid    = source_valid;
assign source_ready = oct_ready;
assign oct_data     = source_data;

// =============================================================================
// WAH PLACEHOLDER
// =============================================================================

logic               wah_valid;
logic               wah_ready;
logic signed [31:0] wah_data;

assign wah_valid = oct_valid;
assign oct_ready = wah_ready;
assign wah_data  = oct_data;

// =============================================================================
// DISTORTION SECTION
// =============================================================================

logic               dist_valid;
logic               dist_ready;
logic signed [31:0] dist_data;

// Enable que se aplicara en el mismo flanco que los parametros del overdrive.
wire [31:0] dist_core_target = commit_pending ? global_cfg.core_ctrl : core_ctrl_active;
wire [31:0] dist_fx_target = commit_pending ? global_cfg.fx_enable : fx_enable_active;
wire dist_enable_target = fx_enable_sync[1] && dist_core_target[CORE_CTRL_ENABLE_BIT] && dist_fx_target[FX_EN_DIST];

fx_dist_section u_dist_section(
    .clk        (clk),
    .rst_n      (rst_n),

    .enable     (dist_enable_target),
    .cfg_apply  (cfg_state == CFG_APPLY),
    .cfg_ready  (dist_apply_ready),

    .in_valid   (wah_valid),
    .in_ready   (wah_ready),
    .in_data    (wah_data),

    .out_valid  (dist_valid),
    .out_ready  (dist_ready),
    .out_data   (dist_data),

    .od_cfg     (commit_pending ? od_cfg : od_cfg_active),

    .wt_wr_en   (dist_wt_we),
    .wt_wr_ready(dist_wt_ready),
    .wt_wr_bank (dist_wt_bank),
    .status_clear(dist_status_clear),
    .status     (dist_status),
    .wt_wr_addr (dist_wt_addr),
    .wt_wr_data (dist_wt_data)
);

// =============================================================================
// TONE / EQ
// =============================================================================

logic               tone_eq_valid;
logic               tone_eq_ready;
logic signed [31:0] tone_eq_data;

fx_tone_eq u_tone_eq(
    .clk         (clk),
    .rst_n       (rst_n),

    .enable_tone (en_tone),
    .enable_eq   (en_eq),

    .in_valid    (dist_valid),
    .in_ready    (dist_ready),
    .in_data     (dist_data),

    .out_valid   (tone_eq_valid),
    .out_ready   (tone_eq_ready),
    .out_data    (tone_eq_data),

    .tone_cfg    (tone_cfg),
    .eq_cfg      (eq_cfg)
);

// =============================================================================
// MODULATION
//
// chorus_cfg.ctrl is structural because ctrl[0] selects its internal LPF.
// Numeric chorus parameters remain live.
// =============================================================================

chorus_cfg_t chorus_cfg_effective;

always_comb begin
    chorus_cfg_effective = chorus_cfg;
    chorus_cfg_effective.ctrl = chorus_ctrl_active;
end

logic               mod_valid;
logic               mod_ready;
logic signed [31:0] mod_data;

fx_mod_section u_mod_section(
    .clk            (clk),
    .rst_n          (rst_n),

    .enable_chorus  (en_chorus),
    .enable_flanger (en_flanger),
    .enable_tremolo (en_tremolo),
    .enable_phaser  (en_phaser),

    .in_valid       (tone_eq_valid),
    .in_ready       (tone_eq_ready),
    .in_data        (tone_eq_data),

    .out_valid      (mod_valid),
    .out_ready      (mod_ready),
    .out_data       (mod_data),

    .chorus_cfg     (chorus_cfg_effective),
    .flanger_cfg    (flanger_cfg),
    .tremolo_cfg    (tremolo_cfg),
    .phaser_cfg     (phaser_cfg)
);

// =============================================================================
// DELAY
// =============================================================================

logic               delay_valid;
logic               delay_ready;
logic signed [31:0] delay_data;

fx_delay_simple #(
    .ADDR_W(15)
) u_delay(
    .clk        (clk),
    .rst_n      (rst_n),

    .enable     (en_delay),

    .in_valid   (mod_valid),
    .in_ready   (mod_ready),
    .in_data    (mod_data),

    .out_valid  (delay_valid),
    .out_ready  (delay_ready),
    .out_data   (delay_data),

    .D_16_16    (delay_cfg.time_16_16),
    .fb_q1_31   ($signed(delay_cfg.fb_q1_31)),
    .wet_q1_31  ($signed(delay_cfg.wet_q1_31))
);

// =============================================================================
// REVERB PLACEHOLDER
// =============================================================================

logic               reverb_valid;
logic               reverb_ready;
logic signed [31:0] reverb_data;

assign reverb_valid = delay_valid;
assign delay_ready  = reverb_ready;
assign reverb_data  = delay_data;

// =============================================================================
// CAB SIM
// =============================================================================

logic               cab_valid;
logic               cab_ready;
logic signed [31:0] cab_data;

fx_cabsim u_cab(
    .clk       (clk),
    .rst_n     (rst_n),

    .enable    (en_cab),

    .in_valid  (reverb_valid),
    .in_ready  (reverb_ready),
    .in_data   (reverb_data),

    .out_valid (cab_valid),
    .out_ready (cab_ready),
    .out_data  (cab_data),

    .level_q1_31 (cab_cfg.level_q1_31),

    .coef_we   (cab_coef_we),
    .coef_addr (cab_coef_addr),
    .coef_data (cab_coef_data)
);

// =============================================================================
// OUTPUT STAGE
// =============================================================================

logic [31:0] output_ctrl_effective;
logic signed [31:0] output_level_effective;

logic output_stage_busy;

logic               output_valid;
logic               output_ready;
logic signed [31:0] output_data;

assign output_ctrl_effective =
    core_active
        ? output_cfg.ctrl
        : 32'd0;

assign output_level_effective =
    core_active
        ? $signed(output_cfg.level_q1_31)
        : 32'sh7FFF_FFFF;

fx_output_stage u_output_stage(
    .clk                     (clk),
    .rst_n                   (rst_n),

    .in_valid                (cab_valid),
    .in_ready                (cab_ready),
    .in_data                 (cab_data),

    .out_valid               (output_valid),
    .out_ready               (output_ready),
    .out_data                (output_data),

    .ctrl                    (output_ctrl_effective),
    .level_q1_31             (output_level_effective),

    .limiter_threshold_q3_29 (
        output_cfg.limiter_threshold_q3_29
    ),

    .busy                    (output_stage_busy)
);

// =============================================================================
// TONE TEST
// =============================================================================

logic signed [31:0] tone_sample;
logic [5:0] tone_count;

always_ff @(posedge clk) begin
    if (!rst_n) begin
        tone_count  <= 6'd0;
        tone_sample <= 32'sh0800_0000;
    end else if (
        return_valid &&
        return_ready
    ) begin
        if (tone_count == 6'd53) begin
            tone_count  <= 6'd0;
            tone_sample <= -tone_sample;
        end else begin
            tone_count <= tone_count + 1'b1;
        end
    end
end

assign return_valid =
    output_valid;

assign output_ready =
    return_ready;

assign return_data =
    tone_test_active
        ? tone_sample
        : output_data;

// =============================================================================
// STATUS
// =============================================================================
//
// PERF_STATUS:
// bit0      adapter fully idle
// bit1      config drain/apply busy
// bits9:2   number of samples currently inside DSP
// =============================================================================

assign perf_status = {
    22'd0,
    core_inflight_count,
    core_cfg_busy,
    adapter_idle
};

assign output_status = {
    30'd0,
    1'b0,
    output_stage_busy
};

// =============================================================================
// RESERVED CONFIG
// =============================================================================

logic unused_config;

always_comb begin
    unused_config =
        ^octaver_cfg ^
        ^wah_cfg ^
        ^reverb_cfg ^
        ^cab_cfg.ctrl;
end

// =============================================================================
// SIMULATION CHECKS
// =============================================================================

`ifndef SYNTHESIS

always_ff @(posedge clk) begin
    if (rst_n) begin

        if (
            cfg_state != CFG_RUN &&
            sample_enter_core
        )
            $error(
                "fx_core: sample entered DSP while configuration was draining"
            );

        if (
            sample_leave_core &&
            core_inflight_count == 0 &&
            !sample_enter_core
        )
            $error(
                "fx_core: output sample without an inflight input sample"
            );
    end
end

`endif

endmodule
