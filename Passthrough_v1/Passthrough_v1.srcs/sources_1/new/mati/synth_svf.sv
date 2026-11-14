// synth_svf.sv
// Pasabajos de dos polos del synth: filtro de estado variable (SVF) TPT, salida LP.
//
// v3 = x - ic2
// v1 = a1*ic1 + a2*v3                  (salida BP, solo se usa internamente)
// v2 = ic2 + a2*ic1 + a3*v3            (salida LP)
// ic1 = 2*v1 - ic1,  ic2 = 2*v2 - ic2  (estados de los integradores)
//
// g = tan(pi*fc/fs), k = 1/Q, a1 = 1/(1 + g*(g + k)), a2 = g*a1, a3 = g*a2
// (los coeficientes llegan de synth_svf_coef y pueden cambiar en cada muestra).
// Integradores trapezoidales, Zavalishin cap. 4.
//
// Con enable = 0 la salida es la entrada, pero el filtro sigue corriendo para que
// no haya un salto al prenderlo.
// Un multiplicador de 32x32 bits (mul32_seq, 1 DSP48) compartido por una FSM: 4 productos.

`timescale 1ns/1ps

module synth_svf(
    input  logic               clk,
    input  logic               rst_n,
    input  logic               clear_state,

    input  logic               in_valid,
    output logic               in_ready,
    input  logic signed [31:0] in_data,

    output logic               out_valid,
    input  logic               out_ready,
    output logic signed [31:0] out_data,

    input  logic               enable,
    input  logic signed [31:0] a1_q1_31,
    input  logic signed [31:0] a2_q1_31,
    input  logic signed [31:0] a3_q1_31
);

    import fx_dsp_pkg::*;

    //estados
    typedef enum logic [3:0] {
        ST_IDLE,
        ST_LOAD_A1_IC1,
        ST_MUL_A1_IC1,
        ST_LOAD_A2_V3,
        ST_MUL_A2_V3,
        ST_LOAD_A2_IC1,
        ST_MUL_A2_IC1,
        ST_LOAD_A3_V3,
        ST_MUL_A3_V3
    } state_t;

    state_t state;

    //copias de la muestra y de los parametros
    logic signed [31:0] sample_reg;
    logic signed [31:0] a1_reg;
    logic signed [31:0] a2_reg;
    logic signed [31:0] a3_reg;
    logic               enable_reg;

    //estados de los integradores y valores intermedios
    logic signed [31:0] ic1_reg;
    logic signed [31:0] ic2_reg;
    logic signed [31:0] v3_reg;
    logic signed [31:0] v1_reg;
    logic signed [31:0] term_reg;

    //multiplicador compartido
    logic signed [31:0] mul_a_reg;
    logic signed [31:0] mul_b_reg;
    logic               mul_start;
    logic               mul_valid;
    logic signed [63:0] mul_p;

    //resultados combinacionales
    logic signed [31:0] mul_result;      //producto por coeficiente Q1.31
    logic signed [31:0] v3_next;
    logic signed [31:0] v1_next;
    logic signed [31:0] v2_next;
    logic signed [31:0] ic1_next;
    logic signed [31:0] ic2_next;

    //buffer de salida
    logic signed [31:0] out_buf;
    logic               out_buf_valid;

    wire can_accept;
    wire in_fire;
    wire out_fire;

    //instancias
    mul32_seq u_mul (
        .clk   (clk                  ),
        .rst_n (rst_n && !clear_state), //clear tambien corta un producto en curso
        .start (mul_start            ),
        .a     (mul_a_reg            ),
        .b     (mul_b_reg            ),
        .busy  (                     ),
        .valid (mul_valid            ),
        .p     (mul_p                )
    );

    //assigns
    assign can_accept = (state == ST_IDLE) && !out_buf_valid && !clear_state;

    assign in_fire  = in_valid && in_ready;
    assign out_fire = out_valid && out_ready;

    assign in_ready  = can_accept;
    assign out_valid = out_buf_valid;
    assign out_data  = out_buf;

    //logica combinacional
    always_comb begin
        mul_result = sat32((mul_p + (64'sd1 <<< 30)) >>> 31);   //Q1.31 x Q1.31 -> Q1.31 con redondeo

        v3_next  = sat32(64'(in_data) - 64'(ic2_reg));                      //v3 = x - ic2
        v1_next  = sat32(64'(term_reg) + 64'(mul_result));                  //v1 = a1*ic1 + a2*v3
        v2_next  = sat32(64'(ic2_reg) + 64'(term_reg) + 64'(mul_result));   //v2 = ic2 + a2*ic1 + a3*v3
        ic1_next = sat32((64'sd2 * 64'(v1_reg)) - 64'(ic1_reg));            //ic1 = 2*v1 - ic1
        ic2_next = sat32((64'sd2 * 64'(v2_next)) - 64'(ic2_reg));           //ic2 = 2*v2 - ic2
    end

    //logica secuencial y FSM
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            sample_reg    <= '0;
            a1_reg        <= '0;
            a2_reg        <= '0;
            a3_reg        <= '0;
            enable_reg    <= 1'b0;
            ic1_reg       <= '0;
            ic2_reg       <= '0;
            v3_reg        <= '0;
            v1_reg        <= '0;
            term_reg      <= '0;
            mul_a_reg     <= '0;
            mul_b_reg     <= '0;
            mul_start     <= 1'b0;
            out_buf_valid <= 1'b0;
            out_buf       <= '0;
        end
        else if (clear_state) begin //borra los integradores y descarta la muestra en curso
            state         <= ST_IDLE;
            ic1_reg       <= '0;
            ic2_reg       <= '0;
            v3_reg        <= '0;
            v1_reg        <= '0;
            term_reg      <= '0;
            mul_a_reg     <= '0;
            mul_b_reg     <= '0;
            mul_start     <= 1'b0;
            out_buf_valid <= 1'b0;
            out_buf       <= '0;
        end
        else begin
            if (out_fire) out_buf_valid <= 1'b0;

            mul_start <= 1'b0; //pulso de un ciclo

            case (state)
                ST_IDLE: begin
                    if (in_fire) begin
                        sample_reg <= in_data;
                        a1_reg     <= a1_q1_31;
                        a2_reg     <= a2_q1_31;
                        a3_reg     <= a3_q1_31;
                        enable_reg <= enable;
                        v3_reg     <= v3_next;
                        state      <= ST_LOAD_A1_IC1;
                    end
                end

                ST_LOAD_A1_IC1: begin //a1 * ic1
                    mul_a_reg <= ic1_reg;
                    mul_b_reg <= a1_reg;
                    mul_start <= 1'b1;
                    state     <= ST_MUL_A1_IC1;
                end

                ST_MUL_A1_IC1: begin
                    if (mul_valid) begin
                        term_reg <= mul_result;
                        state    <= ST_LOAD_A2_V3;
                    end
                end

                ST_LOAD_A2_V3: begin //a2 * v3
                    mul_a_reg <= v3_reg;
                    mul_b_reg <= a2_reg;
                    mul_start <= 1'b1;
                    state     <= ST_MUL_A2_V3;
                end

                ST_MUL_A2_V3: begin
                    if (mul_valid) begin
                        v1_reg <= v1_next;
                        state  <= ST_LOAD_A2_IC1;
                    end
                end

                ST_LOAD_A2_IC1: begin //a2 * ic1
                    mul_a_reg <= ic1_reg;
                    mul_b_reg <= a2_reg;
                    mul_start <= 1'b1;
                    state     <= ST_MUL_A2_IC1;
                end

                ST_MUL_A2_IC1: begin
                    if (mul_valid) begin
                        term_reg <= mul_result;
                        state    <= ST_LOAD_A3_V3;
                    end
                end

                ST_LOAD_A3_V3: begin //a3 * v3
                    mul_a_reg <= v3_reg;
                    mul_b_reg <= a3_reg;
                    mul_start <= 1'b1;
                    state     <= ST_MUL_A3_V3;
                end

                ST_MUL_A3_V3: begin //actualiza los integradores y saca la muestra
                    if (mul_valid) begin
                        ic1_reg       <= ic1_next;
                        ic2_reg       <= ic2_next;
                        out_buf       <= enable_reg ? v2_next : sample_reg;
                        out_buf_valid <= 1'b1;
                        state         <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
