module fx_delay_simple #(
  parameter int ADDR_W = 15
)(
  input  logic               clk,
  input  logic               rst_n,
  input  logic               enable,

  // Stream mono in
  input  logic               in_valid,
  output logic               in_ready,
  input  logic signed [31:0] in_data,

  // Stream mono out
  output logic               out_valid,
  input  logic               out_ready,
  output logic signed [31:0] out_data,

  // Parámetros
  input  logic [31:0]        D_16_16,
  input  logic signed [31:0] fb_q1_31,
  input  logic signed [31:0] wet_q1_31
);

  import fx_dsp_pkg::*;

  // --- Output buffer ---
  logic               out_buf_valid;
  logic signed [31:0] out_buf;
  assign out_valid = out_buf_valid;
  assign out_data  = out_buf;
  wire out_fire = out_valid && out_ready;

  // --- Delay line ---
  logic               req_valid, req_ready;
  logic signed [31:0] d_raw;
  logic               d_valid, d_ready;
  logic               w_valid, w_ready;
  logic signed [31:0] w_in;
  logic               clear_req, clear_busy, clear_done;

  delay_line #(.ADDR_W(ADDR_W)) u_dl (
    .clk(clk), .rst_n(rst_n),
    .req_valid(req_valid), .req_ready(req_ready), .D_16_16(D_16_16),
    .d_out(d_raw), .d_valid(d_valid), .d_ready(d_ready),
    .w_valid(w_valid), .w_ready(w_ready), .w_in(w_in),
    .clear_req(clear_req), .clear_busy(clear_busy), .clear_done(clear_done),
    .write_ptr_dbg()
  );

  // --- Enable rise (para clear del BRAM) ---
  logic enable_d;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) enable_d <= 1'b0;
    else        enable_d <= enable;
  end
  wire enable_rise = enable && !enable_d;

  // --- FSM: 5 estados ---
  typedef enum logic [2:0] {
    ST_IDLE   = 3'd0,
    ST_WAIT_D = 3'd1,
    ST_MUL    = 3'd2,
    ST_MIX    = 3'd3,
    ST_WAIT_W = 3'd4
  } state_t;

  state_t state;
  logic signed [31:0] x_reg;       // sample de entrada latched
  logic signed [31:0] d_reg;       // sample del delay latched
  logic signed [31:0] wet_term_r;  // d * wet
  logic signed [31:0] fb_term_r;   // d * fb

  wire in_fire = in_valid && in_ready;
  wire w_fire  = w_valid  && w_ready;

  // --- Bypass cuando disable o clearing ---
  wire bypass_mode     = (!enable) || clear_busy;
  wire can_accept_bp   = (state == ST_IDLE) && (!out_buf_valid);
  wire can_accept_act  = (state == ST_IDLE) && (!out_buf_valid) && req_ready && enable && !clear_busy;
  assign in_ready = bypass_mode ? can_accept_bp : can_accept_act;

  // --- Clear control ---
  always_ff @(posedge clk) begin
    if (!rst_n)
      clear_req <= 1'b0;
    else begin
      clear_req <= 1'b0;
      if (enable_rise && (state == ST_IDLE) && !out_buf_valid && !clear_busy)
        clear_req <= 1'b1;
    end
  end

  // --- Handshake hacia delay_line ---
  assign req_valid = (!bypass_mode) && (state == ST_IDLE) && in_fire;
  assign d_ready   = (state == ST_WAIT_D);
  assign w_valid   = (state == ST_WAIT_W);

  // --- FSM principal ---
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state       <= ST_IDLE;
      x_reg       <= '0;
      d_reg       <= '0;
      out_buf_valid <= 1'b0;
      out_buf     <= '0;
      wet_term_r  <= '0;
      fb_term_r   <= '0;
      w_in        <= '0;
    end else begin
      // Consumo de salida
      if (out_fire) out_buf_valid <= 1'b0;

      if (bypass_mode) begin
        state <= ST_IDLE;
        if (in_fire) begin
          out_buf       <= in_data;
          out_buf_valid <= 1'b1;
        end
      end else begin
        case (state)
          ST_IDLE: if (in_fire) begin
            x_reg <= in_data;
            state <= ST_WAIT_D;
          end

          ST_WAIT_D: if (d_valid && d_ready) begin
            d_reg <= d_raw;
            state <= ST_MUL;
          end

          ST_MUL: begin
            wet_term_r <= mul_aud_q31(d_reg, wet_q1_31);
            fb_term_r  <= mul_aud_q31(d_reg, fb_q1_31);
            state      <= ST_MIX;
          end

          ST_MIX: begin
            out_buf       <= sat_add32(x_reg, wet_term_r);
            out_buf_valid <= 1'b1;
            w_in          <= sat_add32(x_reg, fb_term_r);
            state         <= ST_WAIT_W;
          end

          ST_WAIT_W: if (w_fire) state <= ST_IDLE;

          default: state <= ST_IDLE;
        endcase
      end
    end
  end

endmodule