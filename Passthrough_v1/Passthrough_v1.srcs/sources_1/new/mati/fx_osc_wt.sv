// =============================================================================
// fx_osc_wt.sv - OSCILADOR POR WAVETABLE (acumulador de fase + tabla + interp)
//
// Sirve para las DOS cosas del proyecto:
//   - LFO      (Leslie, chorus, tremolo): phase_inc chico -> fracciones de Hz
//   - DDS      (sintetizador):            phase_inc grande -> audio (110-2000Hz)
// Es exactamente el mismo hardware; solo cambia el rango de phase_inc.
//
// FRECUENCIA:  f = phase_inc * Fs / 2^32     ->   phase_inc = f * 2^32 / Fs
//   ejemplos (Fs=48k):  0.5 Hz -> 44739  |  440 Hz -> 39370533
//   resolucion: Fs/2^32 = 11.2 uHz. Sobra para afinacion musical.
//
// TABLA: 256 entradas Q3.29, PERIODICA (T[255] interpola contra T[0], no clampea
// como el waveshaper). Reescribible en runtime: seno, triangular, sierra,
// cuadrada, pulso... desde el PS por wt_wr_*.
//
// CUADRATURA: sale sin_out (fase actual) y cos_out (fase + 90 grados). El Leslie
// los necesita: la AMPLITUD sigue la POSICION del cuerno, y el Doppler sigue su
// DERIVADA -> quedan 90 grados desfasados. Un solo acumulador, dos lecturas.
//
// AMPLITUD: amp_q1_31 escala la salida (para el sinte: la envolvente del
// theremin entra por aca -> la mano de volumen controla el nivel del oscilador).
//
// Handshake: produce UNA muestra por cada tick de entrada (in_valid), asi se
// engancha a la cadena de audio como cualquier otro bloque. FSM un-mul-por-estado.
// Reset SINCRONO.
// =============================================================================
module fx_osc_wt (
  input  logic               clk,
  input  logic               rst_n,
  input  logic               enable,

  // tick de muestra (una salida por cada pulso)
  input  logic               in_valid,
  output logic               in_ready,

  output logic               out_valid,
  input  logic               out_ready,
  output logic signed [31:0] sin_out,    // Q3.29
  output logic signed [31:0] cos_out,    // Q3.29, +90 grados

  // Parametros
  input  logic [31:0]        phase_inc,      // f * 2^32 / Fs
  input  logic [31:0]        phase_offset,   // desfasaje fijo (0 = ninguno)
  input  logic signed [31:0] amp_q1_31,      // amplitud (envolvente)
  input  logic               phase_clear,    // resetea la fase a 0

  // Carga de la tabla desde el PS
  input  logic               wt_wr_en,
  input  logic [7:0]         wt_wr_addr,
  input  logic [31:0]        wt_wr_data
);
  import fx_dsp_pkg::*;

  // ---- Wavetable periodica ----
  logic signed [31:0] table_mem [0:255];
  initial $readmemh("osc_sine.mem", table_mem);

  always_ff @(posedge clk) begin
    if (wt_wr_en) table_mem[wt_wr_addr] <= wt_wr_data;
  end

  // ---- Acumulador de fase ----
  logic [31:0] phase_acc;

  // Fases de lectura: la actual y la de +90 grados (1/4 de vuelta = 2^30)
  wire [31:0] ph_sin = phase_acc + phase_offset;
  wire [31:0] ph_cos = phase_acc + phase_offset + 32'h4000_0000;

  // ---- Pipeline ----
  logic signed [31:0] s_t0, s_t1, c_t0, c_t1;
  logic [15:0]        s_frac, c_frac;
  logic signed [31:0] s_raw, c_raw;
  logic signed [31:0] s_term, c_term;

  typedef enum logic [2:0] {
    ST_IDLE  = 3'd0,
    ST_RD    = 3'd1,   // leer T[idx] y T[idx+1] de ambas fases (wrap periodico)
    ST_MUL_S = 3'd2,   // interp seno:  term = (T1-T0)*frac        (mul)
    ST_MUL_C = 3'd3,   // interp coseno                            (mul)
    ST_AMP_S = 3'd4,   // seno   * amplitud                        (mul)
    ST_AMP_C = 3'd5    // coseno * amplitud                        (mul)
  } state_t;
  state_t st;

  logic               out_buf_valid;
  logic signed [31:0] sin_buf, cos_buf;

  assign out_valid = out_buf_valid;
  assign sin_out   = sin_buf;
  assign cos_out   = cos_buf;
  wire out_fire = out_valid && out_ready;
  wire in_fire  = in_valid && in_ready;
  assign in_ready = (st == ST_IDLE) && !out_buf_valid;

  // indices y fracciones (la tabla es periodica -> idx+1 envuelve solo)
  wire [7:0]  s_idx  = ph_sin[31:24];
  wire [7:0]  c_idx  = ph_cos[31:24];

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      st <= ST_IDLE; phase_acc <= '0;
      s_t0 <= '0; s_t1 <= '0; c_t0 <= '0; c_t1 <= '0;
      s_frac <= '0; c_frac <= '0; s_raw <= '0; c_raw <= '0;
      s_term <= '0; c_term <= '0;
      out_buf_valid <= 1'b0; sin_buf <= '0; cos_buf <= '0;
    end else begin
      if (out_fire) out_buf_valid <= 1'b0;
      if (phase_clear) phase_acc <= '0;

      case (st)
        ST_IDLE: if (in_fire) begin
          if (enable) begin
            // capturar las dos lecturas de la tabla (idx e idx+1, con wrap)
            s_t0   <= table_mem[s_idx];
            s_t1   <= table_mem[s_idx + 8'd1];   // wrap natural en 8 bits
            s_frac <= ph_sin[23:8];
            c_t0   <= table_mem[c_idx];
            c_t1   <= table_mem[c_idx + 8'd1];
            c_frac <= ph_cos[23:8];
            st     <= ST_MUL_S;
          end else begin
            sin_buf       <= '0;
            cos_buf       <= '0;
            out_buf_valid <= 1'b1;
          end
          // avanzar la fase una muestra
          phase_acc <= phase_acc + phase_inc;
        end

        ST_MUL_S: begin
          logic signed [31:0] d;
          logic signed [48:0] p;
          d      = sat_sub32(s_t1, s_t0);
          p      = $signed(d) * $signed({1'b0, s_frac});
          s_term <= p[47:16];
          st     <= ST_MUL_C;
        end

        ST_MUL_C: begin
          logic signed [31:0] d;
          logic signed [48:0] p;
          d      = sat_sub32(c_t1, c_t0);
          p      = $signed(d) * $signed({1'b0, c_frac});
          c_term <= p[47:16];
          s_raw  <= sat_add32(s_t0, s_term);   // seno interpolado listo
          st     <= ST_AMP_S;
        end

        ST_AMP_S: begin
          c_raw   <= sat_add32(c_t0, c_term);  // coseno interpolado listo
          sin_buf <= mul_aud_q31(s_raw, amp_q1_31);
          st      <= ST_AMP_C;
        end

        ST_AMP_C: begin
          cos_buf       <= mul_aud_q31(c_raw, amp_q1_31);
          out_buf_valid <= 1'b1;
          st            <= ST_IDLE;
        end

        default: st <= ST_IDLE;
      endcase
    end
  end
endmodule
