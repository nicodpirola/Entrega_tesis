// -----------------------------------------------------------------------------
// fx_filter_onepole_tpt_lp.sv  (pipelineado en 3 etapas)
//
// Filtro low-pass 1 polo basado en TPT/ZDF (integrador trapezoidal).
//   G  = g/(1+g)   (se provee como coeficiente en Q1.31)
//   v  = (x - s) * G
//   y  = s + v
//   s  = s + 2*v
//
// Handshake: single-in-flight.
// Usa fx_dsp_pkg para sat32, sat_add32, sat_sub32, mul_aud_q31.
// -----------------------------------------------------------------------------
module fx_lpf_1p_tpt #(
  parameter int DATA_W = 32
)(
  input  logic                 clk,
  input  logic                 rst_n,

  // Stream mono IN
  input  logic                 in_valid,
  output logic                 in_ready,
  input  logic signed [DATA_W-1:0] in_data,

  // Stream mono OUT
  output logic                 out_valid,
  input  logic                 out_ready,
  output logic signed [DATA_W-1:0] out_data,

  // Coeficiente (TPT)
  input  logic signed [31:0]   G_q1_31,

  // Limpieza de estado (pulso 1 ciclo recomendado)
  input  logic                 state_clear
);

  import fx_dsp_pkg::*;

  // -----------------------------
  // Estado del filtro (s[n])
  // -----------------------------
  logic signed [31:0] s_state;

  // -----------------------------
  // Pipeline registers
  // -----------------------------
  logic signed [31:0] s_eff_r;       // snapshot de s_state al aceptar
  logic signed [31:0] x_minus_s_r;   // x - s, registrado
  logic signed [31:0] v_r;           // v = (x-s)*G, registrado

  // -----------------------------
  // FSM
  // -----------------------------
  typedef enum logic [1:0] {
    ST_IDLE    = 2'd0,
    ST_MUL     = 2'd1,   // NUEVO: v = x_minus_s * G
    ST_STAGE2  = 2'd2,   // y = s + v, s_next = s + 2v
    ST_OUTWAIT = 2'd3
  } state_t;

  state_t st;

  wire in_fire  = in_valid && in_ready;
  wire out_fire = out_valid && out_ready;

  assign in_ready = (st == ST_IDLE);

  // -----------------------------
  // Secuencial
  // -----------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_state    <= '0;
      s_eff_r    <= '0;
      x_minus_s_r <= '0;
      v_r        <= '0;
      out_valid  <= 1'b0;
      out_data   <= '0;
      st         <= ST_IDLE;
    end else begin
      // state_clear con prioridad alta
      if (state_clear)
        s_state <= '0;

      case (st)
        // -------------------------------------------------
        // ST_IDLE: acepta muestra, computa x - s_eff
        //   Path: in_data, s_state → mux(state_clear) → sat_sub32 → registro
        //   Total: ~3 ns (1 subtraction)
        // -------------------------------------------------
        ST_IDLE: begin
          out_valid <= 1'b0;

          if (in_fire) begin
            logic signed [31:0] s_eff_l;
            s_eff_l     = state_clear ? 32'sd0 : s_state;
            s_eff_r     <= s_eff_l;
            x_minus_s_r <= sat_sub32(in_data, s_eff_l);
            st          <= ST_MUL;
          end
        end

        // -------------------------------------------------
        // ST_MUL: v = (x - s) * G
        //   Path: x_minus_s_r, G_q1_31 → DSP48 mul → registro
        //   Total: ~8 ns (1 multiplication)
        // -------------------------------------------------
        ST_MUL: begin
          v_r <= mul_aud_q31(x_minus_s_r, G_q1_31);
          st  <= ST_STAGE2;
        end

        // -------------------------------------------------
        // ST_STAGE2: y = s + v, s_next = s + 2v
        //   Path: s_eff_r, v_r → sat_add32 → registro
        //   Total: ~3 ns (additions only)
        // -------------------------------------------------
        ST_STAGE2: begin
          logic signed [63:0] v64_l;

          out_data  <= sat_add32(s_eff_r, v_r);
          out_valid <= 1'b1;

          v64_l = $signed(v_r);
          if (!state_clear)
            s_state <= sat_add32(s_eff_r, sat32(v64_l <<< 1));

          st <= ST_OUTWAIT;
        end

        // -------------------------------------------------
        // ST_OUTWAIT: mantiene out_valid hasta handshake
        // -------------------------------------------------
        ST_OUTWAIT: begin
          if (out_fire) begin
            out_valid <= 1'b0;
            st        <= ST_IDLE;
          end
        end

        default: begin
          st <= ST_IDLE;
        end
      endcase
    end
  end

endmodule