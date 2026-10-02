// =============================================================================
// fx_tone_blend.sv - Control de TONO por mezcla de dos ramas en PARALELO.
//   (la topologia del tone de los pedales clasicos: Big Muff, Tube Screamer...)
//
//      in --+--> [ LPF ] (rama oscura)   --+
//           |                              +--> out = lpf + blend*(hpf - lpf)
//           +--> [ HPF ] (rama brillante) -+
//
//   blend (Q1.31): 0.0 = oscuro total | 0.5 = balanceado | ~1.0 = brillante
//
//   Los 10 coeficientes (5 LPF + 5 HPF) entran POR PUERTOS en Q2.30: el PS los
//   calcula con las formulas RBJ y los escribe por AXI. Asi se emula el tone de
//   cualquier pedal (cambiando las frecuencias de esquina) SIN resintetizar.
// =============================================================================
module fx_tone_blend (
  input  logic               clk,
  input  logic               rst_n,
  input  logic               enable,

  input  logic               in_valid,
  output logic               in_ready,
  input  logic signed [31:0] in_data,

  output logic               out_valid,
  input  logic               out_ready,
  output logic signed [31:0] out_data,

  // Coeficientes Q2.30 (del PS)
  input  logic signed [31:0] lpf_b0,
  input  logic signed [31:0] lpf_b1,
  input  logic signed [31:0] lpf_b2,
  input  logic signed [31:0] lpf_a1,
  input  logic signed [31:0] lpf_a2,
  input  logic signed [31:0] hpf_b0,
  input  logic signed [31:0] hpf_b1,
  input  logic signed [31:0] hpf_b2,
  input  logic signed [31:0] hpf_a1,
  input  logic signed [31:0] hpf_a2,

  input  logic signed [31:0] blend_q1_31
);
  import fx_dsp_pkg::*;

  // ---- Las dos ramas (siempre activas cuando el bloque lo esta) ----
  logic l_iv, l_ir, l_ov, l_or; logic signed [31:0] l_od;
  logic h_iv, h_ir, h_ov, h_or; logic signed [31:0] h_od;

  fx_biquad u_lpf (
    .clk(clk), .rst_n(rst_n), .state_clear(1'b0), .enable(enable),
    .in_valid(l_iv), .in_ready(l_ir), .in_data(in_data),
    .out_valid(l_ov), .out_ready(l_or), .out_data(l_od),
    .b0_q2_30(lpf_b0), .b1_q2_30(lpf_b1), .b2_q2_30(lpf_b2),
    .a1_q2_30(lpf_a1), .a2_q2_30(lpf_a2)
  );

  fx_biquad u_hpf (
    .clk(clk), .rst_n(rst_n), .state_clear(1'b0), .enable(enable),
    .in_valid(h_iv), .in_ready(h_ir), .in_data(in_data),
    .out_valid(h_ov), .out_ready(h_or), .out_data(h_od),
    .b0_q2_30(hpf_b0), .b1_q2_30(hpf_b1), .b2_q2_30(hpf_b2),
    .a1_q2_30(hpf_a1), .a2_q2_30(hpf_a2)
  );

  // ---- FSM: broadcast -> esperar ambas -> restar -> multiplicar -> sumar ----
  typedef enum logic [2:0] {
    ST_IDLE = 3'd0,
    ST_WAIT = 3'd1,
    ST_SUB  = 3'd2,
    ST_MUL  = 3'd3,
    ST_ADD  = 3'd4
  } state_t;
  state_t st;

  logic signed [31:0] ylpf_r, yhpf_r, dif_r, term_r;
  logic               got_l, got_h;

  logic               out_buf_valid;
  logic signed [31:0] out_buf;

  // Bypass: un solo driver por senal
  assign out_valid = enable ? out_buf_valid : in_valid;
  assign out_data  = enable ? out_buf       : in_data;
  assign in_ready  = enable ? ((st == ST_IDLE) && !out_buf_valid && l_ir && h_ir)
                            : out_ready;
  wire out_fire = out_valid && out_ready;
  wire in_fire  = in_valid && in_ready && enable;

  // broadcast: la muestra entra a las DOS ramas en el mismo ciclo
  assign l_iv = in_fire;
  assign h_iv = in_fire;
  assign l_or = (st == ST_WAIT);
  assign h_or = (st == ST_WAIT);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      st <= ST_IDLE;
      ylpf_r <= '0; yhpf_r <= '0; dif_r <= '0; term_r <= '0;
      got_l <= 1'b0; got_h <= 1'b0;
      out_buf_valid <= 1'b0; out_buf <= '0;
    end else begin
      if (out_fire) out_buf_valid <= 1'b0;

      if (!enable) begin
        st <= ST_IDLE; got_l <= 1'b0; got_h <= 1'b0;
        out_buf_valid <= 1'b0;
      end else begin
        case (st)
          ST_IDLE: if (in_fire) begin
            got_l <= 1'b0; got_h <= 1'b0;
            st    <= ST_WAIT;
          end

          ST_WAIT: begin
            if (l_ov && l_or) begin ylpf_r <= l_od; got_l <= 1'b1; end
            if (h_ov && h_or) begin yhpf_r <= h_od; got_h <= 1'b1; end
            if ((got_l || (l_ov && l_or)) && (got_h || (h_ov && h_or)))
              st <= ST_SUB;
          end

          ST_SUB: begin dif_r  <= sat_sub32(yhpf_r, ylpf_r);        st <= ST_MUL; end
          ST_MUL: begin term_r <= mul_aud_q31(dif_r, blend_q1_31);  st <= ST_ADD; end
          ST_ADD: begin
            out_buf       <= sat_add32(ylpf_r, term_r);
            out_buf_valid <= 1'b1;
            st            <= ST_IDLE;
          end

          default: st <= ST_IDLE;
        endcase
      end
    end
  end
endmodule