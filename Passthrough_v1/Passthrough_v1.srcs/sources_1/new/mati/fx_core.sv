// =============================================================================
// fx_core.sv - FINAL-3: cadena completa + SYNTH parametrizable desde el PS
//   (base: version de ChatGPT con enable-freeze en adapter_idle)
//
//   mono -> DCB_in -> HPF_pre -> SYNTH_INSERT -> DISTORSION 2x
//        -> DCB_post -> PEAK -> TONE_BLEND -> CHORUS -> FLANGER
//        -> TREMOLO -> PHASER -> DELAY -> CAB_SIM -> out
//
//   FX_EN: [0]DIST..[12]PHASER [13]SYNTH [14]SYNTH_ONLY [15]SYNTH_FILTER
//   Enables congelados: solo cambian en adapter_idle (sin muestra en vuelo)
//   -> arregla el cuelgue al togglear cualquier efecto (synth, cab, etc).
//   SYNTH: todos los parametros vienen del regmap (0xC0-0xFC).
// =============================================================================
module fx_core (
  input logic         clk,
  input logic         rst_n,
  input logic         fx_enable,

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

  input  logic [31:0] s_axis_tdata,
  input  logic [2:0]  s_axis_tid,
  input  logic        s_axis_tvalid,
  output logic        s_axis_tready,
  output logic [31:0] m_axis_tdata,
  output logic [2:0]  m_axis_tid,
  output logic        m_axis_tvalid,
  input  logic        m_axis_tready,

  input  logic [5:0]  enc_a,
  input  logic [5:0]  enc_b
);

  logic               mono_valid, mono_ready;
  logic signed [31:0] mono_data;
  logic               ret_valid, ret_ready;
  logic signed [31:0] ret_data;
  logic signed [31:0] ret_data_mux;
  logic               adapter_idle;

  logic        reg_enable, reg_tone_test;
  logic [15:0] fx_en;
  logic [31:0] dist_drive, dist_level, dist_mix, dist_tone;
  logic [7:0]  wt_addr;  logic [31:0] wt_data;  logic wt_wr;
  logic signed [31:0] tl_l_b0, tl_l_b1, tl_l_b2, tl_l_a1, tl_l_a2;
  logic signed [31:0] tl_h_b0, tl_h_b1, tl_h_b2, tl_h_a1, tl_h_a2;
  logic [31:0] cho_center, cho_depth, cho_rate, cho_wet, cho_lpf_g;
  logic [31:0] fl_depth, fl_rate, fl_fb, fl_wet;
  logic [31:0] trem_rate, trem_depth;
  logic [31:0] dly_time, dly_fb, dly_wet;
  // synth params
  logic [31:0] syn_waves, syn_ranges, syn_o2t, syn_o3t;
  logic [31:0] syn_o1l, syn_o2l, syn_o3l, syn_nl, syn_eg, syn_sl, syn_dl;
  logic signed [31:0] syn_fb0, syn_fb1, syn_fb2, syn_fa1, syn_fa2;

  logic               enc_tick;
  logic signed [15:0] enc_count [0:5];
  logic [5:0]         enc_step;
  tick_gen #(.DIV(2500)) u_tick (.clk(clk), .rst_n(rst_n), .tick(enc_tick));
  genvar i;
  generate
    for (i = 0; i < 6; i++) begin : g_enc
      quad_decoder #(.CNT_W(16), .DB_N(8)) u_enc (
        .clk(clk), .rst_n(rst_n), .tick(enc_tick),
        .a_raw(enc_a[i]), .b_raw(enc_b[i]),
        .count(enc_count[i]), .step(enc_step[i])
      );
    end
  endgenerate

  // Sincronizador + enables congelados (solo cambian en adapter_idle)
  logic [1:0] enable_sync;
  always_ff @(posedge clk) begin
    if (!rst_n) enable_sync <= 2'b00;
    else        enable_sync <= {enable_sync[0], fx_enable};
  end
  logic        enable_active, reg_enable_active, reg_tone_test_active;
  logic [15:0] fx_en_active;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      enable_active<=1'b0; reg_enable_active<=1'b0;
      reg_tone_test_active<=1'b0; fx_en_active<=16'd0;
    end else if (adapter_idle) begin
      enable_active        <= enable_sync[1];
      reg_enable_active    <= reg_enable;
      reg_tone_test_active <= reg_tone_test;
      fx_en_active         <= fx_en;
    end
  end

  logic [31:0] audio_snoop;
  always_ff @(posedge clk) begin
    if (!rst_n)          audio_snoop <= '0;
    else if (mono_valid) audio_snoop <= mono_data;
  end

  fx_regmap u_regmap (
    .clk(clk), .rst_n(rst_n),
    .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb), .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
    .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
    .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
    .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp), .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
    .o_enable(reg_enable), .o_tone_test(reg_tone_test), .o_fx_en(fx_en),
    .o_dist_drive_16_16(dist_drive), .o_dist_level_q1_31(dist_level),
    .o_dist_mix_q1_31(dist_mix), .o_dist_tone_q1_31(dist_tone),
    .o_wt_addr(wt_addr), .o_wt_data(wt_data), .o_wt_wr(wt_wr),
    .o_tl_l_b0(tl_l_b0), .o_tl_l_b1(tl_l_b1), .o_tl_l_b2(tl_l_b2), .o_tl_l_a1(tl_l_a1), .o_tl_l_a2(tl_l_a2),
    .o_tl_h_b0(tl_h_b0), .o_tl_h_b1(tl_h_b1), .o_tl_h_b2(tl_h_b2), .o_tl_h_a1(tl_h_a1), .o_tl_h_a2(tl_h_a2),
    .o_cho_center_16_16(cho_center), .o_cho_depth_16_16(cho_depth),
    .o_cho_rate_inc_u32(cho_rate), .o_cho_wet_q1_31(cho_wet), .o_cho_lpf_g_q1_31(cho_lpf_g),
    .o_fl_depth_16_16(fl_depth), .o_fl_rate_inc_u32(fl_rate), .o_fl_fb_q1_31(fl_fb), .o_fl_wet_q1_31(fl_wet),
    .o_trem_rate_inc_u32(trem_rate), .o_trem_depth_q1_31(trem_depth),
    .o_dly_time_16_16(dly_time), .o_dly_fb_q1_31(dly_fb), .o_dly_wet_q1_31(dly_wet),
    .o_syn_waves(syn_waves), .o_syn_ranges(syn_ranges),
    .o_syn_osc2_tune(syn_o2t), .o_syn_osc3_tune(syn_o3t),
    .o_syn_osc1_level(syn_o1l), .o_syn_osc2_level(syn_o2l), .o_syn_osc3_level(syn_o3l),
    .o_syn_noise_level(syn_nl), .o_syn_env_gain(syn_eg),
    .o_syn_synth_level(syn_sl), .o_syn_dry_level(syn_dl),
    .o_syn_f_b0(syn_fb0), .o_syn_f_b1(syn_fb1), .o_syn_f_b2(syn_fb2),
    .o_syn_f_a1(syn_fa1), .o_syn_f_a2(syn_fa2),
    .i_audio_snoop(audio_snoop), .i_enc_count(enc_count)
  );

  fx_axis_mono_adapter u_adapter (
    .clk(clk), .rst_n(rst_n),
    .s_axis_tdata(s_axis_tdata), .s_axis_tid(s_axis_tid),
    .s_axis_tvalid(s_axis_tvalid), .s_axis_tready(s_axis_tready),
    .m_axis_tdata(m_axis_tdata), .m_axis_tid(m_axis_tid),
    .m_axis_tvalid(m_axis_tvalid), .m_axis_tready(m_axis_tready),
    .in_valid(mono_valid), .in_data(mono_data), .in_ready(mono_ready),
    .out_valid(ret_valid), .out_data(ret_data_mux), .out_ready(ret_ready),
    .idle(adapter_idle)
  );

  wire gl       = reg_enable_active && enable_active;
  wire en_dist  = gl && fx_en_active[0];
  wire en_cho   = gl && fx_en_active[1];
  wire en_fl    = gl && fx_en_active[2];
  wire en_trem  = gl && fx_en_active[3];
  wire en_dly   = gl && fx_en_active[4];
  wire en_blend = gl && fx_en_active[5];
  wire en_peak  = gl && fx_en_active[6];
  wire en_hpf   = gl && fx_en_active[7];
  wire en_dcbi  = gl && fx_en_active[8];
  wire en_dcbp  = gl && fx_en_active[9];
  wire cho_lpf_on =    fx_en_active[10];
  wire en_cab   = gl && fx_en_active[11];
  wire en_phaser= gl && fx_en_active[12];
  wire en_synth = gl && fx_en_active[13];
  wire synth_only = fx_en_active[14];
  wire synth_filter_on = fx_en_active[15];

  localparam logic signed [31:0] PH90_GMIN = 32'sh0277_1680;
  localparam logic signed [31:0] PH90_GMAX = 32'sh0C2C_7F97;
  localparam logic signed [31:0] PH90_FB   = 32'sh2666_6666;
  localparam logic [31:0]        PH90_RATE = 32'd89478;

  logic c0_v, c0_r; logic signed [31:0] c0_d;
  logic c1_v, c1_r; logic signed [31:0] c1_d;
  logic c1s_v, c1s_r; logic signed [31:0] c1s_d;
  logic c2_v, c2_r; logic signed [31:0] c2_d;
  logic c3_v, c3_r; logic signed [31:0] c3_d;
  logic c4_v, c4_r; logic signed [31:0] c4_d;
  logic c5_v, c5_r; logic signed [31:0] c5_d;
  logic c6_v, c6_r; logic signed [31:0] c6_d;
  logic c7_v, c7_r; logic signed [31:0] c7_d;
  logic c8_v, c8_r; logic signed [31:0] c8_d;
  logic c8b_v, c8b_r; logic signed [31:0] c8b_d;
  logic c9_v, c9_r; logic signed [31:0] c9_d;

  fx_dcb_byp u_dcb_in (
    .clk(clk), .rst_n(rst_n), .enable(en_dcbi),
    .in_valid(mono_valid), .in_ready(mono_ready), .in_data(mono_data),
    .out_valid(c0_v), .out_ready(c0_r), .out_data(c0_d)
  );

  // ---- Analisis de pitch/envelope: tap pasivo post-DCB_IN ----
  wire pitch_sample_valid = c0_v && c0_r;
  logic signed [31:0] synth_env_q3_29, synth_env_vca_q1_31;
  logic               synth_gate, synth_pitch_locked;
  logic [31:0]        synth_period_16_16;
  logic               synth_period_valid;
  logic [31:0]        synth_base_phase_inc;
  logic               synth_inc_valid;

  fx_synth_frontend #(.GLIDE(8), .ENV_VCA_SHIFT(4)) u_synth_frontend (
    .clk(clk), .rst_n(rst_n),
    .sample_valid(pitch_sample_valid), .sample_data_q3_29(c0_d),
    .env_gain_q1_31(syn_eg),
    .env_q3_29(synth_env_q3_29), .env_vca_q1_31(synth_env_vca_q1_31),
    .gate(synth_gate), .pitch_locked(synth_pitch_locked),
    .period_16_16(synth_period_16_16), .period_valid(synth_period_valid),
    .base_phase_inc(synth_base_phase_inc), .inc_valid(synth_inc_valid)
  );

  fx_biquad u_bq_hpf (
    .clk(clk), .rst_n(rst_n), .state_clear(1'b0), .enable(en_hpf),
    .in_valid(c0_v), .in_ready(c0_r), .in_data(c0_d),
    .out_valid(c1_v), .out_ready(c1_r), .out_data(c1_d),
    .b0_q2_30(32'sh3F4AFFE0), .b1_q2_30(32'sh816A003F), .b2_q2_30(32'sh3F4AFFE0),
    .a1_q2_30(32'sh816C0001), .a2_q2_30(32'sh3E97FF82)
  );

  // SYNTH INSERT: todos los parametros del regmap
  fx_synth_insert u_synth_insert (
    .clk(clk), .rst_n(rst_n),
    .enable(en_synth), .synth_only(synth_only),
    .in_valid(c1_v), .in_ready(c1_r), .in_data(c1_d),
    .out_valid(c1s_v), .out_ready(c1s_r), .out_data(c1s_d),
    .base_phase_inc(synth_base_phase_inc), .inc_valid(synth_inc_valid),
    .env_vca_q1_31(synth_env_vca_q1_31),
    .p_waves(syn_waves), .p_ranges(syn_ranges),
    .p_osc2_tune(syn_o2t), .p_osc3_tune(syn_o3t),
    .p_osc1_level(syn_o1l), .p_osc2_level(syn_o2l), .p_osc3_level(syn_o3l),
    .p_noise_level(syn_nl),
    .p_synth_level(syn_sl), .p_dry_level(syn_dl),
    .p_f_b0(syn_fb0), .p_f_b1(syn_fb1), .p_f_b2(syn_fb2),
    .p_f_a1(syn_fa1), .p_f_a2(syn_fa2), .p_filter_on(synth_filter_on)
  );

  fx_distortion #(.OS_FACTOR(2), .IN_SHIFT(0)) u_dist (
    .clk(clk), .rst_n(rst_n), .enable(en_dist),
    .in_valid(c1s_v), .in_ready(c1s_r), .in_data(c1s_d),
    .out_valid(c2_v), .out_ready(c2_r), .out_data(c2_d),
    .drive_16_16(dist_drive), .level_q1_31(dist_level), .mix_q1_31(dist_mix),
    .wt_wr_en(wt_wr), .wt_wr_addr(wt_addr), .wt_wr_data(wt_data)
  );

  fx_dcb_byp u_dcb_post (
    .clk(clk), .rst_n(rst_n), .enable(en_dcbp),
    .in_valid(c2_v), .in_ready(c2_r), .in_data(c2_d),
    .out_valid(c3_v), .out_ready(c3_r), .out_data(c3_d)
  );

  fx_biquad u_bq_peak (
    .clk(clk), .rst_n(rst_n), .state_clear(1'b0), .enable(en_peak),
    .in_valid(c3_v), .in_ready(c3_r), .in_data(c3_d),
    .out_valid(c4_v), .out_ready(c4_r), .out_data(c4_d),
    .b0_q2_30(32'sh41A68BBE), .b1_q2_30(32'sh865074DA), .b2_q2_30(32'sh38B496CF),
    .a1_q2_30(32'sh865074DA), .a2_q2_30(32'sh3A5B228D)
  );

  fx_tone_blend u_blend (
    .clk(clk), .rst_n(rst_n), .enable(en_blend),
    .in_valid(c4_v), .in_ready(c4_r), .in_data(c4_d),
    .out_valid(c5_v), .out_ready(c5_r), .out_data(c5_d),
    .lpf_b0(tl_l_b0), .lpf_b1(tl_l_b1), .lpf_b2(tl_l_b2), .lpf_a1(tl_l_a1), .lpf_a2(tl_l_a2),
    .hpf_b0(tl_h_b0), .hpf_b1(tl_h_b1), .hpf_b2(tl_h_b2), .hpf_a1(tl_h_a1), .hpf_a2(tl_h_a2),
    .blend_q1_31(dist_tone)
  );

  fx_chorus #(.ADDR_W(11)) u_chorus (
    .clk(clk), .rst_n(rst_n), .enable(en_cho),
    .in_valid(c5_v), .in_ready(c5_r), .in_data(c5_d),
    .out_valid(c6_v), .out_ready(c6_r), .out_data(c6_d),
    .D_center_16_16(cho_center), .D_depth_16_16(cho_depth),
    .wet_q1_31(cho_wet), .lfo_phase_inc_u32(cho_rate),
    .lpf_on(cho_lpf_on), .lpf_G_q1_31(cho_lpf_g)
  );

  fx_flanger #(.ADDR_W(11)) u_flanger (
    .clk(clk), .rst_n(rst_n), .enable(en_fl),
    .in_valid(c6_v), .in_ready(c6_r), .in_data(c6_d),
    .out_valid(c7_v), .out_ready(c7_r), .out_data(c7_d),
    .D_center_16_16(32'h0090_0000), .D_depth_16_16(fl_depth),
    .wet_q1_31(fl_wet), .fb_q1_31(fl_fb), .lfo_phase_inc_u32(fl_rate)
  );

  fx_tremolo u_trem (
    .clk(clk), .rst_n(rst_n), .enable(en_trem),
    .in_valid(c7_v), .in_ready(c7_r), .in_data(c7_d),
    .out_valid(c8_v), .out_ready(c8_r), .out_data(c8_d),
    .depth_q1_31(trem_depth), .lfo_phase_inc_u32(trem_rate)
  );

  fx_phaser u_phaser (
    .clk(clk), .rst_n(rst_n), .enable(en_phaser),
    .in_valid(c8_v), .in_ready(c8_r), .in_data(c8_d),
    .out_valid(c8b_v), .out_ready(c8b_r), .out_data(c8b_d),
    .lfo_phase_inc(PH90_RATE),
    .g_min_q1_31(PH90_GMIN), .g_max_q1_31(PH90_GMAX), .fb_q1_31(PH90_FB),
    .wt_wr_en(1'b0), .wt_wr_addr(8'd0), .wt_wr_data(32'd0)
  );

  fx_delay_simple #(.ADDR_W(15)) u_delay (
    .clk(clk), .rst_n(rst_n), .enable(en_dly),
    .in_valid(c8b_v), .in_ready(c8b_r), .in_data(c8b_d),
    .out_valid(c9_v), .out_ready(c9_r), .out_data(c9_d),
    .D_16_16(dly_time), .fb_q1_31(dly_fb), .wet_q1_31(dly_wet)
  );

  fx_cabsim u_cab (
    .clk(clk), .rst_n(rst_n), .enable(en_cab),
    .in_valid(c9_v), .in_ready(c9_r), .in_data(c9_d),
    .out_valid(ret_valid), .out_ready(ret_ready), .out_data(ret_data)
  );

  logic signed [31:0] tone_sample;
  logic [5:0]         tone_cnt;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      tone_cnt <= '0; tone_sample <= 32'sh0800_0000;
    end else if (ret_valid && ret_ready) begin
      if (tone_cnt == 6'd53) begin tone_cnt <= '0; tone_sample <= -tone_sample; end
      else tone_cnt <= tone_cnt + 1;
    end
  end
  assign ret_data_mux = reg_tone_test_active ? tone_sample : ret_data;

endmodule