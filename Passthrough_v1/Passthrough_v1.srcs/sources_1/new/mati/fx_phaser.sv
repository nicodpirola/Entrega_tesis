//! @title Efecto Phaser
//! @file fx_phaser.sv
//! @author [Matias Repila / Nicolas Pirola]
//! @brief Phaser de cuatro etapas all-pass.
//!
//! @details
//! Usamos filtro TPT, ecuaciones del libro:
//!
//! v  = (x - s) * G
//! ap = s + v
//! s  = ap + v
//! y  = 2 * ap - x
//!
//! La FSM multiplexa en el tiempo un unico multiplicador de 32x32 bits
//! para calcular G, el feedback y las cuatro etapas all-pass.
//!

module fx_phaser (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               enable,

    input  logic               in_valid,
    output logic               in_ready,
    input  logic signed [31:0] in_data,

    output logic               out_valid,
    input  logic               out_ready,
    output logic signed [31:0] out_data,

    input  logic        [31:0] lfo_phase_inc,
    input  logic signed [31:0] g_min_q1_31,
    input  logic signed [31:0] g_max_q1_31,
    input  logic signed [31:0] fb_q1_31
);

    import fx_dsp_pkg::*;

    typedef enum logic [3:0] {
        ST_IDLE,
        ST_LOAD_G,
        ST_MUL_G,
        ST_LOAD_FB,
        ST_MUL_FB,
        ST_PREP_STAGE,
        ST_LOAD_STAGE,
        ST_MUL_STAGE,
        ST_STORE_STAGE,
        ST_MIX
    } state_t;

    state_t state;

    logic signed [31:0] lfo_q1_31;
    logic signed [31:0] lfo_reg;
    logic               lfo_tick;
    logic               lfo_clear;

    logic signed [31:0] g_min_reg;
    logic signed [31:0] g_max_reg;
    logic signed [31:0] feedback_cfg_reg;

    logic signed [31:0] ap_state_0;
    logic signed [31:0] ap_state_1;
    logic signed [31:0] ap_state_2;
    logic signed [31:0] ap_state_3;

    logic signed [31:0] feedback_reg;
    logic signed [31:0] sample_reg;
    logic signed [31:0] g_reg;
    logic signed [31:0] stage_input_reg;
    logic signed [31:0] allpass_output_reg;
    logic        [1:0]  stage_index;

    logic signed [31:0] mul_a_reg;
    logic signed [31:0] mul_b_reg;
    logic signed [63:0] mul_product_reg;

    logic signed [31:0] lfo_unipolar;
    logic signed [31:0] g_range;
    logic signed [31:0] mul_result;
    logic signed [31:0] g_next;
    logic signed [31:0] feedback_input;

    logic signed [31:0] stage_state;
    logic signed [31:0] stage_v;
    logic signed [31:0] stage_ap;
    logic signed [31:0] stage_state_next;
    logic signed [31:0] stage_output;
    logic signed [31:0] mix_value;

    logic               out_buf_valid;
    logic signed [31:0] out_buf;
    logic               enable_d;

    wire enable_rise;
    wire can_accept;
    wire in_fire;
    wire out_fire;

    fx_lfo_tri u_lfo (
        .clk           (clk),
        .rst_n         (rst_n),
        .tick          (lfo_tick),
        .phase_inc_u32 (lfo_phase_inc),
        .phase_clear   (lfo_clear),
        .lfo_q1_31     (lfo_q1_31)
    );

    assign enable_rise = enable && !enable_d;
    assign can_accept  = (state == ST_IDLE) && !out_buf_valid && !enable_rise;
    assign in_fire     = in_valid && in_ready && enable;
    assign out_fire    = out_valid && out_ready;

    assign lfo_tick  = in_fire;
    assign lfo_clear = enable_rise;

    assign in_ready  = enable ? can_accept    : out_ready;
    assign out_valid = enable ? out_buf_valid : in_valid;
    assign out_data  = enable ? out_buf       : in_data;

    always_comb begin
        lfo_unipolar = (lfo_reg >>> 1) + 32'sh4000_0000;
        g_range      = sat_sub32(g_max_reg, g_min_reg);

        mul_result = sat32((mul_product_reg + (64'sd1 <<< 30)) >>> 31);

        g_next         = sat_add32(g_min_reg, mul_result);
        feedback_input = sat_add32(sample_reg, mul_result);

        case (stage_index)
            2'd0: stage_state = ap_state_0;
            2'd1: stage_state = ap_state_1;
            2'd2: stage_state = ap_state_2;
            default: stage_state = ap_state_3;
        endcase

        stage_v          = mul_result;
        stage_ap         = sat_add32(stage_state, stage_v);
        stage_state_next = sat_add32(stage_ap, stage_v);
        stage_output     = sat_sub32(sat_add32(stage_ap, stage_ap), stage_input_reg);

        mix_value = sat_add32(sample_reg >>> 1, allpass_output_reg >>> 1);
    end

    always_ff @(posedge clk) begin
        if (!rst_n)
            enable_d <= 1'b0;
        else
            enable_d <= enable;
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state              <= ST_IDLE;

            lfo_reg            <= '0;
            g_min_reg          <= '0;
            g_max_reg          <= '0;
            feedback_cfg_reg   <= '0;

            ap_state_0         <= '0;
            ap_state_1         <= '0;
            ap_state_2         <= '0;
            ap_state_3         <= '0;

            feedback_reg       <= '0;
            sample_reg         <= '0;
            g_reg              <= '0;
            stage_input_reg    <= '0;
            allpass_output_reg <= '0;
            stage_index        <= '0;

            mul_a_reg          <= '0;
            mul_b_reg          <= '0;
            mul_product_reg    <= '0;

            out_buf_valid      <= 1'b0;
            out_buf            <= '0;
        end else begin
            if (out_fire)
                out_buf_valid <= 1'b0;

            if (enable_rise) begin
                state              <= ST_IDLE;
                ap_state_0         <= '0;
                ap_state_1         <= '0;
                ap_state_2         <= '0;
                ap_state_3         <= '0;
                feedback_reg       <= '0;
                out_buf_valid      <= 1'b0;
            end else begin
                if ((state == ST_MUL_G) ||
                    (state == ST_MUL_FB) ||
                    (state == ST_MUL_STAGE)) begin

                    mul_product_reg <=
                        $signed(mul_a_reg) *
                        $signed(mul_b_reg);
                end

                case (state)
                    ST_IDLE: begin
                        if (in_fire) begin
                            sample_reg       <= in_data;
                            lfo_reg          <= lfo_q1_31;
                            g_min_reg        <= g_min_q1_31;
                            g_max_reg        <= g_max_q1_31;
                            feedback_cfg_reg <= fb_q1_31;
                            stage_index      <= 2'd0;
                            state            <= ST_LOAD_G;
                        end
                    end

                    ST_LOAD_G: begin
                        mul_a_reg <= lfo_unipolar;
                        mul_b_reg <= g_range;
                        state     <= ST_MUL_G;
                    end

                    ST_MUL_G: begin
                        state <= ST_LOAD_FB;
                    end

                    ST_LOAD_FB: begin
                        g_reg     <= g_next;
                        mul_a_reg <= feedback_reg;
                        mul_b_reg <= feedback_cfg_reg;
                        state     <= ST_MUL_FB;
                    end

                    ST_MUL_FB: begin
                        state <= ST_PREP_STAGE;
                    end

                    ST_PREP_STAGE: begin
                        stage_input_reg <= feedback_input;
                        stage_index     <= 2'd0;
                        state           <= ST_LOAD_STAGE;
                    end

                    ST_LOAD_STAGE: begin
                        mul_a_reg <= sat_sub32(
                            stage_input_reg,
                            stage_state
                        );

                        mul_b_reg <= g_reg;
                        state     <= ST_MUL_STAGE;
                    end

                    ST_MUL_STAGE: begin
                        state <= ST_STORE_STAGE;
                    end

                    ST_STORE_STAGE: begin
                        case (stage_index)
                            2'd0: ap_state_0 <= stage_state_next;
                            2'd1: ap_state_1 <= stage_state_next;
                            2'd2: ap_state_2 <= stage_state_next;
                            default: ap_state_3 <= stage_state_next;
                        endcase

                        if (stage_index == 2'd3) begin
                            allpass_output_reg <= stage_output;
                            state              <= ST_MIX;
                        end else begin
                            stage_input_reg <= stage_output;
                            stage_index     <= stage_index + 2'd1;
                            state           <= ST_LOAD_STAGE;
                        end
                    end

                    ST_MIX: begin
                        out_buf       <= mix_value;
                        feedback_reg  <= allpass_output_reg;
                        out_buf_valid <= 1'b1;
                        state         <= ST_IDLE;
                    end

                    default: begin
                        state <= ST_IDLE;
                    end
                endcase
            end
        end
    end

endmodule
