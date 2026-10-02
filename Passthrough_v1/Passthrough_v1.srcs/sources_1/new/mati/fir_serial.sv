// =============================================================================
// fir_serial.sv - FIR generico, MAC serial (1 mul por ciclo), N taps.
//
// Coeficientes Q1.31 en el parametro COEFS (packed, tap N-1 en los bits altos).
// Datos Q3.29. Handshake una-muestra-en-vuelo como el resto del proyecto.
// Latencia: N ciclos de MAC + 2.
// =============================================================================
module fir_serial #(
  parameter int N = 32,
  parameter logic [32*N-1:0] COEFS = '0
)(
  input  logic               clk,
  input  logic               rst_n,
  input  logic               state_clear,   // limpia la linea de retardo (pulso)

  input  logic               in_valid,
  output logic               in_ready,
  input  logic signed [31:0] in_data,

  output logic               out_valid,
  input  logic               out_ready,
  output logic signed [31:0] out_data
);
  import fx_dsp_pkg::*;

  // Linea de retardo
  logic signed [31:0] dline [0:N-1];

  // Coeficiente del tap actual (part-select dinamico del parametro packed)
  logic [$clog2(N)-1:0] tap_idx;
  wire signed [31:0] coef_cur = $signed(COEFS[32*tap_idx +: 32]);

  logic signed [63:0] acc;

  typedef enum logic [1:0] { ST_IDLE=2'd0, ST_MAC=2'd1, ST_DONE=2'd2 } state_t;
  state_t st;

  logic               out_buf_valid;
  logic signed [31:0] out_buf;
  assign out_valid = out_buf_valid;
  assign out_data  = out_buf;
  wire out_fire = out_valid && out_ready;
  wire in_fire  = in_valid && in_ready;
  assign in_ready = (st == ST_IDLE) && !out_buf_valid;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st <= ST_IDLE; tap_idx <= '0; acc <= '0;
      out_buf_valid <= 1'b0; out_buf <= '0;
      for (int i=0;i<N;i++) dline[i] <= '0;
    end else begin
      if (out_fire) out_buf_valid <= 1'b0;

      if (state_clear) begin
        for (int i=0;i<N;i++) dline[i] <= '0;
      end

      case (st)
        ST_IDLE: if (in_fire) begin
          for (int i=N-1;i>0;i--) dline[i] <= dline[i-1];
          dline[0] <= in_data;
          acc      <= '0;
          tap_idx  <= '0;
          st       <= ST_MAC;
        end

        ST_MAC: begin
          acc <= acc + ($signed(dline[tap_idx]) * coef_cur);
          if (tap_idx == N-1) st <= ST_DONE;
          else                tap_idx <= tap_idx + 1;
        end

        ST_DONE: begin
          out_buf       <= sat32(acc >>> 31);
          out_buf_valid <= 1'b1;
          st            <= ST_IDLE;
        end

        default: st <= ST_IDLE;
      endcase
    end
  end
endmodule
