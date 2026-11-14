// synth_mixer.sv
// Mezcla de los dos osciladores del synth con nivel independiente y trim de bus.
//
// s[n] = osc1[n] * L1 + osc2[n] * L2       (suma ancha, saturada a Q3.29)
// y[n] = s[n] * trim
//
// Un multiplicador de 32x32 bits (mul32_seq, 1 DSP48) compartido por una FSM.

`timescale 1ns/1ps

module synth_mixer(
    input  logic               clk,
    input  logic               rst_n,

    input  logic               in_valid,
    output logic               in_ready,
    input  logic signed [31:0] in_osc1,
    input  logic signed [31:0] in_osc2,

    output logic               out_valid,
    input  logic               out_ready,
    output logic signed [31:0] out_data,

    input  logic        [31:0] osc1_level_q1_31,
    input  logic        [31:0] osc2_level_q1_31,
    input  logic        [31:0] bus_trim_q1_31,
    input  logic signed [31:0] t1_q3_29,

    output logic               overdrive,
    output logic               clip
);

    import fx_dsp_pkg::*;

    //estados
    typedef enum logic [3:0] {
        ST_IDLE,
        ST_LOAD_L1,
        ST_MUL_L1,
        ST_LOAD_L2,
        ST_MUL_L2,
        ST_SUM,
        ST_LIMIT,
        ST_LOAD_TRIM,
        ST_MUL_TRIM
    } state_t;

    state_t state;

    //copias de la muestra y de los parametros
    logic signed [31:0] osc1_reg;
    logic signed [31:0] osc2_reg;
    logic signed [31:0] level1_reg;
    logic signed [31:0] level2_reg;
    logic signed [31:0] trim_reg;
    logic signed [31:0] t1_reg;

    logic signed [31:0] weighted1_reg;
    logic signed [31:0] weighted2_reg;
    logic signed [32:0] sum_reg;
    logic signed [31:0] limited_reg;

    //multiplicador compartido
    logic signed [31:0] mul_a_reg;
    logic signed [31:0] mul_b_reg;
    logic               mul_start;
    logic               mul_valid;
    logic signed [63:0] mul_p;

    //resultados combinacionales
    logic signed [31:0] mul_result;
    logic signed [31:0] limited_next;
    logic signed [32:0] t1_ext;

    //buffer de salida
    logic signed [31:0] out_buf;
    logic               out_buf_valid;

    wire can_accept;
    wire in_fire;
    wire out_fire;

    //niveles sin signo de 0 a 1: si llega el bit 31 en 1 se limita a 1
    function automatic logic signed [31:0] safe_level(input logic [31:0] x);
        safe_level = x[31] ? 32'sh7FFF_FFFF : $signed(x);
    endfunction

    //instancias
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
    assign can_accept = (state == ST_IDLE) && !out_buf_valid;

    assign in_fire  = in_valid && in_ready;
    assign out_fire = out_valid && out_ready;

    assign in_ready  = can_accept;
    assign out_valid = out_buf_valid;
    assign out_data  = out_buf;

    //logica combinacional
    always_comb begin
        mul_result = sat32((mul_p + (64'sd1 <<< 30)) >>> 31); //Q3.29 x Q1.31 -> Q3.29, redondeo

        //limite numerico de la suma ancha a Q3.29
        if (sum_reg > 33'sd2147483647)       limited_next = 32'sh7FFF_FFFF;
        else if (sum_reg < -33'sd2147483648) limited_next = 32'sh8000_0000;
        else                                 limited_next = sum_reg[31:0];

        t1_ext = {t1_reg[31], t1_reg};
    end

    //logica secuencial y FSM
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            osc1_reg      <= '0;
            osc2_reg      <= '0;
            level1_reg    <= '0;
            level2_reg    <= '0;
            trim_reg      <= '0;
            t1_reg        <= '0;
            weighted1_reg <= '0;
            weighted2_reg <= '0;
            sum_reg       <= '0;
            limited_reg   <= '0;
            mul_a_reg     <= '0;
            mul_b_reg     <= '0;
            mul_start     <= 1'b0;
            overdrive     <= 1'b0;
            clip          <= 1'b0;
            out_buf_valid <= 1'b0;
            out_buf       <= '0;
        end
        else begin
            if (out_fire) out_buf_valid <= 1'b0;

            mul_start <= 1'b0; //pulso de un ciclo

            case (state)
                ST_IDLE: begin
                    if (in_fire) begin
                        osc1_reg   <= in_osc1;
                        osc2_reg   <= in_osc2;
                        level1_reg <= safe_level(osc1_level_q1_31);
                        level2_reg <= safe_level(osc2_level_q1_31);
                        trim_reg   <= safe_level(bus_trim_q1_31);
                        t1_reg     <= t1_q3_29;
                        overdrive  <= 1'b0;
                        clip       <= 1'b0;
                        state      <= ST_LOAD_L1;
                    end
                end

                ST_LOAD_L1: begin //osc1 * L1
                    mul_a_reg <= osc1_reg;
                    mul_b_reg <= level1_reg;
                    mul_start <= 1'b1;
                    state     <= ST_MUL_L1;
                end

                ST_MUL_L1: begin
                    if (mul_valid) begin
                        weighted1_reg <= mul_result;
                        state         <= ST_LOAD_L2;
                    end
                end

                ST_LOAD_L2: begin //osc2 * L2
                    mul_a_reg <= osc2_reg;
                    mul_b_reg <= level2_reg;
                    mul_start <= 1'b1;
                    state     <= ST_MUL_L2;
                end

                ST_MUL_L2: begin
                    if (mul_valid) begin
                        weighted2_reg <= mul_result;
                        state         <= ST_SUM;
                    end
                end

                ST_SUM: begin //suma en 33 bits, sin saturar todavia
                    sum_reg <= {weighted1_reg[31], weighted1_reg} + {weighted2_reg[31], weighted2_reg};
                    state   <= ST_LIMIT;
                end

                ST_LIMIT: begin
                    overdrive   <= (sum_reg > t1_ext) || (sum_reg < -t1_ext); //solo indicador, no toca el audio
                    clip        <= (sum_reg > 33'sd2147483647) || (sum_reg < -33'sd2147483648);
                    limited_reg <= limited_next;
                    state       <= ST_LOAD_TRIM;
                end

                ST_LOAD_TRIM: begin //s * trim
                    mul_a_reg <= limited_reg;
                    mul_b_reg <= trim_reg;
                    mul_start <= 1'b1;
                    state     <= ST_MUL_TRIM;
                end

                ST_MUL_TRIM: begin
                    if (mul_valid) begin
                        out_buf       <= mul_result;
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
