// =============================================================================
// fx_phaser.sv - Phaser estilo MXR Phase 90
//
//   4 etapas ALL-PASS de 1er orden (TPT) en cascada, barridas por un LFO
//   triangular. La cascada corre la fase; al sumar con la senal seca aparecen
//   NOTCHES (muescas) en el espectro que se MUEVEN con el LFO -> el "whoosh".
//
//   4 etapas = 2 notches moviles = el sonido caracteristico del Phase 90.
//   (El Phase 100 usa 6 etapas = 3 notches; el 90 es de 4, mas musical.)
//
//   Estructura fiel al original:
//     - una sola perilla: SPEED (rate del LFO). Sin control de profundidad.
//     - feedback suave (script setea ~0.3) que resalta los notches.
//     - all-pass TPT: se banca que la fc cambie CADA MUESTRA sin clicks
//       (un biquad con coefs recalculados por muestra chillaria).
//
//   All-pass TPT 1er orden:  v = (x - s) * G ;  ap = v + s ;  s <= ap + v
//     donde G = tan(pi*fc/fs)/(1+tan(...)). El LFO modula G (via fc).
//   Salida del all-pass: y_ap = 2*ap - x   (equivalente al all-pass clasico)
//
//   FSM: procesa las 4 etapas en serie reusando UN multiplicador (el de G).
//   Reset SINCRONO. Bypass con auto-clear de los estados.
// =============================================================================
module fx_phaser (
  input  logic               clk,
  input  logic               rst_n,
  input  logic               enable,

  input  logic               in_valid,
  output logic               in_ready,
  input  logic signed [31:0] in_data,

  output logic               out_valid,
  input  logic               out_ready,
  output logic signed [31:0] out_data,

  // LFO: el PS entrega el incremento de fase (rate = Speed)
  input  logic [31:0]        lfo_phase_inc,
  // profundidad del barrido: G minimo y maximo (Q1.31) que recorre el LFO
  input  logic signed [31:0] g_min_q1_31,
  input  logic signed [31:0] g_max_q1_31,
  // feedback (Q1.31, tipico ~0.3)
  input  logic signed [31:0] fb_q1_31,

  // tabla del LFO (triangular por defecto) - opcional reescribir
  input  logic               wt_wr_en,
  input  logic [7:0]         wt_wr_addr,
  input  logic [31:0]        wt_wr_data
);
  import fx_dsp_pkg::*;

  // ---- LFO triangular por wavetable ----
  logic signed [31:0] lfo_tab [0:255];
  initial $readmemh("osc_tri.mem", lfo_tab);
  always_ff @(posedge clk) if (wt_wr_en) lfo_tab[wt_wr_addr] <= wt_wr_data;

  logic [31:0] lfo_phase;
  wire  [7:0]  lfo_idx = lfo_phase[31:24];
  logic signed [31:0] lfo_val;    // -1..1 Q3.29

  // ---- Estados de los 4 all-pass ----
  logic signed [31:0] s0, s1, s2, s3;
  logic signed [31:0] fb_reg;      // realimentacion (salida anterior)

  // ---- G actual (mapeado del LFO): G = g_min + (lfo01)*(g_max-g_min) ----
  logic signed [31:0] g_cur;

  // ---- Pipeline FSM ----
  logic signed [31:0] dry_r;       // muestra seca registrada al aceptar la entrada
  logic signed [31:0] x_in;        // entrada + feedback
  logic signed [31:0] ap_in;       // entrada de la etapa actual
  logic signed [31:0] v_r, ap_r;
  logic [1:0]         stage;

  typedef enum logic [2:0] {
    ST_IDLE  = 3'd0,
    ST_LFO   = 3'd1,   // calcular G del LFO       (mul: lfo01 * rango)
    ST_SUB   = 3'd2,   // v = (ap_in - s)*G        (mul)
    ST_STORE = 3'd3,   // ap = v + s ; s <= ap + v ; siguiente etapa
    ST_MIX   = 3'd4    // out = (dry + allpass_out)/2 ; feedback
  } state_t;
  state_t st;

  logic enable_d;
  wire clear_int = enable && !enable_d;

  logic               out_buf_valid;
  logic signed [31:0] out_buf;
  assign out_valid = enable ? out_buf_valid : in_valid;
  assign out_data  = enable ? out_buf       : in_data;
  assign in_ready  = enable ? ((st == ST_IDLE) && !out_buf_valid) : out_ready;
  wire out_fire = out_valid && out_ready;
  wire in_fire  = in_valid && in_ready && enable;

  // lfo01 = (lfo_val + 1)/2 en [0,1].
  // IMPORTANTE: el resultado sigue estando codificado en Q3.29.
  wire signed [31:0] lfo01_q3_29 =
      (lfo_val >>> 1) + 32'sh1000_0000;

  wire signed [31:0] g_range_q1_31 =
      sat_sub32(g_max_q1_31, g_min_q1_31);

  // Q3.29 * Q1.31 -> Q1.31, para poder sumarlo con g_min_q1_31.
  wire signed [31:0] g_delta_q1_31 =
      mul_q29_q31_to_q31(lfo01_q3_29, g_range_q1_31);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      st <= ST_IDLE; lfo_phase <= '0; lfo_val <= '0;
      s0<='0; s1<='0; s2<='0; s3<='0; fb_reg<='0;
      g_cur<='0; dry_r<='0; x_in<='0; ap_in<='0; v_r<='0; ap_r<='0; stage<='0;
      out_buf_valid<=1'b0; out_buf<='0; enable_d<=1'b0;
    end else begin
      enable_d <= enable;
      if (out_fire) out_buf_valid <= 1'b0;
      if (clear_int) begin
        s0<='0; s1<='0; s2<='0; s3<='0; fb_reg<='0; out_buf_valid<=1'b0;
      end

      case (st)
        ST_IDLE: if (in_fire) begin
          lfo_val   <= lfo_tab[lfo_idx];
          lfo_phase <= lfo_phase + lfo_phase_inc;
          // Registrar la muestra seca: in_data puede cambiar mientras la FSM procesa.
          dry_r <= in_data;
          // Entrada de la cascada = muestra actual + feedback de la salida anterior.
          x_in  <= sat_add32(in_data, mul_aud_q31(fb_reg, fb_q1_31));
          stage <= 2'd0;
          st    <= ST_LFO;
        end

        // G(Q1.31) = g_min(Q1.31) + delta_G(Q1.31)
        ST_LFO: begin
          g_cur <= sat_add32(g_min_q1_31, g_delta_q1_31);
          ap_in <= x_in;
          st    <= ST_SUB;
        end

        // v = (ap_in - s_stage) * G
        ST_SUB: begin
          logic signed [31:0] s_cur;
          case (stage)
            2'd0: s_cur = s0; 2'd1: s_cur = s1;
            2'd2: s_cur = s2; default: s_cur = s3;
          endcase
          v_r <= mul_aud_q31(sat_sub32(ap_in, s_cur), g_cur);
          st  <= ST_STORE;
        end

        // ap = v + s ; s <= ap + v ; salida all-pass = 2*ap - x = ap + s_old...
        // (usamos y_ap = ap + v_old_stored equivalente: ap_r = s_cur + v ; s <= ap_r + v)
        ST_STORE: begin
          logic signed [31:0] s_cur, ap_val;
          case (stage)
            2'd0: s_cur = s0; 2'd1: s_cur = s1;
            2'd2: s_cur = s2; default: s_cur = s3;
          endcase
          ap_val = sat_add32(s_cur, v_r);              // ap = s + v
          // actualizar estado: s <= ap + v
          case (stage)
            2'd0: s0 <= sat_add32(ap_val, v_r);
            2'd1: s1 <= sat_add32(ap_val, v_r);
            2'd2: s2 <= sat_add32(ap_val, v_r);
            default: s3 <= sat_add32(ap_val, v_r);
          endcase
          // salida del all-pass = 2*ap - in_stage
          ap_r <= sat_sub32(sat_add32(ap_val, ap_val), ap_in);
          if (stage == 2'd3) st <= ST_MIX;
          else begin
            ap_in <= sat_sub32(sat_add32(ap_val, ap_val), ap_in);
            stage <= stage + 2'd1;
            st    <= ST_SUB;
          end
        end

        ST_MIX: begin
          // salida = (seco + procesado) / 2   (mezcla clasica del phaser)
          logic signed [31:0] mixv;
          mixv          = sat_add32(dry_r >>> 1, ap_r >>> 1);
          out_buf       <= mixv;
          fb_reg        <= ap_r;          // feedback = salida de la cascada
          out_buf_valid <= 1'b1;
          st            <= ST_IDLE;
        end

        default: st <= ST_IDLE;
      endcase
    end
  end
endmodule