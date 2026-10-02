// =============================================================================
// fx_waveshaper.sv - Distorsion por tabla, DOMINIO ANCHO (+-4.0)
//
//   y = tabla( x * drive )     con interpolacion lineal
//
// CAMBIO CLAVE vs la version anterior:
//   Antes el dominio de la tabla era [-1,+1) y x*drive se CLAMPEABA ahi.
//   Con drive alto casi toda la onda quedaba aplastada contra el tope: la
//   salida era una CUADRADA (con esquina dura en la derivada -> aspereza
//   digital), y la curva nunca se recorria de verdad.
//
//   Ahora el dominio es [-4,+4) = el rango NATURAL de Q3.29. El drive empuja
//   la senal ADENTRO de la curva (y = tanh(drive*x) de verdad). En el borde
//   del dominio la curva ya esta plana (tanh(4)=0.9993, derivada ~0.001), asi
//   que la saturacion es suave: NO hay esquina.
//
//   Indexado: xd en Q3.29 -> invertir el bit de signo da un unsigned que
//   mapea [-4,+4) a [0, 2^32).  idx = u[31:24] (256 entradas), frac = u[23:8].
//
// Tabla: 256 entradas Q3.29, reescribible en runtime (wt_wr_*).
// FSM un-mul-por-estado. Reset sincrono.
// =============================================================================
module fx_waveshaper (
  input  logic               clk,
  input  logic               rst_n,

  input  logic               in_valid,
  output logic               in_ready,
  input  logic signed [31:0] in_data,

  output logic               out_valid,
  input  logic               out_ready,
  output logic signed [31:0] out_data,

  input  logic [31:0]        drive_16_16,

  input  logic               wt_wr_en,
  input  logic [7:0]         wt_wr_addr,
  input  logic [31:0]        wt_wr_data
);
  import fx_dsp_pkg::*;

  // ---- Wavetable (dominio [-4,+4), salida Q3.29) ----
  logic signed [31:0] table_mem [0:255];
  initial $readmemh("tanh_table.mem", table_mem);

  always_ff @(posedge clk) begin
    if (wt_wr_en) table_mem[wt_wr_addr] <= wt_wr_data;
  end

  // ---- Pipeline ----
  logic signed [31:0] x_reg;
  logic signed [31:0] xd_r;        // x*drive, saturado a Q3.29 (= +-4.0)
  logic [7:0]         idx_r;
  logic [15:0]        frac_r;
  logic signed [31:0] t0_r, t1_r;
  logic signed [31:0] term_r;

  typedef enum logic [2:0] {
    ST_IDLE  = 3'd0,
    ST_DRIVE = 3'd1,   // xd = sat(x * drive)          (mul 1)
    ST_RD0   = 3'd2,   // idx/frac + leer T[idx]
    ST_RD1   = 3'd3,   // leer T[idx+1]
    ST_MUL   = 3'd4,   // term = (T1-T0) * frac        (mul 2)
    ST_ADD   = 3'd5    // y = T0 + term
  } state_t;
  state_t st;

  logic               out_buf_valid;
  logic signed [31:0] out_buf;
  assign out_valid = out_buf_valid;
  assign out_data  = out_buf;
  wire out_fire = out_valid && out_ready;
  wire in_fire  = in_valid && in_ready;
  assign in_ready = (st == ST_IDLE) && !out_buf_valid;

  // Mapeo Q3.29 [-4,+4) -> unsigned [0, 2^32): invertir el bit de signo
  wire [31:0] u_w = {~xd_r[31], xd_r[30:0]};

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      st <= ST_IDLE; x_reg <= '0; xd_r <= '0;
      idx_r <= '0; frac_r <= '0; t0_r <= '0; t1_r <= '0; term_r <= '0;
      out_buf_valid <= 1'b0; out_buf <= '0;
    end else begin
      if (out_fire) out_buf_valid <= 1'b0;

      case (st)
        ST_IDLE: if (in_fire) begin
          x_reg <= in_data;
          st    <= ST_DRIVE;
        end

        // x (Q3.29) * drive (Q16.16) -> Q3.29 con saturacion.
        // La saturacion tope (+-4.0) cae donde la curva YA esta plana: suave.
        ST_DRIVE: begin
          logic signed [63:0] p;
          p    = $signed(x_reg) * $signed({1'b0, drive_16_16});
          xd_r <= sat32(p >>> 16);
          st   <= ST_RD0;
        end

        ST_RD0: begin
          idx_r  <= u_w[31:24];
          frac_r <= u_w[23:8];
          t0_r   <= table_mem[u_w[31:24]];
          st     <= ST_RD1;
        end

        ST_RD1: begin
          // ultima entrada: no hay T[256] -> repetir T[255] (curva ya plana)
          if (idx_r == 8'd255) t1_r <= t0_r;
          else                 t1_r <= table_mem[idx_r + 8'd1];
          st <= ST_MUL;
        end

        ST_MUL: begin
          logic signed [31:0] delta;
          logic signed [48:0] p;
          delta  = sat_sub32(t1_r, t0_r);
          p      = $signed(delta) * $signed({1'b0, frac_r});
          term_r <= p[47:16];              // >> 16
          st     <= ST_ADD;
        end

        ST_ADD: begin
          out_buf       <= sat_add32(t0_r, term_r);
          out_buf_valid <= 1'b1;
          st            <= ST_IDLE;
        end

        default: st <= ST_IDLE;
      endcase
    end
  end
endmodule