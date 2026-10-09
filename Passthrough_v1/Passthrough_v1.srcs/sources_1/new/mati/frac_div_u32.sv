
// restoring division
//    Q = numerador/denominador en uq1.31
// Lo uso para polyblep entonces siempre n < d
//
// Los nombres de los registros uso los de mi apunte
//     M     = divisor
//     Acc   = acumulador / resto        A es el que se shiftea y resta
//     Q     = cociente                  se arma bit a bit
//     Count = iteraciones restantes     baja de 31 a 0
//
// Operacion por paso:  LS(Acc:Q) ; Acc = Acc - M ; si Acc>=0 -> Q0=1

module frac_div_u32 (
  input  logic        clk,
  input  logic        rst_n,

  // request
  input  logic        in_valid,
  output logic        in_ready,
  input  logic [31:0] numerator,
  input  logic [31:0] denominator,

  // response (UQ1.31)
  output logic        out_valid,
  input  logic        out_ready,
  output logic [31:0] quotient_q31
);


  typedef enum logic [1:0] {
    S_IDLE = 2'd0,
    S_RUN  = 2'd1,
    S_HOLD = 2'd2
  } state_t;

  state_t state;


  //   Acc de 33 bits: al hacer LS (Acc<<1) puede necesitar el bit extra.

  logic [32:0] M;        // latch denominador denominador
  logic [32:0] Acc;      // acumulador / resto parcial
  logic [31:0] Q;
  logic [5:0]  Count;

  //Una iteracion restoring combinacional
  //   shift de Acc y de Q una posicion a la izquierda.
  //   Si el divisor entra (Acc_shift >= M): Acc = Acc_shift - M y Q0 = 1.
  //   Si no Acc queda igual y Q0 = 0
  // ---------------------------------------------------------------------------
  logic [32:0] Acc_shift;
  logic [32:0] Acc_next;
  logic [31:0] Q_next;

  always_comb begin
    Acc_shift = Acc << 1;
    Q_next    = Q   << 1;      // hace lugar para el nuevo bit (arranca en 0)
    Acc_next  = Acc_shift;     // por defecto no se resta

    if (Acc_shift >= M) begin
      Acc_next    = Acc_shift - M;
      Q_next[0]   = 1'b1;      // el bit de este paso es 1
    end
  end


  //Handshake
  assign in_ready     = (state == S_IDLE);
  assign out_valid    = (state == S_HOLD);
  assign quotient_q31 = Q;


  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state <= S_IDLE;
      M     <= '0;
      Acc   <= '0;
      Q     <= '0;
      Count <= '0;
    end else begin
      case (state)

        S_IDLE: begin
          if (in_valid && in_ready) begin
            // proteccion den=0 o num>=den -> devuelvo 0
            if ((denominator == 32'd0) || (numerator >= denominator)) begin
              Q     <= 32'd0;
              state <= S_HOLD;
            end else begin
              Acc   <= {1'b0, numerator};     // Acc <- Dividend
              M     <= {1'b0, denominator};   // M   <- Divisor
              Q     <= 32'd0;                 // Q   <- 0
              Count <= 6'd31;                 // Count <- n
              state <= S_RUN;
            end
          end
        end

        // un bit fraccional por ciclo. Count baja de 31 a 1 (31 pasos).
        S_RUN: begin
          Acc <= Acc_next;
          Q   <= Q_next;

          if (Count == 6'd1)
            state <= S_HOLD;      // ultimo bit hecho
          else
            Count <= Count - 1'b1;
        end


        S_HOLD: begin
          if (out_valid && out_ready)
            state <= S_IDLE;
        end

        default: state <= S_IDLE;
      endcase
    end
  end

  // ---------------------------------------------------------------------------
  // Assert de contrato (solo simulacion)
  // ---------------------------------------------------------------------------
`ifndef SYNTHESIS
  always_ff @(posedge clk) begin
    if (rst_n && in_valid && in_ready) begin
      assert (denominator != 32'd0)
        else $error("frac_div_u32: denominator == 0");
      assert (numerator < denominator)
        else $error("frac_div_u32: numerator >= denominator");
    end
  end
`endif

endmodule
