// -----------------------------------------------------------------------------
// fx_tremolo.sv   (modulacion de amplitud con LFO triangular)
//
//   out = x * gain(t)
//   gain(t) = 1 - depth*(1+lfo)/2      con lfo en [-1,+1]
//     depth=0 -> gain=1 (sin tremolo)
//     depth=1 -> gain va de 1 a 0 (tremolo total, se calla en los valles)
//
// FSM (4 estados, 1 mul principal):
//   ST_IDLE : acepta x, snapshot LFO
//   ST_GAIN : calcula gain_q (unipolar) a partir de lfo y depth
//   ST_MUL  : out = x * gain
//   ST_OUT  : emite
//
// Formato: x en Q3.29, depth/gain en Q1.31, mul con mul_aud_q31.
// -----------------------------------------------------------------------------
module fx_tremolo (
  input  logic               clk,
  input  logic               rst_n,
  input  logic               enable,

  input  logic               in_valid,
  output logic               in_ready,
  input  logic signed [31:0] in_data,

  output logic               out_valid,
  input  logic               out_ready,
  output logic signed [31:0] out_data,

  input  logic signed [31:0] depth_q1_31,       // profundidad 0..1
  input  logic [31:0]        lfo_phase_inc_u32  // velocidad
);

  import fx_dsp_pkg::*;

  // Output buffer
  logic               out_buf_valid;
  logic signed [31:0] out_buf;
  assign out_valid = out_buf_valid;
  assign out_data  = out_buf;
  wire out_fire = out_valid && out_ready;

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
  typedef enum logic [1:0] {
    ST_IDLE = 2'd0,
    ST_GAIN = 2'd1,
    ST_MUL  = 2'd2,
    ST_OUT  = 2'd3
  } state_t;

  state_t state;
  logic signed [31:0] x_reg;
  logic signed [31:0] lfo_r;
  logic signed [31:0] gain_r;     // ganancia unipolar Q1.31
  logic signed [31:0] out_r;

  // Bypass
  wire bypass_mode = (!enable);
  wire can_accept = (state == ST_IDLE) && (!out_buf_valid);
  assign in_ready = can_accept;

  wire in_fire = in_valid && in_ready;

  assign lfo_tick  = (!bypass_mode) && (state == ST_IDLE) && in_fire;
  assign lfo_clear = enable_rise && (state == ST_IDLE) && !out_buf_valid;

  // depth clamp a [0,1]
  logic signed [31:0] depth_eff;
  always_comb begin
    if (depth_q1_31 < 32'sd0)             depth_eff = 32'sd0;
    else if (depth_q1_31 > 32'sh7FFF_FFFF) depth_eff = 32'sh7FFF_FFFF;
    else                                   depth_eff = depth_q1_31;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= ST_IDLE; x_reg <= '0; lfo_r <= '0; gain_r <= '0; out_r <= '0;
      out_buf <= '0; out_buf_valid <= 1'b0;
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
            state <= ST_GAIN;
          end

          // gain = 1 - depth*(1+lfo)/2
          // (1+lfo)/2  en Q1.31: lfo va de -2^31 a +2^31-1.
          //   (1+lfo)/2 = (lfo >>> 1) + 2^30   -> rango [0, 2^31) = [0,1)
          // depth_term = depth * (1+lfo)/2     (mul_aud_q31)
          // gain = 2^31(=1.0) - depth_term  (saturado)
          ST_GAIN: begin
            logic signed [31:0] half_lfo;   // (1+lfo)/2 en Q1.31
            logic signed [31:0] depth_term;
            half_lfo   = (lfo_r >>> 1) + 32'sh4000_0000;   // (lfo/2)+0.5
            depth_term = mul_aud_q31(depth_eff, half_lfo);
            // gain = 1.0 - depth_term ; 1.0 en Q1.31 ~ 0x7FFFFFFF
            gain_r <= sat_sub32(32'sh7FFF_FFFF, depth_term);
            state  <= ST_MUL;
          end

          ST_MUL: begin
            out_r <= mul_aud_q31(x_reg, gain_r);
            state <= ST_OUT;
          end

          ST_OUT: begin
            out_buf       <= out_r;
            out_buf_valid <= 1'b1;
            state         <= ST_IDLE;
          end

          default: state <= ST_IDLE;
        endcase
      end
    end
  end

endmodule