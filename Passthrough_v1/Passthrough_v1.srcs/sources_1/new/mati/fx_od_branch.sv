`timescale 1ns/1ps
//! @title Rama de ganancia del overdrive
//! @file fx_od_branch.sv
//! @brief Pasaaltos y pasabajos TPT, seguidos por la ganancia de Drive.
//!
//! Por etapa: v = G*x - G*s; lp = s + v; s_next = s + 2*v.
//! La primera entrega hp = x - lp; la segunda entrega lp.
//! Entrada Q3.29; estados Q5.27; salida virtual Q12.20. Registros de 32 bits.
//! Todavia no incluye los HPF de entrada, diodos, suma directa ni Tone.

module fx_od_branch (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               in_valid,
    output logic               in_ready,
    input  logic signed [31:0] in_data,
    output logic               out_valid,
    input  logic               out_ready,
    output logic signed [31:0] out_data,
    input  logic signed [31:0] hp_g_q1_31,
    input  logic signed [31:0] lp_g_q1_31,
    input  logic signed [31:0] gain_q9_23
);

    import fx_dsp_pkg::*;

    // Estados
    typedef enum logic [4:0] {
        ST_IDLE, ST_CONVERT_INPUT, ST_LOAD_X, ST_MUL_X, ST_LOAD_STATE, ST_MUL_STATE,
        ST_SUB_PRODUCT, ST_ROUND_STAGE, ST_SAVE_V, ST_ADD_STAGE, ST_SAVE_STAGE,
        ST_SUB_HP, ST_SAVE_HP, ST_LOAD_GAIN, ST_MUL_GAIN, ST_ROUND_GAIN, ST_SAVE_OUTPUT
    } state_t;

    state_t state;

    // Registros de muestra, parametros y filtros
    logic signed [31:0] hp_g_reg, lp_g_reg, gain_reg;
    logic signed [31:0] hp_state_reg, lp_state_reg;
    logic signed [31:0] sample_reg, stage_input_reg, stage_v_reg, stage_lp_reg, filtered_reg;
    logic               stage_index;

    // Multiplicador compartido
    logic signed [31:0] mul_a_reg, mul_b_reg;
    logic signed [63:0] mul_product_reg, mul_x_reg;
    logic signed [63:0] difference_reg, rounded_reg;
    logic signed [32:0] lp_sum_reg, hp_difference_reg;
    logic signed [33:0] state_sum_reg;

    logic signed [31:0] stage_state, stage_g;

    logic               out_buf_valid;
    logic signed [31:0] out_buf;
    wire in_fire, out_fire;

    // Saturacion por extension de signo, sin comparaciones aritmeticas.
    function automatic logic signed [31:0] sat_sum32(input logic signed [33:0] value);
        logic overflow;
        begin
            overflow = |(value[33:32] ^ {2{value[31]}});
            if (!overflow) sat_sum32 = value[31:0];
            else if (value[33]) sat_sum32 = 32'sh8000_0000;
            else sat_sum32 = 32'sh7FFF_FFFF;
        end
    endfunction

    // Handshake y salidas
    assign in_ready  = rst_n && (state == ST_IDLE) && !out_buf_valid;
    assign in_fire   = in_valid && in_ready;
    assign out_fire  = out_valid && out_ready;
    assign out_valid = out_buf_valid;
    assign out_data  = out_buf;

    // Logica combinacional
    always_comb begin
        stage_state = stage_index ? lp_state_reg : hp_state_reg;
        stage_g     = stage_index ? lp_g_reg : hp_g_reg;

    end

    // Logica secuencial y FSM: reset sincronico
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state           <= ST_IDLE;
            hp_g_reg        <= '0;
            lp_g_reg        <= '0;
            gain_reg        <= '0;
            hp_state_reg    <= '0;
            lp_state_reg    <= '0;
            sample_reg      <= '0;
            stage_input_reg <= '0;
            stage_v_reg     <= '0;
            stage_lp_reg    <= '0;
            filtered_reg    <= '0;
            stage_index     <= 1'b0;
            mul_a_reg       <= '0;
            mul_b_reg       <= '0;
            mul_product_reg <= '0;
            mul_x_reg       <= '0;
            difference_reg  <= '0;
            rounded_reg     <= '0;
            lp_sum_reg      <= '0;
            hp_difference_reg <= '0;
            state_sum_reg   <= '0;
            out_buf_valid   <= 1'b0;
            out_buf         <= '0;
        end else begin
            if (out_fire) out_buf_valid <= 1'b0;

            if ((state == ST_MUL_X) || (state == ST_MUL_STATE) || (state == ST_MUL_GAIN))
                mul_product_reg <= $signed(mul_a_reg) * $signed(mul_b_reg);

            case (state)
                ST_IDLE: begin
                    if (in_fire) begin
                        sample_reg  <= in_data;
                        hp_g_reg    <= (hp_g_q1_31 < 0) ? 32'sd0 : hp_g_q1_31;
                        lp_g_reg    <= (lp_g_q1_31 < 0) ? 32'sd0 : lp_g_q1_31;
                        gain_reg    <= (gain_q9_23 < 0) ? 32'sd0 : gain_q9_23;
                        stage_index <= 1'b0;
                        state       <= ST_CONVERT_INPUT;
                    end
                end

                ST_CONVERT_INPUT: begin
                    // Q3.29 -> Q5.27, redondeo simetrico con suma de 33 bits.
                    stage_input_reg <= ($signed({sample_reg[31], sample_reg}) +
                                       (sample_reg[31] ? 33'sd1 : 33'sd2)) >>> 2;
                    state <= ST_LOAD_X;
                end

                ST_LOAD_X: begin
                    mul_a_reg <= stage_input_reg;
                    mul_b_reg <= stage_g;
                    state     <= ST_MUL_X;
                end

                ST_MUL_X: state <= ST_LOAD_STATE;

                ST_LOAD_STATE: begin
                    mul_x_reg <= mul_product_reg;
                    mul_a_reg <= stage_state;
                    mul_b_reg <= stage_g;
                    state     <= ST_MUL_STATE;
                end

                ST_MUL_STATE: state <= ST_SUB_PRODUCT;

                ST_SUB_PRODUCT: begin
                    // G no negativo: la diferencia de estos productos cabe en 64 bits.
                    difference_reg <= mul_x_reg - mul_product_reg;
                    state          <= ST_ROUND_STAGE;
                end

                ST_ROUND_STAGE: begin
                    // Redondeo al mas cercano, empates alejandose de cero, sin negar.
                    rounded_reg <= difference_reg + (difference_reg[63] ? 64'sd1073741823 : 64'sd1073741824);
                    state       <= ST_SAVE_V;
                end

                ST_SAVE_V: begin
                    stage_v_reg <= sat32(rounded_reg >>> 31);
                    state       <= ST_ADD_STAGE;
                end

                ST_ADD_STAGE: begin
                    lp_sum_reg    <= $signed({stage_state[31], stage_state}) + $signed({stage_v_reg[31], stage_v_reg});
                    state_sum_reg <= $signed({{2{stage_state[31]}}, stage_state}) + ($signed({{2{stage_v_reg[31]}}, stage_v_reg}) <<< 1);
                    state         <= ST_SAVE_STAGE;
                end

                ST_SAVE_STAGE: begin
                    stage_lp_reg <= sat_sum32($signed({lp_sum_reg[32], lp_sum_reg}));
                    if (!stage_index) begin
                        hp_state_reg <= sat_sum32(state_sum_reg);
                        state        <= ST_SUB_HP;
                    end else begin
                        lp_state_reg <= sat_sum32(state_sum_reg);
                        filtered_reg <= sat_sum32($signed({lp_sum_reg[32], lp_sum_reg}));
                        state        <= ST_LOAD_GAIN;
                    end
                end

                ST_SUB_HP: begin
                    hp_difference_reg <= $signed({stage_input_reg[31], stage_input_reg}) - $signed({stage_lp_reg[31], stage_lp_reg});
                    state             <= ST_SAVE_HP;
                end

                ST_SAVE_HP: begin
                    stage_input_reg <= sat_sum32($signed({hp_difference_reg[32], hp_difference_reg}));
                    stage_index     <= 1'b1;
                    state           <= ST_LOAD_X;
                end

                ST_LOAD_GAIN: begin
                    mul_a_reg <= filtered_reg;
                    mul_b_reg <= gain_reg;
                    state     <= ST_MUL_GAIN;
                end

                ST_MUL_GAIN: state <= ST_ROUND_GAIN;

                ST_ROUND_GAIN: begin
                    // Q5.27 * Q9.23 -> Q12.20: desplazar 30 despues de redondear.
                    rounded_reg <= mul_product_reg + (mul_product_reg[63] ? 64'sd536870911 : 64'sd536870912);
                    state       <= ST_SAVE_OUTPUT;
                end

                ST_SAVE_OUTPUT: begin
                    out_buf       <= sat32(rounded_reg >>> 30);
                    out_buf_valid <= 1'b1;
                    state         <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
