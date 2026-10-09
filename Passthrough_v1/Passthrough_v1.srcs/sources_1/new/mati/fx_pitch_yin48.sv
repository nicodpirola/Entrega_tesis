`timescale 1ns/1ps

// =============================================================================
// fx_pitch_yin48.sv
//
// Detector de periodo YIN (de Cheveigne & Kawahara, JASA 2002) a 48 kHz, sin
// diezmado, con los lags repartidos en N carriles paralelos.
//
// Especificacion bit-exacta: Pitch_YIN48/modelo/yin48_fixed.py
// Desarrollo:                Pitch_YIN48/YIN48_desarrollo.md
//
//   sample_data (Q3.29, 48 kHz) -> x18 = sat18(x >>> 13)
//     -> prefiltro FIR 48 taps (1 DSP), juego de coeficientes segun "perfil":
//          0 = guitarra (pasa 2,3 kHz), 1 = theremin (pasa 8,5 kHz)   -> y16
//     -> nucleo, por muestra:
//          escribe y16 en el anillo X (2048, entrelazado en N bancos)
//          PRELUDIO (carril 0): 4 lecturas x[n-W] (W = 128..1024) y 6 lags de
//                   frontera (d(b) con la ventana de b+1 y d(b+1) con la de b)
//          BARRIDO: tau = 1..800, N lags por ciclo (uno por carril):
//                   d(tau) += (dn - do)(dn + do)         (1 DSP por carril)
//                   y, cada 16 muestras, en el mismo barrido:
//                   S, umbral 128*tau*dh < 19*S (1 DSP por carril) y busqueda
//          DIV:     interpolacion parabolica (15 ciclos)
//          EMIT:    period_16_16 + period_valid + confianza (CL, CR)
//
// Memoria entrelazada: la muestra de direccion a vive en el banco (a mod N).
// En un ciclo los carriles piden x[n-tau0-j], j = 0..N-1 (direcciones
// consecutivas) -> caen en N bancos distintos. Lo mismo x[n-W-tau0-j] (W es
// multiplo de N). Sin conflictos y sin replicar memoria.
//
// Ciclos por muestra (50 MHz -> 1041 disponibles):
//   ~52 (FIR) + 10 (preludio) + 800/N (barrido) + ~14 (pipeline) + ~18 (div)
//   N = 1: ~894    N = 2: ~494    N = 4: ~294
// Recursos: 1 + 2N DSP48E1; N BRAM18 (anillo) + N memorias d(tau) (800/N x 45).
// =============================================================================

module fx_pitch_yin48 #(
    parameter int N          = 2,      // carriles: 1, 2 o 4
    parameter int THETA_NUM  = 19,     // umbral theta = THETA_NUM / 128
    parameter int TAU_MIN    = 6,      // 48000 / 6   = 8 kHz
    parameter int TAU_MAX    = 800,    // 48000 / 800 = 60 Hz (multiplo de N)
    parameter int HOP        = 16      // una busqueda cada HOP muestras (3 kHz)
)(
    input  logic               clk,
    input  logic               rst_n,

    input  logic               perfil,          // 0 guitarra, 1 theremin (prefiltro)

    input  logic               sample_valid,
    input  logic signed [31:0] sample_data,

    output logic [31:0]        period_16_16,
    output logic               period_valid,
    output logic [33:0]        conf_cl,         // tau * sat24(dh >> k)
    output logic [51:0]        conf_cr,         // S >> k            (d' = conf_cl / conf_cr)
    output logic               busy,
    output logic               overrun          // llego una muestra con el nucleo ocupado (no deberia)
);

localparam int LOGN  = (N == 4) ? 2 : (N == 2) ? 1 : 0;
localparam int IW    = (LOGN > 0) ? LOGN : 1;
localparam int NX    = 2048;
localparam int DEPX  = NX / N;
localparam int XA    = $clog2(DEPX);
localparam int DEPD  = TAU_MAX / N;
localparam int NFIR  = 48;
localparam int KBITS = 24;
localparam int LANE_W = 10;                       // ancho del tau

initial begin
    if (!(N == 1 || N == 2 || N == 4)) $fatal(1, "fx_pitch_yin48: N tiene que ser 1, 2 o 4");
    if (TAU_MAX % N != 0)              $fatal(1, "fx_pitch_yin48: TAU_MAX tiene que ser multiplo de N");
    if (THETA_NUM < 1 || THETA_NUM > 31) $fatal(1, "fx_pitch_yin48: THETA_NUM fuera de rango (1..31)");
    if (TAU_MAX > 800 || TAU_MIN < 2)  $fatal(1, "fx_pitch_yin48: TAU_MIN/TAU_MAX fuera de rango");
end

// =============================================================================
// FUNCIONES
// =============================================================================

function automatic logic signed [17:0] fir_coef(input logic p, input logic [5:0] k);
    if (!p) begin
        case (k)
            6'd0: fir_coef = -18'sd32;
            6'd1: fir_coef = 18'sd295;
            6'd2: fir_coef = 18'sd434;
            6'd3: fir_coef = 18'sd656;
            6'd4: fir_coef = 18'sd864;
            6'd5: fir_coef = 18'sd990;
            6'd6: fir_coef = 18'sd967;
            6'd7: fir_coef = 18'sd740;
            6'd8: fir_coef = 18'sd283;
            6'd9: fir_coef = -18'sd384;
            6'd10: fir_coef = -18'sd1187;
            6'd11: fir_coef = -18'sd1996;
            6'd12: fir_coef = -18'sd2636;
            6'd13: fir_coef = -18'sd2915;
            6'd14: fir_coef = -18'sd2651;
            6'd15: fir_coef = -18'sd1708;
            6'd16: fir_coef = -18'sd32;
            6'd17: fir_coef = 18'sd2331;
            6'd18: fir_coef = 18'sd5225;
            6'd19: fir_coef = 18'sd8399;
            6'd20: fir_coef = 18'sd11532;
            6'd21: fir_coef = 18'sd14277;
            6'd22: fir_coef = 18'sd16316;
            6'd23: fir_coef = 18'sd17402;
            6'd24: fir_coef = 18'sd17402;
            6'd25: fir_coef = 18'sd16316;
            6'd26: fir_coef = 18'sd14277;
            6'd27: fir_coef = 18'sd11532;
            6'd28: fir_coef = 18'sd8399;
            6'd29: fir_coef = 18'sd5225;
            6'd30: fir_coef = 18'sd2331;
            6'd31: fir_coef = -18'sd32;
            6'd32: fir_coef = -18'sd1708;
            6'd33: fir_coef = -18'sd2651;
            6'd34: fir_coef = -18'sd2915;
            6'd35: fir_coef = -18'sd2636;
            6'd36: fir_coef = -18'sd1996;
            6'd37: fir_coef = -18'sd1187;
            6'd38: fir_coef = -18'sd384;
            6'd39: fir_coef = 18'sd283;
            6'd40: fir_coef = 18'sd740;
            6'd41: fir_coef = 18'sd967;
            6'd42: fir_coef = 18'sd990;
            6'd43: fir_coef = 18'sd864;
            6'd44: fir_coef = 18'sd656;
            6'd45: fir_coef = 18'sd434;
            6'd46: fir_coef = 18'sd295;
            6'd47: fir_coef = -18'sd32;
            default: fir_coef = 18'sd0;
        endcase
    end else begin
        case (k)
            6'd0: fir_coef = -18'sd74;
            6'd1: fir_coef = -18'sd89;
            6'd2: fir_coef = 18'sd84;
            6'd3: fir_coef = 18'sd301;
            6'd4: fir_coef = 18'sd155;
            6'd5: fir_coef = -18'sd345;
            6'd6: fir_coef = -18'sd461;
            6'd7: fir_coef = 18'sd273;
            6'd8: fir_coef = 18'sd935;
            6'd9: fir_coef = 18'sd213;
            6'd10: fir_coef = -18'sd1266;
            6'd11: fir_coef = -18'sd1115;
            6'd12: fir_coef = 18'sd1170;
            6'd13: fir_coef = 18'sd2365;
            6'd14: fir_coef = -18'sd232;
            6'd15: fir_coef = -18'sd3582;
            6'd16: fir_coef = -18'sd1876;
            6'd17: fir_coef = 18'sd4146;
            6'd18: fir_coef = 18'sd5465;
            6'd19: fir_coef = -18'sd3030;
            6'd20: fir_coef = -18'sd11279;
            6'd21: fir_coef = -18'sd2401;
            6'd22: fir_coef = 18'sd25354;
            6'd23: fir_coef = 18'sd50976;
            6'd24: fir_coef = 18'sd50976;
            6'd25: fir_coef = 18'sd25354;
            6'd26: fir_coef = -18'sd2401;
            6'd27: fir_coef = -18'sd11279;
            6'd28: fir_coef = -18'sd3030;
            6'd29: fir_coef = 18'sd5465;
            6'd30: fir_coef = 18'sd4146;
            6'd31: fir_coef = -18'sd1876;
            6'd32: fir_coef = -18'sd3582;
            6'd33: fir_coef = -18'sd232;
            6'd34: fir_coef = 18'sd2365;
            6'd35: fir_coef = 18'sd1170;
            6'd36: fir_coef = -18'sd1115;
            6'd37: fir_coef = -18'sd1266;
            6'd38: fir_coef = 18'sd213;
            6'd39: fir_coef = 18'sd935;
            6'd40: fir_coef = 18'sd273;
            6'd41: fir_coef = -18'sd461;
            6'd42: fir_coef = -18'sd345;
            6'd43: fir_coef = 18'sd155;
            6'd44: fir_coef = 18'sd301;
            6'd45: fir_coef = 18'sd84;
            6'd46: fir_coef = -18'sd89;
            6'd47: fir_coef = -18'sd74;
            default: fir_coef = 18'sd0;
        endcase
    end
endfunction

// grupo de ventana: 0 -> W 128 (s 3), 1 -> 256 (2), 2 -> 512 (1), 3 -> 1024 (0)
function automatic logic [1:0] grp_of_tau(input logic [LANE_W-1:0] t);
    if      (t <= 10'd64)  grp_of_tau = 2'd0;
    else if (t <= 10'd128) grp_of_tau = 2'd1;
    else if (t <= 10'd256) grp_of_tau = 2'd2;
    else                   grp_of_tau = 2'd3;
endfunction

function automatic logic [10:0] w_of_grp(input logic [1:0] g);
    w_of_grp = 11'd128 << g;
endfunction

// =============================================================================
// SECUENCIADOR DE BORRADO (memorias a cero: la suma incremental lo necesita)
// =============================================================================

localparam int CLR_N = (DEPX > DEPD) ? DEPX : DEPD;
localparam int CLR_W = $clog2(CLR_N + 1);

logic             clr_busy;
logic [CLR_W-1:0] clr_addr;

always_ff @(posedge clk) begin
    if (!rst_n) begin
        clr_busy <= 1'b1;
        clr_addr <= '0;
    end else if (clr_busy) begin
        clr_addr <= clr_addr + 1'b1;
        if (clr_addr == CLR_W'(CLR_N - 1))
            clr_busy <= 1'b0;
    end
end

// =============================================================================
// PREFILTRO FIR (48 taps, 1 DSP, una salida por muestra)
// =============================================================================

(* ram_style = "distributed" *) logic signed [17:0] fir_ring [0:63];

logic [5:0]         fir_wp;
logic               fir_run;
logic [5:0]         fir_k, fir_k_d;
logic [2:0]         fir_vld, fir_last;
logic signed [24:0] fir_ma;
logic signed [17:0] fir_mb;
logic signed [42:0] fir_mp;
logic signed [47:0] fir_acc;
logic signed [17:0] fir_rdata;
logic               perfil_r;

logic signed [18:0] x_shift;
logic signed [17:0] x18;

always_comb begin
    x_shift = sample_data[31:13];
    if (x_shift > 19'sd131071)       x18 = 18'sd131071;
    else if (x_shift < -19'sd131072) x18 = -18'sd131072;
    else                             x18 = x_shift[17:0];
end

always_ff @(posedge clk) begin
    if (clr_busy)          fir_ring[clr_addr[5:0]] <= 18'sd0;
    else if (sample_valid) fir_ring[fir_wp + 6'd1] <= x18;
    fir_rdata <= fir_ring[fir_wp - fir_k];
end

logic               y_push;
logic signed [15:0] y16;

always_ff @(posedge clk) begin
    if (!rst_n || clr_busy) begin
        fir_wp   <= 6'd0 - 6'd1;
        fir_run  <= 1'b0;
        fir_k    <= 6'd0;
        fir_k_d  <= 6'd0;
        fir_vld  <= 3'd0;
        fir_last <= 3'd0;
        fir_ma   <= '0;
        fir_mb   <= '0;
        fir_mp   <= '0;
        fir_acc  <= '0;
        y_push   <= 1'b0;
        y16      <= '0;
        perfil_r <= 1'b0;
    end else begin
        y_push <= 1'b0;
        if (sample_valid) begin
            fir_wp   <= fir_wp + 6'd1;
            fir_run  <= 1'b1;
            fir_k    <= 6'd0;
            perfil_r <= perfil;              // el juego de coeficientes cambia entre muestras
        end else if (fir_run) begin
            if (fir_k == 6'(NFIR - 1)) fir_run <= 1'b0;
            else                       fir_k   <= fir_k + 6'd1;
        end
        fir_vld  <= {fir_vld[1:0],  fir_run};
        fir_last <= {fir_last[1:0], fir_run && (fir_k == 6'(NFIR - 1))};
        fir_k_d  <= fir_k;
        if (fir_vld[0]) begin
            fir_ma <= {{7{fir_rdata[17]}}, fir_rdata};
            fir_mb <= fir_coef(perfil_r, fir_k_d);
        end
        fir_mp <= fir_ma * fir_mb;
        if (fir_vld[2]) begin : fir_acc_blk
            logic signed [47:0] acc_n, rnd;
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

// =============================================================================
// SECUENCIADOR DE OPERACIONES
//
// Por muestra: TAP x4 (x[n-W]), ALT x6 (lags de frontera), LAG x TAU_MAX/N.
// Las TAP y ALT usan solo el carril 0.
// =============================================================================

typedef enum logic [1:0] { OP_NONE, OP_TAP, OP_ALT, OP_LAG } op_t;
typedef enum logic [2:0] { Q_IDLE, Q_PRE, Q_SWEEP, Q_DRAIN, Q_DIV, Q_EMIT } qstate_t;

qstate_t            qs;
logic [10:0]        n_ptr;                 // n mod 2048 (direccion de la muestra actual)
logic [3:0]         hop_cnt;               // n mod 16
logic               busca;                 // este barrido busca
logic signed [15:0] xn;                    // x[n]
logic [3:0]         pre_cnt;
logic [LANE_W-1:0]  tau0;                  // tau del carril 0 en el barrido

// operacion que entra al pipeline (c0)
op_t                i_op;
logic [LANE_W-1:0]  i_tau  [N];
logic [1:0]         i_grp  [N];            // grupo de ventana de cada carril (para x[n-W] y s)
logic [2:0]         i_ai;                  // indice ALT 0..5 / TAP 0..3
logic               i_last;                // ultima LAG del barrido

// lista de ALT: (tau, grupo de ventana)
function automatic logic [LANE_W-1:0] alt_tau(input logic [2:0] a);
    case (a)
        3'd0: alt_tau = 10'd64;   3'd1: alt_tau = 10'd65;
        3'd2: alt_tau = 10'd128;  3'd3: alt_tau = 10'd129;
        3'd4: alt_tau = 10'd256;  default: alt_tau = 10'd257;
    endcase
endfunction
function automatic logic [1:0] alt_grp(input logic [2:0] a);
    case (a)
        3'd0: alt_grp = 2'd1;  3'd1: alt_grp = 2'd0;   // 64 con W 256 ; 65 con W 128
        3'd2: alt_grp = 2'd2;  3'd3: alt_grp = 2'd1;   // 128 con 512  ; 129 con 256
        3'd4: alt_grp = 2'd3;  default: alt_grp = 2'd2; // 256 con 1024 ; 257 con 512
    endcase
endfunction

logic       div_go, div_done;
logic       scan_end;                      // la ultima LAG paso por la etapa de busqueda

always_comb begin
    i_op   = OP_NONE;
    i_ai   = pre_cnt[2:0];
    i_last = 1'b0;
    for (int j = 0; j < N; j++) begin
        i_tau[j] = tau0 + LANE_W'(j);
        i_grp[j] = grp_of_tau(tau0 + LANE_W'(j));
    end
    if (qs == Q_PRE) begin
        if (pre_cnt < 4'd4) begin
            i_op     = OP_TAP;
            i_ai     = pre_cnt[2:0];
            i_tau[0] = LANE_W'(0);
            i_grp[0] = pre_cnt[1:0];
        end else begin
            i_op     = OP_ALT;
            i_ai     = 3'(pre_cnt - 4'd4);
            i_tau[0] = alt_tau(3'(pre_cnt - 4'd4));
            i_grp[0] = alt_grp(3'(pre_cnt - 4'd4));
        end
    end else if (qs == Q_SWEEP) begin
        i_op   = OP_LAG;
        i_last = (tau0 == LANE_W'(TAU_MAX - N + 1));
    end
end

always_ff @(posedge clk) begin
    if (!rst_n || clr_busy) begin
        qs      <= Q_IDLE;
        n_ptr   <= 11'd2047;
        hop_cnt <= 4'd15;
        busca   <= 1'b0;
        xn      <= '0;
        pre_cnt <= '0;
        tau0    <= LANE_W'(1);
        div_go  <= 1'b0;
        overrun <= 1'b0;
    end else begin
        div_go <= 1'b0;
        if (y_push && qs != Q_IDLE) overrun <= 1'b1;
        case (qs)
            Q_IDLE: if (y_push) begin
                n_ptr   <= n_ptr + 11'd1;
                hop_cnt <= hop_cnt + 4'd1;
                busca   <= (hop_cnt + 4'd1 == 4'(HOP - 1));
                xn      <= y16;
                pre_cnt <= '0;
                qs      <= Q_PRE;
            end
            Q_PRE: begin
                pre_cnt <= pre_cnt + 4'd1;
                if (pre_cnt == 4'd9) begin
                    tau0 <= LANE_W'(1);
                    qs   <= Q_SWEEP;
                end
            end
            Q_SWEEP: begin
                tau0 <= tau0 + LANE_W'(N);
                if (i_last) qs <= Q_DRAIN;
            end
            Q_DRAIN: if (scan_end) begin
                if (busca) begin
                    div_go <= 1'b1;
                    qs     <= Q_DIV;
                end else begin
                    qs <= Q_IDLE;
                end
            end
            Q_DIV: if (div_done) qs <= Q_IDLE;
            default: qs <= Q_IDLE;
        endcase
    end
end

assign busy = (qs != Q_IDLE);

// =============================================================================
// ANILLO X ENTRELAZADO (N bancos, 2 puertos de lectura cada uno)
// =============================================================================

// direcciones de cada carril (c0)
logic [10:0] addrA [N];
logic [10:0] addrB [N];
logic [LOGN > 0 ? LOGN-1 : 0 : 0] rot_c0;

always_comb begin
    for (int j = 0; j < N; j++) begin
        addrA[j] = n_ptr - 11'(i_tau[j]);
        addrB[j] = n_ptr - w_of_grp(i_grp[j]) - 11'(i_tau[j]);
    end
    if (i_op == OP_TAP) addrA[0] = n_ptr - w_of_grp(i_grp[0]);
end

generate if (LOGN > 0) begin : g_rot
    assign rot_c0 = addrA[0][LOGN-1:0];          // banco del carril 0; el carril j va al (rot - j) mod N
end else begin : g_rot1
    assign rot_c0 = 1'b0;
end endgenerate

logic signed [15:0] bank_qa [N];
logic signed [15:0] bank_qb [N];

genvar gb;
generate for (gb = 0; gb < N; gb++) begin : g_bank
    (* ram_style = "block" *) logic signed [15:0] mem [0:DEPX-1];
    logic [10:0] ra, rb;
    logic        we;
    logic [10:0] wa;
    logic signed [15:0] wd;
    always_comb begin
        ra = addrA[0];
        rb = addrB[0];
        for (int j = 0; j < N; j++) begin
            if (((2'(rot_c0) - 2'(j)) & 2'(N - 1)) == 2'(gb)) begin
                ra = addrA[j];
                rb = addrB[j];
            end
        end
        we = 1'b0; wa = n_ptr + 11'd1; wd = y16;
        if (clr_busy) begin
            we = 1'b1; wd = '0;
        end else if (qs == Q_IDLE && y_push && ((n_ptr + 11'd1) % 11'(N)) == 11'(gb)) begin
            we = 1'b1;
        end
    end
    always_ff @(posedge clk) begin
        if (we) begin
            if (clr_busy) begin
                if (int'(clr_addr) < DEPX) mem[clr_addr[XA-1:0]] <= wd;
            end else begin
                mem[XA'(wa >> LOGN)] <= wd;
            end
            bank_qa[gb] <= '0;
        end else begin
            bank_qa[gb] <= mem[XA'(ra >> LOGN)];
        end
        bank_qb[gb] <= mem[XA'(rb >> LOGN)];
    end
end endgenerate

// =============================================================================
// PIPELINE DE LOS CARRILES
//   c0 direcciones -> c1 BRAM -> c2 datos al carril -> c3 dn, do -> c4 u, v
//   -> c5 (lectura d) / producto -> c7 d nuevo -> busqueda c8..c11
// =============================================================================

localparam int PL = 12;

op_t               p_op   [PL];
logic [LANE_W-1:0] p_tau  [PL][N];
logic [1:0]        p_grp  [PL][N];
logic [2:0]        p_ai   [PL];
logic              p_last [PL];
logic [LOGN > 0 ? LOGN-1 : 0 : 0] p_rot [3];

always_ff @(posedge clk) begin
    if (!rst_n || clr_busy) begin
        for (int s = 0; s < PL; s++) begin
            p_op[s] <= OP_NONE; p_ai[s] <= '0; p_last[s] <= 1'b0;
            for (int j = 0; j < N; j++) begin p_tau[s][j] <= '0; p_grp[s][j] <= '0; end
        end
        for (int s = 0; s < 3; s++) p_rot[s] <= '0;
    end else begin
        p_op[0] <= i_op; p_ai[0] <= i_ai; p_last[0] <= i_last;
        for (int j = 0; j < N; j++) begin p_tau[0][j] <= i_tau[j]; p_grp[0][j] <= i_grp[j]; end
        p_rot[0] <= rot_c0;
        for (int s = 1; s < 3; s++) p_rot[s] <= p_rot[s-1];
        for (int s = 1; s < PL; s++) begin
            p_op[s] <= p_op[s-1]; p_ai[s] <= p_ai[s-1]; p_last[s] <= p_last[s-1];
            for (int j = 0; j < N; j++) begin p_tau[s][j] <= p_tau[s-1][j]; p_grp[s][j] <= p_grp[s-1][j]; end
        end
    end
end
// indice s del arreglo = etapa c(s+1): p_*[0] = c1, p_*[1] = c2, ...

// ---- c2: datos de los bancos al carril --------------------------------------
logic signed [15:0] xa [N];      // x[n - tau]
logic signed [15:0] xb [N];      // x[n - W - tau]
logic signed [15:0] xw [4];      // x[n - W_g]

always_ff @(posedge clk) begin
    for (int j = 0; j < N; j++) begin
        xa[j] <= bank_qa[IW'((2'(p_rot[0]) - 2'(j)) & 2'(N - 1))];
        xb[j] <= bank_qb[IW'((2'(p_rot[0]) - 2'(j)) & 2'(N - 1))];
    end
end

always_ff @(posedge clk) begin
    if (!rst_n || clr_busy) begin
        for (int g = 0; g < 4; g++) xw[g] <= '0;
    end else if (p_op[1] == OP_TAP) begin
        xw[p_ai[1][1:0]] <= xa[0];
    end
end

// ---- c3: dn, do ; c4: u, v ; c5..c7: producto -------------------------------
logic signed [16:0] dn  [N];
logic signed [16:0] dd  [N];
logic signed [17:0] u   [N];
logic signed [17:0] v   [N];
(* use_dsp = "yes" *) logic signed [35:0] pm1 [N];
logic signed [35:0] pm2 [N];

always_ff @(posedge clk) begin
    for (int j = 0; j < N; j++) begin
        dn[j]  <= 17'(xn) - 17'(xa[j]);
        dd[j]  <= 17'(xw[p_grp[1][j]]) - 17'(xb[j]);
        u[j]   <= 18'(dn[j]) - 18'(dd[j]);
        v[j]   <= 18'(dn[j]) + 18'(dd[j]);
        pm1[j] <= u[j] * v[j];
        pm2[j] <= pm1[j];
    end
end
// dn/dd en c3 (p_*[2]), u/v en c4 (p_*[3]), pm1 en c5 (p_*[4]), pm2 en c6 (p_*[5])

// ---- memoria d(tau) por carril (lectura en c5, escritura en c7) --------------
localparam int DW = 45;
localparam int DA = $clog2(DEPD);

logic signed [DW-1:0] d_rd   [N];        // c6
logic signed [DW-1:0] d_new  [N];        // c7
logic signed [DW-1:0] alt_dr [6];
logic signed [DW-1:0] alt_rd;            // c6

genvar gl;
generate for (gl = 0; gl < N; gl++) begin : g_dmem
    (* ram_style = "block" *) logic signed [DW-1:0] dmem [0:DEPD-1];
    logic [DA-1:0] ra_d, wa_d;
    logic          we_d;
    logic signed [DW-1:0] wd_d;
    always_comb begin
        // indice del lag tau en su carril: (tau - 1) / N
        ra_d = DA'((p_tau[4][gl] - 10'd1) >> LOGN);     // se lee al final de c5 -> d_rd valido en c6
        wa_d = DA'((p_tau[5][gl] - 10'd1) >> LOGN);     // c7
        we_d = (p_op[5] == OP_LAG);
        wd_d = 45'(d_rd[gl]) + 45'(pm2[gl]);
        if (clr_busy) begin
            we_d = (int'(clr_addr) < DEPD); wa_d = clr_addr[DA-1:0]; wd_d = '0;
        end
    end
    always_ff @(posedge clk) begin
        if (we_d) dmem[wa_d] <= wd_d;
        d_rd[gl] <= dmem[ra_d];
    end
    always_ff @(posedge clk) d_new[gl] <= wd_d;
end endgenerate

// lags de frontera (registros)
always_ff @(posedge clk) begin
    if (!rst_n || clr_busy) begin
        for (int a = 0; a < 6; a++) alt_dr[a] <= '0;
        alt_rd <= '0;
    end else begin
        alt_rd <= alt_dr[p_ai[4]];
        if (p_op[5] == OP_ALT) alt_dr[p_ai[5]] <= alt_rd + 45'(pm2[0]);
    end
end

// =============================================================================
// BUSQUEDA (solo en los barridos con busca = 1)
//   c7 d_new -> c8 dh, S, dk -> c9/c10 tau*dk, 19*(S>>k) -> c11 test -> escaneo
// =============================================================================

logic [5:0] kshift;                       // bloque: k
logic [51:0] s_acc;                       // S acumulado del barrido

logic [42:0] dh8  [N];                    // c8
logic [51:0] s8   [N];
logic [23:0] dk8  [N];
(* use_dsp = "yes" *) logic [33:0] cl9 [N];
logic [33:0] cl10 [N];
logic [51:0] sk9  [N];
logic [56:0] rhs10 [N];
logic [42:0] dh9 [N], dh10 [N], dh11 [N];
logic [51:0] sk10 [N], sk11 [N];
logic [33:0] cl11 [N];
logic        hit11 [N];
logic [42:0] alt_hi [3], alt_lo [3];      // valores normalizados para el escaneo

// THETA_NUM * x con sumas (THETA_NUM es constante: se sintetiza como sumadores)
function automatic logic [56:0] mul_theta(input logic [51:0] x);
    mul_theta = '0;
    for (int b = 0; b < 5; b++)
        if (THETA_NUM[b]) mul_theta = mul_theta + (57'(x) << b);
endfunction

function automatic logic [42:0] norm(input logic signed [DW-1:0] d, input logic [1:0] g);
    logic [DW+2:0] t;
    t = {3'b000, d} << (2'd3 - g);
    norm = t[42:0];
endfunction

always_comb begin
    // d(b) con la ventana de b+1 (grupo g+1) y d(b+1) con la de b (grupo g)
    for (int i = 0; i < 3; i++) begin
        alt_hi[i] = norm(alt_dr[2*i],   2'(i + 1));
        alt_lo[i] = norm(alt_dr[2*i+1], 2'(i));
    end
end

always_ff @(posedge clk) begin : srch_pipe
    logic [51:0] sc;
    logic [42:0] dhv;
    logic [42:0] dks;
    if (!rst_n || clr_busy || qs == Q_PRE) begin
        s_acc <= '0;
        for (int j = 0; j < N; j++) begin
            dh8[j] <= '0; s8[j] <= '0; dk8[j] <= '0;
        end
    end else begin
        sc = s_acc;
        for (int j = 0; j < N; j++) begin
            dhv = norm(d_new[j], p_grp[6][j]);           // c7 -> c8
            sc  = sc + 52'(dhv);
            dh8[j] <= dhv;
            s8[j]  <= sc;
            dks = dhv >> kshift;
            dk8[j] <= (dks > 43'd8388607) ? 24'd8388607 : dks[23:0];
        end
        if (p_op[6] == OP_LAG) s_acc <= sc;
    end
    for (int j = 0; j < N; j++) begin
        cl9[j]   <= 34'(p_tau[7][j]) * 34'(dk8[j]);    // c9
        cl10[j]  <= cl9[j];
        sk9[j]   <= s8[j] >> kshift;
        rhs10[j] <= mul_theta(sk9[j]);
        sk10[j]  <= sk9[j];
        dh9[j]   <= dh8[j];
        dh10[j]  <= dh9[j];
        // c11
        hit11[j] <= (p_tau[9][j] >= LANE_W'(TAU_MIN)) && ((57'(cl10[j]) << 7) < rhs10[j]);
        dh11[j]  <= dh10[j];
        cl11[j]  <= cl10[j];
        sk11[j]  <= sk10[j];
    end
end

// ---- escaneo (c11): carriles en orden de tau --------------------------------
logic [1:0]         fase;
logic [LANE_W-1:0]  t_sel;
logic [42:0]        dm_r, d0_r, dp_r, dprev_r;
logic [33:0]        cl_r;
logic [51:0]        cr_r;
logic               scan_on;

assign scan_on  = (p_op[10] == OP_LAG) && busca;
assign scan_end = (p_op[10] == OP_LAG) && p_last[10];

always_ff @(posedge clk) begin : scan_blk
    logic [1:0]        f;
    logic [LANE_W-1:0] t;
    logic [42:0]       dm, d0, dp, dprev, pm, aa;
    logic [33:0]       cl;
    logic [51:0]       cr;
    logic [LANE_W-1:0] tau;
    if (!rst_n || clr_busy || qs == Q_PRE) begin
        fase <= 2'd0; t_sel <= '0; dm_r <= '0; d0_r <= '0; dp_r <= '0; dprev_r <= '0;
        cl_r <= '0; cr_r <= '0;
    end else if (scan_on) begin
        f = fase; t = t_sel; dm = dm_r; d0 = d0_r; dp = dp_r; dprev = dprev_r; cl = cl_r; cr = cr_r;
        for (int j = 0; j < N; j++) begin
            tau = p_tau[10][j];
            pm  = dprev;            // d(tau-1) con la ventana de tau
            aa  = dh11[j];          // d(tau)   con la ventana de tau-1
            if (j == 0) begin
                if (tau == 10'd65)  begin pm = alt_hi[0]; aa = alt_lo[0]; end
                if (tau == 10'd129) begin pm = alt_hi[1]; aa = alt_lo[1]; end
                if (tau == 10'd257) begin pm = alt_hi[2]; aa = alt_lo[2]; end
            end
            if (f == 2'd0) begin
                if (hit11[j]) begin
                    f = 2'd1; t = tau; dm = pm; d0 = dh11[j]; cl = cl11[j]; cr = sk11[j];
                end
            end else if (f == 2'd1) begin
                if (aa < d0) begin
                    t = tau; dm = pm; d0 = dh11[j]; cl = cl11[j]; cr = sk11[j];
                end else begin
                    dp = aa; f = 2'd2;
                end
            end
            dprev = dh11[j];
        end
        fase <= f; t_sel <= t; dm_r <= dm; d0_r <= d0; dp_r <= dp; dprev_r <= dprev; cl_r <= cl; cr_r <= cr;
    end
end

// =============================================================================
// FIN DEL BARRIDO: bloque k, division, salida
// =============================================================================

logic [5:0]  bl;                          // bitlen(s_acc)
always_comb begin
    bl = 6'd0;
    for (int i = 0; i < 52; i++) if (s_acc[i]) bl = 6'(i + 1);
end

typedef enum logic [1:0] { D_IDLE, D_RUN, D_OUT } dstate_t;
dstate_t      ds;
logic [3:0]   dcnt;
logic [46:0]  drem;
logic [43:0]  dden;
logic [14:0]  dq;
logic         dneg, dsat, dzero;

always_ff @(posedge clk) begin : div_blk
    logic signed [44:0] num, den;
    logic [44:0]        anum;
    logic [46:0]        r2;
    if (!rst_n || clr_busy) begin
        ds <= D_IDLE; dcnt <= '0; drem <= '0; dden <= '0; dq <= '0;
        dneg <= 1'b0; dsat <= 1'b0; dzero <= 1'b0;
        div_done <= 1'b0; period_valid <= 1'b0; period_16_16 <= '0;
        conf_cl <= '0; conf_cr <= '0; kshift <= '0;
    end else begin
        div_done     <= 1'b0;
        period_valid <= 1'b0;
        case (ds)
            D_IDLE: if (div_go) begin
                kshift <= (bl > 6'(KBITS)) ? 6'(bl - 6'(KBITS)) : 6'd0;
                num  = 45'(dm_r) - 45'(dp_r);
                den  = 45'(dm_r) - (45'(d0_r) << 1) + 45'(dp_r);
                anum  = num[44] ? 45'(-num) : 45'(num);
                dneg  <= num[44];
                dzero <= (den <= 0);
                dsat  <= (den > 0) && ($signed({1'b0, anum}) >= 46'(den));
                drem  <= {2'b00, anum};
                dden  <= den[43:0];
                dq    <= '0;
                dcnt  <= '0;
                if (fase == 2'd2) ds <= D_RUN;
                else              div_done <= 1'b1;      // sin estimacion
            end
            D_RUN: begin
                r2 = drem << 1;
                if (r2 >= 47'(dden)) begin
                    drem <= r2 - 47'(dden);
                    dq   <= {dq[13:0], 1'b1};
                end else begin
                    drem <= r2;
                    dq   <= {dq[13:0], 1'b0};
                end
                dcnt <= dcnt + 4'd1;
                if (dcnt == 4'd14) ds <= D_OUT;
            end
            D_OUT: begin : out_blk
                logic [15:0] q;
                logic signed [31:0] fr;
                q  = dzero ? 16'd0 : dsat ? 16'd32768 : {1'b0, dq};
                fr = dneg ? -32'(q) : 32'(q);
                period_16_16 <= ({22'd0, t_sel} << 16) + fr;
                conf_cl      <= cl_r;
                conf_cr      <= cr_r;
                period_valid <= 1'b1;
                div_done     <= 1'b1;
                ds           <= D_IDLE;
            end
            default: ds <= D_IDLE;
        endcase
    end
end

endmodule
