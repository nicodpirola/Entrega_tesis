`timescale 1ns/1ps
//! @title Rama de ganancia del overdrive
//! @file fx_od_branch.sv
//! @brief Pasaaltos y pasabajos TPT, seguidos por la ganancia de Drive.
//!
//! Por etapa: v = G*x - G*s; lp = s + v; s_next = s + 2*v.
//! La primera entrega hp = x - lp; la segunda entrega lp.
//! Entrada y estados Q3.29. Salida u en voltios virtuales Q11.21.
//! Todavia no incluye los HPF de entrada, diodos, suma directa ni Tone.

module fx_od_rama(
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

    // Estados
    typedef enum logic [3:0] {
        ST_IDLE, ST_LOAD_X, ST_MUL_X, ST_LOAD_STATE, ST_MUL_STATE,
        ST_SUB_PRODUCT, ST_STORE_STAGE, ST_LOAD_GAIN, ST_MUL_GAIN, ST_SAVE_OUTPUT
    } state_t;

    state_t state;

    // Registros de muestra, parametros y filtros
    logic signed [31:0] hp_g_reg, lp_g_reg, gain_reg;
    logic signed [31:0] hp_state_reg, lp_state_reg;
    logic signed [31:0] stage_input_reg, stage_v_reg, filtered_reg;
    logic               stage_index;

    // Multiplicador compartido
    logic signed [31:0] mul_a_reg, mul_b_reg;
    logic signed [63:0] mul_product_reg, mul_x_reg;

    logic signed [31:0] stage_state, stage_g;
    logic signed [31:0] stage_lp, stage_hp, stage_state_next;
    logic signed [31:0] stage_v_next, gain_result;
    logic signed [64:0] product_difference, stage_lp_ext, stage_hp_ext, stage_state_ext;

    logic               out_buf_valid;
    logic signed [31:0] out_buf;
    wire in_fire, out_fire;

    // Funciones de conversion redondear antes de saturar
    function automatic logic signed [31:0] sat32(input logic signed [64:0] value);
        begin
            if (value > 65'sd2147483647) sat32 = 32'sh7FFF_FFFF;
            else if (value < -65'sd2147483648) sat32 = 32'sh8000_0000;
            else sat32 = value[31:0];
        end
    endfunction

    function automatic logic signed [64:0] round_shift31(input logic signed [64:0] value);
        logic signed [65:0] magnitude;
        begin
            magnitude = $signed({value[64], value});
            if (value < 0) magnitude = -magnitude;
            magnitude = (magnitude + (66'sd1 <<< 30)) >>> 31;
            if (value < 0) round_shift31 = -magnitude;
            else round_shift31 = magnitude;
        end
    endfunction

    //Handshake y salidas
    assign in_ready  = rst_n && (state == ST_IDLE) && !out_buf_valid;
    assign in_fire   = in_valid && in_ready;
    assign out_fire  = out_valid && out_ready;
    assign out_valid = out_buf_valid;
    assign out_data  = out_buf;

    //Logica combinacional
    always_comb begin
        stage_state = stage_index ? lp_state_reg : hp_state_reg;
        stage_g     = stage_index ? lp_g_reg : hp_g_reg;

        // Se resta a ancho completo; no se limita x-s antes de multiplicar.
        product_difference = $signed({mul_x_reg[63], mul_x_reg}) - $signed({mul_product_reg[63], mul_product_reg});
        stage_v_next = sat32(round_shift31(product_difference));

        stage_lp_ext    = $signed({{33{stage_state[31]}}, stage_state}) + $signed({{33{stage_v_reg[31]}}, stage_v_reg});
        stage_state_ext = $signed({{33{stage_state[31]}}, stage_state}) + ($signed({{33{stage_v_reg[31]}}, stage_v_reg}) <<< 1);
        stage_lp        = sat32(stage_lp_ext);
        stage_state_next = sat32(stage_state_ext);
        stage_hp_ext    = $signed({{33{stage_input_reg[31]}}, stage_input_reg}) - $signed({{33{stage_lp[31]}}, stage_lp});
        stage_hp        = sat32(stage_hp_ext);

        // Q3.29 * Q9.23 -> Q11.21: desplazar 31 bits.
        gain_result = sat32(round_shift31($signed({mul_product_reg[63], mul_product_reg})));
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
            stage_input_reg <= '0;
            stage_v_reg     <= '0;
            filtered_reg    <= '0;
            stage_index     <= 1'b0;
            mul_a_reg       <= '0;
            mul_b_reg       <= '0;
            mul_product_reg <= '0;
            mul_x_reg       <= '0;
            out_buf_valid   <= 1'b0;
            out_buf         <= '0;
        end else begin
            if (out_fire) out_buf_valid <= 1'b0;

            if ((state == ST_MUL_X) || (state == ST_MUL_STATE) || (state == ST_MUL_GAIN))
                mul_product_reg <= $signed(mul_a_reg) * $signed(mul_b_reg);

            case (state)
                ST_IDLE: begin
                    if (in_fire) begin
                        stage_input_reg <= in_data;
                        hp_g_reg    <= (hp_g_q1_31 < 0) ? 32'sd0 : hp_g_q1_31;
                        lp_g_reg    <= (lp_g_q1_31 < 0) ? 32'sd0 : lp_g_q1_31;
                        gain_reg    <= (gain_q9_23 < 0) ? 32'sd0 : gain_q9_23;
                        stage_index <= 1'b0;
                        state       <= ST_LOAD_X;
                    end
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
                    stage_v_reg <= stage_v_next;
                    state       <= ST_STORE_STAGE;
                end

                ST_STORE_STAGE: begin
                    if (!stage_index) begin
                        hp_state_reg    <= stage_state_next;
                        stage_input_reg <= stage_hp;
                        stage_index     <= 1'b1;
                        state           <= ST_LOAD_X;
                    end else begin
                        lp_state_reg <= stage_state_next;
                        filtered_reg <= stage_lp;
                        state        <= ST_LOAD_GAIN;
                    end
                end

                ST_LOAD_GAIN: begin
                    mul_a_reg <= filtered_reg;
                    mul_b_reg <= gain_reg;
                    state     <= ST_MUL_GAIN;
                end

                ST_MUL_GAIN: state <= ST_SAVE_OUTPUT;

                ST_SAVE_OUTPUT: begin
                    out_buf       <= gain_result;
                    out_buf_valid <= 1'b1;
                    state         <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
