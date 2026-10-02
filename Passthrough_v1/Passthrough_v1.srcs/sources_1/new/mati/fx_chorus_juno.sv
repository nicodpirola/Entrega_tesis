// -----------------------------------------------------------------------------
// fx_chorus_juno.sv   (Chorus tipo Roland Juno: 2 delay lines en contrafase)
//
// Dos voces moduladas por el MISMO LFO pero en CONTRAFASE:
//   Voz A: D_A = clamp(center + depth*lfo)
//   Voz B: D_B = clamp(center - depth*lfo)
// Se suman, (opcional LPF sobre la suma), se multiplica por wet, y
//   out = x + wet*(vozA + vozB)/2     ( /2 para no saturar al sumar dos voces )
//
// FSM (secuencial, un acceso a delay por vez para reusar el delay_line tal cual):
//   ST_IDLE    : acepta muestra x, snapshot LFO
//   ST_DMOD    : dmodA = (depth*lfo)>>>31 ; dmodB = -dmodA           (1 mul)
//   ST_REQ_A   : D_A estable -> req a delay A
//   ST_WAIT_A  : registra dA
//   ST_REQ_B   : D_B estable -> req a delay B
//   ST_WAIT_B  : registra dB
//   ST_SUM     : sum = (dA + dB) >>> 1   (promedio, evita saturacion)
//   ST_LPF_FB  : si lpf_on -> manda sum al LPF ; si no -> salta a MUL
//   ST_LPF_WT  : espera salida del LPF
//   ST_MUL     : wet_term = sum_filt * wet                          (1 mul)
//   ST_OUT     : out = x + wet_term, prepara writes
//   ST_WR_A    : escribe x en delay A
//   ST_WR_B    : escribe x en delay B
// -----------------------------------------------------------------------------
module fx_chorus_juno #(
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
  input  logic [31:0]        lfo_phase_inc_u32,

  input  logic               lpf_on,
  input  logic signed [31:0] lpf_G_q1_31
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

  // ---- Delay line A ----
  logic               reqA_valid, reqA_ready;
  logic signed [31:0] dA_raw;
  logic               dA_valid, dA_ready;
  logic               wA_valid, wA_ready;
  logic signed [31:0] wA_in;
  logic               clearA_req, clearA_busy, clearA_done;

  // ---- Delay line B ----
  logic               reqB_valid, reqB_ready;
  logic signed [31:0] dB_raw;
  logic               dB_valid, dB_ready;
  logic               wB_valid, wB_ready;
  logic signed [31:0] wB_in;
  logic               clearB_req, clearB_busy, clearB_done;

  // D_mod combinacionales (A y B en contrafase)
  logic signed [31:0] dmodA_r;        // (depth*lfo)>>>31 registrado
  logic [31:0]        D_modA_comb;    // clamp(center + dmodA)
  logic [31:0]        D_modB_comb;    // clamp(center - dmodA)

  function automatic logic [31:0] clamp_D(input logic signed [31:0] d_signed);
    if (d_signed < $signed(D_MIN_16_16))      clamp_D = D_MIN_16_16;
    else if (d_signed > $signed(D_MAX_16_16)) clamp_D = D_MAX_16_16;
    else                                       clamp_D = d_signed[31:0];
  endfunction

  always_comb begin
    D_modA_comb = clamp_D($signed(D_center_16_16) + dmodA_r);
    D_modB_comb = clamp_D($signed(D_center_16_16) - dmodA_r);
  end

  delay_line #(.ADDR_W(ADDR_W)) u_delay_A (
    .clk(clk), .rst_n(rst_n),
    .req_valid(reqA_valid), .req_ready(reqA_ready), .D_16_16(D_modA_comb),
    .d_out(dA_raw), .d_valid(dA_valid), .d_ready(dA_ready),
    .w_valid(wA_valid), .w_ready(wA_ready), .w_in(wA_in),
    .clear_req(clearA_req), .clear_busy(clearA_busy), .clear_done(clearA_done),
    .write_ptr_dbg()
  );

  delay_line #(.ADDR_W(ADDR_W)) u_delay_B (
    .clk(clk), .rst_n(rst_n),
    .req_valid(reqB_valid), .req_ready(reqB_ready), .D_16_16(D_modB_comb),
    .d_out(dB_raw), .d_valid(dB_valid), .d_ready(dB_ready),
    .w_valid(wB_valid), .w_ready(wB_ready), .w_in(wB_in),
    .clear_req(clearB_req), .clear_busy(clearB_busy), .clear_done(clearB_done),
    .write_ptr_dbg()
  );

  // LFO (uno solo; la contrafase es -lfo)
  logic signed [31:0] lfo_q1_31;
  logic               lfo_tick, lfo_clear;
  fx_lfo_tri u_lfo (
    .clk(clk), .rst_n(rst_n), .tick(lfo_tick),
    .phase_inc_u32(lfo_phase_inc_u32), .phase_clear(lfo_clear), .lfo_q1_31(lfo_q1_31)
  );

  // LPF sobre la suma de las dos voces
  logic               lpf_in_valid, lpf_in_ready;
  logic signed [31:0] lpf_in_data;
  logic               lpf_out_valid;
  logic signed [31:0] lpf_out_data;
  logic               lpf_state_clear;
  fx_lpf_1p_tpt u_lpf (
    .clk(clk), .rst_n(rst_n),
    .in_valid(lpf_in_valid), .in_ready(lpf_in_ready), .in_data(lpf_in_data),
    .out_valid(lpf_out_valid), .out_ready(1'b1), .out_data(lpf_out_data),
    .G_q1_31(lpf_G_q1_31), .state_clear(lpf_state_clear)
  );

  // Enable rise
  logic enable_d;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) enable_d <= 1'b0;
    else        enable_d <= enable;
  end
  wire enable_rise = enable && !enable_d;

  // FSM - 13 estados
  typedef enum logic [3:0] {
    ST_IDLE   = 4'd0,
    ST_DMOD   = 4'd1,
    ST_REQ_A  = 4'd2,
    ST_WAIT_A = 4'd3,
    ST_REQ_B  = 4'd4,
    ST_WAIT_B = 4'd5,
    ST_SUM    = 4'd6,
    ST_LPF_FB = 4'd7,
    ST_LPF_WT = 4'd8,
    ST_MUL    = 4'd9,
    ST_OUT    = 4'd10,
    ST_WR_A   = 4'd11,
    ST_WR_B   = 4'd12
  } state_t;

  state_t state;
  logic signed [31:0] x_reg;
  logic signed [31:0] lfo_r;
  logic signed [31:0] dA_r, dB_r;
  logic signed [31:0] sum_r;       // (dA+dB)/2
  logic signed [31:0] sum_filt_r;  // despues del LPF (o sin filtrar)
  logic signed [31:0] wet_eff_r;
  logic signed [31:0] wet_term_r;

  // Bypass
  wire any_clear_busy = clearA_busy || clearB_busy;
  wire bypass_mode = (!enable) || any_clear_busy;
  wire can_accept_bypass = (state == ST_IDLE) && (!out_buf_valid);
  wire can_accept_active = (state == ST_IDLE) && (!out_buf_valid) && enable && !any_clear_busy;
  assign in_ready = bypass_mode ? can_accept_bypass : can_accept_active;

  wire in_fire = in_valid && in_ready;
  wire wA_fire = wA_valid && wA_ready;
  wire wB_fire = wB_valid && wB_ready;

  assign lfo_tick  = (!bypass_mode) && (state == ST_IDLE) && in_fire;
  assign lfo_clear = enable_rise && (state == ST_IDLE) && !out_buf_valid && !any_clear_busy;

  // handshakes delay A/B
  assign reqA_valid = (state == ST_REQ_A);
  assign dA_ready   = (state == ST_WAIT_A);
  assign reqB_valid = (state == ST_REQ_B);
  assign dB_ready   = (state == ST_WAIT_B);
  assign wA_valid   = (state == ST_WR_A);
  assign wB_valid   = (state == ST_WR_B);

  // LPF feed
  assign lpf_in_valid = (state == ST_LPF_FB) && lpf_on;
  assign lpf_in_data  = sum_r;
  assign lpf_state_clear = lfo_clear;

  // wet clamp
  localparam logic signed [31:0] WET_MAX_Q31 = 32'sh5A82_79A0;
  logic signed [31:0] wet_eff_q1_31;
  always_comb begin
    if (wet_q1_31 > WET_MAX_Q31)   wet_eff_q1_31 = WET_MAX_Q31;
    else if (wet_q1_31 < 32'sd0)   wet_eff_q1_31 = 32'sd0;
    else                            wet_eff_q1_31 = wet_q1_31;
  end

  // clear de ambas delay lines al subir enable
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      clearA_req <= 1'b0; clearB_req <= 1'b0;
    end else begin
      clearA_req <= 1'b0; clearB_req <= 1'b0;
      if (enable_rise && (state == ST_IDLE) && !out_buf_valid && !any_clear_busy) begin
        clearA_req <= 1'b1; clearB_req <= 1'b1;
      end
    end
  end

  // Secuencial principal
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= ST_IDLE; x_reg <= '0; out_buf_valid <= 1'b0; out_buf <= '0;
      wA_in <= '0; wB_in <= '0; lfo_r <= '0; dmodA_r <= '0;
      dA_r <= '0; dB_r <= '0; sum_r <= '0; sum_filt_r <= '0;
      wet_eff_r <= '0; wet_term_r <= '0;
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
            p       = $signed({1'b0, D_depth_16_16}) * $signed(lfo_r);
            dmodA_r <= $signed(p >>> 31);
            state   <= ST_REQ_A;
          end

          ST_REQ_A: if (reqA_ready) state <= ST_WAIT_A;

          ST_WAIT_A: if (dA_valid && dA_ready) begin
            dA_r  <= dA_raw;
            state <= ST_REQ_B;
          end

          ST_REQ_B: if (reqB_ready) state <= ST_WAIT_B;

          ST_WAIT_B: if (dB_valid && dB_ready) begin
            dB_r      <= dB_raw;
            wet_eff_r <= wet_eff_q1_31;
            state     <= ST_SUM;
          end

          // sum = (dA + dB) / 2  (promedio para no saturar)
          ST_SUM: begin
            logic signed [32:0] s33;
            s33   = $signed({dA_r[31], dA_r}) + $signed({dB_r[31], dB_r});
            sum_r <= s33[32:1];   // dividir por 2 = shift aritmetico
            state <= ST_LPF_FB;
          end

          ST_LPF_FB: begin
            if (lpf_on) begin
              if (lpf_in_ready) state <= ST_LPF_WT;
            end else begin
              sum_filt_r <= sum_r;
              state      <= ST_MUL;
            end
          end

          ST_LPF_WT: if (lpf_out_valid) begin
            sum_filt_r <= lpf_out_data;
            state      <= ST_MUL;
          end

          ST_MUL: begin
            wet_term_r <= mul_aud_q31(sum_filt_r, wet_eff_r);
            state      <= ST_OUT;
          end

          ST_OUT: begin
            out_buf       <= sat_add32(x_reg, wet_term_r);
            out_buf_valid <= 1'b1;
            wA_in         <= x_reg;
            wB_in         <= x_reg;
            state         <= ST_WR_A;
          end

          ST_WR_A: if (wA_fire) state <= ST_WR_B;
          ST_WR_B: if (wB_fire) state <= ST_IDLE;

          default: state <= ST_IDLE;
        endcase
      end
    end
  end

endmodule