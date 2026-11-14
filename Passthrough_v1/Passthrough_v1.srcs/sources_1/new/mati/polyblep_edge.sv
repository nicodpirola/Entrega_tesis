// polyblep_edge.sv
// Correccion PolyBLEP de un salto (edge) de la forma de onda.
//
// Sea dt = phase_inc (lo que avanza la fase en una muestra) y d la distancia de la
// fase al salto, en muestras:
//   despues del salto (d = (phase - edge)/dt < 1):  c = -(1 - d)^2
//   antes del salto   (d = (edge - phase)/dt < 1):  c = +(1 - d)^2
//   lejos del salto:                                c = 0
// Son los dos tramos del polinomio de 2do orden: 2d - d^2 - 1 = -(1 - d)^2 despues
// del salto y d^2 - 2d + 1 = (1 - d)^2 antes, asi alcanza con un solo cuadrado.
//
// La division d = distancia/dt la hace frac_div_u32 (restoring, sin DSP).
// El cuadrado usa un multiplicador de 32x32 bits (mul32_seq, 1 DSP48).

`timescale 1ns/1ps

module polyblep_edge(
    input  logic               clk,
    input  logic               rst_n,

    input  logic               in_valid,
    output logic               in_ready,
    input  logic        [31:0] phase,
    input  logic        [31:0] edge_phase,
    input  logic        [31:0] phase_inc,

    output logic               out_valid,
    input  logic               out_ready,
    output logic signed [31:0] correction_q31
);

    //estados
    typedef enum logic [2:0] {
        ST_IDLE,
        ST_DIV_REQ,
        ST_DIV_WAIT,
        ST_LOAD_SQ,
        ST_MUL_SQ,
        ST_HOLD
    } state_t;

    state_t state;

    //distancias modulares al salto (la resta de 32 bits sin signo da la vuelta sola)
    logic [31:0] d_after;
    logic [31:0] d_before;

    logic [31:0] div_num;
    logic [31:0] div_den;
    logic        negative_side;

    //divisor
    logic        div_in_valid;
    logic        div_in_ready;
    logic        div_out_valid;
    logic        div_out_ready;
    logic [31:0] div_quotient_q31;

    logic [31:0] delta_q31;      //1 - d, de 0 a 1 inclusive (UQ1.31)
    logic [31:0] magnitude_q31;  //(1 - d)^2

    //multiplicador compartido
    logic signed [31:0] mul_a_reg;
    logic signed [31:0] mul_b_reg;
    logic               mul_start;
    logic               mul_valid;
    logic signed [63:0] mul_p;

    //instancias
    frac_div_u32 u_div (
        .clk          (clk             ),
        .rst_n        (rst_n           ),
        .in_valid     (div_in_valid    ),
        .in_ready     (div_in_ready    ),
        .numerator    (div_num         ),
        .denominator  (div_den         ),
        .out_valid    (div_out_valid   ),
        .out_ready    (div_out_ready   ),
        .quotient_q31 (div_quotient_q31)
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
    assign d_after  = phase - edge_phase;
    assign d_before = edge_phase - phase;

    assign div_in_valid  = (state == ST_DIV_REQ);
    assign div_out_ready = (state == ST_DIV_WAIT);

    //delta va de 0 a 2^31: con signo 2^31 se lee -2^31, pero su cuadrado (2^62) es el mismo
    assign magnitude_q31 = mul_p[62:31];

    assign in_ready  = (state == ST_IDLE);
    assign out_valid = (state == ST_HOLD);

    //logica secuencial y FSM
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            div_num        <= '0;
            div_den        <= '0;
            negative_side  <= 1'b0;
            delta_q31      <= '0;
            mul_a_reg      <= '0;
            mul_b_reg      <= '0;
            mul_start      <= 1'b0;
            correction_q31 <= '0;
        end
        else begin
            mul_start <= 1'b0; //pulso de un ciclo

            case (state)
                ST_IDLE: begin
                    if (in_valid && in_ready) begin
                        if ((phase_inc == 32'd0) || (phase_inc >= 32'h8000_0000)) begin
                            correction_q31 <= 32'sd0;
                            state          <= ST_HOLD;
                        end
                        //justo en el salto d_after y d_before valen 0: se toma el lado
                        //de despues, que da la correccion -1
                        else if (d_after < phase_inc) begin
                            div_num       <= d_after;
                            div_den       <= phase_inc;
                            negative_side <= 1'b1;
                            state         <= ST_DIV_REQ;
                        end
                        else if (d_before < phase_inc) begin
                            div_num       <= d_before;
                            div_den       <= phase_inc;
                            negative_side <= 1'b0;
                            state         <= ST_DIV_REQ;
                        end
                        else begin
                            correction_q31 <= 32'sd0;
                            state          <= ST_HOLD;
                        end
                    end
                end

                ST_DIV_REQ: begin
                    if (div_in_valid && div_in_ready) state <= ST_DIV_WAIT;
                end

                ST_DIV_WAIT: begin //1 - d
                    if (div_out_valid && div_out_ready) begin
                        delta_q31 <= 32'h8000_0000 - div_quotient_q31;
                        state     <= ST_LOAD_SQ;
                    end
                end

                ST_LOAD_SQ: begin //(1 - d)^2
                    mul_a_reg <= $signed(delta_q31);
                    mul_b_reg <= $signed(delta_q31);
                    mul_start <= 1'b1;
                    state     <= ST_MUL_SQ;
                end

                ST_MUL_SQ: begin
                    //con d = 0 la magnitud es 0x8000_0000 y su negativo da el mismo
                    //valor, que en Q1.31 es -1: la correccion maxima sale sola
                    if (mul_valid) begin
                        if (negative_side) correction_q31 <= $signed(~magnitude_q31 + 32'd1);
                        else               correction_q31 <= $signed(magnitude_q31);
                        state <= ST_HOLD;
                    end
                end

                ST_HOLD: begin
                    if (out_valid && out_ready) state <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
