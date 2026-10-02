// DC blocker 1er orden:  y[n] = x[n] - x[n-1] + R*y[n-1]
module fx_dc_blocker_1pole #(
  parameter int DATA_W = 32
)(
  input  logic                     clk,
  input  logic                     rst_n,

  // Stream IN
  input  logic                     in_valid,
  output logic                     in_ready,
  input  logic signed [DATA_W-1:0] in_data,

  // Stream OUT
  output logic                     out_valid,
  input  logic                     out_ready,
  output logic signed [DATA_W-1:0] out_data,

  // Coeficiente
  input  logic signed [31:0]       R_q1_31,

  // Limpieza de estado (pulso 1 ciclo recomendado)
  input  logic                     state_clear
);

  import fx_dsp_pkg::*;


  // Estado del filtro: x[n-1], y[n-1]
  logic signed [31:0] x1;
  logic signed [31:0] y1;

  // registers
  logic signed [31:0] x_eff_r;       // x[n] capturado
  logic signed [31:0] x1_eff_r;      // x[n-1] (0 si clear)
  logic signed [31:0] y1_eff_r;      // y[n-1] (0 si clear)
  logic signed [31:0] diff_r;        // x - x1
  logic signed [31:0] ry1_r;         // R * y1
  logic               commit_r;      // si comprometer estado

  // FSM
  typedef enum logic [1:0] {
    ST_IDLE    = 2'd0,
    ST_MUL     = 2'd1,   // mul(y1_eff, R) + sub(x, x1_eff)
    ST_ADD     = 2'd2,   // y = diff + ry1
    ST_OUTWAIT = 2'd3
  } state_t;

  state_t st;

  wire in_fire  = in_valid && in_ready;
  wire out_fire = out_valid && out_ready;

  assign in_ready = (st == ST_IDLE);


  // Secuencial
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      x1        <= '0;
      y1        <= '0;
      x_eff_r   <= '0;
      x1_eff_r  <= '0;
      y1_eff_r  <= '0;
      diff_r    <= '0;
      ry1_r     <= '0;
      commit_r  <= 1'b0;
      out_valid <= 1'b0;
      out_data  <= '0;
      st        <= ST_IDLE;
    end else begin
      if (state_clear) begin
        x1 <= '0;
        y1 <= '0;
      end

      case (st)
        ST_IDLE: begin
          out_valid <= 1'b0;

          if (in_fire) begin
            x_eff_r  <= in_data;
            x1_eff_r <= state_clear ? 32'sd0 : x1;
            y1_eff_r <= state_clear ? 32'sd0 : y1;
            commit_r <= !state_clear;
            st       <= ST_MUL;
          end
        end
        ST_MUL: begin
          ry1_r  <= mul_aud_q31(y1_eff_r, R_q1_31);
          diff_r <= sat_sub32(x_eff_r, x1_eff_r);
          st     <= ST_ADD;
        end
        ST_ADD: begin
          logic signed [31:0] y_val;
          y_val = sat_add32(diff_r, ry1_r);

          out_data  <= y_val;
          out_valid <= 1'b1;

          if (!state_clear && commit_r) begin
            x1 <= x_eff_r;
            y1 <= y_val;
          end

          st <= ST_OUTWAIT;
        end

        ST_OUTWAIT: begin
          if (out_fire) begin
            out_valid <= 1'b0;
            st        <= ST_IDLE;
          end
        end

        default: st <= ST_IDLE;
      endcase
    end
  end

endmodule
