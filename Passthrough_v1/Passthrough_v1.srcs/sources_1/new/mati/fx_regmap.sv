// =============================================================================
// fx_regmap.sv - VERSION FINAL-2 (definitiva)
//
// Decodifica addr[9:2]. MAPA (offsets en bytes):
//   0x00 CTRL   [0]=master enable   [3]=tono test
//   0x04 FX_EN  [0]DIST [1]CHORUS [2]FLANGER [3]TREMOLO [4]DELAY
//               [5]TONE_BLEND [6]PEAK [7]HPF_PRE [8]DCB_IN [9]DCB_POST
//               [10]CHORUS_LPF
//   0x08 SNOOP (RO)
//   -- DIST --   0x10 DRIVE(Q16.16) 0x14 LEVEL(Q1.31) 0x18 MIX(Q1.31)
//                0x1C WT_ADDR  0x20 WT_DATA (carga y auto-incrementa)
//                0x24 TONE_BLEND(Q1.31)
//                0x28..0x38 coefs LPF del tone (b0,b1,b2,a1,a2) Q2.30
//                0x3C..0x4C coefs HPF del tone (b0,b1,b2,a1,a2) Q2.30
//   -- CHORUS -- 0x50 CENTER 0x54 DEPTH (muestras Q16.16) 0x58 RATE 0x5C WET
//                0x60 LPF_G (Q1.31, TPT)
//   -- FLANGER - 0x70 DEPTH 0x74 RATE 0x78 FB 0x7C WET (center fijo en RTL)
//   -- TREMOLO - 0x90 RATE 0x94 DEPTH
//   -- DELAY --  0xB0 TIME(muestras Q16.16) 0xB4 FB 0xB8 WET
//   0xC0..0xFC reservado (cab sim, touch, pitch/DDS, EQ...)
//   0x100..0x114 ENCODERS (RO)
// =============================================================================
module fx_regmap (
  input  logic        clk,
  input  logic        rst_n,

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

  // Global
  output logic        o_enable,
  output logic        o_tone_test,
  output logic [15:0] o_fx_en,

  // Distorsion
  output logic [31:0] o_dist_drive_16_16,
  output logic [31:0] o_dist_level_q1_31,
  output logic [31:0] o_dist_mix_q1_31,
  output logic [31:0] o_dist_tone_q1_31,
  output logic [7:0]  o_wt_addr,
  output logic [31:0] o_wt_data,
  output logic        o_wt_wr,
  // coeficientes del tone blend (Q2.30, calculados en el PS)
  output logic signed [31:0] o_tl_l_b0,
  output logic signed [31:0] o_tl_l_b1,
  output logic signed [31:0] o_tl_l_b2,
  output logic signed [31:0] o_tl_l_a1,
  output logic signed [31:0] o_tl_l_a2,
  output logic signed [31:0] o_tl_h_b0,
  output logic signed [31:0] o_tl_h_b1,
  output logic signed [31:0] o_tl_h_b2,
  output logic signed [31:0] o_tl_h_a1,
  output logic signed [31:0] o_tl_h_a2,

  // Chorus
  output logic [31:0] o_cho_center_16_16,
  output logic [31:0] o_cho_depth_16_16,
  output logic [31:0] o_cho_rate_inc_u32,
  output logic [31:0] o_cho_wet_q1_31,
  output logic [31:0] o_cho_lpf_g_q1_31,

  // Flanger
  output logic [31:0] o_fl_depth_16_16,
  output logic [31:0] o_fl_rate_inc_u32,
  output logic [31:0] o_fl_fb_q1_31,
  output logic [31:0] o_fl_wet_q1_31,

  // Tremolo
  output logic [31:0] o_trem_rate_inc_u32,
  output logic [31:0] o_trem_depth_q1_31,

  // Delay (fx_delay_simple: sin LPF interno)
  output logic [31:0] o_dly_time_16_16,
  output logic [31:0] o_dly_fb_q1_31,
  output logic [31:0] o_dly_wet_q1_31,

  // -- SYNTH (Minimoog) --
  output logic [31:0] o_syn_waves,      // [2:0]w1 [5:3]w2 [8:6]w3
  output logic [31:0] o_syn_ranges,     // [3:0]r1 [7:4]r2 [11:8]r3 signed
  output logic [31:0] o_syn_osc2_tune,  // Q2.30
  output logic [31:0] o_syn_osc3_tune,  // Q2.30
  output logic [31:0] o_syn_osc1_level, // Q1.31
  output logic [31:0] o_syn_osc2_level,
  output logic [31:0] o_syn_osc3_level,
  output logic [31:0] o_syn_noise_level,
  output logic [31:0] o_syn_env_gain,   // Q1.31 (calibra volumen)
  output logic [31:0] o_syn_synth_level,
  output logic [31:0] o_syn_dry_level,
  output logic signed [31:0] o_syn_f_b0, // Q2.30 (filtro, off por defecto)
  output logic signed [31:0] o_syn_f_b1,
  output logic signed [31:0] o_syn_f_b2,
  output logic signed [31:0] o_syn_f_a1,
  output logic signed [31:0] o_syn_f_a2,

  // Read-only desde el PL
  input  logic [31:0] i_audio_snoop,
  input  logic signed [15:0] i_enc_count [0:5]
);

  logic [31:0] r_ctrl, r_fx_en;
  logic [31:0] r_drive, r_level, r_mix, r_tone;
  logic [7:0]  r_wt_addr;
  logic signed [31:0] r_l_b0, r_l_b1, r_l_b2, r_l_a1, r_l_a2;
  logic signed [31:0] r_h_b0, r_h_b1, r_h_b2, r_h_a1, r_h_a2;
  logic [31:0] r_cho_c, r_cho_d, r_cho_r, r_cho_w, r_cho_g;
  logic [31:0] r_fl_d,  r_fl_r,  r_fl_fb, r_fl_w;
  logic [31:0] r_tr_r,  r_tr_d;
  logic [31:0] r_dl_t,  r_dl_fb, r_dl_w;
  // synth
  logic [31:0] r_syn_wav, r_syn_rng, r_syn_o2t, r_syn_o3t;
  logic [31:0] r_syn_o1l, r_syn_o2l, r_syn_o3l, r_syn_nl;
  logic [31:0] r_syn_eg, r_syn_sl, r_syn_dl;
  logic signed [31:0] r_syn_fb0, r_syn_fb1, r_syn_fb2, r_syn_fa1, r_syn_fa2;

  assign o_enable    = r_ctrl[0];
  assign o_tone_test = r_ctrl[3];
  assign o_fx_en     = r_fx_en[15:0];
  assign o_dist_drive_16_16 = r_drive;
  assign o_dist_level_q1_31 = r_level;
  assign o_dist_mix_q1_31   = r_mix;
  assign o_dist_tone_q1_31  = r_tone;
  assign o_tl_l_b0 = r_l_b0;
  assign o_tl_l_b1 = r_l_b1;
  assign o_tl_l_b2 = r_l_b2;
  assign o_tl_l_a1 = r_l_a1;
  assign o_tl_l_a2 = r_l_a2;
  assign o_tl_h_b0 = r_h_b0;
  assign o_tl_h_b1 = r_h_b1;
  assign o_tl_h_b2 = r_h_b2;
  assign o_tl_h_a1 = r_h_a1;
  assign o_tl_h_a2 = r_h_a2;
  assign o_cho_center_16_16 = r_cho_c;
  assign o_cho_depth_16_16  = r_cho_d;
  assign o_cho_rate_inc_u32 = r_cho_r;
  assign o_cho_wet_q1_31    = r_cho_w;
  assign o_cho_lpf_g_q1_31  = r_cho_g;
  assign o_fl_depth_16_16   = r_fl_d;
  assign o_fl_rate_inc_u32  = r_fl_r;
  assign o_fl_fb_q1_31      = r_fl_fb;
  assign o_fl_wet_q1_31     = r_fl_w;
  assign o_trem_rate_inc_u32 = r_tr_r;
  assign o_trem_depth_q1_31  = r_tr_d;
  assign o_dly_time_16_16 = r_dl_t;
  assign o_dly_fb_q1_31   = r_dl_fb;
  assign o_dly_wet_q1_31  = r_dl_w;
  assign o_syn_waves       = r_syn_wav;
  assign o_syn_ranges      = r_syn_rng;
  assign o_syn_osc2_tune   = r_syn_o2t;
  assign o_syn_osc3_tune   = r_syn_o3t;
  assign o_syn_osc1_level  = r_syn_o1l;
  assign o_syn_osc2_level  = r_syn_o2l;
  assign o_syn_osc3_level  = r_syn_o3l;
  assign o_syn_noise_level = r_syn_nl;
  assign o_syn_env_gain    = r_syn_eg;
  assign o_syn_synth_level = r_syn_sl;
  assign o_syn_dry_level   = r_syn_dl;
  assign o_syn_f_b0        = r_syn_fb0;
  assign o_syn_f_b1        = r_syn_fb1;
  assign o_syn_f_b2        = r_syn_fb2;
  assign o_syn_f_a1        = r_syn_fa1;
  assign o_syn_f_a2        = r_syn_fa2;

  // ---- Write path ----
  // AXI4-Lite has independent AW and W channels.  Store each channel on its
  // own handshake and execute the write only when both payloads are present.
  logic [7:0]  wr_addr_lat;
  logic [31:0] wr_data_lat;
  logic [3:0]  wr_strb_lat;
  logic        aw_pending;
  logic        w_pending;

  function automatic logic [31:0] apply_wstrb (
    input logic [31:0] old_value,
    input logic [31:0] new_value,
    input logic [3:0]  strobe
  );
    logic [31:0] merged;
    begin
      merged = old_value;
      for (int byte_idx = 0; byte_idx < 4; byte_idx++) begin
        if (strobe[byte_idx])
          merged[byte_idx*8 +: 8] = new_value[byte_idx*8 +: 8];
      end
      apply_wstrb = merged;
    end
  endfunction

  // Conservative one-transaction implementation: while BVALID is pending,
  // do not accept another write.  This avoids needing a response FIFO.
  assign s_axi_awready = rst_n && !aw_pending && !s_axi_bvalid;
  assign s_axi_wready  = rst_n && !w_pending  && !s_axi_bvalid;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      r_ctrl  <= 32'h0000_0001;   // master enable ON
      r_fx_en <= 32'h0000_0000;   // TODO en bypass al arrancar
      r_drive <= 32'h0003_0000;   // 3.0
      r_level <= 32'h2000_0000;   // 0.25  (gain staging!)
      r_mix   <= 32'h7FFF_FFFF;   // 1.0
      r_tone  <= 32'h4000_0000;   // blend 0.5
      // tone blend default: LPF/HPF 900Hz Q=0.707 (el PS los pisa)
      r_l_b0 <= 32'sh00346CE6; r_l_b1 <= 32'sh0068D9CD; r_l_b2 <= 32'sh00346CE6;
      r_l_a1 <= 32'sh8AA478E9; r_l_a2 <= 32'sh362D3AB1;
      r_h_b0 <= 32'sh3AE23072; r_h_b1 <= 32'sh8A3B9F1C; r_h_b2 <= 32'sh3AE23072;
      r_h_a1 <= 32'sh8AA478E9; r_h_a2 <= 32'sh362D3AB1;
      r_wt_addr <= 8'd0;
      r_cho_c <= 32'h02D0_0000;   // 15ms  = 720 muestras
      r_cho_d <= 32'h0048_0000;   // 1.5ms = 72
      r_cho_r <= 32'd35791;       // ~0.4 Hz
      r_cho_w <= 32'h4000_0000;   // 0.5
      r_cho_g <= 32'h2070_4E2B;   // LPF TPT ~5kHz
      r_fl_d  <= 32'h0060_0000;   // 2ms = 96
      r_fl_r  <= 32'd35791;
      r_fl_fb <= 32'h4000_0000;
      r_fl_w  <= 32'h4000_0000;
      r_tr_r  <= 32'd447392;      // ~5 Hz
      r_tr_d  <= 32'h4000_0000;
      r_dl_t  <= 32'h3840_0000;   // 300ms = 14400
      r_dl_fb <= 32'h3333_3333;   // 0.4
      r_dl_w  <= 32'h4000_0000;
      r_syn_wav <= 32'h0000_00D2; r_syn_rng <= 32'h0000_0F00;
      r_syn_o2t <= 32'h4042_6168; r_syn_o3t <= 32'h4000_0000;
      r_syn_o1l <= 32'h3999_9999; r_syn_o2l <= 32'h2666_6666;
      r_syn_o3l <= 32'h1999_999A; r_syn_nl  <= 32'h0000_0000;
      r_syn_eg  <= 32'h4000_0000; r_syn_sl  <= 32'h7333_3333;
      r_syn_dl  <= 32'h4000_0000;
      r_syn_fb0 <= 32'h4000_0000; r_syn_fb1 <= 32'h0000_0000;
      r_syn_fb2 <= 32'h0000_0000; r_syn_fa1 <= 32'h0000_0000;
      r_syn_fa2 <= 32'h0000_0000;

      s_axi_bvalid <= 1'b0;
      s_axi_bresp  <= 2'b00;      // OKAY
      aw_pending   <= 1'b0;
      w_pending    <= 1'b0;
      wr_addr_lat  <= '0;
      wr_data_lat  <= '0;
      wr_strb_lat  <= '0;

      o_wt_wr   <= 1'b0;
      o_wt_addr <= 8'd0;
      o_wt_data <= 32'd0;
    end else begin
      o_wt_wr <= 1'b0;            // pulso de un ciclo

      // Capture address only on a real AW handshake.
      if (s_axi_awvalid && s_axi_awready) begin
        wr_addr_lat <= s_axi_awaddr[9:2];
        aw_pending  <= 1'b1;
      end

      // Capture data and byte strobes only on a real W handshake.
      if (s_axi_wvalid && s_axi_wready) begin
        wr_data_lat <= s_axi_wdata;
        wr_strb_lat <= s_axi_wstrb;
        w_pending   <= 1'b1;
      end

      // Commit only after both independent channels have been accepted.
      if (!s_axi_bvalid && aw_pending && w_pending) begin
        case (wr_addr_lat)
          8'h00: r_ctrl  <= apply_wstrb(r_ctrl,  wr_data_lat, wr_strb_lat); // 0x00
          8'h01: r_fx_en <= apply_wstrb(r_fx_en, wr_data_lat, wr_strb_lat); // 0x04
          // DIST
          8'h04: r_drive <= apply_wstrb(r_drive, wr_data_lat, wr_strb_lat); // 0x10
          8'h05: r_level <= apply_wstrb(r_level, wr_data_lat, wr_strb_lat); // 0x14
          8'h06: r_mix   <= apply_wstrb(r_mix,   wr_data_lat, wr_strb_lat); // 0x18
          8'h07: begin                                                      // 0x1C
            if (wr_strb_lat[0])
              r_wt_addr <= wr_data_lat[7:0];
          end
          8'h08: begin                                                      // 0x20 WT_DATA
            if (|wr_strb_lat) begin
              o_wt_addr <= r_wt_addr;
              o_wt_data <= apply_wstrb(o_wt_data, wr_data_lat, wr_strb_lat);
              o_wt_wr   <= 1'b1;
              r_wt_addr <= r_wt_addr + 8'd1;
            end
          end
          8'h09: r_tone <= apply_wstrb(r_tone, wr_data_lat, wr_strb_lat);   // 0x24
          8'h0A: r_l_b0 <= apply_wstrb(r_l_b0, wr_data_lat, wr_strb_lat);   // 0x28
          8'h0B: r_l_b1 <= apply_wstrb(r_l_b1, wr_data_lat, wr_strb_lat);   // 0x2C
          8'h0C: r_l_b2 <= apply_wstrb(r_l_b2, wr_data_lat, wr_strb_lat);   // 0x30
          8'h0D: r_l_a1 <= apply_wstrb(r_l_a1, wr_data_lat, wr_strb_lat);   // 0x34
          8'h0E: r_l_a2 <= apply_wstrb(r_l_a2, wr_data_lat, wr_strb_lat);   // 0x38
          8'h0F: r_h_b0 <= apply_wstrb(r_h_b0, wr_data_lat, wr_strb_lat);   // 0x3C
          8'h10: r_h_b1 <= apply_wstrb(r_h_b1, wr_data_lat, wr_strb_lat);   // 0x40
          8'h11: r_h_b2 <= apply_wstrb(r_h_b2, wr_data_lat, wr_strb_lat);   // 0x44
          8'h12: r_h_a1 <= apply_wstrb(r_h_a1, wr_data_lat, wr_strb_lat);   // 0x48
          8'h13: r_h_a2 <= apply_wstrb(r_h_a2, wr_data_lat, wr_strb_lat);   // 0x4C
          // CHORUS
          8'h14: r_cho_c <= apply_wstrb(r_cho_c, wr_data_lat, wr_strb_lat); // 0x50
          8'h15: r_cho_d <= apply_wstrb(r_cho_d, wr_data_lat, wr_strb_lat); // 0x54
          8'h16: r_cho_r <= apply_wstrb(r_cho_r, wr_data_lat, wr_strb_lat); // 0x58
          8'h17: r_cho_w <= apply_wstrb(r_cho_w, wr_data_lat, wr_strb_lat); // 0x5C
          8'h18: r_cho_g <= apply_wstrb(r_cho_g, wr_data_lat, wr_strb_lat); // 0x60
          // FLANGER
          8'h1C: r_fl_d  <= apply_wstrb(r_fl_d,  wr_data_lat, wr_strb_lat); // 0x70
          8'h1D: r_fl_r  <= apply_wstrb(r_fl_r,  wr_data_lat, wr_strb_lat); // 0x74
          8'h1E: r_fl_fb <= apply_wstrb(r_fl_fb, wr_data_lat, wr_strb_lat); // 0x78
          8'h1F: r_fl_w  <= apply_wstrb(r_fl_w,  wr_data_lat, wr_strb_lat); // 0x7C
          // TREMOLO
          8'h24: r_tr_r  <= apply_wstrb(r_tr_r, wr_data_lat, wr_strb_lat); // 0x90
          8'h25: r_tr_d  <= apply_wstrb(r_tr_d, wr_data_lat, wr_strb_lat); // 0x94
          // DELAY
          8'h2C: r_dl_t  <= apply_wstrb(r_dl_t,  wr_data_lat, wr_strb_lat); // 0xB0
          8'h2D: r_dl_fb <= apply_wstrb(r_dl_fb, wr_data_lat, wr_strb_lat); // 0xB4
          8'h2E: r_dl_w  <= apply_wstrb(r_dl_w,  wr_data_lat, wr_strb_lat); // 0xB8
          // -- SYNTH --
          8'h30: r_syn_wav <= apply_wstrb(r_syn_wav, wr_data_lat, wr_strb_lat); // 0xC0
          8'h31: r_syn_rng <= apply_wstrb(r_syn_rng, wr_data_lat, wr_strb_lat); // 0xC4
          8'h32: r_syn_o2t <= apply_wstrb(r_syn_o2t, wr_data_lat, wr_strb_lat); // 0xC8
          8'h33: r_syn_o3t <= apply_wstrb(r_syn_o3t, wr_data_lat, wr_strb_lat); // 0xCC
          8'h34: r_syn_o1l <= apply_wstrb(r_syn_o1l, wr_data_lat, wr_strb_lat); // 0xD0
          8'h35: r_syn_o2l <= apply_wstrb(r_syn_o2l, wr_data_lat, wr_strb_lat); // 0xD4
          8'h36: r_syn_o3l <= apply_wstrb(r_syn_o3l, wr_data_lat, wr_strb_lat); // 0xD8
          8'h37: r_syn_nl  <= apply_wstrb(r_syn_nl,  wr_data_lat, wr_strb_lat); // 0xDC
          8'h38: r_syn_eg  <= apply_wstrb(r_syn_eg,  wr_data_lat, wr_strb_lat); // 0xE0
          8'h39: r_syn_sl  <= apply_wstrb(r_syn_sl,  wr_data_lat, wr_strb_lat); // 0xE4
          8'h3A: r_syn_dl  <= apply_wstrb(r_syn_dl,  wr_data_lat, wr_strb_lat); // 0xE8
          8'h3B: r_syn_fb0 <= apply_wstrb(r_syn_fb0, wr_data_lat, wr_strb_lat); // 0xEC
          8'h3C: r_syn_fb1 <= apply_wstrb(r_syn_fb1, wr_data_lat, wr_strb_lat); // 0xF0
          8'h3D: r_syn_fb2 <= apply_wstrb(r_syn_fb2, wr_data_lat, wr_strb_lat); // 0xF4
          8'h3E: r_syn_fa1 <= apply_wstrb(r_syn_fa1, wr_data_lat, wr_strb_lat); // 0xF8
          8'h3F: r_syn_fa2 <= apply_wstrb(r_syn_fa2, wr_data_lat, wr_strb_lat); // 0xFC
          default: ;
        endcase

        s_axi_bvalid <= 1'b1;
        s_axi_bresp  <= 2'b00;     // OKAY
        aw_pending   <= 1'b0;
        w_pending    <= 1'b0;
      end

      // Hold BVALID until the master acknowledges the response.
      if (s_axi_bvalid && s_axi_bready)
        s_axi_bvalid <= 1'b0;
    end
  end

  // ---- Read path ----
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      s_axi_arready <= 1'b0; s_axi_rvalid <= 1'b0;
      s_axi_rdata <= '0; s_axi_rresp <= 2'b00;
    end else begin
      s_axi_arready <= 1'b0;
      if (s_axi_arvalid && !s_axi_rvalid) begin
        s_axi_arready <= 1'b1;
        s_axi_rvalid  <= 1'b1;
        case (s_axi_araddr[9:2])
          8'h00: s_axi_rdata <= r_ctrl;
          8'h01: s_axi_rdata <= r_fx_en;
          8'h02: s_axi_rdata <= i_audio_snoop;
          8'h04: s_axi_rdata <= r_drive;
          8'h05: s_axi_rdata <= r_level;
          8'h06: s_axi_rdata <= r_mix;
          8'h09: s_axi_rdata <= r_tone;
          8'h0A: s_axi_rdata <= r_l_b0;
          8'h0B: s_axi_rdata <= r_l_b1;
          8'h0C: s_axi_rdata <= r_l_b2;
          8'h0D: s_axi_rdata <= r_l_a1;
          8'h0E: s_axi_rdata <= r_l_a2;
          8'h0F: s_axi_rdata <= r_h_b0;
          8'h10: s_axi_rdata <= r_h_b1;
          8'h11: s_axi_rdata <= r_h_b2;
          8'h12: s_axi_rdata <= r_h_a1;
          8'h13: s_axi_rdata <= r_h_a2;
          8'h14: s_axi_rdata <= r_cho_c;
          8'h15: s_axi_rdata <= r_cho_d;
          8'h16: s_axi_rdata <= r_cho_r;
          8'h17: s_axi_rdata <= r_cho_w;
          8'h18: s_axi_rdata <= r_cho_g;
          8'h1C: s_axi_rdata <= r_fl_d;
          8'h1D: s_axi_rdata <= r_fl_r;
          8'h1E: s_axi_rdata <= r_fl_fb;
          8'h1F: s_axi_rdata <= r_fl_w;
          8'h24: s_axi_rdata <= r_tr_r;
          8'h25: s_axi_rdata <= r_tr_d;
          8'h2C: s_axi_rdata <= r_dl_t;
          8'h2D: s_axi_rdata <= r_dl_fb;
          8'h2E: s_axi_rdata <= r_dl_w;
          8'h30: s_axi_rdata <= r_syn_wav;
          8'h31: s_axi_rdata <= r_syn_rng;
          8'h32: s_axi_rdata <= r_syn_o2t;
          8'h33: s_axi_rdata <= r_syn_o3t;
          8'h34: s_axi_rdata <= r_syn_o1l;
          8'h35: s_axi_rdata <= r_syn_o2l;
          8'h36: s_axi_rdata <= r_syn_o3l;
          8'h37: s_axi_rdata <= r_syn_nl;
          8'h38: s_axi_rdata <= r_syn_eg;
          8'h39: s_axi_rdata <= r_syn_sl;
          8'h3A: s_axi_rdata <= r_syn_dl;
          8'h3B: s_axi_rdata <= r_syn_fb0;
          8'h3C: s_axi_rdata <= r_syn_fb1;
          8'h3D: s_axi_rdata <= r_syn_fb2;
          8'h3E: s_axi_rdata <= r_syn_fa1;
          8'h3F: s_axi_rdata <= r_syn_fa2;
          8'h40: s_axi_rdata <= {{16{i_enc_count[0][15]}}, i_enc_count[0]};
          8'h41: s_axi_rdata <= {{16{i_enc_count[1][15]}}, i_enc_count[1]};
          8'h42: s_axi_rdata <= {{16{i_enc_count[2][15]}}, i_enc_count[2]};
          8'h43: s_axi_rdata <= {{16{i_enc_count[3][15]}}, i_enc_count[3]};
          8'h44: s_axi_rdata <= {{16{i_enc_count[4][15]}}, i_enc_count[4]};
          8'h45: s_axi_rdata <= {{16{i_enc_count[5][15]}}, i_enc_count[5]};
          default: s_axi_rdata <= 32'hDEAD_BEEF;
        endcase
      end
      if (s_axi_rvalid && s_axi_rready)
        s_axi_rvalid <= 1'b0;
    end
  end
endmodule