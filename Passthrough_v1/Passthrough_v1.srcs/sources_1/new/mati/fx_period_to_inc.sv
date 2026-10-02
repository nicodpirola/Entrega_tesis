// =============================================================================
// fx_period_to_inc.sv - Periodo Q16.16 -> phase increment DDS de 32 bits
//
//   phase_inc = 2^32 / periodo_muestras
//             = 2^48 / period_16_16
//
// El divisor es secuencial (49 iteraciones). El glide avanza una vez por
// muestra de audio, no por clock FPGA. El primer periodo valido se engancha
// directamente; los cambios posteriores se suavizan.
//
// GLIDE aproximado a Fs=48 kHz:
//   0  : inmediato
//   10 : ~21 ms
//   11 : ~43 ms
//   12 : ~85 ms
//
// Reset sincrono activo en bajo mediante rst_n.
// =============================================================================
module fx_period_to_inc #(
  parameter int GLIDE = 10
)(
  input  logic        clk,
  input  logic        rst_n,

  input  logic [31:0] period_16_16,
  input  logic        period_valid,
  input  logic        gate,
  input  logic        sample_tick,

  output logic [31:0] phase_inc,
  output logic        inc_valid
);

  // ---------------------------------------------------------------------------
  // Divisor secuencial: 2^48 / period_16_16
  // ---------------------------------------------------------------------------
  localparam logic [48:0] DIVIDEND = 49'h1_0000_0000_0000;

  typedef enum logic [1:0] {
    D_IDLE = 2'd0,
    D_RUN  = 2'd1,
    D_DONE = 2'd2
  } dstate_t;

  dstate_t ds;
  logic [48:0] rem;
  logic [31:0] quot;
  logic [31:0] den;
  logic [5:0]  cnt;
  logic        div_done;
  logic [31:0] inc_target;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      ds         <= D_IDLE;
      rem        <= '0;
      quot       <= '0;
      den        <= '0;
      cnt        <= '0;
      div_done   <= 1'b0;
      inc_target <= '0;
    end else begin
      div_done <= 1'b0;

      case (ds)
        D_IDLE: begin
          if (period_valid && (period_16_16 != 32'd0)) begin
            rem  <= '0;
            quot <= '0;
            den  <= period_16_16;
            cnt  <= 6'd49;
            ds   <= D_RUN;
          end
        end

        D_RUN: begin
          logic [48:0] rem_shifted;
          logic        dividend_bit;

          dividend_bit = DIVIDEND[cnt-1'b1];
          rem_shifted   = {rem[47:0], dividend_bit};

          if (rem_shifted >= {17'd0, den}) begin
            rem  <= rem_shifted - {17'd0, den};
            quot <= {quot[30:0], 1'b1};
          end else begin
            rem  <= rem_shifted;
            quot <= {quot[30:0], 1'b0};
          end

          cnt <= cnt - 1'b1;
          if (cnt == 6'd1)
            ds <= D_DONE;
        end

        D_DONE: begin
          // quot ya contiene el ultimo bit calculado en D_RUN.
          inc_target <= quot;
          div_done   <= 1'b1;
          ds         <= D_IDLE;
        end

        default: ds <= D_IDLE;
      endcase
    end
  end

  // ---------------------------------------------------------------------------
  // Glide por muestra
  // ---------------------------------------------------------------------------
  logic [31:0] inc_smooth;
  logic        have_target;

  assign phase_inc = inc_smooth;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      inc_smooth <= '0;
      have_target <= 1'b0;
      inc_valid   <= 1'b0;
    end else begin
      inc_valid <= 1'b0;

      // div_done se observa un ciclo despues de D_DONE; para entonces
      // inc_target ya contiene el cociente nuevo.
      if (div_done) begin
        if (!have_target) begin
          // Primera nota: no hacer glide desde 0 Hz.
          inc_smooth <= inc_target;
          inc_valid  <= 1'b1;
        end
        have_target <= 1'b1;
      end

      // Sin gate se conserva la ultima frecuencia. El VCA silencia la voz.
      if (gate && have_target && sample_tick && !div_done) begin
        if (GLIDE == 0) begin
          if (inc_smooth != inc_target) begin
            inc_smooth <= inc_target;
            inc_valid  <= 1'b1;
          end
        end else begin
          logic signed [32:0] current_s;
          logic signed [32:0] target_s;
          logic signed [32:0] diff_s;
          logic signed [32:0] step_s;
          logic signed [32:0] next_s;
          logic        [32:0] mag_s;

          current_s = $signed({1'b0, inc_smooth});
          target_s  = $signed({1'b0, inc_target});
          diff_s    = target_s - current_s;
          step_s    = 33'sd0;

          if (diff_s > 0) begin
            step_s = diff_s >>> GLIDE;
            if (step_s == 0)
              step_s = 33'sd1;
          end else if (diff_s < 0) begin
            mag_s  = $unsigned(-diff_s);
            step_s = -$signed(mag_s >> GLIDE);
            if (step_s == 0)
              step_s = -33'sd1;
          end

          next_s = current_s + step_s;

          if (step_s != 0) begin
            // El paso nunca sobrepasa el target; estas defensas evitan
            // resultados fuera de rango ante parametros invalidos.
            if (next_s < 0)
              inc_smooth <= 32'd0;
            else if (next_s > $signed(33'h0_FFFF_FFFF))
              inc_smooth <= 32'hFFFF_FFFF;
            else
              inc_smooth <= next_s[31:0];

            inc_valid <= 1'b1;
          end
        end
      end
    end
  end

`ifndef SYNTHESIS
  initial begin
    if ((GLIDE < 0) || (GLIDE > 31))
      $error("fx_period_to_inc: GLIDE debe estar entre 0 y 31");
  end
`endif

endmodule
