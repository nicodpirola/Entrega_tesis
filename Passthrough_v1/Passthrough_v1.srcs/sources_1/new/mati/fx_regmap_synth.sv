`timescale 1ns/1ps

module fx_regmap_synth(
    input logic clk,
    input logic rst_n,

    // AXI4-Lite write address
    input  logic [31:0] s_axi_awaddr,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,

    // AXI4-Lite write data
    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,

    // AXI4-Lite write response
    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,

    // AXI4-Lite read address
    input  logic [31:0] s_axi_araddr,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,

    // AXI4-Lite read data
    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    // General
    output logic        o_enable,
    output logic [1:0]  o_output_sel,
    output logic [31:0] o_base_phase_inc,

    // OSC1
    output logic [1:0]  o_osc1_mode,
    output logic [2:0]  o_osc1_range,
    output logic [31:0] o_osc1_pulse_width,
    output logic [5:0]  o_osc1_n_harmonics,

    // OSC2
    output logic [1:0]  o_osc2_waveform,
    output logic [2:0]  o_osc2_range,
    output logic [31:0] o_osc2_pulse_width,
    output logic [31:0] o_osc2_detune_q2_30,

    // Additive amplitude memory write
    output logic               o_amp_we,
    output logic [4:0]         o_amp_addr,
    output logic signed [31:0] o_amp_wdata,

    // Mixer
    output logic [31:0] o_osc1_level_q1_31,
    output logic [31:0] o_osc2_level_q1_31,
    output logic [31:0] o_noise_level_q1_31,

    output logic        o_mix_softclip_enable,
    output logic [31:0] o_mix_bus_trim_q1_31,

    output logic signed [31:0] o_mix_t1_q3_29,
    output logic signed [31:0] o_mix_t2_q3_29,
    output logic signed [31:0] o_mix_k1_q1_31,
    output logic signed [31:0] o_mix_k2_q1_31,

    // Noise
    output logic [31:0] o_noise_ctrl,
    output logic [31:0] o_noise_seed,

    // SVF
    output logic [31:0]        o_svf_ctrl,
    output logic signed [31:0] o_svf_a1_q1_31,
    output logic signed [31:0] o_svf_a2_q1_31,
    output logic signed [31:0] o_svf_a3_q1_31,
    output logic signed [31:0] o_svf_k_q3_29,
    output logic [31:0]        o_svf_drive,

    // VCA / output
    output logic [31:0] o_vca_ctrl,
    output logic [31:0] o_env_gain_q1_31,
    output logic [31:0] o_synth_master_q1_31,

    // LFO
    output logic [31:0] o_lfo_ctrl,
    output logic [31:0] o_lfo_rate,
    output logic [31:0] o_lfo_depth,

    // Status
    input logic i_synth_ready,
    input logic i_synth_busy,
    input logic i_mixer_overdrive,
    input logic i_mixer_clip
);

// =============================================================================
// REGMAP - word addresses
// =============================================================================

// General / oscillators
localparam logic [5:0] A_CTRL        = 6'h00; // 0x00
localparam logic [5:0] A_BASE_INC    = 6'h01; // 0x04
localparam logic [5:0] A_OSC1_CTRL   = 6'h02; // 0x08
localparam logic [5:0] A_OSC1_PW     = 6'h03; // 0x0C
localparam logic [5:0] A_OSC2_CTRL   = 6'h04; // 0x10
localparam logic [5:0] A_OSC2_PW     = 6'h05; // 0x14
localparam logic [5:0] A_OSC2_DETUNE = 6'h06; // 0x18
localparam logic [5:0] A_AMP_DATA    = 6'h07; // 0x1C
localparam logic [5:0] A_AMP_CTRL    = 6'h08; // 0x20
localparam logic [5:0] A_STATUS      = 6'h09; // 0x24

// Mixer
localparam logic [5:0] A_OSC1_LEVEL  = 6'h0A; // 0x28
localparam logic [5:0] A_OSC2_LEVEL  = 6'h0B; // 0x2C
localparam logic [5:0] A_NOISE_LEVEL = 6'h0C; // 0x30
localparam logic [5:0] A_MIX_CTRL    = 6'h0D; // 0x34
localparam logic [5:0] A_BUS_TRIM    = 6'h0E; // 0x38
localparam logic [5:0] A_MIX_T1      = 6'h0F; // 0x3C
localparam logic [5:0] A_MIX_T2      = 6'h10; // 0x40
localparam logic [5:0] A_MIX_K1      = 6'h11; // 0x44
localparam logic [5:0] A_MIX_K2      = 6'h12; // 0x48

// Noise
localparam logic [5:0] A_NOISE_CTRL  = 6'h14; // 0x50
localparam logic [5:0] A_NOISE_SEED  = 6'h15; // 0x54

// SVF
localparam logic [5:0] A_SVF_CTRL    = 6'h18; // 0x60
localparam logic [5:0] A_SVF_A1      = 6'h19; // 0x64
localparam logic [5:0] A_SVF_A2      = 6'h1A; // 0x68
localparam logic [5:0] A_SVF_A3      = 6'h1B; // 0x6C
localparam logic [5:0] A_SVF_K       = 6'h1C; // 0x70
localparam logic [5:0] A_SVF_DRIVE   = 6'h1D; // 0x74

// VCA / output
localparam logic [5:0] A_VCA_CTRL    = 6'h20; // 0x80
localparam logic [5:0] A_ENV_GAIN    = 6'h21; // 0x84
localparam logic [5:0] A_MASTER      = 6'h22; // 0x88

// LFO
localparam logic [5:0] A_LFO_CTRL    = 6'h24; // 0x90
localparam logic [5:0] A_LFO_RATE    = 6'h25; // 0x94
localparam logic [5:0] A_LFO_DEPTH   = 6'h26; // 0x98

// =============================================================================
// AXI WRITE CAPTURE
// =============================================================================

logic [31:0] awaddr_r;
logic        aw_pending;

logic [31:0] wdata_r;
logic [3:0]  wstrb_r;
logic        w_pending;

logic [31:0] amp_data_r;
logic [31:0] write_merged;

assign s_axi_awready =
    !aw_pending &&
    !s_axi_bvalid;

assign s_axi_wready =
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
// WRITE
// =============================================================================

always_ff @(posedge clk) begin
    if (!rst_n) begin
        awaddr_r <= 32'd0;
        aw_pending <= 1'b0;

        wdata_r <= 32'd0;
        wstrb_r <= 4'd0;
        w_pending <= 1'b0;

        s_axi_bvalid <= 1'b0;

        o_amp_we <= 1'b0;
        o_amp_addr <= 5'd0;
        o_amp_wdata <= 32'sd0;
        amp_data_r <= 32'd0;

        // General
        o_enable <= 1'b0;
        o_output_sel <= 2'd0;

        // 440 Hz @ 48 kHz
        o_base_phase_inc <= 32'h0258_BF26;

        // OSC1: additive, 8', 1 harmonic
        o_osc1_mode <= 2'd0;
        o_osc1_range <= 3'd2;
        o_osc1_pulse_width <= 32'h8000_0000;
        o_osc1_n_harmonics <= 6'd1;

        // OSC2: saw, 8', detune unity
        o_osc2_waveform <= 2'd0;
        o_osc2_range <= 3'd2;
        o_osc2_pulse_width <= 32'h8000_0000;
        o_osc2_detune_q2_30 <= 32'h4000_0000;

        // Mixer
        o_osc1_level_q1_31 <= 32'd0;
        o_osc2_level_q1_31 <= 32'd0;
        o_noise_level_q1_31 <= 32'd0;

        o_mix_softclip_enable <= 1'b0;

        // 5%
        o_mix_bus_trim_q1_31 <= 32'h0666_6666;

        o_mix_t1_q3_29 <= 32'sh1999_999A;
        o_mix_t2_q3_29 <= 32'sh2666_6666;
        o_mix_k1_q1_31 <= 32'sh4000_0000;
        o_mix_k2_q1_31 <= 32'sh0000_0000;

        // Noise
        o_noise_ctrl <= 32'd0;
        o_noise_seed <= 32'h1ACE_B00C;

        // SVF
        //
        // Default coefficients:
        // fc = 1 kHz
        // Q  = 0.70710678
        //
        // CTRL reset:
        // enable=0
        // mode=LP
        // clear=0
        o_svf_ctrl <= 32'd0;

        o_svf_a1_q1_31 <= 32'sh74AE_DF37;
        o_svf_a2_q1_31 <= 32'sh07A5_D723;
        o_svf_a3_q1_31 <= 32'sh0080_52DA;
        o_svf_k_q3_29  <= 32'sh2D41_3CCE;

        o_svf_drive <= 32'd0;

        // VCA / master
        o_vca_ctrl <= 32'd0;
        o_env_gain_q1_31 <= 32'h7FFF_FFFF;
        o_synth_master_q1_31 <= 32'h7FFF_FFFF;

        // LFO
        o_lfo_ctrl <= 32'd0;
        o_lfo_rate <= 32'd0;
        o_lfo_depth <= 32'd0;

    end else begin
        // Pulsos de un clock.
        o_amp_we <= 1'b0;

        // SVF_CTRL bit3 = clear_state.
        // Si fue escrito a 1, solamente dura un clock.
        o_svf_ctrl[3] <= 1'b0;

        // Capture AW independently.
        if (s_axi_awvalid && s_axi_awready) begin
            awaddr_r <= s_axi_awaddr;
            aw_pending <= 1'b1;
        end

        // Capture W independently.
        if (s_axi_wvalid && s_axi_wready) begin
            wdata_r <= s_axi_wdata;
            wstrb_r <= s_axi_wstrb;
            w_pending <= 1'b1;
        end

        // Complete write when both address and data are available.
        if (
            !s_axi_bvalid &&
            aw_pending &&
            w_pending
        ) begin
            case (awaddr_r[7:2])

                // -------------------------------------------------------------
                // CTRL
                //
                // bit0    enable
                // bits2:1 output_sel
                // -------------------------------------------------------------
                A_CTRL: begin
                    write_merged = apply_wstrb(
                        {29'd0, o_output_sel, o_enable},
                        wdata_r,
                        wstrb_r
                    );

                    o_enable <= write_merged[0];
                    o_output_sel <= write_merged[2:1];
                end

                A_BASE_INC: begin
                    o_base_phase_inc <= apply_wstrb(
                        o_base_phase_inc,
                        wdata_r,
                        wstrb_r
                    );
                end

                // -------------------------------------------------------------
                // OSC1 CTRL
                //
                // bits1:0  mode
                // bits4:2  range
                // bits10:5 n_harmonics
                // -------------------------------------------------------------
                A_OSC1_CTRL: begin
                    write_merged = apply_wstrb(
                        {
                            21'd0,
                            o_osc1_n_harmonics,
                            o_osc1_range,
                            o_osc1_mode
                        },
                        wdata_r,
                        wstrb_r
                    );

                    o_osc1_mode <= write_merged[1:0];
                    o_osc1_range <= write_merged[4:2];
                    o_osc1_n_harmonics <= write_merged[10:5];
                end

                A_OSC1_PW: begin
                    o_osc1_pulse_width <= apply_wstrb(
                        o_osc1_pulse_width,
                        wdata_r,
                        wstrb_r
                    );
                end

                // -------------------------------------------------------------
                // OSC2 CTRL
                //
                // bits1:0 waveform
                // bits4:2 range
                // -------------------------------------------------------------
                A_OSC2_CTRL: begin
                    write_merged = apply_wstrb(
                        {
                            27'd0,
                            o_osc2_range,
                            o_osc2_waveform
                        },
                        wdata_r,
                        wstrb_r
                    );

                    o_osc2_waveform <= write_merged[1:0];
                    o_osc2_range <= write_merged[4:2];
                end

                A_OSC2_PW: begin
                    o_osc2_pulse_width <= apply_wstrb(
                        o_osc2_pulse_width,
                        wdata_r,
                        wstrb_r
                    );
                end

                A_OSC2_DETUNE: begin
                    o_osc2_detune_q2_30 <= apply_wstrb(
                        o_osc2_detune_q2_30,
                        wdata_r,
                        wstrb_r
                    );
                end

                // -------------------------------------------------------------
                // Additive RAM
                //
                // AMP_DATA stores the value.
                // Writing AMP_CTRL commits it to amp_mem[address].
                // -------------------------------------------------------------
                A_AMP_DATA: begin
                    amp_data_r <= apply_wstrb(
                        amp_data_r,
                        wdata_r,
                        wstrb_r
                    );
                end

                A_AMP_CTRL: begin
                    write_merged = apply_wstrb(
                        {27'd0, o_amp_addr},
                        wdata_r,
                        wstrb_r
                    );

                    o_amp_addr <= write_merged[4:0];
                    o_amp_wdata <= $signed(amp_data_r);
                    o_amp_we <= 1'b1;
                end

                // -------------------------------------------------------------
                // Mixer
                // -------------------------------------------------------------
                A_OSC1_LEVEL: begin
                    o_osc1_level_q1_31 <= apply_wstrb(
                        o_osc1_level_q1_31,
                        wdata_r,
                        wstrb_r
                    );
                end

                A_OSC2_LEVEL: begin
                    o_osc2_level_q1_31 <= apply_wstrb(
                        o_osc2_level_q1_31,
                        wdata_r,
                        wstrb_r
                    );
                end

                A_NOISE_LEVEL: begin
                    o_noise_level_q1_31 <= apply_wstrb(
                        o_noise_level_q1_31,
                        wdata_r,
                        wstrb_r
                    );
                end

                A_MIX_CTRL: begin
                    write_merged = apply_wstrb(
                        {31'd0, o_mix_softclip_enable},
                        wdata_r,
                        wstrb_r
                    );

                    o_mix_softclip_enable <= write_merged[0];
                end

                A_BUS_TRIM: begin
                    o_mix_bus_trim_q1_31 <= apply_wstrb(
                        o_mix_bus_trim_q1_31,
                        wdata_r,
                        wstrb_r
                    );
                end

                A_MIX_T1: begin
                    o_mix_t1_q3_29 <= $signed(
                        apply_wstrb(
                            o_mix_t1_q3_29,
                            wdata_r,
                            wstrb_r
                        )
                    );
                end

                A_MIX_T2: begin
                    o_mix_t2_q3_29 <= $signed(
                        apply_wstrb(
                            o_mix_t2_q3_29,
                            wdata_r,
                            wstrb_r
                        )
                    );
                end

                A_MIX_K1: begin
                    o_mix_k1_q1_31 <= $signed(
                        apply_wstrb(
                            o_mix_k1_q1_31,
                            wdata_r,
                            wstrb_r
                        )
                    );
                end

                A_MIX_K2: begin
                    o_mix_k2_q1_31 <= $signed(
                        apply_wstrb(
                            o_mix_k2_q1_31,
                            wdata_r,
                            wstrb_r
                        )
                    );
                end

                // -------------------------------------------------------------
                // Noise
                // -------------------------------------------------------------
                A_NOISE_CTRL: begin
                    o_noise_ctrl <= apply_wstrb(
                        o_noise_ctrl,
                        wdata_r,
                        wstrb_r
                    );
                end

                A_NOISE_SEED: begin
                    o_noise_seed <= apply_wstrb(
                        o_noise_seed,
                        wdata_r,
                        wstrb_r
                    );
                end

                // -------------------------------------------------------------
                // SVF
                //
                // CTRL:
                //   bit0    enable
                //   bits2:1 mode
                //   bit3    clear_state - pulse one clock
                //
                // modes:
                //   0 LP
                //   1 BP
                //   2 HP
                //   3 BYPASS
                // -------------------------------------------------------------
                A_SVF_CTRL: begin
                    o_svf_ctrl <= apply_wstrb(
                        o_svf_ctrl,
                        wdata_r,
                        wstrb_r
                    );
                end

                A_SVF_A1: begin
                    o_svf_a1_q1_31 <= $signed(
                        apply_wstrb(
                            o_svf_a1_q1_31,
                            wdata_r,
                            wstrb_r
                        )
                    );
                end

                A_SVF_A2: begin
                    o_svf_a2_q1_31 <= $signed(
                        apply_wstrb(
                            o_svf_a2_q1_31,
                            wdata_r,
                            wstrb_r
                        )
                    );
                end

                A_SVF_A3: begin
                    o_svf_a3_q1_31 <= $signed(
                        apply_wstrb(
                            o_svf_a3_q1_31,
                            wdata_r,
                            wstrb_r
                        )
                    );
                end

                A_SVF_K: begin
                    o_svf_k_q3_29 <= $signed(
                        apply_wstrb(
                            o_svf_k_q3_29,
                            wdata_r,
                            wstrb_r
                        )
                    );
                end

                A_SVF_DRIVE: begin
                    o_svf_drive <= apply_wstrb(
                        o_svf_drive,
                        wdata_r,
                        wstrb_r
                    );
                end

                // -------------------------------------------------------------
                // VCA / MASTER
                // -------------------------------------------------------------
                A_VCA_CTRL: begin
                    o_vca_ctrl <= apply_wstrb(
                        o_vca_ctrl,
                        wdata_r,
                        wstrb_r
                    );
                end

                A_ENV_GAIN: begin
                    o_env_gain_q1_31 <= apply_wstrb(
                        o_env_gain_q1_31,
                        wdata_r,
                        wstrb_r
                    );
                end

                A_MASTER: begin
                    o_synth_master_q1_31 <= apply_wstrb(
                        o_synth_master_q1_31,
                        wdata_r,
                        wstrb_r
                    );
                end

                // -------------------------------------------------------------
                // LFO
                // -------------------------------------------------------------
                A_LFO_CTRL: begin
                    o_lfo_ctrl <= apply_wstrb(
                        o_lfo_ctrl,
                        wdata_r,
                        wstrb_r
                    );
                end

                A_LFO_RATE: begin
                    o_lfo_rate <= apply_wstrb(
                        o_lfo_rate,
                        wdata_r,
                        wstrb_r
                    );
                end

                A_LFO_DEPTH: begin
                    o_lfo_depth <= apply_wstrb(
                        o_lfo_depth,
                        wdata_r,
                        wstrb_r
                    );
                end

                default: begin
                end
            endcase

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

always_comb begin
    read_data_w = 32'd0;

    case (s_axi_araddr[7:2])

        A_CTRL:
            read_data_w = {
                29'd0,
                o_output_sel,
                o_enable
            };

        A_BASE_INC:
            read_data_w = o_base_phase_inc;

        A_OSC1_CTRL:
            read_data_w = {
                21'd0,
                o_osc1_n_harmonics,
                o_osc1_range,
                o_osc1_mode
            };

        A_OSC1_PW:
            read_data_w = o_osc1_pulse_width;

        A_OSC2_CTRL:
            read_data_w = {
                27'd0,
                o_osc2_range,
                o_osc2_waveform
            };

        A_OSC2_PW:
            read_data_w = o_osc2_pulse_width;

        A_OSC2_DETUNE:
            read_data_w = o_osc2_detune_q2_30;

        A_AMP_DATA:
            read_data_w = amp_data_r;

        A_AMP_CTRL:
            read_data_w = {
                27'd0,
                o_amp_addr
            };

        A_STATUS:
            read_data_w = {
                28'd0,
                i_mixer_clip,
                i_mixer_overdrive,
                i_synth_busy,
                i_synth_ready
            };

        A_OSC1_LEVEL:
            read_data_w = o_osc1_level_q1_31;

        A_OSC2_LEVEL:
            read_data_w = o_osc2_level_q1_31;

        A_NOISE_LEVEL:
            read_data_w = o_noise_level_q1_31;

        A_MIX_CTRL:
            read_data_w = {
                31'd0,
                o_mix_softclip_enable
            };

        A_BUS_TRIM:
            read_data_w = o_mix_bus_trim_q1_31;

        A_MIX_T1:
            read_data_w = o_mix_t1_q3_29;

        A_MIX_T2:
            read_data_w = o_mix_t2_q3_29;

        A_MIX_K1:
            read_data_w = o_mix_k1_q1_31;

        A_MIX_K2:
            read_data_w = o_mix_k2_q1_31;

        A_NOISE_CTRL:
            read_data_w = o_noise_ctrl;

        A_NOISE_SEED:
            read_data_w = o_noise_seed;

        A_SVF_CTRL:
            read_data_w = o_svf_ctrl;

        A_SVF_A1:
            read_data_w = o_svf_a1_q1_31;

        A_SVF_A2:
            read_data_w = o_svf_a2_q1_31;

        A_SVF_A3:
            read_data_w = o_svf_a3_q1_31;

        A_SVF_K:
            read_data_w = o_svf_k_q3_29;

        A_SVF_DRIVE:
            read_data_w = o_svf_drive;

        A_VCA_CTRL:
            read_data_w = o_vca_ctrl;

        A_ENV_GAIN:
            read_data_w = o_env_gain_q1_31;

        A_MASTER:
            read_data_w = o_synth_master_q1_31;

        A_LFO_CTRL:
            read_data_w = o_lfo_ctrl;

        A_LFO_RATE:
            read_data_w = o_lfo_rate;

        A_LFO_DEPTH:
            read_data_w = o_lfo_depth;

        default:
            read_data_w = 32'd0;
    endcase
end

// =============================================================================
// AXI READ
// =============================================================================

assign s_axi_arready = !s_axi_rvalid;
assign s_axi_rresp = 2'b00;

always_ff @(posedge clk) begin
    if (!rst_n) begin
        s_axi_rdata <= 32'd0;
        s_axi_rvalid <= 1'b0;
    end else begin
        if (s_axi_arvalid && s_axi_arready) begin
            s_axi_rdata <= read_data_w;
            s_axi_rvalid <= 1'b1;
        end else if (s_axi_rvalid && s_axi_rready) begin
            s_axi_rvalid <= 1'b0;
        end
    end
end

endmodule