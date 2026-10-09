`timescale 1ns/1ps

module fx_regmap(
    input logic clk,
    input logic rst_n,

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

    // Grouped configuration
    output fx_ctrl_pkg::global_cfg_t     o_global_cfg,
    output fx_ctrl_pkg::frontend_cfg_t   o_frontend_cfg,
    output fx_ctrl_pkg::synth_cfg_t      o_synth_cfg,
    output fx_ctrl_pkg::osc1_cfg_t       o_osc1_cfg,
    output fx_ctrl_pkg::osc2_cfg_t       o_osc2_cfg,
    output fx_ctrl_pkg::synth_mix_cfg_t  o_synth_mix_cfg,
    output fx_ctrl_pkg::synth_svf_cfg_t  o_synth_svf_cfg,
    output fx_ctrl_pkg::synth_out_cfg_t  o_synth_out_cfg,

    output fx_ctrl_pkg::octaver_cfg_t    o_octaver_cfg,
    output fx_ctrl_pkg::wah_cfg_t        o_wah_cfg,
    output fx_ctrl_pkg::dist_cfg_t       o_dist_cfg, // registros anteriores, solo lectura/escritura
    output fx_ctrl_pkg::overdrive_cfg_t  o_od_cfg,
    output fx_ctrl_pkg::tone_cfg_t       o_tone_cfg,
    output fx_ctrl_pkg::eq_cfg_t         o_eq_cfg,
    output fx_ctrl_pkg::chorus_cfg_t     o_chorus_cfg,
    output fx_ctrl_pkg::flanger_cfg_t    o_flanger_cfg,
    output fx_ctrl_pkg::tremolo_cfg_t    o_tremolo_cfg,
    output fx_ctrl_pkg::phaser_cfg_t     o_phaser_cfg,
    output fx_ctrl_pkg::delay_cfg_t      o_delay_cfg,
    output fx_ctrl_pkg::reverb_cfg_t     o_reverb_cfg,
    output fx_ctrl_pkg::cab_cfg_t        o_cab_cfg,
    output fx_ctrl_pkg::output_cfg_t     o_output_cfg,

    // One-cycle commands
    output logic               o_config_commit,
    output logic               o_frontend_clear,
    output logic               o_synth_svf_clear,

    // Additive amplitude write port
    output logic               o_amp_we,
    output logic [4:0]         o_amp_addr,
    output logic signed [31:0] o_amp_wdata,

    // Distortion wavetable write port
    output logic               o_dist_wt_we,
    output logic [11:0]        o_dist_wt_addr,
    output logic               o_dist_wt_bank,
    output logic               o_dist_status_clear,
    output logic [31:0]        o_dist_wt_data,

    // Cab IR coefficient write port (1024 taps, Q1.17)
    output logic               o_cab_coef_we,
    output logic [9:0]         o_cab_coef_addr,
    output logic [17:0]        o_cab_coef_data,

    // Read-only status
    input logic        i_core_ready,
    input logic        i_core_busy,
    input logic [31:0] i_audio_snoop,
    input logic [31:0] i_perf_status,

    input logic        i_frontend_gate,
    input logic        i_pitch_locked,
    input logic        i_period_valid,
    input logic        i_inc_valid,
    input logic signed [31:0] i_env_q3_29,
    input logic [31:0] i_period_16_16,
    input logic [31:0] i_pitch_phase_inc,

    input logic        i_synth_ready,
    input logic        i_synth_busy,
    input logic        i_mixer_overdrive,
    input logic        i_mixer_clip,

    input logic [31:0] i_output_status,
    input logic [31:0] i_dist_status,

    // Front-panel encoder counters
    input logic signed [31:0] i_enc_count [0:5]
);

import fx_ctrl_pkg::*;

// =============================================================================
// AXI WRITE CAPTURE
// =============================================================================

logic [31:0] awaddr_r;
logic        aw_pending;

logic [31:0] wdata_r;
logic [3:0]  wstrb_r;
logic        w_pending;

logic [11:0] wr_off;
logic [11:0] rd_off;

logic [31:0] amp_shadow [0:31];

logic [11:0] dist_wt_addr_r;
logic        dist_wt_bank_r;
logic [31:0] dist_wt_data_r;

logic [9:0]  cab_coef_addr_r;
logic [31:0] cab_coef_data_r;

assign wr_off = {awaddr_r[11:2], 2'b00};
assign rd_off = {s_axi_araddr[11:2], 2'b00};

assign s_axi_awready =
    rst_n &&
    !aw_pending &&
    !s_axi_bvalid;

assign s_axi_wready =
    rst_n &&
    !w_pending &&
    !s_axi_bvalid;

assign s_axi_bresp = 2'b00;

// =============================================================================
// WSTRB
// =============================================================================

function automatic logic [31:0] apply_wstrb(
    input logic [31:0] old_value,
    input logic [31:0] new_value,
    input logic [3:0]  strb
);
logic [31:0] result;
integer i;
begin
    result = old_value;

    for (i = 0; i < 4; i = i + 1) begin
        if (strb[i])
            result[i*8 +: 8] = new_value[i*8 +: 8];
    end

    apply_wstrb = result;
end
endfunction

// =============================================================================
// WRITE PATH
// =============================================================================

integer k;
logic [31:0] merged_w;
logic [4:0]  amp_index_w;

assign amp_index_w =
    (wr_off - REG_ADD_AMP_BASE) >> 2;

always_ff @(posedge clk) begin
    if (!rst_n) begin
        awaddr_r <= 32'd0;
        aw_pending <= 1'b0;

        wdata_r <= 32'd0;
        wstrb_r <= 4'd0;
        w_pending <= 1'b0;

        s_axi_bvalid <= 1'b0;

        // Commands
        o_config_commit <= 1'b0;
        o_frontend_clear <= 1'b0;
        o_synth_svf_clear <= 1'b0;

        // Additive write pulse
        o_amp_we <= 1'b0;
        o_amp_addr <= 5'd0;
        o_amp_wdata <= 32'sd0;

        // Distortion WT write pulse
        o_dist_wt_we <= 1'b0;
        o_dist_wt_addr <= 12'd0;
        o_dist_wt_bank <= 1'b0;
        o_dist_status_clear <= 1'b0;
        o_dist_wt_data <= 32'd0;

        dist_wt_addr_r <= 12'd0;
        dist_wt_bank_r <= 1'b0;
        dist_wt_data_r <= 32'd0;

        // Cab coef write pulse
        o_cab_coef_we <= 1'b0;
        o_cab_coef_addr <= 10'd0;
        o_cab_coef_data <= 18'd0;
        cab_coef_addr_r <= 10'd0;
        cab_coef_data_r <= 32'd0;

        // ---------------------------------------------------------------------
        // GLOBAL
        // ---------------------------------------------------------------------
        o_global_cfg.core_ctrl <= 32'h0000_0001;
        o_global_cfg.source_ctrl <= 32'd0;     // AUDIO
        o_global_cfg.fx_enable <= 32'd0;       // all bypass

        // ---------------------------------------------------------------------
        // FRONTEND
        // ---------------------------------------------------------------------
        o_frontend_cfg.ctrl <= 32'd0;
        o_frontend_cfg.env_gain_q1_31 <= 32'h7FFF_FFFF;
        o_frontend_cfg.zc_hyst_q3_29 <= 32'sh0008_3127; // 0.001
        o_frontend_cfg.glide_ctrl <= 32'd8;
        o_frontend_cfg.env_attack_q1_31 <= 32'sh7F77_C02F;
        o_frontend_cfg.env_release_q1_31 <= 32'sh7FFB_72FF;
        o_frontend_cfg.gate_on_thr_q3_29 <= 32'sh0051_EB85;  // 0.010
        o_frontend_cfg.gate_off_thr_q3_29 <= 32'sh0028_F5C3; // 0.005
        o_frontend_cfg.pitch_ctrl <= PITCH_CTRL_GUITARRA;
        o_frontend_cfg.pitch_cfg2 <= PITCH_CFG2_DEFAULT;

        // ---------------------------------------------------------------------
        // SYNTH
        // ---------------------------------------------------------------------
        o_synth_cfg.ctrl <= 32'h0000_0001;
        o_synth_cfg.base_phase_inc <= 32'h0258_BF26; // 440 Hz

        // OSC1: additive, 8', 1 harmonic
        o_osc1_cfg.ctrl <= 32'h0000_0028;
        o_osc1_cfg.pulse_width <= 32'h8000_0000;
        o_osc1_cfg.level_q1_31 <= 32'd0;

        // OSC2: saw, 8', unity detune
        o_osc2_cfg.ctrl <= 32'h0000_0008;
        o_osc2_cfg.pulse_width <= 32'h8000_0000;
        o_osc2_cfg.detune_q2_30 <= 32'h4000_0000;
        o_osc2_cfg.level_q1_31 <= 32'd0;

        // Additive amplitudes: H1 = 1, rest = 0
        for (k = 0; k < 32; k = k + 1)
            amp_shadow[k] <= 32'd0;
        amp_shadow[0] <= 32'h7FFF_FFFF;

        // Noise / mixer
        o_synth_mix_cfg.noise_ctrl <= 32'd0;
        o_synth_mix_cfg.noise_seed <= 32'h1ACE_B00C;
        o_synth_mix_cfg.noise_level_q1_31 <= 32'd0;
        o_synth_mix_cfg.bus_trim_q1_31 <= 32'h0666_6666; // 5%

        // SVF: bypass, coefficients = 1 kHz / Q 0.707
        o_synth_svf_cfg.ctrl <= 32'd0;
        o_synth_svf_cfg.a1_q1_31 <= 32'sh74AE_DF37;
        o_synth_svf_cfg.a2_q1_31 <= 32'sh07A5_D723;
        o_synth_svf_cfg.a3_q1_31 <= 32'sh0080_52DA;
        o_synth_svf_cfg.k_q3_29  <= 32'sh2D41_3CCE;
        o_synth_svf_cfg.drive <= 32'd0;

        o_synth_out_cfg.ctrl <= 32'd0;
        o_synth_out_cfg.master_q1_31 <= 32'h7FFF_FFFF;

        // ---------------------------------------------------------------------
        // FUTURE / EFFECTS
        // ---------------------------------------------------------------------
        o_octaver_cfg.ctrl <= 32'd0;
        o_octaver_cfg.mode <= 32'd0;
        o_octaver_cfg.mix_q1_31 <= 32'h7FFF_FFFF;
        o_octaver_cfg.level_q1_31 <= 32'h7FFF_FFFF;

        o_wah_cfg.ctrl <= 32'd0;
        o_wah_cfg.position_q1_31 <= 32'h4000_0000;
        o_wah_cfg.resonance_q1_31 <= 32'h4000_0000;
        o_wah_cfg.mix_q1_31 <= 32'h7FFF_FFFF;
        o_wah_cfg.min_freq_16_16 <= 32'd300 << 16;
        o_wah_cfg.max_freq_16_16 <= 32'd3000 << 16;

        // Distortion defaults from previous working regmap
        o_dist_cfg.ctrl <= 32'd0;
        o_dist_cfg.drive_16_16 <= 32'h0003_0000;
        o_dist_cfg.level_q1_31 <= 32'h2000_0000;
        o_dist_cfg.mix_q1_31 <= 32'h7FFF_FFFF;

        // Overdrive: Drive/Tone 50%, sensibilidad supuesta 1,7 V/FS, OS=8.
        o_od_cfg.ctrl <= 32'd0;
        o_od_cfg.input1_g <= 32'sh0022108D;
        o_od_cfg.input2_g <= 32'sh00216C2E;
        o_od_cfg.branch_hp_g <= 32'sh00C00474;
        o_od_cfg.branch_lp_g <= 32'sh0A02168E;
        o_od_cfg.branch_gain <= 32'sh366FA8DA;
        o_od_cfg.tone_b0 <= 32'sh00698039;
        o_od_cfg.tone_b1 <= 32'sh000037D5;
        o_od_cfg.tone_b2 <= 32'shFF96B79D;
        o_od_cfg.tone_a1 <= 32'sh810B597F;
        o_od_cfg.tone_a2 <= 32'sh3EF52157;
        o_od_cfg.output_g <= 32'sh00006C25;
        o_od_cfg.level_q3_29 <= 32'sh20000000;

        // Tone blend defaults from previous working regmap
        o_tone_cfg.blend_q1_31 <= 32'h4000_0000;
        o_tone_cfg.l_b0 <= 32'sh0034_6CE6;
        o_tone_cfg.l_b1 <= 32'sh0068_D9CD;
        o_tone_cfg.l_b2 <= 32'sh0034_6CE6;
        o_tone_cfg.l_a1 <= 32'sh8AA4_78E9;
        o_tone_cfg.l_a2 <= 32'sh362D_3AB1;
        o_tone_cfg.h_b0 <= 32'sh3AE2_3072;
        o_tone_cfg.h_b1 <= 32'sh8A3B_9F1C;
        o_tone_cfg.h_b2 <= 32'sh3AE2_3072;
        o_tone_cfg.h_a1 <= 32'sh8AA4_78E9;
        o_tone_cfg.h_a2 <= 32'sh362D_3AB1;

        // Peak EQ defaults from previous fx_core
        o_eq_cfg.ctrl <= 32'd0;
        o_eq_cfg.b0 <= 32'sh41A6_8BBE;
        o_eq_cfg.b1 <= 32'sh8650_74DA;
        o_eq_cfg.b2 <= 32'sh38B4_96CF;
        o_eq_cfg.a1 <= 32'sh8650_74DA;
        o_eq_cfg.a2 <= 32'sh3A5B_228D;

        // Chorus
        o_chorus_cfg.ctrl <= 32'h0000_0001; // bit0 = internal LPF on
        o_chorus_cfg.center_16_16 <= 32'h02D0_0000;
        o_chorus_cfg.depth_16_16 <= 32'h0048_0000;
        o_chorus_cfg.rate_inc_u32 <= 32'd35791;
        o_chorus_cfg.wet_q1_31 <= 32'h4000_0000;
        o_chorus_cfg.lpf_g_q1_31 <= 32'h2070_4E2B;

        // Flanger
        o_flanger_cfg.ctrl <= 32'd0;
        o_flanger_cfg.center_16_16 <= 32'h0090_0000;
        o_flanger_cfg.depth_16_16 <= 32'h0060_0000;
        o_flanger_cfg.rate_inc_u32 <= 32'd35791;
        o_flanger_cfg.fb_q1_31 <= 32'h4000_0000;
        o_flanger_cfg.wet_q1_31 <= 32'h4000_0000;

        // Tremolo
        o_tremolo_cfg.ctrl <= 32'd0;
        o_tremolo_cfg.rate_inc_u32 <= 32'd447392;
        o_tremolo_cfg.depth_q1_31 <= 32'h4000_0000;

        // Phaser: old PH90 defaults
        o_phaser_cfg.ctrl <= 32'd0;
        o_phaser_cfg.rate_inc_u32 <= 32'd89478;
        o_phaser_cfg.g_min_q1_31 <= 32'sh0277_1680;
        o_phaser_cfg.g_max_q1_31 <= 32'sh0C2C_7F97;
        o_phaser_cfg.fb_q1_31 <= 32'sh2666_6666;

        // Delay
        o_delay_cfg.ctrl <= 32'd0;
        o_delay_cfg.time_16_16 <= 32'h3840_0000;
        o_delay_cfg.fb_q1_31 <= 32'h3333_3333;
        o_delay_cfg.wet_q1_31 <= 32'h4000_0000;

        // Reverb reserved
        o_reverb_cfg.ctrl <= 32'd0;
        o_reverb_cfg.mix_q1_31 <= 32'h4000_0000;
        o_reverb_cfg.decay_q1_31 <= 32'h4000_0000;
        o_reverb_cfg.damping_q1_31 <= 32'h4000_0000;
        o_reverb_cfg.size_q1_31 <= 32'h4000_0000;
        o_reverb_cfg.predelay_16_16 <= 32'd0;
        o_reverb_cfg.diffusion_q1_31 <= 32'h4000_0000;
        o_reverb_cfg.mod_depth_q1_31 <= 32'd0;
        o_reverb_cfg.mod_rate_inc_u32 <= 32'd0;

        // Cab
        o_cab_cfg.ctrl <= 32'd0;
        o_cab_cfg.level_q1_31 <= 32'h7FFF_FFFF;

        // Output
        o_output_cfg.ctrl <= 32'd0;
        o_output_cfg.level_q1_31 <= 32'h7FFF_FFFF;
        o_output_cfg.limiter_threshold_q3_29 <= 32'sh2000_0000; // 1.0 Q3.29

    end else begin
        // One-cycle pulses
        o_config_commit <= 1'b0;
        o_frontend_clear <= 1'b0;
        o_synth_svf_clear <= 1'b0;
        o_amp_we <= 1'b0;
        o_dist_wt_we <= 1'b0;
        o_dist_status_clear <= 1'b0;
        o_cab_coef_we <= 1'b0;

        // Capture AW and W independently
        if (s_axi_awvalid && s_axi_awready) begin
            awaddr_r <= s_axi_awaddr;
            aw_pending <= 1'b1;
        end

        if (s_axi_wvalid && s_axi_wready) begin
            wdata_r <= s_axi_wdata;
            wstrb_r <= s_axi_wstrb;
            w_pending <= 1'b1;
        end

        // Commit write only after both channels were accepted
        if (
            !s_axi_bvalid &&
            aw_pending &&
            w_pending
        ) begin

            // -----------------------------------------------------------------
            // Additive amplitude window
            // -----------------------------------------------------------------
            if (
                (wr_off >= REG_ADD_AMP_BASE) &&
                (wr_off <= REG_ADD_AMP_LAST)
            ) begin
                merged_w = apply_wstrb(
                    amp_shadow[amp_index_w],
                    wdata_r,
                    wstrb_r
                );

                amp_shadow[amp_index_w] <= merged_w;

                o_amp_addr <= amp_index_w;
                o_amp_wdata <= $signed(merged_w);
                o_amp_we <= 1'b1;

            end else begin
                case (wr_off)

                    // =========================================================
                    // GLOBAL
                    // =========================================================

                    REG_CORE_CTRL:
                        o_global_cfg.core_ctrl <= apply_wstrb(
                            o_global_cfg.core_ctrl,
                            wdata_r,
                            wstrb_r
                        );

                    REG_SOURCE_CTRL:
                        o_global_cfg.source_ctrl <= apply_wstrb(
                            o_global_cfg.source_ctrl,
                            wdata_r,
                            wstrb_r
                        );

                    REG_FX_ENABLE:
                        o_global_cfg.fx_enable <= apply_wstrb(
                            o_global_cfg.fx_enable,
                            wdata_r,
                            wstrb_r
                        );

                    REG_CORE_COMMAND: begin
                        merged_w = apply_wstrb(
                            32'd0,
                            wdata_r,
                            wstrb_r
                        );

                        if (merged_w[0])
                            o_config_commit <= 1'b1;
                    end

                    // =========================================================
                    // FRONTEND
                    // =========================================================

                    REG_FRONTEND_CTRL: begin
                        merged_w = apply_wstrb(
                            o_frontend_cfg.ctrl,
                            wdata_r,
                            wstrb_r
                        );

                        o_frontend_cfg.ctrl <=
                            merged_w & 32'hFFFF_FFFB;

                        if (merged_w[FRONTEND_CTRL_CLEAR_BIT])
                            o_frontend_clear <= 1'b1;
                    end

                    REG_ENV_GAIN:
                        o_frontend_cfg.env_gain_q1_31 <= apply_wstrb(
                            o_frontend_cfg.env_gain_q1_31,
                            wdata_r,
                            wstrb_r
                        );

                    REG_ZC_HYST:
                        o_frontend_cfg.zc_hyst_q3_29 <= $signed(
                            apply_wstrb(
                                o_frontend_cfg.zc_hyst_q3_29,
                                wdata_r,
                                wstrb_r
                            )
                        );

                    REG_GLIDE_CTRL:
                        o_frontend_cfg.glide_ctrl <= apply_wstrb(
                            o_frontend_cfg.glide_ctrl,
                            wdata_r,
                            wstrb_r
                        );

                    REG_ENV_ATTACK:
                        o_frontend_cfg.env_attack_q1_31 <= $signed(
                            apply_wstrb(
                                o_frontend_cfg.env_attack_q1_31,
                                wdata_r,
                                wstrb_r
                            )
                        );

                    REG_ENV_RELEASE:
                        o_frontend_cfg.env_release_q1_31 <= $signed(
                            apply_wstrb(
                                o_frontend_cfg.env_release_q1_31,
                                wdata_r,
                                wstrb_r
                            )
                        );

                    REG_GATE_ON_THR:
                        o_frontend_cfg.gate_on_thr_q3_29 <= $signed(
                            apply_wstrb(
                                o_frontend_cfg.gate_on_thr_q3_29,
                                wdata_r,
                                wstrb_r
                            )
                        );

                    REG_GATE_OFF_THR:
                        o_frontend_cfg.gate_off_thr_q3_29 <= $signed(
                            apply_wstrb(
                                o_frontend_cfg.gate_off_thr_q3_29,
                                wdata_r,
                                wstrb_r
                            )
                        );

                    REG_PITCH_CTRL:
                        o_frontend_cfg.pitch_ctrl <= apply_wstrb(
                            o_frontend_cfg.pitch_ctrl,
                            wdata_r,
                            wstrb_r
                        );

                    REG_PITCH_CFG2:
                        o_frontend_cfg.pitch_cfg2 <= apply_wstrb(
                            o_frontend_cfg.pitch_cfg2,
                            wdata_r,
                            wstrb_r
                        );

                    // =========================================================
                    // SYNTH GLOBAL
                    // =========================================================

                    REG_SYNTH_CTRL:
                        o_synth_cfg.ctrl <= apply_wstrb(
                            o_synth_cfg.ctrl,
                            wdata_r,
                            wstrb_r
                        );

                    REG_SYNTH_BASE_INC:
                        o_synth_cfg.base_phase_inc <= apply_wstrb(
                            o_synth_cfg.base_phase_inc,
                            wdata_r,
                            wstrb_r
                        );

                    // =========================================================
                    // OSC1 / OSC2
                    // =========================================================

                    REG_OSC1_CTRL:
                        o_osc1_cfg.ctrl <= apply_wstrb(
                            o_osc1_cfg.ctrl,
                            wdata_r,
                            wstrb_r
                        );

                    REG_OSC1_PW:
                        o_osc1_cfg.pulse_width <= apply_wstrb(
                            o_osc1_cfg.pulse_width,
                            wdata_r,
                            wstrb_r
                        );

                    REG_OSC1_LEVEL:
                        o_osc1_cfg.level_q1_31 <= apply_wstrb(
                            o_osc1_cfg.level_q1_31,
                            wdata_r,
                            wstrb_r
                        );

                    REG_OSC2_CTRL:
                        o_osc2_cfg.ctrl <= apply_wstrb(
                            o_osc2_cfg.ctrl,
                            wdata_r,
                            wstrb_r
                        );

                    REG_OSC2_PW:
                        o_osc2_cfg.pulse_width <= apply_wstrb(
                            o_osc2_cfg.pulse_width,
                            wdata_r,
                            wstrb_r
                        );

                    REG_OSC2_DETUNE:
                        o_osc2_cfg.detune_q2_30 <= apply_wstrb(
                            o_osc2_cfg.detune_q2_30,
                            wdata_r,
                            wstrb_r
                        );

                    REG_OSC2_LEVEL:
                        o_osc2_cfg.level_q1_31 <= apply_wstrb(
                            o_osc2_cfg.level_q1_31,
                            wdata_r,
                            wstrb_r
                        );

                    // =========================================================
                    // SYNTH MIX / NOISE
                    // =========================================================

                    REG_NOISE_CTRL:
                        o_synth_mix_cfg.noise_ctrl <= apply_wstrb(
                            o_synth_mix_cfg.noise_ctrl,
                            wdata_r,
                            wstrb_r
                        );

                    REG_NOISE_SEED:
                        o_synth_mix_cfg.noise_seed <= apply_wstrb(
                            o_synth_mix_cfg.noise_seed,
                            wdata_r,
                            wstrb_r
                        );

                    REG_NOISE_LEVEL:
                        o_synth_mix_cfg.noise_level_q1_31 <= apply_wstrb(
                            o_synth_mix_cfg.noise_level_q1_31,
                            wdata_r,
                            wstrb_r
                        );

                    REG_SYNTH_BUS_TRIM:
                        o_synth_mix_cfg.bus_trim_q1_31 <= apply_wstrb(
                            o_synth_mix_cfg.bus_trim_q1_31,
                            wdata_r,
                            wstrb_r
                        );

                    // =========================================================
                    // SYNTH SVF
                    // =========================================================

                    REG_SYNTH_SVF_CTRL: begin
                        merged_w = apply_wstrb(
                            o_synth_svf_cfg.ctrl,
                            wdata_r,
                            wstrb_r
                        );

                        o_synth_svf_cfg.ctrl <=
                            merged_w & 32'hFFFF_FFF7;

                        if (merged_w[3])
                            o_synth_svf_clear <= 1'b1;
                    end

                    REG_SYNTH_SVF_A1:
                        o_synth_svf_cfg.a1_q1_31 <= $signed(
                            apply_wstrb(
                                o_synth_svf_cfg.a1_q1_31,
                                wdata_r,
                                wstrb_r
                            )
                        );

                    REG_SYNTH_SVF_A2:
                        o_synth_svf_cfg.a2_q1_31 <= $signed(
                            apply_wstrb(
                                o_synth_svf_cfg.a2_q1_31,
                                wdata_r,
                                wstrb_r
                            )
                        );

                    REG_SYNTH_SVF_A3:
                        o_synth_svf_cfg.a3_q1_31 <= $signed(
                            apply_wstrb(
                                o_synth_svf_cfg.a3_q1_31,
                                wdata_r,
                                wstrb_r
                            )
                        );

                    REG_SYNTH_SVF_K:
                        o_synth_svf_cfg.k_q3_29 <= $signed(
                            apply_wstrb(
                                o_synth_svf_cfg.k_q3_29,
                                wdata_r,
                                wstrb_r
                            )
                        );

                    REG_SYNTH_SVF_DRIVE:
                        o_synth_svf_cfg.drive <= apply_wstrb(
                            o_synth_svf_cfg.drive,
                            wdata_r,
                            wstrb_r
                        );

                    REG_SYNTH_OUT_CTRL:
                        o_synth_out_cfg.ctrl <= apply_wstrb(
                            o_synth_out_cfg.ctrl,
                            wdata_r,
                            wstrb_r
                        );

                    REG_SYNTH_MASTER:
                        o_synth_out_cfg.master_q1_31 <= apply_wstrb(
                            o_synth_out_cfg.master_q1_31,
                            wdata_r,
                            wstrb_r
                        );

                    // =========================================================
                    // OCTAVER / WAH
                    // =========================================================

                    REG_OCT_CTRL:
                        o_octaver_cfg.ctrl <= apply_wstrb(
                            o_octaver_cfg.ctrl,
                            wdata_r,
                            wstrb_r
                        );

                    REG_OCT_MODE:
                        o_octaver_cfg.mode <= apply_wstrb(
                            o_octaver_cfg.mode,
                            wdata_r,
                            wstrb_r
                        );

                    REG_OCT_MIX:
                        o_octaver_cfg.mix_q1_31 <= apply_wstrb(
                            o_octaver_cfg.mix_q1_31,
                            wdata_r,
                            wstrb_r
                        );

                    REG_OCT_LEVEL:
                        o_octaver_cfg.level_q1_31 <= apply_wstrb(
                            o_octaver_cfg.level_q1_31,
                            wdata_r,
                            wstrb_r
                        );

                    REG_WAH_CTRL:
                        o_wah_cfg.ctrl <= apply_wstrb(
                            o_wah_cfg.ctrl,
                            wdata_r,
                            wstrb_r
                        );

                    REG_WAH_POSITION:
                        o_wah_cfg.position_q1_31 <= apply_wstrb(
                            o_wah_cfg.position_q1_31,
                            wdata_r,
                            wstrb_r
                        );

                    REG_WAH_RESONANCE:
                        o_wah_cfg.resonance_q1_31 <= apply_wstrb(
                            o_wah_cfg.resonance_q1_31,
                            wdata_r,
                            wstrb_r
                        );

                    REG_WAH_MIX:
                        o_wah_cfg.mix_q1_31 <= apply_wstrb(
                            o_wah_cfg.mix_q1_31,
                            wdata_r,
                            wstrb_r
                        );

                    REG_WAH_MIN_FREQ:
                        o_wah_cfg.min_freq_16_16 <= apply_wstrb(
                            o_wah_cfg.min_freq_16_16,
                            wdata_r,
                            wstrb_r
                        );

                    REG_WAH_MAX_FREQ:
                        o_wah_cfg.max_freq_16_16 <= apply_wstrb(
                            o_wah_cfg.max_freq_16_16,
                            wdata_r,
                            wstrb_r
                        );

                    // =========================================================
                    // DISTORTION
                    // =========================================================


                    // Overdrive: parametros shadow; se aplican con CORE_COMMAND.
                    REG_OD_CTRL: o_od_cfg.ctrl <= apply_wstrb(o_od_cfg.ctrl, wdata_r, wstrb_r);
                    REG_OD_INPUT1_G: o_od_cfg.input1_g <= $signed(apply_wstrb(o_od_cfg.input1_g, wdata_r, wstrb_r));
                    REG_OD_INPUT2_G: o_od_cfg.input2_g <= $signed(apply_wstrb(o_od_cfg.input2_g, wdata_r, wstrb_r));
                    REG_OD_BRANCH_HP_G: o_od_cfg.branch_hp_g <= $signed(apply_wstrb(o_od_cfg.branch_hp_g, wdata_r, wstrb_r));
                    REG_OD_BRANCH_LP_G: o_od_cfg.branch_lp_g <= $signed(apply_wstrb(o_od_cfg.branch_lp_g, wdata_r, wstrb_r));
                    REG_OD_BRANCH_GAIN: o_od_cfg.branch_gain <= $signed(apply_wstrb(o_od_cfg.branch_gain, wdata_r, wstrb_r));
                    REG_OD_TONE_B0: o_od_cfg.tone_b0 <= $signed(apply_wstrb(o_od_cfg.tone_b0, wdata_r, wstrb_r));
                    REG_OD_TONE_B1: o_od_cfg.tone_b1 <= $signed(apply_wstrb(o_od_cfg.tone_b1, wdata_r, wstrb_r));
                    REG_OD_TONE_B2: o_od_cfg.tone_b2 <= $signed(apply_wstrb(o_od_cfg.tone_b2, wdata_r, wstrb_r));
                    REG_OD_TONE_A1: o_od_cfg.tone_a1 <= $signed(apply_wstrb(o_od_cfg.tone_a1, wdata_r, wstrb_r));
                    REG_OD_TONE_A2: o_od_cfg.tone_a2 <= $signed(apply_wstrb(o_od_cfg.tone_a2, wdata_r, wstrb_r));
                    REG_OD_OUTPUT_G: o_od_cfg.output_g <= $signed(apply_wstrb(o_od_cfg.output_g, wdata_r, wstrb_r));
                    REG_OD_LEVEL_Q3_29: o_od_cfg.level_q3_29 <= $signed(apply_wstrb(o_od_cfg.level_q3_29, wdata_r, wstrb_r));
                    REG_OD_COMMAND: if (wstrb_r[0] && wdata_r[0]) o_dist_status_clear <= 1'b1;

                    REG_DIST_CTRL:
                        o_dist_cfg.ctrl <= apply_wstrb(
                            o_dist_cfg.ctrl,
                            wdata_r,
                            wstrb_r
                        );

                    REG_DIST_DRIVE:
                        o_dist_cfg.drive_16_16 <= apply_wstrb(
                            o_dist_cfg.drive_16_16,
                            wdata_r,
                            wstrb_r
                        );

                    REG_DIST_LEVEL:
                        o_dist_cfg.level_q1_31 <= apply_wstrb(
                            o_dist_cfg.level_q1_31,
                            wdata_r,
                            wstrb_r
                        );

                    REG_DIST_MIX:
                        o_dist_cfg.mix_q1_31 <= apply_wstrb(
                            o_dist_cfg.mix_q1_31,
                            wdata_r,
                            wstrb_r
                        );

                    REG_DIST_WT_ADDR: begin
                        merged_w = apply_wstrb(
                            {19'd0, dist_wt_bank_r, dist_wt_addr_r},
                            wdata_r,
                            wstrb_r
                        );

                        dist_wt_addr_r <= merged_w[11:0];
                        dist_wt_bank_r <= merged_w[12];
                    end

                    REG_DIST_WT_DATA: begin
                        merged_w = apply_wstrb(
                            dist_wt_data_r,
                            wdata_r,
                            wstrb_r
                        );

                        dist_wt_data_r <= merged_w;

                        o_dist_wt_addr <= dist_wt_addr_r;
                        o_dist_wt_bank <= dist_wt_bank_r;
                        o_dist_wt_data <= merged_w;
                        o_dist_wt_we <= 1'b1;

                        dist_wt_addr_r <= dist_wt_addr_r + 1'b1;
                    end

                    // bit0: limpiar el aviso de escritura rechazada.
                    REG_DIST_WT_CMD: begin
                        if (wstrb_r[0] && wdata_r[0]) o_dist_status_clear <= 1'b1;
                    end

                    // =========================================================
                    // TONE
                    // =========================================================

                    REG_TONE_BLEND:
                        o_tone_cfg.blend_q1_31 <= apply_wstrb(
                            o_tone_cfg.blend_q1_31,
                            wdata_r,
                            wstrb_r
                        );

                    REG_TONE_L_B0:
                        o_tone_cfg.l_b0 <= $signed(apply_wstrb(o_tone_cfg.l_b0, wdata_r, wstrb_r));
                    REG_TONE_L_B1:
                        o_tone_cfg.l_b1 <= $signed(apply_wstrb(o_tone_cfg.l_b1, wdata_r, wstrb_r));
                    REG_TONE_L_B2:
                        o_tone_cfg.l_b2 <= $signed(apply_wstrb(o_tone_cfg.l_b2, wdata_r, wstrb_r));
                    REG_TONE_L_A1:
                        o_tone_cfg.l_a1 <= $signed(apply_wstrb(o_tone_cfg.l_a1, wdata_r, wstrb_r));
                    REG_TONE_L_A2:
                        o_tone_cfg.l_a2 <= $signed(apply_wstrb(o_tone_cfg.l_a2, wdata_r, wstrb_r));
                    REG_TONE_H_B0:
                        o_tone_cfg.h_b0 <= $signed(apply_wstrb(o_tone_cfg.h_b0, wdata_r, wstrb_r));
                    REG_TONE_H_B1:
                        o_tone_cfg.h_b1 <= $signed(apply_wstrb(o_tone_cfg.h_b1, wdata_r, wstrb_r));
                    REG_TONE_H_B2:
                        o_tone_cfg.h_b2 <= $signed(apply_wstrb(o_tone_cfg.h_b2, wdata_r, wstrb_r));
                    REG_TONE_H_A1:
                        o_tone_cfg.h_a1 <= $signed(apply_wstrb(o_tone_cfg.h_a1, wdata_r, wstrb_r));
                    REG_TONE_H_A2:
                        o_tone_cfg.h_a2 <= $signed(apply_wstrb(o_tone_cfg.h_a2, wdata_r, wstrb_r));

                    // =========================================================
                    // EQ
                    // =========================================================

                    REG_EQ_CTRL:
                        o_eq_cfg.ctrl <= apply_wstrb(o_eq_cfg.ctrl, wdata_r, wstrb_r);
                    REG_EQ_B0:
                        o_eq_cfg.b0 <= $signed(apply_wstrb(o_eq_cfg.b0, wdata_r, wstrb_r));
                    REG_EQ_B1:
                        o_eq_cfg.b1 <= $signed(apply_wstrb(o_eq_cfg.b1, wdata_r, wstrb_r));
                    REG_EQ_B2:
                        o_eq_cfg.b2 <= $signed(apply_wstrb(o_eq_cfg.b2, wdata_r, wstrb_r));
                    REG_EQ_A1:
                        o_eq_cfg.a1 <= $signed(apply_wstrb(o_eq_cfg.a1, wdata_r, wstrb_r));
                    REG_EQ_A2:
                        o_eq_cfg.a2 <= $signed(apply_wstrb(o_eq_cfg.a2, wdata_r, wstrb_r));

                    // =========================================================
                    // MODULATION
                    // =========================================================

                    REG_CHORUS_CTRL:
                        o_chorus_cfg.ctrl <= apply_wstrb(o_chorus_cfg.ctrl, wdata_r, wstrb_r);
                    REG_CHORUS_CENTER:
                        o_chorus_cfg.center_16_16 <= apply_wstrb(o_chorus_cfg.center_16_16, wdata_r, wstrb_r);
                    REG_CHORUS_DEPTH:
                        o_chorus_cfg.depth_16_16 <= apply_wstrb(o_chorus_cfg.depth_16_16, wdata_r, wstrb_r);
                    REG_CHORUS_RATE:
                        o_chorus_cfg.rate_inc_u32 <= apply_wstrb(o_chorus_cfg.rate_inc_u32, wdata_r, wstrb_r);
                    REG_CHORUS_WET:
                        o_chorus_cfg.wet_q1_31 <= apply_wstrb(o_chorus_cfg.wet_q1_31, wdata_r, wstrb_r);
                    REG_CHORUS_LPF_G:
                        o_chorus_cfg.lpf_g_q1_31 <= apply_wstrb(o_chorus_cfg.lpf_g_q1_31, wdata_r, wstrb_r);

                    REG_FLANGER_CTRL:
                        o_flanger_cfg.ctrl <= apply_wstrb(o_flanger_cfg.ctrl, wdata_r, wstrb_r);
                    REG_FLANGER_CENTER:
                        o_flanger_cfg.center_16_16 <= apply_wstrb(o_flanger_cfg.center_16_16, wdata_r, wstrb_r);
                    REG_FLANGER_DEPTH:
                        o_flanger_cfg.depth_16_16 <= apply_wstrb(o_flanger_cfg.depth_16_16, wdata_r, wstrb_r);
                    REG_FLANGER_RATE:
                        o_flanger_cfg.rate_inc_u32 <= apply_wstrb(o_flanger_cfg.rate_inc_u32, wdata_r, wstrb_r);
                    REG_FLANGER_FB:
                        o_flanger_cfg.fb_q1_31 <= apply_wstrb(o_flanger_cfg.fb_q1_31, wdata_r, wstrb_r);
                    REG_FLANGER_WET:
                        o_flanger_cfg.wet_q1_31 <= apply_wstrb(o_flanger_cfg.wet_q1_31, wdata_r, wstrb_r);

                    REG_TREMOLO_CTRL:
                        o_tremolo_cfg.ctrl <= apply_wstrb(o_tremolo_cfg.ctrl, wdata_r, wstrb_r);
                    REG_TREMOLO_RATE:
                        o_tremolo_cfg.rate_inc_u32 <= apply_wstrb(o_tremolo_cfg.rate_inc_u32, wdata_r, wstrb_r);
                    REG_TREMOLO_DEPTH:
                        o_tremolo_cfg.depth_q1_31 <= apply_wstrb(o_tremolo_cfg.depth_q1_31, wdata_r, wstrb_r);

                    REG_PHASER_CTRL:
                        o_phaser_cfg.ctrl <= apply_wstrb(o_phaser_cfg.ctrl, wdata_r, wstrb_r);
                    REG_PHASER_RATE:
                        o_phaser_cfg.rate_inc_u32 <= apply_wstrb(o_phaser_cfg.rate_inc_u32, wdata_r, wstrb_r);
                    REG_PHASER_GMIN:
                        o_phaser_cfg.g_min_q1_31 <= $signed(apply_wstrb(o_phaser_cfg.g_min_q1_31, wdata_r, wstrb_r));
                    REG_PHASER_GMAX:
                        o_phaser_cfg.g_max_q1_31 <= $signed(apply_wstrb(o_phaser_cfg.g_max_q1_31, wdata_r, wstrb_r));
                    REG_PHASER_FB:
                        o_phaser_cfg.fb_q1_31 <= $signed(apply_wstrb(o_phaser_cfg.fb_q1_31, wdata_r, wstrb_r));

                    // =========================================================
                    // DELAY / REVERB / CAB / OUTPUT
                    // =========================================================

                    REG_DELAY_CTRL:
                        o_delay_cfg.ctrl <= apply_wstrb(o_delay_cfg.ctrl, wdata_r, wstrb_r);
                    REG_DELAY_TIME:
                        o_delay_cfg.time_16_16 <= apply_wstrb(o_delay_cfg.time_16_16, wdata_r, wstrb_r);
                    REG_DELAY_FB:
                        o_delay_cfg.fb_q1_31 <= apply_wstrb(o_delay_cfg.fb_q1_31, wdata_r, wstrb_r);
                    REG_DELAY_WET:
                        o_delay_cfg.wet_q1_31 <= apply_wstrb(o_delay_cfg.wet_q1_31, wdata_r, wstrb_r);

                    REG_REVERB_CTRL:
                        o_reverb_cfg.ctrl <= apply_wstrb(o_reverb_cfg.ctrl, wdata_r, wstrb_r);
                    REG_REVERB_MIX:
                        o_reverb_cfg.mix_q1_31 <= apply_wstrb(o_reverb_cfg.mix_q1_31, wdata_r, wstrb_r);
                    REG_REVERB_DECAY:
                        o_reverb_cfg.decay_q1_31 <= apply_wstrb(o_reverb_cfg.decay_q1_31, wdata_r, wstrb_r);
                    REG_REVERB_DAMPING:
                        o_reverb_cfg.damping_q1_31 <= apply_wstrb(o_reverb_cfg.damping_q1_31, wdata_r, wstrb_r);
                    REG_REVERB_SIZE:
                        o_reverb_cfg.size_q1_31 <= apply_wstrb(o_reverb_cfg.size_q1_31, wdata_r, wstrb_r);
                    REG_REVERB_PREDELAY:
                        o_reverb_cfg.predelay_16_16 <= apply_wstrb(o_reverb_cfg.predelay_16_16, wdata_r, wstrb_r);
                    REG_REVERB_DIFFUSION:
                        o_reverb_cfg.diffusion_q1_31 <= apply_wstrb(o_reverb_cfg.diffusion_q1_31, wdata_r, wstrb_r);
                    REG_REVERB_MOD_DEPTH:
                        o_reverb_cfg.mod_depth_q1_31 <= apply_wstrb(o_reverb_cfg.mod_depth_q1_31, wdata_r, wstrb_r);
                    REG_REVERB_MOD_RATE:
                        o_reverb_cfg.mod_rate_inc_u32 <= apply_wstrb(o_reverb_cfg.mod_rate_inc_u32, wdata_r, wstrb_r);

                    REG_CAB_CTRL:
                        o_cab_cfg.ctrl <= apply_wstrb(o_cab_cfg.ctrl, wdata_r, wstrb_r);
                    REG_CAB_LEVEL:
                        o_cab_cfg.level_q1_31 <= apply_wstrb(o_cab_cfg.level_q1_31, wdata_r, wstrb_r);
                    REG_CAB_COEF_ADDR: begin
                        merged_w = apply_wstrb({22'd0, cab_coef_addr_r}, wdata_r, wstrb_r);
                        cab_coef_addr_r <= merged_w[9:0];
                    end
                    REG_CAB_COEF_DATA: begin
                        merged_w = apply_wstrb(cab_coef_data_r, wdata_r, wstrb_r);
                        cab_coef_data_r <= merged_w;
                        o_cab_coef_addr <= cab_coef_addr_r;
                        o_cab_coef_data <= merged_w[17:0];
                        o_cab_coef_we   <= 1'b1;
                        cab_coef_addr_r <= cab_coef_addr_r + 1'b1;
                    end

                    REG_OUTPUT_CTRL:
                        o_output_cfg.ctrl <= apply_wstrb(o_output_cfg.ctrl, wdata_r, wstrb_r);
                    REG_OUTPUT_LEVEL:
                        o_output_cfg.level_q1_31 <= apply_wstrb(o_output_cfg.level_q1_31, wdata_r, wstrb_r);
                    REG_LIMITER_THRESH:
                        o_output_cfg.limiter_threshold_q3_29 <= $signed(
                            apply_wstrb(
                                o_output_cfg.limiter_threshold_q3_29,
                                wdata_r,
                                wstrb_r
                            )
                        );

                    default: begin
                    end
                endcase
            end

            aw_pending <= 1'b0;
            w_pending <= 1'b0;
            s_axi_bvalid <= 1'b1;
        end

        if (s_axi_bvalid && s_axi_bready)
            s_axi_bvalid <= 1'b0;
    end
end

// =============================================================================
// READ DATA
// =============================================================================

logic [31:0] read_data_w;
logic [4:0]  amp_index_r;

always_comb begin
    read_data_w = 32'd0;
    amp_index_r = 5'd0;

    if (
        (rd_off >= REG_ADD_AMP_BASE) &&
        (rd_off <= REG_ADD_AMP_LAST)
    ) begin
        amp_index_r =
            (rd_off - REG_ADD_AMP_BASE) >> 2;

        read_data_w =
            amp_shadow[amp_index_r];

    end else begin
        case (rd_off)

            // Global
            REG_CORE_CTRL:    read_data_w = o_global_cfg.core_ctrl;
            REG_SOURCE_CTRL:  read_data_w = o_global_cfg.source_ctrl;
            REG_FX_ENABLE:    read_data_w = o_global_cfg.fx_enable;

            REG_CORE_STATUS:
                read_data_w = {
                    26'd0,
                    i_synth_busy,
                    i_synth_ready,
                    i_mixer_clip,
                    i_mixer_overdrive,
                    i_core_busy,
                    i_core_ready
                };

            REG_AUDIO_SNOOP:  read_data_w = i_audio_snoop;
            REG_PERF_STATUS:  read_data_w = i_perf_status;
            REG_CORE_ID:      read_data_w = FX_CORE_ID;
            REG_CORE_VERSION: read_data_w = FX_CORE_VERSION;
            REG_CORE_COMMAND: read_data_w = 32'd0;

            // Frontend
            REG_FRONTEND_CTRL: read_data_w = o_frontend_cfg.ctrl;
            REG_ENV_GAIN:      read_data_w = o_frontend_cfg.env_gain_q1_31;
            REG_ZC_HYST:       read_data_w = o_frontend_cfg.zc_hyst_q3_29;
            REG_GLIDE_CTRL:    read_data_w = o_frontend_cfg.glide_ctrl;
            REG_PITCH_CTRL:    read_data_w = o_frontend_cfg.pitch_ctrl;
            REG_PITCH_CFG2:    read_data_w = o_frontend_cfg.pitch_cfg2;

            REG_FRONTEND_STATUS:
                read_data_w = {
                    28'd0,
                    i_inc_valid,
                    i_period_valid,
                    i_pitch_locked,
                    i_frontend_gate
                };

            REG_ENV_VALUE:       read_data_w = i_env_q3_29;
            REG_PITCH_PERIOD:    read_data_w = i_period_16_16;
            REG_PITCH_PHASE_INC: read_data_w = i_pitch_phase_inc;
            REG_ENV_ATTACK:      read_data_w = o_frontend_cfg.env_attack_q1_31;
            REG_ENV_RELEASE:     read_data_w = o_frontend_cfg.env_release_q1_31;
            REG_GATE_ON_THR:     read_data_w = o_frontend_cfg.gate_on_thr_q3_29;
            REG_GATE_OFF_THR:    read_data_w = o_frontend_cfg.gate_off_thr_q3_29;

            // Synth
            REG_SYNTH_CTRL:     read_data_w = o_synth_cfg.ctrl;
            REG_SYNTH_BASE_INC: read_data_w = o_synth_cfg.base_phase_inc;

            REG_SYNTH_STATUS:
                read_data_w = {
                    28'd0,
                    i_mixer_clip,
                    i_mixer_overdrive,
                    i_synth_busy,
                    i_synth_ready
                };

            REG_OSC1_CTRL:  read_data_w = o_osc1_cfg.ctrl;
            REG_OSC1_PW:    read_data_w = o_osc1_cfg.pulse_width;
            REG_OSC1_LEVEL: read_data_w = o_osc1_cfg.level_q1_31;

            REG_OSC2_CTRL:   read_data_w = o_osc2_cfg.ctrl;
            REG_OSC2_PW:     read_data_w = o_osc2_cfg.pulse_width;
            REG_OSC2_DETUNE: read_data_w = o_osc2_cfg.detune_q2_30;
            REG_OSC2_LEVEL:  read_data_w = o_osc2_cfg.level_q1_31;

            REG_NOISE_CTRL:     read_data_w = o_synth_mix_cfg.noise_ctrl;
            REG_NOISE_SEED:     read_data_w = o_synth_mix_cfg.noise_seed;
            REG_NOISE_LEVEL:    read_data_w = o_synth_mix_cfg.noise_level_q1_31;
            REG_SYNTH_BUS_TRIM: read_data_w = o_synth_mix_cfg.bus_trim_q1_31;

            REG_SYNTH_MIX_STATUS:
                read_data_w = {
                    30'd0,
                    i_mixer_clip,
                    i_mixer_overdrive
                };

            REG_SYNTH_SVF_CTRL:  read_data_w = o_synth_svf_cfg.ctrl;
            REG_SYNTH_SVF_A1:    read_data_w = o_synth_svf_cfg.a1_q1_31;
            REG_SYNTH_SVF_A2:    read_data_w = o_synth_svf_cfg.a2_q1_31;
            REG_SYNTH_SVF_A3:    read_data_w = o_synth_svf_cfg.a3_q1_31;
            REG_SYNTH_SVF_K:     read_data_w = o_synth_svf_cfg.k_q3_29;
            REG_SYNTH_SVF_DRIVE: read_data_w = o_synth_svf_cfg.drive;

            REG_SYNTH_OUT_CTRL: read_data_w = o_synth_out_cfg.ctrl;
            REG_SYNTH_MASTER:   read_data_w = o_synth_out_cfg.master_q1_31;

            // Octaver
            REG_OCT_CTRL:  read_data_w = o_octaver_cfg.ctrl;
            REG_OCT_MODE:  read_data_w = o_octaver_cfg.mode;
            REG_OCT_MIX:   read_data_w = o_octaver_cfg.mix_q1_31;
            REG_OCT_LEVEL: read_data_w = o_octaver_cfg.level_q1_31;

            // Wah
            REG_WAH_CTRL:      read_data_w = o_wah_cfg.ctrl;
            REG_WAH_POSITION:  read_data_w = o_wah_cfg.position_q1_31;
            REG_WAH_RESONANCE: read_data_w = o_wah_cfg.resonance_q1_31;
            REG_WAH_MIX:       read_data_w = o_wah_cfg.mix_q1_31;
            REG_WAH_MIN_FREQ:  read_data_w = o_wah_cfg.min_freq_16_16;
            REG_WAH_MAX_FREQ:  read_data_w = o_wah_cfg.max_freq_16_16;

            // Distortion
            REG_DIST_CTRL:    read_data_w = o_dist_cfg.ctrl;
            REG_DIST_DRIVE:   read_data_w = o_dist_cfg.drive_16_16;
            REG_DIST_LEVEL:   read_data_w = o_dist_cfg.level_q1_31;
            REG_DIST_MIX:     read_data_w = o_dist_cfg.mix_q1_31;
            REG_DIST_WT_ADDR: read_data_w = {19'd0, dist_wt_bank_r, dist_wt_addr_r};
            REG_DIST_WT_DATA: read_data_w = dist_wt_data_r;
            REG_DIST_WT_CMD:  read_data_w = 32'd0;


            REG_OD_CTRL: read_data_w = o_od_cfg.ctrl;
            REG_OD_INPUT1_G: read_data_w = o_od_cfg.input1_g;
            REG_OD_INPUT2_G: read_data_w = o_od_cfg.input2_g;
            REG_OD_BRANCH_HP_G: read_data_w = o_od_cfg.branch_hp_g;
            REG_OD_BRANCH_LP_G: read_data_w = o_od_cfg.branch_lp_g;
            REG_OD_BRANCH_GAIN: read_data_w = o_od_cfg.branch_gain;
            REG_OD_TONE_B0: read_data_w = o_od_cfg.tone_b0;
            REG_OD_TONE_B1: read_data_w = o_od_cfg.tone_b1;
            REG_OD_TONE_B2: read_data_w = o_od_cfg.tone_b2;
            REG_OD_TONE_A1: read_data_w = o_od_cfg.tone_a1;
            REG_OD_TONE_A2: read_data_w = o_od_cfg.tone_a2;
            REG_OD_OUTPUT_G: read_data_w = o_od_cfg.output_g;
            REG_OD_LEVEL_Q3_29: read_data_w = o_od_cfg.level_q3_29;
            REG_OD_STATUS: read_data_w = i_dist_status;
            REG_OD_COMMAND: read_data_w = 32'd0;
            REG_OD_INFO: read_data_w = {16'd2561, 8'd0, 8'(FX_OD_OS_FACTOR)};

            // Tone
            REG_TONE_BLEND: read_data_w = o_tone_cfg.blend_q1_31;
            REG_TONE_L_B0:  read_data_w = o_tone_cfg.l_b0;
            REG_TONE_L_B1:  read_data_w = o_tone_cfg.l_b1;
            REG_TONE_L_B2:  read_data_w = o_tone_cfg.l_b2;
            REG_TONE_L_A1:  read_data_w = o_tone_cfg.l_a1;
            REG_TONE_L_A2:  read_data_w = o_tone_cfg.l_a2;
            REG_TONE_H_B0:  read_data_w = o_tone_cfg.h_b0;
            REG_TONE_H_B1:  read_data_w = o_tone_cfg.h_b1;
            REG_TONE_H_B2:  read_data_w = o_tone_cfg.h_b2;
            REG_TONE_H_A1:  read_data_w = o_tone_cfg.h_a1;
            REG_TONE_H_A2:  read_data_w = o_tone_cfg.h_a2;

            // EQ
            REG_EQ_CTRL: read_data_w = o_eq_cfg.ctrl;
            REG_EQ_B0:   read_data_w = o_eq_cfg.b0;
            REG_EQ_B1:   read_data_w = o_eq_cfg.b1;
            REG_EQ_B2:   read_data_w = o_eq_cfg.b2;
            REG_EQ_A1:   read_data_w = o_eq_cfg.a1;
            REG_EQ_A2:   read_data_w = o_eq_cfg.a2;

            // Chorus
            REG_CHORUS_CTRL:   read_data_w = o_chorus_cfg.ctrl;
            REG_CHORUS_CENTER: read_data_w = o_chorus_cfg.center_16_16;
            REG_CHORUS_DEPTH:  read_data_w = o_chorus_cfg.depth_16_16;
            REG_CHORUS_RATE:   read_data_w = o_chorus_cfg.rate_inc_u32;
            REG_CHORUS_WET:    read_data_w = o_chorus_cfg.wet_q1_31;
            REG_CHORUS_LPF_G:  read_data_w = o_chorus_cfg.lpf_g_q1_31;

            // Flanger
            REG_FLANGER_CTRL:   read_data_w = o_flanger_cfg.ctrl;
            REG_FLANGER_CENTER: read_data_w = o_flanger_cfg.center_16_16;
            REG_FLANGER_DEPTH:  read_data_w = o_flanger_cfg.depth_16_16;
            REG_FLANGER_RATE:   read_data_w = o_flanger_cfg.rate_inc_u32;
            REG_FLANGER_FB:     read_data_w = o_flanger_cfg.fb_q1_31;
            REG_FLANGER_WET:    read_data_w = o_flanger_cfg.wet_q1_31;

            // Tremolo
            REG_TREMOLO_CTRL:  read_data_w = o_tremolo_cfg.ctrl;
            REG_TREMOLO_RATE:  read_data_w = o_tremolo_cfg.rate_inc_u32;
            REG_TREMOLO_DEPTH: read_data_w = o_tremolo_cfg.depth_q1_31;

            // Phaser
            REG_PHASER_CTRL: read_data_w = o_phaser_cfg.ctrl;
            REG_PHASER_RATE: read_data_w = o_phaser_cfg.rate_inc_u32;
            REG_PHASER_GMIN: read_data_w = o_phaser_cfg.g_min_q1_31;
            REG_PHASER_GMAX: read_data_w = o_phaser_cfg.g_max_q1_31;
            REG_PHASER_FB:   read_data_w = o_phaser_cfg.fb_q1_31;

            // Delay
            REG_DELAY_CTRL: read_data_w = o_delay_cfg.ctrl;
            REG_DELAY_TIME: read_data_w = o_delay_cfg.time_16_16;
            REG_DELAY_FB:   read_data_w = o_delay_cfg.fb_q1_31;
            REG_DELAY_WET:  read_data_w = o_delay_cfg.wet_q1_31;

            // Reverb
            REG_REVERB_CTRL:      read_data_w = o_reverb_cfg.ctrl;
            REG_REVERB_MIX:       read_data_w = o_reverb_cfg.mix_q1_31;
            REG_REVERB_DECAY:     read_data_w = o_reverb_cfg.decay_q1_31;
            REG_REVERB_DAMPING:   read_data_w = o_reverb_cfg.damping_q1_31;
            REG_REVERB_SIZE:      read_data_w = o_reverb_cfg.size_q1_31;
            REG_REVERB_PREDELAY:  read_data_w = o_reverb_cfg.predelay_16_16;
            REG_REVERB_DIFFUSION: read_data_w = o_reverb_cfg.diffusion_q1_31;
            REG_REVERB_MOD_DEPTH: read_data_w = o_reverb_cfg.mod_depth_q1_31;
            REG_REVERB_MOD_RATE:  read_data_w = o_reverb_cfg.mod_rate_inc_u32;

            // Cab
            REG_CAB_CTRL:  read_data_w = o_cab_cfg.ctrl;
            REG_CAB_LEVEL: read_data_w = o_cab_cfg.level_q1_31;
            REG_CAB_COEF_ADDR: read_data_w = {22'd0, cab_coef_addr_r};
            REG_CAB_COEF_DATA: read_data_w = cab_coef_data_r;

            // Output
            REG_OUTPUT_CTRL:    read_data_w = o_output_cfg.ctrl;
            REG_OUTPUT_LEVEL:   read_data_w = o_output_cfg.level_q1_31;
            REG_LIMITER_THRESH: read_data_w = o_output_cfg.limiter_threshold_q3_29;
            REG_OUTPUT_STATUS:  read_data_w = i_output_status;

            // Front panel
            REG_ENCODER_1: read_data_w = i_enc_count[0];
            REG_ENCODER_2: read_data_w = i_enc_count[1];
            REG_ENCODER_3: read_data_w = i_enc_count[2];
            REG_ENCODER_4: read_data_w = i_enc_count[3];
            REG_ENCODER_5: read_data_w = i_enc_count[4];
            REG_ENCODER_6: read_data_w = i_enc_count[5];

            default:
                read_data_w = 32'hDEAD_BEEF;
        endcase
    end
end

// =============================================================================
// AXI READ PATH
// =============================================================================

assign s_axi_arready =
    rst_n &&
    !s_axi_rvalid;

assign s_axi_rresp = 2'b00;

always_ff @(posedge clk) begin
    if (!rst_n) begin
        s_axi_rdata <= 32'd0;
        s_axi_rvalid <= 1'b0;
    end else begin
        if (
            s_axi_arvalid &&
            s_axi_arready
        ) begin
            s_axi_rdata <= read_data_w;
            s_axi_rvalid <= 1'b1;

        end else if (
            s_axi_rvalid &&
            s_axi_rready
        ) begin
            s_axi_rvalid <= 1'b0;
        end
    end
end

endmodule
