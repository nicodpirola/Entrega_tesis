// synth_svf_coef.sv
// Coeficientes del pasabajos del synth calculados en cada muestra, con seguimiento de
// nota y contorno por volumen.
//
// x  = inc/2^32 * corte * (1 + contorno * env)     frecuencia de corte / fs
// g  = tan(pi * x)                                  tabla de 512 puntos + interpolacion lineal
// a1 = 1 / (1 + g*(g + k)),  a2 = g*a1,  a3 = g*a2  (SVF TPT, Zavalishin cap. 4)
//
// El corte se limita entre 20 Hz y 0,40 fs. La division la hace frac_div_u32 (sin DSP).
// Un multiplicador de 32x32 bits (mul32_seq, 1 DSP48) compartido por una FSM: 7 productos.

`timescale 1ns/1ps

module synth_svf_coef(
    input  logic               clk,
    input  logic               rst_n,

    input  logic               start,
    output logic               ready,
    output logic               coef_valid,
    output logic signed [31:0] a1_q1_31,
    output logic signed [31:0] a2_q1_31,
    output logic signed [31:0] a3_q1_31,

    input  logic        [31:0] base_phase_inc,
    input  logic signed [31:0] env_q1_31,
    input  logic signed [31:0] track_q5_27,
    input  logic signed [31:0] contour_q3_29,
    input  logic signed [31:0] k_q3_29
);

    import fx_dsp_pkg::*;

    localparam logic signed [31:0] X_MIN_U32 = 32'sd1789570;     //20 Hz / 48 kHz * 2^32
    localparam logic signed [31:0] X_MAX_U32 = 32'sd1717986918;  //0,40 * 2^32 (g + k/2 entra en 32 bits)
    localparam logic signed [31:0] K_MAX_Q29 = 32'sh4000_0000;   //k = 1/Q <= 2 (Q >= 0,5)
    localparam logic        [31:0] UNO_Q26   = 32'h0400_0000;

    //estados
    typedef enum logic [4:0] {
        ST_IDLE,
        ST_LOAD_TRACK,
        ST_MUL_TRACK,
        ST_LOAD_CONT,
        ST_MUL_CONT,
        ST_LOAD_X,
        ST_MUL_X,
        ST_ROM_A,
        ST_ROM_B,
        ST_LOAD_INTERP,
        ST_MUL_INTERP,
        ST_LOAD_DEN,
        ST_MUL_DEN,
        ST_DIV_REQ,
        ST_DIV_WAIT,
        ST_LOAD_A2,
        ST_MUL_A2,
        ST_LOAD_A3,
        ST_MUL_A3
    } state_t;

    state_t state;

    //copias de los parametros
    logic signed [31:0] inc_reg;
    logic signed [31:0] env_reg;
    logic signed [31:0] track_reg;
    logic signed [31:0] contour_reg;
    logic signed [31:0] k_reg;

    //valores intermedios
    logic signed [31:0] x_reg;          //frecuencia de corte / fs, UQ0.32 (siempre < 2^31)
    logic signed [31:0] factor_reg;     //1 + contorno*env, Q4.28
    logic signed [31:0] t0_reg;         //tan en el punto i de la tabla
    logic signed [31:0] g_reg;          //Q4.28
    logic        [31:0] den_reg;        //1 + g(g+k), UQ6.26
    logic signed [31:0] a1_reg;
    logic signed [31:0] a2_reg;

    //tabla
    logic        [8:0]  rom_addr;
    logic        [31:0] rom_data;

    //divisor
    logic               div_in_valid;
    logic               div_in_ready;
    logic               div_out_valid;
    logic        [31:0] div_quotient;

    //multiplicador compartido
    logic signed [31:0] mul_a_reg;
    logic signed [31:0] mul_b_reg;
    logic               mul_start;
    logic               mul_valid;
    logic signed [63:0] mul_p;

    //resultados combinacionales
    logic signed [63:0] x_track_next;
    logic signed [31:0] ce_next;
    logic signed [63:0] x_mod_next;
    logic signed [31:0] x_next;
    logic signed [31:0] interp_next;
    logic signed [31:0] gk_next;
    logic        [31:0] den_next;

    //redondeo: suma media unidad del ultimo bit y desplaza
    function automatic logic signed [63:0] round_shift(input logic signed [63:0] v, input int sh);
        round_shift = (v + (64'sd1 <<< (sh - 1))) >>> sh;
    endfunction

    //instancias
    synth_tan_rom u_tabla (
        .clk  (clk     ),
        .addr (rom_addr),
        .data (rom_data)
    );

    frac_div_u32 u_div (
        .clk          (clk          ),
        .rst_n        (rst_n        ),
        .in_valid     (div_in_valid ),
        .in_ready     (div_in_ready ),
        .numerator    (UNO_Q26      ),
        .denominator  (den_reg      ),
        .out_valid    (div_out_valid),
        .out_ready    (1'b1         ),
        .quotient_q31 (div_quotient )
    );

    mul32_seq u_mul (
        .clk   (clk      ),
        .rst_n (rst_n    ),
        .start (mul_start),
        .a     (mul_a_reg),
        .b     (mul_b_reg),
        .busy  (         ),
        .valid (mul_valid),
        .p     (mul_p    )
    );

    //assigns
    assign ready        = (state == ST_IDLE);
    assign div_in_valid = (state == ST_DIV_REQ);

    //logica combinacional
    always_comb begin
        //x = inc * corte (Q5.27), limitado a 0,45 fs
        x_track_next = round_shift(mul_p, 27);
        if (x_track_next > 64'(X_MAX_U32)) x_track_next = 64'(X_MAX_U32);

        //contorno * env en Q3.29
        ce_next = sat32(round_shift(mul_p, 31));

        //x * (1 + contorno*env), limitado entre 20 Hz y 0,45 fs
        x_mod_next = round_shift(mul_p, 28);
        if (x_mod_next > 64'(X_MAX_U32))      x_next = X_MAX_U32;
        else if (x_mod_next < 64'(X_MIN_U32)) x_next = X_MIN_U32;
        else                                  x_next = x_mod_next[31:0];

        //(t1 - t0) * fraccion
        interp_next = sat32(round_shift(mul_p, 31));

        gk_next  = g_reg + (k_reg >>> 1);                        //g + k en Q4.28
        den_next = UNO_Q26 + 32'(round_shift(mul_p, 30));         //1 + g(g+k) en UQ6.26 (< 2^32)
    end

    //logica secuencial y FSM
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state       <= ST_IDLE;
            inc_reg     <= '0;
            env_reg     <= '0;
            track_reg   <= '0;
            contour_reg <= '0;
            k_reg       <= '0;
            x_reg       <= '0;
            factor_reg  <= '0;
            t0_reg      <= '0;
            g_reg       <= '0;
            den_reg     <= '0;
            a1_reg      <= '0;
            a2_reg      <= '0;
            rom_addr    <= '0;
            mul_a_reg   <= '0;
            mul_b_reg   <= '0;
            mul_start   <= 1'b0;
            coef_valid  <= 1'b0;
            a1_q1_31    <= 32'sh7FFF_FFFF;   //hasta el primer calculo: filtro abierto en continua
            a2_q1_31    <= '0;
            a3_q1_31    <= '0;
        end
        else begin
            mul_start <= 1'b0; //pulso de un ciclo

            case (state)
                ST_IDLE: begin
                    if (start) begin //copia y limita los parametros de la muestra
                        inc_reg     <= base_phase_inc[31] ? 32'sh7FFF_FFFF : $signed(base_phase_inc);
                        env_reg     <= (env_q1_31 < 0)     ? 32'sd0 : env_q1_31;
                        track_reg   <= (track_q5_27 < 0)   ? 32'sd0 : track_q5_27;
                        contour_reg <= (contour_q3_29 < 0) ? 32'sd0 : contour_q3_29;
                        if (k_q3_29 < 0)              k_reg <= 32'sd0;
                        else if (k_q3_29 > K_MAX_Q29) k_reg <= K_MAX_Q29;
                        else                          k_reg <= k_q3_29;
                        coef_valid  <= 1'b0;
                        state       <= ST_LOAD_TRACK;
                    end
                end

                ST_LOAD_TRACK: begin //inc * corte
                    mul_a_reg <= inc_reg;
                    mul_b_reg <= track_reg;
                    mul_start <= 1'b1;
                    state     <= ST_MUL_TRACK;
                end

                ST_MUL_TRACK: begin
                    if (mul_valid) begin
                        x_reg <= x_track_next[31:0];
                        state <= ST_LOAD_CONT;
                    end
                end

                ST_LOAD_CONT: begin //contorno * env
                    mul_a_reg <= contour_reg;
                    mul_b_reg <= env_reg;
                    mul_start <= 1'b1;
                    state     <= ST_MUL_CONT;
                end

                ST_MUL_CONT: begin
                    if (mul_valid) begin
                        factor_reg <= 32'sh1000_0000 + (ce_next >>> 1); //1 + contorno*env en Q4.28
                        state      <= ST_LOAD_X;
                    end
                end

                ST_LOAD_X: begin //x * factor
                    mul_a_reg <= x_reg;
                    mul_b_reg <= factor_reg;
                    mul_start <= 1'b1;
                    state     <= ST_MUL_X;
                end

                ST_MUL_X: begin
                    if (mul_valid) begin
                        x_reg    <= x_next;
                        rom_addr <= x_next[30:22]; //indice de la tabla: x * 1024
                        state    <= ST_ROM_A;
                    end
                end

                ST_ROM_A: begin //la tabla lee tan(i)
                    rom_addr <= rom_addr + 9'd1;
                    state    <= ST_ROM_B;
                end

                ST_ROM_B: begin //llega tan(i); la tabla lee tan(i+1)
                    t0_reg <= $signed(rom_data);
                    state  <= ST_LOAD_INTERP;
                end

                ST_LOAD_INTERP: begin //(tan(i+1) - tan(i)) * fraccion
                    mul_a_reg <= $signed(rom_data) - t0_reg;
                    mul_b_reg <= $signed({1'b0, x_reg[21:0], 9'd0});
                    mul_start <= 1'b1;
                    state     <= ST_MUL_INTERP;
                end

                ST_MUL_INTERP: begin
                    if (mul_valid) begin
                        g_reg <= t0_reg + interp_next;
                        state <= ST_LOAD_DEN;
                    end
                end

                ST_LOAD_DEN: begin //g * (g + k)
                    mul_a_reg <= g_reg;
                    mul_b_reg <= gk_next;
                    mul_start <= 1'b1;
                    state     <= ST_MUL_DEN;
                end

                ST_MUL_DEN: begin
                    if (mul_valid) begin
                        den_reg <= den_next;
                        state   <= ST_DIV_REQ;
                    end
                end

                ST_DIV_REQ: begin //a1 = 1 / den
                    if (div_in_ready) state <= ST_DIV_WAIT;
                end

                ST_DIV_WAIT: begin
                    if (div_out_valid) begin
                        a1_reg <= $signed(div_quotient);
                        state  <= ST_LOAD_A2;
                    end
                end

                ST_LOAD_A2: begin //a2 = g * a1
                    mul_a_reg <= g_reg;
                    mul_b_reg <= a1_reg;
                    mul_start <= 1'b1;
                    state     <= ST_MUL_A2;
                end

                ST_MUL_A2: begin
                    if (mul_valid) begin
                        a2_reg <= sat32(round_shift(mul_p, 28));
                        state  <= ST_LOAD_A3;
                    end
                end

                ST_LOAD_A3: begin //a3 = g * a2
                    mul_a_reg <= g_reg;
                    mul_b_reg <= a2_reg;
                    mul_start <= 1'b1;
                    state     <= ST_MUL_A3;
                end

                ST_MUL_A3: begin //los tres coeficientes cambian juntos
                    if (mul_valid) begin
                        a1_q1_31   <= a1_reg;
                        a2_q1_31   <= a2_reg;
                        a3_q1_31   <= sat32(round_shift(mul_p, 28));
                        coef_valid <= 1'b1;
                        state      <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
