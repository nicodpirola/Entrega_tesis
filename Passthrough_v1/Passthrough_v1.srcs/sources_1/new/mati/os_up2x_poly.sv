// =============================================================================
// os_up2x_poly.sv - Upsampler 2x POLYPHASE: mitad de multiplicaciones.
//
// En vez de insertar ceros y filtrar con el FIR completo (N MACs x 2 pushes,
// la mitad multiplicando ceros), se separa el filtro en 2 fases:
//   FASE_A = coefs pares  (h0,h2,...)  -> produce la 1ra salida del par
//   FASE_B = coefs impares(h1,h3,...)  -> produce la 2da
// Ambas corren sobre la MISMA linea de retardo de muestras REALES (N/2 prof.).
// Los ceros nunca se materializan: ninguna multiplicacion es por cero.
//
//   Costo por muestra de entrada:  2 x (N/2) = N MACs   (zero-stuff: 2N)
//
// Puertos identicos a os_up2x -> reemplazo directo (drop-in).
// Matematicamente equivalente bit-exact (misma suma entera, mismos productos;
// los productos por cero del zero-stuff aportaban 0 exacto).
// =============================================================================
module os_up2x_poly #(
  parameter int NHALF = 16,                       // taps por fase (N/2)
  parameter logic [32*NHALF-1:0] FASE_A = '0,     // coefs pares
  parameter logic [32*NHALF-1:0] FASE_B = '0      // coefs impares
)(
  input  logic               clk,
  input  logic               rst_n,
  input  logic               state_clear,

  input  logic               in_valid,
  output logic               in_ready,
  input  logic signed [31:0] in_data,

  output logic               out_valid,
  input  logic               out_ready,
  output logic signed [31:0] out_data
);
  import fx_dsp_pkg::*;

  // Linea de retardo: solo muestras REALES
  logic signed [31:0] dline [0:NHALF-1];

  // Coeficiente actual segun fase
  logic [$clog2(NHALF)-1:0] tap_idx;
  logic fase;   // 0 = A, 1 = B
  wire signed [31:0] coef_cur = fase ? $signed(FASE_B[32*tap_idx +: 32])
                                     : $signed(FASE_A[32*tap_idx +: 32]);

  logic signed [63:0] acc;

  typedef enum logic [1:0] {
    ST_IDLE = 2'd0,
    ST_MAC  = 2'd1,   // MAC serial de la fase actual
    ST_OUT  = 2'd2    // entregar la salida de esta fase
  } state_t;
  state_t st;

  logic               out_buf_valid;
  logic signed [31:0] out_buf;
  assign out_valid = out_buf_valid && (st == ST_OUT);
  assign out_data  = out_buf;
  wire out_fire = out_valid && out_ready;
  wire in_fire  = in_valid && in_ready;
  assign in_ready = (st == ST_IDLE);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st <= ST_IDLE; tap_idx <= '0; acc <= '0; fase <= 1'b0;
      out_buf_valid <= 1'b0; out_buf <= '0;
      for (int i=0;i<NHALF;i++) dline[i] <= '0;
    end else begin
      if (state_clear) begin
        for (int i=0;i<NHALF;i++) dline[i] <= '0;
      end

      case (st)
        ST_IDLE: if (in_fire) begin
          // una unica insercion por muestra REAL (no hay push de cero)
          for (int i=NHALF-1;i>0;i--) dline[i] <= dline[i-1];
          dline[0] <= in_data;
          acc     <= '0;
          tap_idx <= '0;
          fase    <= 1'b0;          // arranca la fase A
          st      <= ST_MAC;
        end

        ST_MAC: begin
          acc <= acc + ($signed(dline[tap_idx]) * coef_cur);
          if (tap_idx == NHALF-1) begin
            st <= ST_OUT;
          end else
            tap_idx <= tap_idx + 1;
        end

        ST_OUT: begin
          if (!out_buf_valid) begin
            out_buf       <= sat32(acc >>> 31);
            out_buf_valid <= 1'b1;
          end else if (out_fire) begin
            out_buf_valid <= 1'b0;
            if (fase == 1'b0) begin
              // termino la fase A -> correr la fase B (misma dline)
              fase    <= 1'b1;
              acc     <= '0;
              tap_idx <= '0;
              st      <= ST_MAC;
            end else begin
              st <= ST_IDLE;      // las 2 salidas entregadas
            end
          end
        end

        default: st <= ST_IDLE;
      endcase
    end
  end
endmodule
