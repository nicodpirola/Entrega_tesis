// =============================================================================
// fx_distortion.sv - Distorsion premium con oversampling y wavetable.
//
//   Cadena interna (OS_FACTOR=4):
//     in -> up2x(48->96) -> up2x(96->192) -> waveshaper -> down2x(192->96)
//        -> down2x(96->48) -> level -> mix dry/wet -> out
//
//   OS_FACTOR = 2 o 4 (parametro). Con 2, una sola etapa por lado.
//
//   Parametros runtime (registros):
//     drive_16_16 : Q16.16, ganancia previa a la tabla (empuja a la zona no lineal)
//     level_q1_31 : Q1.31, volumen de salida del wet (compensa la ganancia de la dist.)
//     mix_q1_31   : Q1.31, 0=dry ... 1.0=full wet
//     wt_wr_*     : puerto de escritura de la wavetable (cambiar la curva en runtime)
//
//   enable=0 -> bypass transparente (mismo patron que los otros efectos).
//   Al habilitar (rise) se limpian las lineas de retardo de los FIR.
//
//   Presupuesto de ciclos por muestra de audio (OS_FACTOR=4, MAC serial):
//     up1: 2x(32+4)  up2: 4x(16+4)  shaper: 4x6  down2: 4x(16+4)  down1: 2x(32+4)
//     ~ 350 ciclos de ~1000 disponibles a 50MHz/48kHz -> holgado.
// =============================================================================
module fx_distortion #(
  parameter int OS_FACTOR = 4,  // 2 o 4
  // Alineacion de escala: el stream I2S trae el audio en menos bits que el
  // "1.0" del waveshaper (2^29). IN_SHIFT sube la senal a escala plena al
  // entrar a la cadena y la baja al salir. 6 = audio en bits [23:0] (fs 2^23);
  // 2 = formato AES [27:4] (fs 2^27); 0 = audio ya en Q3.29 pleno.
  parameter int IN_SHIFT  = 6
)(
  input  logic               clk,
  input  logic               rst_n,
  input  logic               enable,

  input  logic               in_valid,
  output logic               in_ready,
  input  logic signed [31:0] in_data,

  output logic               out_valid,
  input  logic               out_ready,
  output logic signed [31:0] out_data,

  // Parametros
  input  logic [31:0]        drive_16_16,
  input  logic signed [31:0] level_q1_31,
  input  logic signed [31:0] mix_q1_31,

  // Escritura de wavetable
  input  logic               wt_wr_en,
  input  logic [7:0]         wt_wr_addr,
  input  logic [31:0]        wt_wr_data
);
  import fx_dsp_pkg::*;

  // ---- Coeficientes (generados con diseno_fir_oversampling / firwin) ----
  // Etapa 1: 32 taps, corte 20k @ fs=96k.  INTERP con ganancia x2.
  localparam logic [32*32-1:0] DECIM1 = 1024'h00354DD6_00086271_FFAC64E7_FFAD96B2_007B0217_010FEBC0_FFC99448_FDC48633_FED499D9_03412835_045BC976_FD283680_F5C0B0A1_FDFF9225_18888C35_316CBACE_316CBACE_18888C35_FDFF9225_F5C0B0A1_FD283680_045BC976_03412835_FED499D9_FDC48633_FFC99448_010FEBC0_007B0217_FFAD96B2_FFAC64E7_00086271_00354DD6;
  localparam logic [32*32-1:0] INTERP1 = 1024'h006A9BAC_0010C4E3_FF58C9CF_FF5B2D65_00F6042D_021FD77F_FF932891_FB890C66_FDA933B3_0682506A_08B792EC_FA506CFF_EB816141_FBFF244A_3111186B_62D9759D_62D9759D_3111186B_FBFF244A_EB816141_FA506CFF_08B792EC_0682506A_FDA933B3_FB890C66_FF932891_021FD77F_00F6042D_FF5B2D65_FF58C9CF_0010C4E3_006A9BAC;
  // Etapa 2: 16 taps, corte 24k @ fs=192k. INTERP con ganancia x2.
  localparam logic [32*16-1:0] DECIM2 = 512'hFFD5855D_FF4ED859_FE6A191A_FE9FE8A0_029D23BB_0B913B74_16D67F2F_1ECCC232_1ECCC232_16D67F2F_0B913B74_029D23BB_FE9FE8A0_FE6A191A_FF4ED859_FFD5855D;
  localparam logic [32*16-1:0] INTERP2 = 512'hFFAB0ABA_FE9DB0B2_FCD43234_FD3FD141_053A4776_172276E8_2DACFE5D_3D998463_3D998463_2DACFE5D_172276E8_053A4776_FD3FD141_FCD43234_FE9DB0B2_FFAB0ABA;

  // Interpoladores en forma POLYPHASE (mitad de MACs, validado bit-exact
  // contra zero-stuff en tb_poly.sv). FASE_A = coefs pares, FASE_B = impares.
  localparam logic [32*16-1:0] IN1_FA = 512'h0010C4E3_FF5B2D65_021FD77F_FB890C66_0682506A_FA506CFF_FBFF244A_62D9759D_3111186B_EB816141_08B792EC_FDA933B3_FF932891_00F6042D_FF58C9CF_006A9BAC;
  localparam logic [32*16-1:0] IN1_FB = 512'h006A9BAC_FF58C9CF_00F6042D_FF932891_FDA933B3_08B792EC_EB816141_3111186B_62D9759D_FBFF244A_FA506CFF_0682506A_FB890C66_021FD77F_FF5B2D65_0010C4E3;
  localparam logic [32*8-1:0]  IN2_FA = 256'hFE9DB0B2_FD3FD141_172276E8_3D998463_2DACFE5D_053A4776_FCD43234_FFAB0ABA;
  localparam logic [32*8-1:0]  IN2_FB = 256'hFFAB0ABA_FCD43234_053A4776_2DACFE5D_3D998463_172276E8_FD3FD141_FE9DB0B2;


  // ---- Clear de estado al habilitar (rise) ----
  logic enable_d;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) enable_d <= 1'b0;
    else        enable_d <= enable;
  end
  logic state_clear;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) state_clear <= 1'b0;
    else        state_clear <= enable && !enable_d;
  end

  // ---- Entrada a la cadena interna (solo cuando enable) ----
  logic               c_in_valid, c_in_ready;
  logic signed [31:0] c_in_data;

  // ---- Cables de la cadena ----
  logic u1_v, u1_r; logic signed [31:0] u1_d;   // up1 -> (up2 | shaper)
  logic sh_iv, sh_ir; logic signed [31:0] sh_id; // entrada al shaper
  logic sh_ov, sh_or; logic signed [31:0] sh_od; // salida del shaper
  logic d2_ov, d2_or; logic signed [31:0] d2_od; // (down2) -> down1
  logic w_v, w_r; logic signed [31:0] w_d;       // salida wet de la cadena

  os_up2x_poly #(.NHALF(16), .FASE_A(IN1_FA), .FASE_B(IN1_FB)) u_up1 (
    .clk(clk), .rst_n(rst_n), .state_clear(state_clear),
    .in_valid(c_in_valid), .in_ready(c_in_ready), .in_data(c_in_data),
    .out_valid(u1_v), .out_ready(u1_r), .out_data(u1_d)
  );

  generate
    if (OS_FACTOR == 4) begin : g_os4
      logic u2_v, u2_r; logic signed [31:0] u2_d;
      os_up2x_poly #(.NHALF(8), .FASE_A(IN2_FA), .FASE_B(IN2_FB)) u_up2 (
        .clk(clk), .rst_n(rst_n), .state_clear(state_clear),
        .in_valid(u1_v), .in_ready(u1_r), .in_data(u1_d),
        .out_valid(u2_v), .out_ready(u2_r), .out_data(u2_d)
      );
      assign sh_iv = u2_v;  assign u2_r = sh_ir;  assign sh_id = u2_d;

      os_down2x #(.N(16), .COEFS(DECIM2)) u_down2 (
        .clk(clk), .rst_n(rst_n), .state_clear(state_clear),
        .in_valid(sh_ov), .in_ready(sh_or), .in_data(sh_od),
        .out_valid(d2_ov), .out_ready(d2_or), .out_data(d2_od)
      );
    end else begin : g_os2
      assign sh_iv = u1_v;  assign u1_r = sh_ir;  assign sh_id = u1_d;
      assign d2_ov = sh_ov; assign sh_or = d2_or; assign d2_od = sh_od;
    end
  endgenerate

  fx_waveshaper u_shaper (
    .clk(clk), .rst_n(rst_n),
    .in_valid(sh_iv), .in_ready(sh_ir), .in_data(sh_id),
    .out_valid(sh_ov), .out_ready(sh_or), .out_data(sh_od),
    .drive_16_16(drive_16_16),
    .wt_wr_en(wt_wr_en), .wt_wr_addr(wt_wr_addr), .wt_wr_data(wt_wr_data)
  );

  os_down2x #(.N(32), .COEFS(DECIM1)) u_down1 (
    .clk(clk), .rst_n(rst_n), .state_clear(state_clear),
    .in_valid(d2_ov), .in_ready(d2_or), .in_data(d2_od),
    .out_valid(w_v), .out_ready(w_r), .out_data(w_d)
  );

  // ===========================================================================
  //  FSM top: bypass / captura dry / mezcla level+mix
  // ===========================================================================
  typedef enum logic [2:0] {
    ST_IDLE   = 3'd0,
    ST_FEED   = 3'd1,  // empujar la muestra a la cadena
    ST_WAIT_W = 3'd2,  // esperar el wet procesado
    ST_LEVEL  = 3'd3,  // wet * level          (mul)
    ST_MIXMUL = 3'd4,  // (wet_lvl - dry)*mix  (mul)
    ST_MIXADD = 3'd5   // out = dry + term
  } state_t;
  state_t st;

  logic signed [31:0] dry_r, wet_r, wl_r, mixterm_r;

  logic               out_buf_valid;
  logic signed [31:0] out_buf;
  assign out_valid = out_buf_valid;
  assign out_data  = out_buf;
  wire out_fire = out_valid && out_ready;
  wire in_fire  = in_valid && in_ready;

  wire bypass_mode = !enable;
  assign in_ready = (st == ST_IDLE) && !out_buf_valid &&
                    (bypass_mode || c_in_ready);

  assign c_in_valid = (!bypass_mode) && (st == ST_IDLE) && in_fire;
  assign c_in_data  = sat32(64'(in_data) <<< IN_SHIFT);   // subir a escala plena
  assign w_r        = (st == ST_WAIT_W);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st <= ST_IDLE; dry_r <= '0; wet_r <= '0; wl_r <= '0; mixterm_r <= '0;
      out_buf_valid <= 1'b0; out_buf <= '0;
    end else begin
      if (out_fire) out_buf_valid <= 1'b0;

      if (bypass_mode) begin
        st <= ST_IDLE;
        if (in_fire) begin
          out_buf       <= in_data;
          out_buf_valid <= 1'b1;
        end
      end else begin
        case (st)
          ST_IDLE: if (in_fire) begin
            dry_r <= in_data;      // la muestra ya entro a la cadena (c_in_valid)
            st    <= ST_WAIT_W;
          end

          ST_WAIT_W: if (w_v && w_r) begin
            wet_r <= w_d >>> IN_SHIFT;   // volver a la escala del DAC
            st    <= ST_LEVEL;
          end

          ST_LEVEL: begin
            wl_r <= mul_aud_q31(wet_r, level_q1_31);
            st   <= ST_MIXMUL;
          end

          ST_MIXMUL: begin
            mixterm_r <= mul_aud_q31(sat_sub32(wl_r, dry_r), mix_q1_31);
            st        <= ST_MIXADD;
          end

          ST_MIXADD: begin
            out_buf       <= sat_add32(dry_r, mixterm_r);
            out_buf_valid <= 1'b1;
            st            <= ST_IDLE;
          end

          default: st <= ST_IDLE;
        endcase
      end
    end
  end
endmodule