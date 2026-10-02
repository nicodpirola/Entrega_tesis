// =============================================================================
// fx_biquad.sv - Biquad DF1 con UN SOLO multiplicador compartido.
//
//   y[n] = b0*x[n] + b1*x[n-1] + b2*x[n-2] - a1*y[n-1] - a2*y[n-2]
//
// AREA: los operandos se MUXEAN por estado hacia un unico multiplicador
// fisico (4 DSP48E1 para un 32x32 con signo), reusado 5 ciclos.
// Antes, con 5 expresiones de multiplicacion separadas, Vivado inferia
// 5 multiplicadores (20 DSPs) por biquad. Ahora: 4 DSPs por biquad.
//
// Coeficientes Q2.30 (|a1| puede llegar a 2). Datos Q3.29. Acumulador 64b,
// una sola saturacion al final. Reset SINCRONO. Bypass con auto-clear.
// =============================================================================
module fx_biquad (
  input  logic               clk,
  input  logic               rst_n,
  input  logic               state_clear,
  input  logic               enable,

  input  logic               in_valid,
  output logic               in_ready,
  input  logic signed [31:0] in_data,

  output logic               out_valid,
  input  logic               out_ready,
  output logic signed [31:0] out_data,

  input  logic signed [31:0] b0_q2_30,
  input  logic signed [31:0] b1_q2_30,
  input  logic signed [31:0] b2_q2_30,
  input  logic signed [31:0] a1_q2_30,
  input  logic signed [31:0] a2_q2_30
);
  import fx_dsp_pkg::*;

  logic enable_d;
  wire  clear_int = state_clear || (enable && !enable_d);

  // Memoria del filtro
  logic signed [31:0] x1, x2, y1, y2;
  logic signed [31:0] x_reg;
  logic signed [63:0] acc;

  typedef enum logic [2:0] {
    ST_IDLE = 3'd0,
    ST_B0   = 3'd1,
    ST_B1   = 3'd2,
    ST_B2   = 3'd3,
    ST_A1   = 3'd4,
    ST_A2   = 3'd5,
    ST_DONE = 3'd6
  } state_t;
  state_t st;

  // ---- EL MULTIPLICADOR UNICO: operandos muxeados por estado ----
  logic signed [31:0] mul_a, mul_b;
  always_comb begin
    case (st)
      ST_B0:   begin mul_a = x_reg; mul_b = b0_q2_30; end
      ST_B1:   begin mul_a = x1;    mul_b = b1_q2_30; end
      ST_B2:   begin mul_a = x2;    mul_b = b2_q2_30; end
      ST_A1:   begin mul_a = y1;    mul_b = a1_q2_30; end
      ST_A2:   begin mul_a = y2;    mul_b = a2_q2_30; end
      default: begin mul_a = 32'sd0; mul_b = 32'sd0;  end
    endcase
  end
  wire signed [63:0] prod = $signed(mul_a) * $signed(mul_b);   // <-- 1 solo mult

  logic               out_buf_valid;
  logic signed [31:0] out_buf;

  assign out_valid = enable ? out_buf_valid : in_valid;
  assign out_data  = enable ? out_buf       : in_data;
  assign in_ready  = enable ? ((st == ST_IDLE) && !out_buf_valid) : out_ready;
  wire out_fire = out_valid && out_ready;
  wire in_fire  = in_valid && in_ready && enable;

  logic signed [31:0] y_new;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      st <= ST_IDLE; x_reg <= '0; acc <= '0; enable_d <= 1'b0;
      x1 <= '0; x2 <= '0; y1 <= '0; y2 <= '0;
      out_buf_valid <= 1'b0; out_buf <= '0;
    end else begin
      enable_d <= enable;
      if (out_fire) out_buf_valid <= 1'b0;

      if (clear_int) begin
        x1 <= '0; x2 <= '0; y1 <= '0; y2 <= '0;
        out_buf_valid <= 1'b0;
      end

      case (st)
        ST_IDLE: if (in_fire) begin
          x_reg <= in_data;
          st    <= ST_B0;
        end

        // Un acumulado por estado, todos con el MISMO multiplicador (prod)
        ST_B0: begin acc <= prod;       st <= ST_B1; end
        ST_B1: begin acc <= acc + prod; st <= ST_B2; end
        ST_B2: begin acc <= acc + prod; st <= ST_A1; end
        ST_A1: begin acc <= acc - prod; st <= ST_A2; end
        ST_A2: begin acc <= acc - prod; st <= ST_DONE; end

        ST_DONE: begin
          y_new = sat32(acc >>> 30);
          out_buf       <= y_new;
          out_buf_valid <= 1'b1;
          x2 <= x1;  x1 <= x_reg;
          y2 <= y1;  y1 <= y_new;
          st <= ST_IDLE;
        end

        default: st <= ST_IDLE;
      endcase
    end
  end
endmodule