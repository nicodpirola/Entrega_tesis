// -----------------------------------------------------------------------------
// fx_flanger.sv   (chorus de delay corto + FEEDBACK + softclip PIPELINEADO)
//
// v2: el softclip se parte en 3 estados (PRE/MUL/ADD) para cerrar timing.
//     Antes estaba todo en un ciclo -> camino combinacional largo (WNS<0).
//
//   d        = delay_line(D_mod)
//   wet_term = d * wet
//   out      = x + wet_term
//   fb_term  = d * fb
//   w_pre    = x + fb_term
//   w_in     = softclip(w_pre)        <-- ahora pipelineado en 3 pasos
//
// FSM:
//   ST_IDLE   : acepta x, snapshot LFO
//   ST_DMOD   : dmod = (depth*lfo)>>>31            (1 mul)
//   ST_REQ    : D_mod = clamp(center + dmod) -> req
//   ST_WAIT_D : registra d_raw
//   ST_MUL    : wet_term = d*wet                   (1 mul)
//   ST_MUL2   : fb_term  = d*fb                    (1 mul)
//   ST_MIX    : out = x+wet_term ; w_pre = x+fb_term
//   ST_CLIP_PRE : |w_pre|, elige tramo (sin mul)
//   ST_CLIP_MUL : 1 mul del tramo                  (1 mul)
//   ST_CLIP_ADD : suma final + signo
//   ST_WAIT_W : escribe en delay_line
// -----------------------------------------------------------------------------
module fx_flanger #(
  parameter int ADDR_W = 11
)(
  input  logic               clk,
  input  logic               rst_n,
  input  logic               enable,

  input  logic               in_valid,
  output logic               in_ready,
  input  logic signed [31:0] in_data,

  output logic               out_valid,
  input  logic               out_ready,
  output logic signed [31:0] out_data,

  input  logic [31:0]        D_center_16_16,
  input  logic [31:0]        D_depth_16_16,
  input  logic signed [31:0] wet_q1_31,
  input  logic signed [31:0] fb_q1_31,
  input  logic [31:0]        lfo_phase_inc_u32
);

  import fx_dsp_pkg::*;

  localparam int MAX_DELAY_SAMPLES = (1 << ADDR_W) - 8;
  localparam logic [31:0] D_MAX_16_16 = {MAX_DELAY_SAMPLES[15:0], 16'd0};
  localparam logic [31:0] D_MIN_16_16 = 32'h0001_0000;

  // Output buffer
  logic               out_buf_valid;
  logic signed [31:0] out_buf;
  assign out_valid = out_buf_valid;
  assign out_data  = out_buf;
  wire out_fire = out_valid && out_ready;

  // delay_line
  logic               req_valid, req_ready;
  logic signed [31:0] d_raw;
  logic               d_valid, d_ready;
  logic               w_valid, w_ready;
  logic signed [31:0] w_in;
  logic               clear_req, clear_busy, clear_done;

  // D_mod combinacional
  logic signed [31:0] dmod_r;
  logic [31:0]        D_mod_comb;

  function automatic logic [31:0] clamp_D(input logic signed [31:0] d_signed);
    if (d_signed < $signed(D_MIN_16_16))      clamp_D = D_MIN_16_16;
    else if (d_signed > $signed(D_MAX_16_16)) clamp_D = D_MAX_16_16;
    else                                       clamp_D = d_signed[31:0];
  endfunction

  always_comb begin
    D_mod_comb = clamp_D($signed(D_center_16_16) + dmod_r);
  end

  delay_line #(.ADDR_W(ADDR_W)) u_delay_line (
    .clk(clk), .rst_n(rst_n),
    .req_valid(req_valid), .req_ready(req_ready), .D_16_16(D_mod_comb),
    .d_out(d_raw), .d_valid(d_valid), .d_ready(d_ready),
    .w_valid(w_valid), .w_ready(w_ready), .w_in(w_in),
    .clear_req(clear_req), .clear_busy(clear_busy), .clear_done(clear_done),
    .write_ptr_dbg()
  );

  // LFO
  logic signed [31:0] lfo_q1_31;
  logic               lfo_tick, lfo_clear;
  fx_lfo_tri u_lfo (
    .clk(clk), .rst_n(rst_n), .tick(lfo_tick),
    .phase_inc_u32(lfo_phase_inc_u32), .phase_clear(lfo_clear), .lfo_q1_31(lfo_q1_31)
  );

  // Enable rise
  logic enable_d;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) enable_d <= 1'b0;
    else        enable_d <= enable;
  end
  wire enable_rise = enable && !enable_d;

  // FSM
  typedef enum logic [3:0] {
    ST_IDLE     = 4'd0,
    ST_DMOD     = 4'd1,
    ST_REQ      = 4'd2,
    ST_WAIT_D   = 4'd3,
    ST_MUL      = 4'd4,
    ST_MUL2     = 4'd5,
    ST_MIX      = 4'd6,
    ST_CLIP_PRE = 4'd7,
    ST_CLIP_MUL = 4'd8,
    ST_CLIP_ADD = 4'd9,
    ST_WAIT_W   = 4'd10
  } state_t;

  state_t state;
  logic signed [31:0] x_reg;
  logic signed [31:0] lfo_r;
  logic signed [31:0] d_raw_r;
  logic signed [31:0] wet_eff_r, fb_eff_r;
  logic signed [31:0] wet_term_r, fb_term_r;
  logic signed [31:0] w_pre_r;

  // Softclip pipeline registers
  logic               sc_neg_r;
  logic signed [31:0] sc_delta_r;
  logic signed [31:0] sc_base_r;
  logic signed [31:0] sc_k_r;
  logic signed [31:0] sc_mul_r;

  // Bypass
  wire bypass_mode = (!enable) || clear_busy;
  wire can_accept_bypass = (state == ST_IDLE) && (!out_buf_valid);
  wire can_accept_active = (state == ST_IDLE) && (!out_buf_valid) && enable && !clear_busy;
  assign in_ready = bypass_mode ? can_accept_bypass : can_accept_active;

  wire in_fire = in_valid && in_ready;
  wire w_fire  = w_valid && w_ready;

  assign lfo_tick  = (!bypass_mode) && (state == ST_IDLE) && in_fire;
  assign lfo_clear = enable_rise && (state == ST_IDLE) && !out_buf_valid && !clear_busy;

  assign req_valid = (state == ST_REQ);
  assign d_ready   = (state == ST_WAIT_D);
  assign w_valid   = (state == ST_WAIT_W);

  // wet/fb clamp
  localparam logic signed [31:0] WET_MAX_Q31 = 32'sh5A82_79A0;
  localparam logic signed [31:0] FB_MAX_Q31  = 32'sh7333_3333;  // ~0.9
  logic signed [31:0] wet_eff_q1_31, fb_eff_q1_31;
  always_comb begin
    if (wet_q1_31 > WET_MAX_Q31)   wet_eff_q1_31 = WET_MAX_Q31;
    else if (wet_q1_31 < 32'sd0)   wet_eff_q1_31 = 32'sd0;
    else                            wet_eff_q1_31 = wet_q1_31;

    if (fb_q1_31 > FB_MAX_Q31)        fb_eff_q1_31 = FB_MAX_Q31;
    else if (fb_q1_31 < -FB_MAX_Q31)  fb_eff_q1_31 = -FB_MAX_Q31;
    else                              fb_eff_q1_31 = fb_q1_31;
  end

  // Softclip constants (Q.29 / Q1.31), mismas del fx_delay viejo
  localparam logic signed [31:0] SC_T1_Q29 = 32'sh1666_6666;
  localparam logic signed [31:0] SC_T2_Q29 = 32'sh1E66_6666;
  localparam logic signed [31:0] SC_K1_Q31 = 32'sh7333_3333;
  localparam logic signed [31:0] SC_K2_Q31 = 32'sh5999_999A;
  localparam logic signed [31:0] SC_Y2_Q29 = 32'sh1D99_9999; // T1 + (T2-T1)*k1

  // clear_req
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) clear_req <= 1'b0;
    else begin
      clear_req <= 1'b0;
      if (enable_rise && (state == ST_IDLE) && !out_buf_valid && !clear_busy)
        clear_req <= 1'b1;
    end
  end

  // Secuencial
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= ST_IDLE; x_reg <= '0; out_buf_valid <= 1'b0; out_buf <= '0;
      w_in <= '0; lfo_r <= '0; dmod_r <= '0; d_raw_r <= '0;
      wet_eff_r <= '0; fb_eff_r <= '0; wet_term_r <= '0; fb_term_r <= '0;
      w_pre_r <= '0;
      sc_neg_r <= 1'b0; sc_delta_r <= '0; sc_base_r <= '0; sc_k_r <= '0; sc_mul_r <= '0;
    end else begin
      if (out_fire) out_buf_valid <= 1'b0;

      if (bypass_mode) begin
        state <= ST_IDLE;
        if (in_fire) begin out_buf <= in_data; out_buf_valid <= 1'b1; end
      end else begin
        unique case (state)

          ST_IDLE: if (in_fire) begin
            x_reg <= in_data;
            lfo_r <= lfo_q1_31;
            state <= ST_DMOD;
          end

          ST_DMOD: begin
            logic signed [63:0] p;
            p      = $signed({1'b0, D_depth_16_16}) * $signed(lfo_r);
            dmod_r <= $signed(p >>> 31);
            state  <= ST_REQ;
          end

          ST_REQ: if (req_ready) state <= ST_WAIT_D;

          ST_WAIT_D: if (d_valid && d_ready) begin
            d_raw_r   <= d_raw;
            wet_eff_r <= wet_eff_q1_31;
            fb_eff_r  <= fb_eff_q1_31;
            state     <= ST_MUL;
          end

          ST_MUL: begin
            wet_term_r <= mul_aud_q31(d_raw_r, wet_eff_r);
            state      <= ST_MUL2;
          end

          ST_MUL2: begin
            fb_term_r <= mul_aud_q31(d_raw_r, fb_eff_r);
            state     <= ST_MIX;
          end

          ST_MIX: begin
            out_buf       <= sat_add32(x_reg, wet_term_r);
            out_buf_valid <= 1'b1;
            w_pre_r       <= sat_add32(x_reg, fb_term_r);
            state         <= ST_CLIP_PRE;
          end

          // --- Softclip pipelineado (3 estados) ---
          // PRE: calcula |w_pre|, decide tramo, prepara delta/base/k (sin mul)
          ST_CLIP_PRE: begin
            logic signed [31:0] a_l;
            a_l = $signed(abs32(w_pre_r));
            sc_neg_r <= w_pre_r[31];

            if (a_l <= $signed(SC_T1_Q29)) begin
              // tramo lineal: w_in = w_pre tal cual (sin clip)
              w_in  <= w_pre_r;
              state <= ST_WAIT_W;
            end else if (a_l <= $signed(SC_T2_Q29)) begin
              sc_delta_r <= sat_sub32(a_l, SC_T1_Q29);
              sc_base_r  <= SC_T1_Q29;
              sc_k_r     <= SC_K1_Q31;
              state      <= ST_CLIP_MUL;
            end else begin
              sc_delta_r <= sat_sub32(a_l, SC_T2_Q29);
              sc_base_r  <= SC_Y2_Q29;
              sc_k_r     <= SC_K2_Q31;
              state      <= ST_CLIP_MUL;
            end
          end

          // MUL: un solo multiplicador
          ST_CLIP_MUL: begin
            sc_mul_r <= mul_aud_q31(sc_delta_r, sc_k_r);
            state    <= ST_CLIP_ADD;
          end

          // ADD: suma final y aplica signo
          ST_CLIP_ADD: begin
            logic signed [31:0] y_mag;
            y_mag = sat_add32(sc_base_r, sc_mul_r);
            w_in  <= sc_neg_r ? -y_mag : y_mag;
            state <= ST_WAIT_W;
          end

          ST_WAIT_W: if (w_fire) state <= ST_IDLE;
          default: state <= ST_IDLE;
        endcase
      end
    end
  end

endmodule