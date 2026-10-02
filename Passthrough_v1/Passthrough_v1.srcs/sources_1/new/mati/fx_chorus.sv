// -----------------------------------------------------------------------------
// fx_chorus.sv  (con LPF opcional en el wet)
//
// FSM:
//   ST_IDLE   : acepta muestra, snapshot LFO
//   ST_DMOD   : dmod_r = (depth * lfo_r) >>> 31           (1 mul)
//   ST_REQ    : D_mod_comb = clamp(center + dmod_r) -> req (comb)
//   ST_WAIT_D : registra d_raw del delay
//   ST_LPF_FB : si lpf_on -> manda d_raw al LPF; si no -> saltea a ST_MUL
//   ST_LPF_WT : espera salida del LPF, la registra
//   ST_MUL    : wet_term = d_filt * wet                   (1 mul)
//   ST_OUT    : out = x + wet_term, prepara write
//   ST_WAIT_W : escribe en delay_line
//
//  lpf_on = 0 -> chorus DIGITAL (wet sin filtrar, el original)
//  lpf_on = 1 -> chorus LPF     (wet pasa por pasabajos -> mas cremoso)
// -----------------------------------------------------------------------------
module fx_chorus #(
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

  // --- Control del LPF ---
  input  logic               lpf_on,        // 0=digital, 1=con pasabajos
  input  logic signed [31:0] lpf_G_q1_31    // coeficiente de corte (del PS)
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
    .req_valid(req_valid), .req_ready(req_ready),
    .D_16_16(D_mod_comb),
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

  // ---- LPF en el camino del wet ----
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

  // FSM - 9 estados
  typedef enum logic [3:0] {
    ST_IDLE    = 4'd0,
    ST_DMOD    = 4'd1,
    ST_REQ     = 4'd2,
    ST_WAIT_D  = 4'd3,
    ST_LPF_FB  = 4'd4,   // feed al LPF (o saltea)
    ST_LPF_WT  = 4'd5,   // espera salida del LPF
    ST_MUL     = 4'd6,
    ST_OUT     = 4'd7,
    ST_WAIT_W  = 4'd8
  } state_t;

  state_t state;
  logic signed [31:0] x_reg;
  logic signed [31:0] lfo_r;
  logic signed [31:0] d_raw_r;
  logic signed [31:0] d_filt_r;     // dato despues del LPF (o sin filtrar)
  logic signed [31:0] wet_eff_r;
  logic signed [31:0] wet_term_r;

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

  // LPF feed: en ST_LPF_FB, solo si lpf_on
  assign lpf_in_valid = (state == ST_LPF_FB) && lpf_on;
  assign lpf_in_data  = d_raw_r;
  // limpiar estado del LPF cuando arranca el efecto
  assign lpf_state_clear = lfo_clear;

  // wet clamp
  localparam logic signed [31:0] WET_MAX_Q31 = 32'sh5A82_79A0;
  logic signed [31:0] wet_eff_q1_31;
  always_comb begin
    if (wet_q1_31 > WET_MAX_Q31)   wet_eff_q1_31 = WET_MAX_Q31;
    else if (wet_q1_31 < 32'sd0)   wet_eff_q1_31 = 32'sd0;
    else                            wet_eff_q1_31 = wet_q1_31;
  end

  // clear_req
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) clear_req <= 1'b0;
    else begin
      clear_req <= 1'b0;
      if (enable_rise && (state == ST_IDLE) && !out_buf_valid && !clear_busy)
        clear_req <= 1'b1;
    end
  end

  // Secuencial principal
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= ST_IDLE; x_reg <= '0; out_buf_valid <= 1'b0; out_buf <= '0;
      w_in <= '0; lfo_r <= '0; dmod_r <= '0;
      d_raw_r <= '0; d_filt_r <= '0; wet_eff_r <= '0; wet_term_r <= '0;
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

          ST_REQ: begin
            if (req_ready) state <= ST_WAIT_D;
          end

          ST_WAIT_D: if (d_valid && d_ready) begin
            d_raw_r   <= d_raw;
            wet_eff_r <= wet_eff_q1_31;
            state     <= ST_LPF_FB;
          end

          // Si LPF on: el dato se manda al filtro (lpf_in_valid=1 este ciclo).
          // Si LPF off: saltamos directo a MUL con el dato crudo.
          ST_LPF_FB: begin
            if (lpf_on) begin
              if (lpf_in_ready)   // el LPF acepto el dato
                state <= ST_LPF_WT;
            end else begin
              d_filt_r <= d_raw_r;   // sin filtrar
              state    <= ST_MUL;
            end
          end

          // Espera la salida del LPF
          ST_LPF_WT: if (lpf_out_valid) begin
            d_filt_r <= lpf_out_data;
            state    <= ST_MUL;
          end

          ST_MUL: begin
            wet_term_r <= mul_aud_q31(d_filt_r, wet_eff_r);
            state      <= ST_OUT;
          end

          ST_OUT: begin
            out_buf       <= sat_add32(x_reg, wet_term_r);
            out_buf_valid <= 1'b1;
            w_in          <= x_reg;
            state         <= ST_WAIT_W;
          end

          ST_WAIT_W: if (w_fire) state <= ST_IDLE;
          default: state <= ST_IDLE;
        endcase
      end
    end
  end

endmodule