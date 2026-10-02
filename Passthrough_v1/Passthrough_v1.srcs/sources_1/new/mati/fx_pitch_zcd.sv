// =============================================================================
// fx_pitch_zcd.sv - DETECTOR DE PITCH por cruces por cero (theremin)
//
// Rama de analisis (observador). Correcciones de dos rondas de revision:
//   - samp_cnt es un CONTADOR LIBRE: cuenta TODAS las muestras del stream,
//     no solo las vistas en ST_IDLE (si no, se pierden ~4 muestras/periodo
//     mientras la FSM procesa un cruce -> error que crece con la frecuencia).
//   - registra la muestra al aceptarla (x_cur_r)
//   - histeresis en el cruce (arma bajo -H)
//   - denominador sin resta signed: |x_prev| + x_cur
//   - posicion del cruce = (idx - 1) + frac
//   - valida rango ANTES de actualizar last_cross (un cruce espurio no
//     se vuelve la referencia del siguiente periodo)
//   - mediana emite recien con 3 periodos
//   - al caer el gate limpia todo Y cancela el divisor (clear)
//   - SIN freq_dbg con division variable (eso se calcula afuera)
// =============================================================================
module fx_pitch_zcd #(
  parameter logic [31:0] PERIOD_MIN_Q16 = 32'd8    << 16,
  parameter logic [31:0] PERIOD_MAX_Q16 = 32'd1200 << 16
)(
  input  logic               clk,
  input  logic               rst_n,

  input  logic               sample_valid,
  input  logic signed [31:0] sample_data,
  input  logic               gate,
  input  logic signed [31:0] zc_hyst_q3_29,

  output logic [31:0]        period_16_16,
  output logic               period_valid
);
  import fx_dsp_pkg::*;

  // ---- CONTADOR LIBRE de muestras (corre con cada sample_valid, sin importar FSM) ----
  logic [31:0] samp_cnt;
  always_ff @(posedge clk) begin
    if (!rst_n)            samp_cnt <= '0;
    else if (sample_valid) samp_cnt <= samp_cnt + 1'b1;
  end

  logic signed [31:0] x_prev;
  logic signed [31:0] x_cur_r;
  logic [31:0]        idx_r;       // indice de la muestra actual (del contador libre)
  logic               zc_armed;

  logic [31:0] last_cross_16_16;
  logic        have_last;
  logic [31:0] p0, p1, p2;
  logic [1:0]  p_fill;

  logic        div_start, div_done;
  logic [31:0] div_num, div_den;
  logic [15:0] div_q;
  div_frac16 u_div (
    .clk(clk), .rst_n(rst_n), .clear(!gate),
    .start(div_start), .num(div_num), .den(div_den),
    .busy(), .done(div_done), .quot(div_q)
  );

  typedef enum logic [2:0] {
    ST_IDLE=3'd0, ST_CHECK=3'd1, ST_DIV=3'd2, ST_PERIOD=3'd3,
    ST_MEDIAN=3'd4, ST_EMIT=3'd5
  } state_t;
  state_t st;

  logic [31:0] cross_now_16_16;
  logic [31:0] period_raw;

  function automatic logic [31:0] median3(input logic [31:0] a,b,c);
    if ((a<=b && b<=c)||(c<=b && b<=a)) median3=b;
    else if ((b<=a && a<=c)||(c<=a && a<=b)) median3=a;
    else median3=c;
  endfunction

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      st<=ST_IDLE; x_prev<='0; x_cur_r<='0; idx_r<='0; zc_armed<=1'b0;
      last_cross_16_16<='0; have_last<=1'b0;
      p0<='0; p1<='0; p2<='0; p_fill<='0;
      div_start<=1'b0; div_num<='0; div_den<='0;
      cross_now_16_16<='0; period_raw<='0;
      period_16_16<='0; period_valid<=1'b0;
    end else if (!gate) begin
      st<=ST_IDLE; x_prev<='0; zc_armed<=1'b0;
      have_last<=1'b0; p_fill<='0; p0<='0; p1<='0; p2<='0;
      period_valid<=1'b0; div_start<=1'b0;
    end else begin
      period_valid <= 1'b0;
      div_start    <= 1'b0;

      case (st)
        ST_IDLE: if (sample_valid) begin
          x_cur_r <= sample_data;
          idx_r   <= samp_cnt;          // snapshot del contador libre
          st      <= ST_CHECK;
        end

        ST_CHECK: begin
          if (x_cur_r <= -zc_hyst_q3_29) zc_armed <= 1'b1;
          if (zc_armed && (x_prev < 0) && (x_cur_r >= 0)) begin
            zc_armed  <= 1'b0;
            div_num   <= abs32(x_prev);
            div_den   <= abs32(x_prev) + $unsigned(x_cur_r);
            div_start <= 1'b1;
            st        <= ST_DIV;
          end else begin
            x_prev <= x_cur_r;
            st     <= ST_IDLE;
          end
        end

        ST_DIV: if (div_done) begin
          // posicion = (idx - 1) + frac
          cross_now_16_16 <= {idx_r[15:0] - 16'd1, div_q};
          st <= ST_PERIOD;
        end

        ST_PERIOD: begin
          logic [31:0] candidate;
          x_prev <= x_cur_r;
          if (!have_last) begin
            last_cross_16_16 <= cross_now_16_16;
            have_last <= 1'b1;
            st <= ST_IDLE;
          end else begin
            candidate = cross_now_16_16 - last_cross_16_16;
            if (candidate < PERIOD_MIN_Q16) begin
              // cruce demasiado cercano: espurio, NO cambiar la referencia
              st <= ST_IDLE;
            end else if (candidate > PERIOD_MAX_Q16) begin
              // perdimos seguimiento: reiniciar referencia y ventana
              last_cross_16_16 <= cross_now_16_16;
              p_fill<='0; p0<='0; p1<='0; p2<='0;
              st <= ST_IDLE;
            end else begin
              period_raw       <= candidate;
              last_cross_16_16 <= cross_now_16_16;
              st <= ST_MEDIAN;
            end
          end
        end

        ST_MEDIAN: begin
          p2<=p1; p1<=p0; p0<=period_raw;
          if (p_fill < 2'd3) p_fill <= p_fill + 1'b1;
          st <= ST_EMIT;
        end

        ST_EMIT: begin
          if (p_fill == 2'd3) begin
            period_16_16 <= median3(p0, p1, p2);
            period_valid <= 1'b1;
          end
          st <= ST_IDLE;
        end

        default: st <= ST_IDLE;
      endcase
    end
  end
endmodule


// divisor serial sin signo con clear sincrono
module div_frac16 (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        clear,
  input  logic        start,
  input  logic [31:0] num,
  input  logic [31:0] den,
  output logic        busy,
  output logic        done,
  output logic [15:0] quot
);
  logic [31:0] rem, d;
  logic [15:0] q;
  logic [4:0]  cnt;
  logic        run;
  assign busy = run;

  always_ff @(posedge clk) begin
    if (!rst_n || clear) begin
      run<=1'b0; done<=1'b0; quot<='0; rem<='0; d<='0; q<='0; cnt<='0;
    end else begin
      done <= 1'b0;
      if (start && !run) begin
        rem<=num; d<=den; q<='0; cnt<=5'd16; run<=1'b1;
      end else if (run) begin
        logic [32:0] rem_sh;
        rem_sh = {rem, 1'b0};
        if (rem_sh >= {1'b0, d}) begin
          rem <= rem_sh - {1'b0, d};
          q   <= {q[14:0], 1'b1};
        end else begin
          rem <= rem_sh[31:0];
          q   <= {q[14:0], 1'b0};
        end
        cnt <= cnt - 1'b1;
        if (cnt == 5'd1) begin
          run<=1'b0; done<=1'b1;
          quot <= (rem_sh >= {1'b0,d}) ? {q[14:0],1'b1} : {q[14:0],1'b0};
        end
      end
    end
  end
endmodule