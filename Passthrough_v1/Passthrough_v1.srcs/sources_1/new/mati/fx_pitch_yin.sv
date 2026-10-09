`timescale 1ns/1ps

// =============================================================================
// fx_pitch_yin.sv
//
// Detector de periodo YIN (de Cheveigne & Kawahara, JASA 2002) reformulado
// para hardware. Reemplazo directo de fx_pitch_zcd: mismos puertos, misma
// salida (periodo en muestras de 48 kHz, Q16.16, con un pulso period_valid).
//
// Especificacion bit-exacta: Pitch_YIN/modelo/yin_fixed.py
// Desarrollo matematico:     Pitch_YIN/YIN_desarrollo.md
//
//   sample_data (Q3.29, 48 kHz, ya pasado por el LPF de pitch)
//     -> x18 = sat18(x >>> 13)
//     -> FIR antialias 48 taps a 48 kHz (1 DSP)          -> y16 (Q1.15)
//          y16 -> anillo Y48 (512)   (para el refinamiento fino)
//          1 de cada 4 -> nucleo YIN (12 kHz)
//     -> nucleo (1 DSP compartido, FSM):
//          PASS : actualizacion incremental de d(tau), tau = 1..200,
//                 umbral sin division y busqueda del minimo (6 ciclos/tau)
//          DIV1 : interpolacion parabolica (unica division, 15 ciclos)
//          REF  : si periodo <= 128 muestras: d48(L) directo para 5 retardos
//                 alrededor del grueso, a 48 kHz (5 ciclos por muestra)
//          DIV2 : interpolacion parabolica fina
//          OCT  : chequeo de octava (si hubo refinamiento): pozos en P y 2P a
//                 48 kHz con ventana 128 -> si 2P es mucho mas profundo y P no
//                 es limpio, el periodo es 2P (corrige el salto de octava hacia
//                 arriba cuando la fundamental se apaga, p. ej. puntos muertos)
//          EMIT : period_16_16, period_valid (solo con gate = 1)
//
// Presupuesto: una muestra diezmada cada 4 x 1041 = 4164 ciclos (50 MHz).
// Peor caso del nucleo: 6*200 + 15 + 1290 + 15 + 7*128 + ~70 = ~3500 ciclos.
//
// Recursos esperados: 2 DSP48E1, sin BRAM (memorias distribuidas:
// xd 512x16, Y48 512x16, d 256x41, anillo FIR 64x18).
//
// Reset: al salir de reset se ponen a cero todas las memorias (512 ciclos).
// Es necesario: la suma incremental d(tau) solo es exacta si d(tau) y el
// buffer de muestras arrancan coherentes (todo en cero).
// =============================================================================

module fx_pitch_yin #(
    parameter int THETA_NUM = 19,     // umbral theta = THETA_NUM / 128
    parameter int TAU_MIN   = 5,      // 12000 / 5   = 2400 Hz
    parameter int TAU_MAX   = 200,    // 12000 / 200 = 60 Hz
    parameter int REF_PMAX  = 128,    // refinar si periodo <= 128 muestras (>= 375 Hz)
    parameter bit OCT_CHECK    = 1'b1, // chequeo de octava a 48 kHz despues del refinamiento
    parameter int OCT_EPS_SH   = 9,    // P "no limpio" si  v(P) << 9 >= E     (eps = 2^-10)
    parameter int OCT_ALPHA_SH = 2     // 2P mas profundo si v(2P) << 2 < v(P)  (alfa = 1/4)
)(
    input  logic               clk,
    input  logic               rst_n,

    input  logic               sample_valid,
    input  logic signed [31:0] sample_data,

    input  logic               gate,
    input  logic signed [31:0] zc_hyst_q3_29,   // sin uso (compatibilidad con fx_pitch_zcd)

    output logic [31:0]        period_16_16,
    output logic               period_valid
);

// =============================================================================
// FUNCIONES
// =============================================================================

function automatic logic signed [17:0] fir_coef(input logic [5:0] k);
    case (k)
        6'd0 : fir_coef = -18'sd32;
        6'd1 : fir_coef =  18'sd295;
        6'd2 : fir_coef =  18'sd434;
        6'd3 : fir_coef =  18'sd656;
        6'd4 : fir_coef =  18'sd864;
        6'd5 : fir_coef =  18'sd990;
        6'd6 : fir_coef =  18'sd967;
        6'd7 : fir_coef =  18'sd740;
        6'd8 : fir_coef =  18'sd283;
        6'd9 : fir_coef = -18'sd384;
        6'd10: fir_coef = -18'sd1187;
        6'd11: fir_coef = -18'sd1996;
        6'd12: fir_coef = -18'sd2636;
        6'd13: fir_coef = -18'sd2915;
        6'd14: fir_coef = -18'sd2651;
        6'd15: fir_coef = -18'sd1708;
        6'd16: fir_coef = -18'sd32;
        6'd17: fir_coef =  18'sd2331;
        6'd18: fir_coef =  18'sd5225;
        6'd19: fir_coef =  18'sd8399;
        6'd20: fir_coef =  18'sd11532;
        6'd21: fir_coef =  18'sd14277;
        6'd22: fir_coef =  18'sd16316;
        6'd23: fir_coef =  18'sd17402;
        6'd24: fir_coef =  18'sd17402;
        6'd25: fir_coef =  18'sd16316;
        6'd26: fir_coef =  18'sd14277;
        6'd27: fir_coef =  18'sd11532;
        6'd28: fir_coef =  18'sd8399;
        6'd29: fir_coef =  18'sd5225;
        6'd30: fir_coef =  18'sd2331;
        6'd31: fir_coef = -18'sd32;
        6'd32: fir_coef = -18'sd1708;
        6'd33: fir_coef = -18'sd2651;
        6'd34: fir_coef = -18'sd2915;
        6'd35: fir_coef = -18'sd2636;
        6'd36: fir_coef = -18'sd1996;
        6'd37: fir_coef = -18'sd1187;
        6'd38: fir_coef = -18'sd384;
        6'd39: fir_coef =  18'sd283;
        6'd40: fir_coef =  18'sd740;
        6'd41: fir_coef =  18'sd967;
        6'd42: fir_coef =  18'sd990;
        6'd43: fir_coef =  18'sd864;
        6'd44: fir_coef =  18'sd656;
        6'd45: fir_coef =  18'sd434;
        6'd46: fir_coef =  18'sd295;
        6'd47: fir_coef = -18'sd32;
        default: fir_coef = 18'sd0;
    endcase
endfunction

// W(tau) = clip(2^ceil(log2(2 tau)), 32, 256)  y  s(tau) = 8 - log2 W(tau)
function automatic logic [8:0] w_of_tau(input logic [7:0] t);
    if      (t <= 8'd16) w_of_tau = 9'd32;
    else if (t <= 8'd32) w_of_tau = 9'd64;
    else if (t <= 8'd64) w_of_tau = 9'd128;
    else                 w_of_tau = 9'd256;
endfunction

function automatic logic [1:0] s_of_tau(input logic [7:0] t);
    if      (t <= 8'd16) s_of_tau = 2'd3;
    else if (t <= 8'd32) s_of_tau = 2'd2;
    else if (t <= 8'd64) s_of_tau = 2'd1;
    else                 s_of_tau = 2'd0;
endfunction

// =============================================================================
// SECUENCIADOR DE BORRADO
// =============================================================================

logic       clr_busy;
logic [8:0] clr_addr;

always_ff @(posedge clk) begin
    if (!rst_n) begin
        clr_busy <= 1'b1;
        clr_addr <= 9'd0;
    end else if (clr_busy) begin
        clr_addr <= clr_addr + 9'd1;
        if (clr_addr == 9'd511)
            clr_busy <= 1'b0;
    end
end

// =============================================================================
// MEMORIAS (distribuidas, lectura sincronica)
// =============================================================================

(* ram_style = "distributed" *) logic signed [17:0] fir_ring [0:63];
(* ram_style = "distributed" *) logic signed [15:0] y48_ring [0:511];
(* ram_style = "distributed" *) logic signed [15:0] xd_ring  [0:511];
(* ram_style = "distributed" *) logic        [40:0] dr_ram   [0:255];

// ---- anillo del FIR -------------------------------------------------------
logic               fir_we;
logic [5:0]         fir_waddr;
logic signed [17:0] fir_wdata;
logic [5:0]         fir_raddr;
logic signed [17:0] fir_rdata;

always_ff @(posedge clk) begin
    if (fir_we) fir_ring[fir_waddr] <= fir_wdata;
    fir_rdata <= fir_ring[fir_raddr];
end

// ---- anillo Y48 (salida del FIR a 48 kHz) --------------------------------
logic               y48_we;
logic [8:0]         y48_waddr;
logic signed [15:0] y48_wdata;
logic [8:0]         y48_raddr;
logic signed [15:0] y48_rdata;

always_ff @(posedge clk) begin
    if (y48_we) y48_ring[y48_waddr] <= y48_wdata;
    y48_rdata <= y48_ring[y48_raddr];
end

// ---- anillo xd (12 kHz) ---------------------------------------------------
logic               xd_we;
logic [8:0]         xd_waddr;
logic signed [15:0] xd_wdata;
logic [8:0]         xd_raddr;
logic signed [15:0] xd_rdata;

always_ff @(posedge clk) begin
    if (xd_we) xd_ring[xd_waddr] <= xd_wdata;
    xd_rdata <= xd_ring[xd_raddr];
end

// ---- d(tau) ----------------------------------------------------------------
logic        dr_we;
logic [7:0]  dr_waddr;
logic [40:0] dr_wdata;
logic [7:0]  dr_raddr;
logic [40:0] dr_rdata;

always_ff @(posedge clk) begin
    if (dr_we) dr_ram[dr_waddr] <= dr_wdata;
    dr_rdata <= dr_ram[dr_raddr];
end

// =============================================================================
// FIR ANTIALIAS (48 taps, 1 DSP, una salida por muestra de 48 kHz)
// =============================================================================

localparam int NFIR = 48;

logic [5:0]         fir_wp;          // posicion de la muestra mas nueva
logic               fir_run;
logic [5:0]         fir_k;           // tap que se lee
logic [2:0]         fir_vld;         // pipeline: lectura -> registro de entrada -> producto
logic [2:0]         fir_last;
logic signed [24:0] fir_ma;
logic signed [17:0] fir_mb;
logic signed [42:0] fir_mp;
logic signed [47:0] fir_acc;
logic [5:0]         fir_k_d;

logic signed [18:0] x_shift;
logic signed [17:0] x18;

always_comb begin
    x_shift = sample_data[31:13];                  // sample >>> 13 (19 bits)
    if (x_shift > 19'sd131071)       x18 = 18'sd131071;
    else if (x_shift < -19'sd131072) x18 = -18'sd131072;
    else                             x18 = x_shift[17:0];
end

// salida del FIR hacia el anillo Y48 y el nucleo
logic               y_push;          // pulso: y16 listo
logic signed [15:0] y16;
logic [8:0]         y_wp;            // n48 mod 512 de la proxima escritura
logic [1:0]         dec_cnt;
logic               xd_push;         // pulso: muestra diezmada lista
logic signed [15:0] xd_push_data;
logic [8:0]         xd_push_n48;

always_comb begin
    fir_we    = 1'b0;
    fir_waddr = fir_wp;
    fir_wdata = x18;
    if (clr_busy) begin
        fir_we    = 1'b1;
        fir_waddr = clr_addr[5:0];
        fir_wdata = 18'sd0;
    end else if (sample_valid) begin
        fir_we    = 1'b1;
        fir_waddr = fir_wp + 6'd1;
    end
    fir_raddr = fir_wp - fir_k;
end

always_ff @(posedge clk) begin
    if (!rst_n || clr_busy) begin
        fir_wp   <= 6'd0 - 6'd1;    // la primera muestra se escribe en 0
        fir_run  <= 1'b0;
        fir_k    <= 6'd0;
        fir_vld  <= 3'd0;
        fir_last <= 3'd0;
        fir_ma   <= '0;
        fir_mb   <= '0;
        fir_mp   <= '0;
        fir_acc  <= '0;
        fir_k_d  <= 6'd0;
        y_push   <= 1'b0;
        y16      <= '0;
    end else begin
        y_push <= 1'b0;

        // lectura de taps
        if (sample_valid) begin
            fir_wp  <= fir_wp + 6'd1;
            fir_run <= 1'b1;
            fir_k   <= 6'd0;
        end else if (fir_run) begin
            if (fir_k == 6'(NFIR - 1)) fir_run <= 1'b0;
            else                   fir_k   <= fir_k + 6'd1;
        end

        // pipeline
        fir_vld  <= {fir_vld[1:0],  fir_run};
        fir_last <= {fir_last[1:0], fir_run && (fir_k == 6'(NFIR - 1))};
        fir_k_d  <= fir_k;

        if (fir_vld[0]) begin                        // dato del anillo disponible
            fir_ma <= {{7{fir_rdata[17]}}, fir_rdata};
            fir_mb <= fir_coef(fir_k_d);
        end
        fir_mp <= fir_ma * fir_mb;

        if (fir_vld[2]) begin : fir_acc_blk
            logic signed [47:0] acc_n;
            logic signed [47:0] rnd;
            acc_n = fir_acc + {{5{fir_mp[42]}}, fir_mp};
            if (fir_last[2]) begin
                rnd = (acc_n + 48'sd131072) >>> 18;
                if (rnd > 48'sd32767)       y16 <= 16'sd32767;
                else if (rnd < -48'sd32768) y16 <= -16'sd32768;
                else                        y16 <= rnd[15:0];
                y_push  <= 1'b1;
                fir_acc <= '0;
            end else begin
                fir_acc <= acc_n;
            end
        end
    end
end

// escritura en Y48 y diezmado
always_comb begin
    y48_we    = 1'b0;
    y48_waddr = y_wp;
    y48_wdata = y16;
    if (clr_busy) begin
        y48_we    = 1'b1;
        y48_waddr = clr_addr;
        y48_wdata = 16'sd0;
    end else if (y_push) begin
        y48_we = 1'b1;
    end
end

always_ff @(posedge clk) begin
    if (!rst_n || clr_busy) begin
        y_wp         <= 9'd0;
        dec_cnt      <= 2'd0;
        xd_push      <= 1'b0;
        xd_push_data <= '0;
        xd_push_n48  <= 9'd0;
    end else begin
        xd_push <= 1'b0;
        if (y_push) begin
            y_wp    <= y_wp + 9'd1;
            dec_cnt <= dec_cnt + 2'd1;
            if (dec_cnt == 2'd3) begin
                xd_push      <= 1'b1;
                xd_push_data <= y16;
                xd_push_n48  <= y_wp;
            end
        end
    end
end

// =============================================================================
// NUCLEO YIN
// =============================================================================

typedef enum logic [3:0] {
    C_IDLE,
    C_PASS,
    C_DIV_SETUP,
    C_DIV_RUN,
    C_DIV_DONE,
    C_REF_INIT,
    C_REF_RUN,
    C_REF_DRAIN,
    C_REF_ARGMIN,
    C_OCT_INIT,
    C_OCT_RUN,
    C_OCT_DRAIN,
    C_OCT_VSEL,
    C_OCT_MUL,
    C_OCT_DEC,
    C_EMIT
} cstate_t;

typedef enum logic [1:0] { SR_NF, SR_DESC, SR_LOCK } srch_t;

cstate_t cst;
logic [1:0] div_mode;                // 0: DIV1 (grueso), 1: DIV2 (fino), 2: vertice (octava)

logic [8:0]         m_ptr;           // m mod 512
logic [1:0]         m_phase;         // m mod 4 (busqueda cuando es 0)
logic               search_pass;
logic signed [15:0] a_r;             // xd[m]
logic [8:0]         n48_r;

// multiplicador compartido (1 DSP)
logic signed [24:0] mul_a;
logic signed [17:0] mul_b;
logic signed [42:0] mul_p;

always_ff @(posedge clk)
    mul_p <= mul_a * mul_b;

// ---- PASS: contextos A (lecturas + d) y B (tau*d + umbral + busqueda) ----
logic [2:0]         ph;
logic [7:0]         tau_a;
logic               a_act;
logic signed [15:0] b_r, e_r;
logic [40:0]        dr_cur;
logic [47:0]        S_acc;

logic [7:0]         tau_b;
logic               b_act;
logic [40:0]        dh_b;
logic [47:0]        S_b;
logic [31:0]        p_lo;

srch_t              srch;
logic [7:0]         t_r;
logic [40:0]        dm_r, d0_r, dp_r, dh_prev;

// ---- division ---------------------------------------------------------------
logic signed [42:0] dv_num;
logic signed [43:0] dv_den;
logic [42:0]        dv_rem;
logic [13:0]        dv_q;
logic [3:0]         dv_cnt;
logic               dv_neg;
logic signed [16:0] frac_r;

// ---- refinamiento --------------------------------------------------------
logic [7:0]         L0_r;
logic [2:0]         ri;              // indice de lectura en REF_INIT
logic               ri_vld;
logic [2:0]         ri_d;
logic [7:0]         ref_i;
logic [2:0]         kc;
logic signed [15:0] ya_r, ya_next;
logic signed [15:0] sr [0:4];
logic signed [15:0] sr_new;
logic [40:0]        acc48 [0:6];     // REF: 0..4 ; OCT: 0..2 = d(L1-1..L1+1), 3..5 = d(L2-1..L2+1), 6 = E
logic [1:0]         tag_v;
logic [2:0]         tag_k0, tag_k1;
logic [2:0]         drain;
logic [2:0]         jmin;

// ---- chequeo de octava ---------------------------------------------------
logic signed [31:0] p_ref;           // periodo refinado (Q16.16)
logic [7:0]         L1_r;            // round(P)
logic [8:0]         L2_r;            // round(2P)
logic [6:0]         oi;              // muestra dentro de la ventana de 128
logic signed [15:0] s1 [0:2];        // s1[k] = y[n-i-(L1-1+k)]
logic signed [15:0] s2 [0:2];        // s2[k] = y[n-i-(L2-1+k)]
logic signed [15:0] s1_new, s2_new;
logic               vsel;            // 0: v(P), 1: v(2P)
logic [1:0]         mstep;
logic [39:0]        pq_lo;
logic [40:0]        v1_r, v2_r;

// combinacionales del contexto A
logic [8:0]         w_a;
logic [1:0]         s_a;
logic signed [16:0] dn_a, do_a;
logic signed [17:0] u_a, v_a;
logic signed [41:0] dr_new;
logic [40:0]        dh_new;

always_comb begin
    w_a    = w_of_tau(tau_a);
    s_a    = s_of_tau(tau_a);
    dn_a   = {a_r[15], a_r} - {b_r[15], b_r};
    do_a   = {xd_rdata[15], xd_rdata} - {e_r[15], e_r};          // c - e (c llega en ph3)
    u_a    = {dn_a[16], dn_a} - {do_a[16], do_a};
    v_a    = {dn_a[16], dn_a} + {do_a[16], do_a};
    dr_new = $signed({1'b0, dr_cur}) + mul_p[41:0];
    dh_new = dr_new[40:0] << s_a;
end

// umbral del contexto B: 128 * tau * dh < THETA_NUM * S
logic [47:0] tdh;
logic [55:0] lhs;
logic [55:0] rhs;
logic        thr_ok;

always_comb begin
    tdh    = ({16'd0, mul_p[31:0]} << 24) + {16'd0, p_lo};      // p_hi llega en ph3
    lhs    = {1'b0, tdh, 7'd0};
    rhs    = '0;                                                // THETA_NUM * S con sumas (THETA_NUM constante)
    for (int k = 0; k < 7; k++)
        if (THETA_NUM[k]) rhs = rhs + ({8'd0, S_b} << k);
    thr_ok = (lhs < rhs);
end

// direcciones de las memorias del nucleo
always_comb begin
    xd_we    = 1'b0;
    xd_waddr = m_ptr;
    xd_wdata = xd_push_data;
    if (clr_busy) begin
        xd_we    = 1'b1;
        xd_waddr = clr_addr;
        xd_wdata = 16'sd0;
    end else if (xd_push && cst == C_IDLE) begin
        xd_we = 1'b1;
    end

    case (ph)
        3'd0:    xd_raddr = m_ptr - {1'b0, tau_a};
        3'd1:    xd_raddr = m_ptr - w_a - {1'b0, tau_a};
        default: xd_raddr = m_ptr - w_a;
    endcase

    dr_raddr = tau_a;
    dr_we    = 1'b0;
    dr_waddr = tau_a;
    dr_wdata = dr_new[40:0];
    if (clr_busy) begin
        dr_we    = 1'b1;
        dr_waddr = clr_addr[7:0];
        dr_wdata = '0;
    end else if (cst == C_PASS && a_act && ph == 3'd5) begin
        dr_we = 1'b1;
    end

    // Y48: REF_INIT lee los 5 retardos y la muestra actual; REF_RUN, 2 lecturas por muestra.
    //      OCT_INIT lee 3 + 3 retardos y la muestra actual; OCT_RUN, 3 lecturas por muestra.
    if (cst == C_REF_INIT) begin
        if (ri <= 3'd4) y48_raddr = n48_r - ({1'b0, L0_r} - 9'd2 + {6'd0, ri});
        else            y48_raddr = n48_r;
    end else if (cst == C_OCT_INIT) begin
        if (ri <= 3'd2)      y48_raddr = n48_r - ({1'b0, L1_r} - 9'd1 + {6'd0, ri});
        else if (ri <= 3'd5) y48_raddr = n48_r - (L2_r - 9'd1 + {6'd0, ri} - 9'd3);
        else                 y48_raddr = n48_r;
    end else if (cst == C_OCT_RUN) begin
        if (kc == 3'd0)      y48_raddr = n48_r - {2'b0, oi} - 9'd1;
        else if (kc == 3'd1) y48_raddr = n48_r - {2'b0, oi} - 9'd1 - {1'b0, L1_r} - 9'd1;
        else                 y48_raddr = n48_r - {2'b0, oi} - 9'd1 - L2_r - 9'd1;
    end else if (kc == 3'd0) begin
        y48_raddr = n48_r - {1'b0, ref_i} - 9'd1;
    end else begin
        y48_raddr = n48_r - {1'b0, ref_i} - 9'd1 - {1'b0, L0_r} - 9'd2;
    end
end

always_ff @(posedge clk) begin
    if (!rst_n || clr_busy) begin
        cst          <= C_IDLE;
        div_mode     <= 2'd0;
        m_ptr        <= 9'd0;
        m_phase      <= 2'd0;
        search_pass  <= 1'b0;
        a_r          <= '0;
        n48_r        <= '0;
        mul_a        <= '0;
        mul_b        <= '0;
        ph           <= 3'd0;
        tau_a        <= 8'd1;
        a_act        <= 1'b0;
        b_act        <= 1'b0;
        b_r          <= '0;
        e_r          <= '0;
        dr_cur       <= '0;
        S_acc        <= '0;
        tau_b        <= '0;
        dh_b         <= '0;
        S_b          <= '0;
        p_lo         <= '0;
        srch         <= SR_NF;
        t_r          <= '0;
        dm_r         <= '0;
        d0_r         <= '0;
        dp_r         <= '0;
        dh_prev      <= '0;
        dv_num       <= '0;
        dv_den       <= '0;
        dv_rem       <= '0;
        dv_q         <= '0;
        dv_cnt       <= '0;
        dv_neg       <= 1'b0;
        frac_r       <= '0;
        L0_r         <= '0;
        ri           <= '0;
        ri_vld       <= 1'b0;
        ri_d         <= '0;
        ref_i        <= '0;
        kc           <= '0;
        ya_r         <= '0;
        ya_next      <= '0;
        sr_new       <= '0;
        for (int k = 0; k < 5; k++) sr[k] <= '0;
        for (int k = 0; k < 7; k++) acc48[k] <= '0;
        for (int k = 0; k < 3; k++) begin
            s1[k] <= '0;
            s2[k] <= '0;
        end
        s1_new       <= '0;
        s2_new       <= '0;
        p_ref        <= '0;
        L1_r         <= '0;
        L2_r         <= '0;
        oi           <= '0;
        vsel         <= 1'b0;
        mstep        <= '0;
        pq_lo        <= '0;
        v1_r         <= '0;
        v2_r         <= '0;
        tag_v        <= '0;
        tag_k0       <= '0;
        tag_k1       <= '0;
        drain        <= '0;
        jmin         <= '0;
        period_16_16 <= 32'd0;
        period_valid <= 1'b0;
    end else begin
        period_valid <= 1'b0;

        case (cst)

        // ---------------------------------------------------------------------
        C_IDLE: begin
            if (xd_push) begin                    // xd_ring[m] <= x (combinacional)
                a_r         <= xd_push_data;
                n48_r       <= xd_push_n48;
                search_pass <= (m_phase == 2'd0);
                ph          <= 3'd0;
                tau_a       <= 8'd1;
                a_act       <= 1'b1;
                b_act       <= 1'b0;
                S_acc       <= '0;
                srch        <= SR_NF;
                dh_prev     <= '0;
                cst         <= C_PASS;
            end
        end

        // ---------------------------------------------------------------------
        // Bucle en tau con intervalo de iniciacion 6. En cada periodo de 6
        // ciclos el contexto A procesa tau (ph 0..5) y el contexto B termina
        // tau-1 (ph 0..3). Ocupacion del multiplicador: A en ph3, B en ph0/ph1.
        // ---------------------------------------------------------------------
        C_PASS: begin
            // ----- contexto A -----
            if (a_act) begin
                case (ph)
                    3'd1: begin b_r <= xd_rdata; dr_cur <= dr_rdata; end
                    3'd2: e_r <= xd_rdata;
                    3'd3: begin
                        mul_a <= {{7{u_a[17]}}, u_a};
                        mul_b <= v_a;
                    end
                    default: ;
                endcase
            end

            // ----- contexto B -----
            if (b_act) begin
                case (ph)
                    3'd0: begin
                        mul_a <= {1'b0, dh_b[23:0]};
                        mul_b <= {10'd0, tau_b};
                    end
                    3'd1: begin
                        mul_a <= {8'd0, dh_b[40:24]};
                        mul_b <= {10'd0, tau_b};
                    end
                    3'd2: p_lo <= mul_p[31:0];
                    3'd3: begin
                        case (srch)
                            SR_NF: if (tau_b >= 8'(TAU_MIN) && thr_ok) begin
                                t_r  <= tau_b;
                                d0_r <= dh_b;
                                dm_r <= dh_prev;
                                srch <= SR_DESC;
                            end
                            SR_DESC: if (dh_b < d0_r) begin
                                dm_r <= d0_r;
                                d0_r <= dh_b;
                                t_r  <= tau_b;
                            end else begin
                                dp_r <= dh_b;
                                srch <= SR_LOCK;
                            end
                            default: ;
                        endcase
                        dh_prev <= dh_b;
                    end
                    default: ;
                endcase
            end

            // ----- avance -----
            if (ph == 3'd5) begin
                ph    <= 3'd0;
                b_act <= a_act;
                if (a_act) begin
                    tau_b <= tau_a;
                    dh_b  <= dh_new;
                    S_b   <= S_acc + {7'd0, dh_new};
                    S_acc <= S_acc + {7'd0, dh_new};
                    if (tau_a == 8'(TAU_MAX)) a_act <= 1'b0;
                    else                       tau_a <= tau_a + 8'd1;
                end
            end else if (!a_act && ph == 3'd3) begin
                // ultimo tau terminado en el contexto B
                b_act <= 1'b0;
                ph    <= 3'd0;
                if (search_pass && (srch == SR_LOCK || (srch == SR_DESC && !(dh_b < d0_r)))) begin
                    div_mode   <= 2'd0;
                    cst        <= C_DIV_SETUP;
                end else begin
                    cst <= C_EMIT;               // sin estimacion: solo avanza m
                end
            end else begin
                ph <= ph + 3'd1;
            end
        end

        // ---------------------------------------------------------------------
        // frac = (dm - dp) / (2 (dm - 2 d0 + dp)), Q0.16, recorte +-0,5
        // ---------------------------------------------------------------------
        C_DIV_SETUP: begin : div_setup_blk
            logic signed [42:0] num;
            logic signed [43:0] den;
            num = $signed({2'b0, dm_r}) - $signed({2'b0, dp_r});
            den = $signed({3'b0, dm_r}) - $signed({2'b0, d0_r, 1'b0}) + $signed({3'b0, dp_r});
            dv_neg <= num[42];
            dv_num <= num[42] ? -num : num;
            dv_den <= den;
            cst    <= C_DIV_RUN;
            dv_cnt <= 4'd0;
            dv_q   <= '0;
        end

        C_DIV_RUN: begin
            if (dv_cnt == 4'd0) begin
                dv_rem <= dv_num[42:0];
                if (dv_den <= 0) begin
                    frac_r <= '0;
                    cst    <= C_DIV_DONE;
                end else if ($signed({1'b0, dv_num}) >= dv_den) begin
                    frac_r <= dv_neg ? -17'sd32768 : 17'sd32768;
                    cst    <= C_DIV_DONE;
                end else begin
                    dv_cnt <= 4'd1;
                end
            end else begin : div_step_blk
                logic [43:0] sh;
                sh = {dv_rem, 1'b0};
                if (sh >= dv_den[43:0]) begin
                    dv_rem <= sh[42:0] - dv_den[42:0];
                    dv_q   <= {dv_q[12:0], 1'b1};
                end else begin
                    dv_rem <= sh[42:0];
                    dv_q   <= {dv_q[12:0], 1'b0};
                end
                if (dv_cnt == 4'd15) begin
                    frac_r <= dv_neg ? -$signed({2'b0, dv_q[13:0], (sh >= dv_den[43:0])})
                                     :  $signed({2'b0, dv_q[13:0], (sh >= dv_den[43:0])});
                    cst    <= C_DIV_DONE;
                end
                dv_cnt <= dv_cnt + 4'd1;
            end
        end

        C_DIV_DONE: begin
            if (div_mode == 2'd0) begin : coarse_blk
                logic signed [31:0] pc;
                pc = $signed({6'd0, t_r, 18'd0}) + ($signed({{15{frac_r[16]}}, frac_r}) <<< 2);
                if (pc <= $signed(REF_PMAX << 16)) begin
                    L0_r   <= 8'((pc + 32'sd32768) >>> 16);
                    ri     <= 3'd0;
                    ri_vld <= 1'b0;
                    cst    <= C_REF_INIT;
                end else begin
                    period_16_16 <= pc;
                    period_valid <= gate;
                    cst          <= C_EMIT;
                end
            end else if (div_mode == 2'd1) begin : fine_blk
                logic signed [31:0] pf;
                pf = $signed({8'd0, L0_r - 8'd2 + {5'd0, jmin}, 16'd0})
                   + $signed({{15{frac_r[16]}}, frac_r});
                if (OCT_CHECK) begin
                    p_ref  <= pf;
                    L1_r   <= 8'((pf + 32'sd32768) >>> 16);          // round(P)
                    L2_r   <= 9'((pf + 32'sd16384) >>> 15);          // round(2P)
                    ri     <= 3'd0;
                    ri_vld <= 1'b0;
                    cst    <= C_OCT_INIT;
                end else begin
                    period_16_16 <= pf;
                    period_valid <= gate;
                    cst          <= C_EMIT;
                end
            end else begin
                mstep <= 2'd0;                                       // vertice: |delta| * |a-c|
                cst   <= C_OCT_MUL;
            end
        end

        // ---------------------------------------------------------------------
        // Refinamiento a 48 kHz: d48(L) = sum_{i<256} (y[n-i] - y[n-i-L])^2
        // para L = L0-2 .. L0+2. sr[k] = y[n-i-(L0-2+k)] se desplaza en 1 por
        // muestra: 2 lecturas y 5 productos por cada i.
        // ---------------------------------------------------------------------
        C_REF_INIT: begin
            ri_vld <= 1'b1;
            ri_d   <= ri;
            ri     <= ri + 3'd1;
            if (ri_vld) begin
                if (ri_d <= 3'd4) sr[ri_d] <= y48_rdata;
                else              ya_r     <= y48_rdata;
            end
            for (int k = 0; k < 5; k++) acc48[k] <= '0;
            if (ri_vld && ri_d == 3'd5) begin
                ref_i <= 8'd0;
                kc    <= 3'd0;
                tag_v <= 2'b00;
                cst   <= C_REF_RUN;
            end
        end

        C_REF_RUN: begin : ref_run_blk
            logic signed [16:0] dif;
            dif   = {ya_r[15], ya_r} - {sr[kc][15], sr[kc]};
            mul_a <= {{8{dif[16]}}, dif};
            mul_b <= {dif[16], dif};
            tag_v  <= {tag_v[0], 1'b1};
            tag_k0 <= kc;
            tag_k1 <= tag_k0;
            if (tag_v[1]) acc48[tag_k1] <= acc48[tag_k1] + mul_p[40:0];

            if (kc == 3'd1) ya_next <= y48_rdata;      // y[n-i-1] (leido en kc0)
            if (kc == 3'd2) sr_new  <= y48_rdata;      // y[n-(i+1)-(L0+2)]

            if (kc == 3'd4) begin
                kc    <= 3'd0;
                ya_r  <= ya_next;
                for (int k = 0; k < 4; k++) sr[k] <= sr[k+1];
                sr[4] <= sr_new;
                if (ref_i == 8'd255) begin
                    drain <= 3'd0;
                    cst   <= C_REF_DRAIN;
                end
                ref_i <= ref_i + 8'd1;
            end else begin
                kc <= kc + 3'd1;
            end
        end

        C_REF_DRAIN: begin
            tag_v  <= {tag_v[0], 1'b0};
            tag_k1 <= tag_k0;
            if (tag_v[1]) acc48[tag_k1] <= acc48[tag_k1] + mul_p[40:0];
            drain <= drain + 3'd1;
            if (drain == 3'd2) cst <= C_REF_ARGMIN;
        end

        C_REF_ARGMIN: begin : argmin_blk
            logic [2:0] j;
            j = 3'd0;
            for (int k = 1; k < 5; k++)
                if (acc48[k] < acc48[j]) j = 3'(k);
            if (j == 3'd0) j = 3'd1;
            if (j == 3'd4) j = 3'd3;
            jmin       <= j;
            dm_r       <= acc48[j - 3'd1];
            d0_r       <= acc48[j];
            dp_r       <= acc48[j + 3'd1];
            div_mode   <= 2'd1;
            cst        <= C_DIV_SETUP;
        end

        // ---------------------------------------------------------------------
        // Chequeo de octava: con la misma ventana de 128 muestras a 48 kHz,
        //   acc 0..2 = d(L1-1..L1+1), L1 = round(P)     (pozo en P)
        //   acc 3..5 = d(L2-1..L2+1), L2 = round(2P)    (pozo en 2P)
        //   acc 6    = E = sum y^2
        // s1 y s2 se desplazan en 1 por muestra: 3 lecturas y 7 productos por i.
        // ---------------------------------------------------------------------
        C_OCT_INIT: begin
            ri_vld <= 1'b1;
            ri_d   <= ri;
            ri     <= ri + 3'd1;
            if (ri_vld) begin
                if (ri_d <= 3'd2)      s1[2'(ri_d)]           <= y48_rdata;
                else if (ri_d <= 3'd5) s2[2'(ri_d - 3'd3)]    <= y48_rdata;
                else                   ya_r            <= y48_rdata;
            end
            for (int k = 0; k < 7; k++) acc48[k] <= '0;
            if (ri_vld && ri_d == 3'd6) begin
                oi    <= 7'd0;
                kc    <= 3'd0;
                tag_v <= 2'b00;
                cst   <= C_OCT_RUN;
            end
        end

        C_OCT_RUN: begin : oct_run_blk
            logic signed [16:0] dif;
            if (kc <= 3'd2)      dif = {ya_r[15], ya_r} - {s1[2'(kc)][15], s1[2'(kc)]};
            else if (kc <= 3'd5) dif = {ya_r[15], ya_r} - {s2[2'(kc - 3'd3)][15], s2[2'(kc - 3'd3)]};
            else                 dif = {ya_r[15], ya_r};
            mul_a <= {{8{dif[16]}}, dif};
            mul_b <= {dif[16], dif};
            tag_v  <= {tag_v[0], 1'b1};
            tag_k0 <= kc;
            tag_k1 <= tag_k0;
            if (tag_v[1]) acc48[tag_k1] <= acc48[tag_k1] + mul_p[40:0];

            if (kc == 3'd1) ya_next <= y48_rdata;      // y[n-i-1]
            if (kc == 3'd2) s1_new  <= y48_rdata;      // y[n-(i+1)-(L1+1)]
            if (kc == 3'd3) s2_new  <= y48_rdata;      // y[n-(i+1)-(L2+1)]

            if (kc == 3'd6) begin
                kc    <= 3'd0;
                ya_r  <= ya_next;
                s1[0] <= s1[1]; s1[1] <= s1[2]; s1[2] <= s1_new;
                s2[0] <= s2[1]; s2[1] <= s2[2]; s2[2] <= s2_new;
                if (oi == 7'd127) begin
                    drain <= 3'd0;
                    cst   <= C_OCT_DRAIN;
                end
                oi <= oi + 7'd1;
            end else begin
                kc <= kc + 3'd1;
            end
        end

        C_OCT_DRAIN: begin
            tag_v  <= {tag_v[0], 1'b0};
            tag_k1 <= tag_k0;
            if (tag_v[1]) acc48[tag_k1] <= acc48[tag_k1] + mul_p[40:0];
            drain <= drain + 3'd1;
            if (drain == 3'd2) begin
                vsel <= 1'b0;
                cst  <= C_OCT_VSEL;
            end
        end

        // vertice de la parabola por (a, b, c):  v = b - |delta| |a - c| / 4
        // |delta| = q / 2^16 sale de la misma division de la interpolacion.
        C_OCT_VSEL: begin
            dm_r     <= vsel ? acc48[3] : acc48[0];
            d0_r     <= vsel ? acc48[4] : acc48[1];
            dp_r     <= vsel ? acc48[5] : acc48[2];
            div_mode <= 2'd2;
            cst      <= C_DIV_SETUP;
        end

        C_OCT_MUL: begin : oct_mul_blk
            logic [15:0] q;
            logic [55:0] prod;
            logic [40:0] corr, v;
            q = frac_r[16] ? 16'(-frac_r) : 16'(frac_r);
            prod = {mul_p[31:0], 24'd0} + {16'd0, pq_lo};
            corr = 41'(prod >> 18);
            v    = (d0_r > corr) ? d0_r - corr : 41'd0;
            mstep <= mstep + 2'd1;
            case (mstep)
                2'd0: begin mul_a <= {1'b0, dv_num[23:0]};  mul_b <= {2'b0, q}; end
                2'd1: begin mul_a <= {9'd0, dv_num[39:24]}; mul_b <= {2'b0, q}; end
                2'd2: pq_lo <= mul_p[39:0];
                default: begin                                // mul_p = q * |a-c|[39:24]
                    if (!vsel) begin
                        v1_r <= v;
                        vsel <= 1'b1;
                        cst  <= C_OCT_VSEL;
                    end else begin
                        v2_r <= v;
                        cst  <= C_OCT_DEC;
                    end
                end
            endcase
        end

        C_OCT_DEC: begin : oct_dec_blk
            logic sw;
            sw = ({8'd0, v1_r} << OCT_EPS_SH) >= {8'd0, acc48[6]} &&
                 ({8'd0, v2_r} << OCT_ALPHA_SH) < {8'd0, v1_r};
            period_16_16 <= sw ? (p_ref <<< 1) : p_ref;
            period_valid <= gate;
            cst          <= C_EMIT;
        end

        // ---------------------------------------------------------------------
        C_EMIT: begin
            m_ptr   <= m_ptr + 9'd1;
            m_phase <= m_phase + 2'd1;
            kc      <= 3'd0;
            cst     <= C_IDLE;
        end

        default: cst <= C_IDLE;
        endcase
    end
end

// =============================================================================
// VERIFICACION (solo simulacion)
// =============================================================================
`ifndef SYNTHESIS
always_ff @(posedge clk) begin
    if (rst_n && !clr_busy) begin
        if (xd_push && cst != C_IDLE)
            $error("fx_pitch_yin: llego una muestra diezmada con el nucleo ocupado (estado %0d)", cst);
        if (sample_valid && fir_run)
            $error("fx_pitch_yin: muestra nueva con el FIR ocupado");
        if (cst == C_PASS && a_act && ph == 3'd5 && dr_new < 0)
            $error("fx_pitch_yin: d(tau) negativo (tau=%0d)", tau_a);
        if (cst == C_PASS && a_act && ph == 3'd5 && dr_new[41])
            $error("fx_pitch_yin: d(tau) desborda 41 bits");
    end
end
`endif

logic unused;
assign unused = ^{zc_hyst_q3_29, sample_data[12:0], mul_p[42]};

endmodule
