`timescale 1ns/1ps

// =============================================================================
// fx_pitch_post.sv
//
// Post-procesado del pitch, entre fx_pitch_yin48 y el conversor de periodo.
// Especificacion bit-exacta: Pitch_YIN48/modelo/post_fixed.py
//
// Todo se configura por registro: el PS carga un perfil (guitarra / theremin).
//
//  - Detector de ataque (cada 1 ms): pk = maximo de la envolvente en los
//    ultimos 8 ms (saca el rizado de las cuerdas graves: Mi2/La2 tienen un
//    pico cada ~6 ms); ataque si pk > ONK/8 * minimo de pk en los 20 ms
//    anteriores, o apertura del gate. En cada ataque se olvida la nota y
//    (si EN_RETRIG) se pide re-ataque del VCA.
//  - ESPERA: despues de un ataque se ignoran las estimaciones ESPERA ms
//    (la ventana de YIN todavia tiene la nota anterior).
//  - Confianza: d' = CL/CR (de YIN). Con nota madura, si 128 CL > CONF*CR
//    se mantiene la nota; sin nota, si 128 CL > CONF0*CR se ignora.
//  - Memoria de nota (nota madura = estable hace >= MEM_MS): octava de
//    arriba o subarmonico (x2, x3, x4) de la nota -> se corrige.
//  - Estabilidad: un salto > ~80 cents necesita K estimaciones seguidas
//    coincidentes (K0 para el primer enganche despues de un ataque).
//
// Comparaciones en cents sin logaritmos: cerca(a, b, M) <=> M*|a-b| < b
//   M = 21 (+-82 c), 29 (+-60 c), 57 (+-30 c). Productos por constantes con
//   sumas y desplazamientos: no usa DSP.
//
// Una estimacion llega cada 16 muestras (~16700 ciclos): la logica es una
// FSM de pocos estados, sin apuro de tiempo.
// =============================================================================

module fx_pitch_post (
    input  logic               clk,
    input  logic               rst_n,

    // configuracion (perfil)
    input  logic               en_oct,
    input  logic               en_sub,
    input  logic [7:0]         mem_ms,
    input  logic [3:0]         conf_num,        // 0 = sin confianza
    input  logic [3:0]         conf0_num,       // 0 = sin umbral de enganche
    input  logic               en_retrig,
    input  logic [4:0]         espera_ms,
    input  logic [5:0]         k_salto,
    input  logic [5:0]         k0_salto,
    input  logic [3:0]         onk,             // ataque si env > onk/8 * minimo

    // por muestra (48 kHz)
    input  logic               sample_valid,
    input  logic signed [31:0] env_q3_29,
    input  logic               gate,
    input  logic signed [31:0] gate_on_thr_q3_29,

    // estimaciones de YIN
    input  logic               in_valid,
    input  logic [31:0]        in_period_16_16,
    input  logic [33:0]        in_cl,
    input  logic [51:0]        in_cr,

    // salida hacia el conversor
    output logic               out_valid,
    output logic [31:0]        out_period_16_16,
    output logic               ataque,          // pulso: hubo ataque en esta muestra
    output logic               retrig           // ataque && en_retrig (re-ataque del VCA)
);

// =============================================================================
// BASE DE TIEMPO, GATE Y ENVOLVENTE POR MUESTRA
// =============================================================================

logic [5:0]          tick_cnt;            // n mod 48
logic                gate_prev;
logic signed [31:0]  hist [20];          // pk de los ultimos 20 ms
logic signed [31:0]  raw  [8];           // env de los ultimos 8 ms (raw[7] = el mas nuevo)
logic signed [31:0]  m7;                 // max(raw[1..7]): para el pk del proximo tick
logic [4:0]          hist_n;              // cuantas posiciones validas (satura en 20)
logic [5:0]          refr;                // ms de refractario
logic signed [31:0]  hmin;                // minimo del historial (se calcula despues de cada tick)
logic [4:0]          scan_i;
logic                scan_run;
logic [15:0]         since_on;            // muestras desde el ultimo ataque (satura)
logic [15:0]         since_out;           // muestras desde el ultimo salto aceptado (satura)
logic                pend;                // hubo ataque desde la ultima estimacion
logic                gate_s;              // gate de la muestra actual
logic                est_clr_pend, est_t_out;

function automatic logic [35:0] mul_onk(input logic [3:0] k, input logic signed [31:0] m);
    logic [35:0] a;
    a = 36'($unsigned(m));
    mul_onk = (k[0] ? a : 36'd0) + (k[1] ? a << 1 : 36'd0) + (k[2] ? a << 2 : 36'd0) + (k[3] ? a << 3 : 36'd0);
endfunction

always_ff @(posedge clk) begin : base
    logic       tick, on_gate, on_env;
    logic [5:0] rv;
    logic signed [31:0] pk;
    if (!rst_n) begin
        tick_cnt <= '0; gate_prev <= 1'b0; hist_n <= '0; refr <= '0; hmin <= '0;
        scan_i <= '0; scan_run <= 1'b0; since_on <= 16'hFFFF; since_out <= 16'hFFFF;
        pend <= 1'b0; gate_s <= 1'b0; ataque <= 1'b0; retrig <= 1'b0;
        for (int i = 0; i < 20; i++) hist[i] <= '0;
        for (int i = 0; i < 8; i++)  raw[i]  <= '0;
        m7 <= '0;
    end else begin
        ataque <= 1'b0;
        retrig <= 1'b0;
        // despues de cada tick: minimo del historial nuevo (arranca con hist[19] = pk del tick y
        // recorre hist[0..18]) y maximo de los 7 env mas nuevos (arranca con raw[7], recorre raw[1..6])
        if (scan_run) begin
            if (hist[scan_i] < hmin) hmin <= hist[scan_i];
            if (scan_i >= 5'd1 && scan_i <= 5'd6 && raw[scan_i[2:0]] > m7) m7 <= raw[scan_i[2:0]];
            if (scan_i == 5'd18) scan_run <= 1'b0;
            scan_i <= scan_i + 5'd1;
        end
        if (sample_valid) begin
            tick      = (tick_cnt == 6'd47);
            tick_cnt  <= tick ? 6'd0 : tick_cnt + 6'd1;
            gate_s    <= gate;
            gate_prev <= gate;
            on_gate   = gate && !gate_prev;
            on_env    = 1'b0;
            rv        = on_gate ? 6'd50 : refr;
            pk        = (env_q3_29 > m7) ? env_q3_29 : m7;     // max de los ultimos 8 ms
            if (tick) begin
                if (gate && hist_n == 5'd20 && rv == 6'd0 && env_q3_29 > gate_on_thr_q3_29 &&
                    ({4'b0000, $unsigned(pk)} << 3) > mul_onk(onk, hmin)) begin
                    on_env = 1'b1;
                    rv     = 6'd50;
                end else if (rv != 6'd0) begin
                    rv = rv - 6'd1;
                end
                for (int i = 0; i < 19; i++) hist[i] <= hist[i+1];
                hist[19] <= pk;
                for (int i = 0; i < 7; i++) raw[i] <= raw[i+1];
                raw[7]   <= env_q3_29;
                if (hist_n != 5'd20) hist_n <= hist_n + 5'd1;
                hmin     <= pk;
                m7       <= env_q3_29;
                scan_i   <= 5'd0;
                scan_run <= 1'b1;
            end
            refr      <= rv;
            since_out <= (since_out == 16'hFFFF) ? since_out : since_out + 16'd1;
            if (on_gate || on_env) begin
                ataque   <= 1'b1;
                retrig   <= en_retrig;
                pend     <= 1'b1;
                since_on <= 16'd0;
            end else begin
                since_on <= (since_on == 16'hFFFF) ? since_on : since_on + 16'd1;
            end
        end
        if (est_clr_pend) pend <= 1'b0;
        if (est_t_out)    since_out <= 16'd0;
    end
end

// =============================================================================
// PROCESAMIENTO DE CADA ESTIMACION (FSM)
// =============================================================================

typedef enum logic [2:0] { E_IDLE, E_GATE, E_CONF, E_MEM1, E_MEM2, E_STEP, E_EMIT } estate_t;

estate_t      es;
logic [31:0]  p, out_p, cand;
logic         have_out, have_cand;
logic [5:0]   cnt;
logic [33:0]  cl_r;
logic [51:0]  cr_r;
logic [31:0]  p3;                       // p / 3

function automatic logic cerca(input logic [31:0] a, input logic [31:0] b, input logic [5:0] m);
    logic [31:0] d;
    logic [37:0] md;
    d  = (a > b) ? a - b : b - a;
    md = (m[0] ? 38'(d) : 38'd0) + (m[1] ? 38'(d) << 1 : 38'd0) + (m[2] ? 38'(d) << 2 : 38'd0) +
         (m[3] ? 38'(d) << 3 : 38'd0) + (m[4] ? 38'(d) << 4 : 38'd0) + (m[5] ? 38'(d) << 5 : 38'd0);
    cerca = md < 38'(b);
endfunction

function automatic logic [56:0] mul4(input logic [3:0] k, input logic [51:0] x);
    logic [56:0] a;
    a = 57'(x);
    mul4 = (k[0] ? a : 57'd0) + (k[1] ? a << 1 : 57'd0) + (k[2] ? a << 2 : 57'd0) + (k[3] ? a << 3 : 57'd0);
endfunction

// ms -> muestras: m * 48 = (m << 5) + (m << 4)
function automatic logic [15:0] ms48(input logic [7:0] m);
    ms48 = (16'(m) << 5) + (16'(m) << 4);
endfunction

logic madura;
assign madura = have_out && (since_out >= ms48(mem_ms));

always_ff @(posedge clk) begin : est
    logic [47:0] pm;
    if (!rst_n) begin
        es <= E_IDLE; p <= '0; out_p <= '0; cand <= '0; have_out <= 1'b0; have_cand <= 1'b0;
        cnt <= '0; cl_r <= '0; cr_r <= '0; est_clr_pend <= 1'b0; est_t_out <= 1'b0;
        out_valid <= 1'b0; out_period_16_16 <= '0; p3 <= '0;
    end else begin
        est_clr_pend <= 1'b0;
        est_t_out    <= 1'b0;
        out_valid    <= 1'b0;
        case (es)
            E_IDLE: if (in_valid) begin
                p    <= in_period_16_16;
                cl_r <= in_cl;
                cr_r <= in_cr;
                if (pend) begin                       // ataque desde la estimacion anterior
                    have_out     <= 1'b0;
                    have_cand    <= 1'b0;
                    cnt          <= '0;
                    est_clr_pend <= 1'b1;
                end
                es <= E_GATE;
            end
            E_GATE: begin
                if (!gate_s || since_on < ms48(8'(espera_ms))) es <= E_IDLE;
                else                                              es <= E_CONF;
            end
            E_CONF: begin
                if (conf_num != 4'd0 && madura && (57'(cl_r) << 7) > mul4(conf_num, cr_r)) begin
                    out_valid        <= 1'b1;            // se mantiene la nota
                    out_period_16_16 <= out_p;
                    es               <= E_IDLE;
                end else if (conf0_num != 4'd0 && !have_out && (57'(cl_r) << 7) > mul4(conf0_num, cr_r)) begin
                    es <= E_IDLE;
                end else begin
                    es <= E_MEM1;
                end
            end
            E_MEM1: begin                              // p * 21845 (p/3) en un ciclo propio
                pm = '0;                               // 21845 = 0x5555: suma de p << 0, 2, ..., 14 (sin DSP)
                for (int b = 0; b < 16; b += 2) pm = pm + (48'(p) << b);
                p3 <= pm[47:16];
                es <= E_MEM2;
            end
            E_MEM2: begin
                if (madura) begin
                    if (en_oct && cerca(p << 1, out_p, 6'd29))                    p <= p << 1;
                    else if (en_sub && cerca(p, out_p << 1, 6'd29))               p <= p >> 1;
                    else if (en_sub && cerca(p, (out_p << 1) + out_p, 6'd29))     p <= p3;
                    else if (en_sub && cerca(p, out_p << 2, 6'd29))               p <= p >> 2;
                end
                es <= E_STEP;
            end
            E_STEP: begin
                if (have_out && cerca(p, out_p, 6'd21)) begin
                    out_p     <= p;
                    have_cand <= 1'b0;
                    cnt       <= '0;
                end else begin : salto
                    logic [5:0] c;
                    c = (have_cand && cerca(p, cand, 6'd57)) ? ((cnt == 6'd63) ? cnt : cnt + 6'd1) : 6'd1;
                    cand      <= p;
                    have_cand <= 1'b1;
                    cnt       <= c;
                    if (c >= (have_out ? k_salto : k0_salto)) begin
                        out_p     <= p;
                        have_out  <= 1'b1;
                        have_cand <= 1'b0;
                        cnt       <= '0;
                        est_t_out <= 1'b1;
                    end
                end
                es <= E_EMIT;
            end
            E_EMIT: begin
                if (have_out) begin
                    out_valid        <= 1'b1;
                    out_period_16_16 <= out_p;
                end
                es <= E_IDLE;
            end
            default: es <= E_IDLE;
        endcase
    end
end

endmodule
