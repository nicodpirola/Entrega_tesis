// =============================================================================
// fx_envelope.sv - SEGUIDOR DE ENVOLVENTE (rama de analisis, NO efecto en serie)
//
//   y = a*(y - |x|) + |x|   (1 mul, forma distribuida)
//   'a' se elige por muestra: sube -> a_atk (rapido) ; baja -> a_rel (lento)
//
// INTERFAZ DE OBSERVADOR: recibe sample_valid (un pulso cuando el stream
// principal transfiere una muestra) y NO frena nada. A 50MHz hay ~1041 ciclos
// entre muestras; sus 4 estados terminan de sobra. No expone in_ready/out_ready.
//
// GATE CON HISTERESIS: dos umbrales (abre alto, cierra bajo) para que no titile
// cuando la señal muere -> el detector de pitch no se resetea constantemente.
//
//   env_out (Q3.29, >=0): amplitud para el DDS (mano de volumen del theremin)
//   gate: 1 mientras hay señal (con histeresis)
//   env_update: pulso de 1 ciclo cuando hay env nuevo
// =============================================================================
module fx_envelope (
  input  logic               clk,
  input  logic               rst_n,

  input  logic               sample_valid,   // pulso: llego una muestra nueva
  input  logic signed [31:0] sample_data,    // Q3.29

  output logic signed [31:0] env_out,        // Q3.29 (>=0)
  output logic               gate,
  output logic               env_update,     // pulso 1 ciclo

  input  logic signed [31:0] a_atk_q1_31,
  input  logic signed [31:0] a_rel_q1_31,
  input  logic signed [31:0] gate_on_thr_q3_29,   // umbral para ABRIR
  input  logic signed [31:0] gate_off_thr_q3_29   // umbral para CERRAR (< on)
);
  import fx_dsp_pkg::*;

  logic signed [31:0] env_reg;
  logic               gate_reg;

  typedef enum logic [1:0] {
    ST_IDLE = 2'd0,
    ST_SUB  = 2'd1,   // diff = env - |x|
    ST_MUL  = 2'd2,   // prod = a * diff      (unico mul)
    ST_DONE = 2'd3    // env  = prod + |x| ; gate con histeresis
  } state_t;
  state_t st;

  logic signed [31:0] rect_r;
  logic signed [31:0] a_sel;
  logic signed [31:0] diff_r;
  logic signed [31:0] prod_r;

  assign env_out = env_reg;
  assign gate    = gate_reg;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      st <= ST_IDLE; env_reg <= '0; gate_reg <= 1'b0;
      rect_r <= '0; a_sel <= '0; diff_r <= '0; prod_r <= '0;
      env_update <= 1'b0;
    end else begin
      env_update <= 1'b0;

      case (st)
        ST_IDLE: if (sample_valid) begin
          logic signed [31:0] ax;
          ax     = $signed(abs32(sample_data));
          rect_r <= ax;
          a_sel  <= (ax > env_reg) ? a_atk_q1_31 : a_rel_q1_31;
          st     <= ST_SUB;
        end

        ST_SUB: begin
          diff_r <= sat_sub32(env_reg, rect_r);
          st     <= ST_MUL;
        end

        ST_MUL: begin
          prod_r <= mul_aud_q31(a_sel, diff_r);
          st     <= ST_DONE;
        end

        ST_DONE: begin
          logic signed [31:0] new_env;
          new_env <= sat_add32(prod_r, rect_r);
          env_reg <= sat_add32(prod_r, rect_r);
          // gate con histeresis
          if (!gate_reg) begin
            if (sat_add32(prod_r, rect_r) >= gate_on_thr_q3_29)  gate_reg <= 1'b1;
          end else begin
            if (sat_add32(prod_r, rect_r) <= gate_off_thr_q3_29) gate_reg <= 1'b0;
          end
          env_update <= 1'b1;
          st <= ST_IDLE;
        end

        default: st <= ST_IDLE;
      endcase
    end
  end
endmodule