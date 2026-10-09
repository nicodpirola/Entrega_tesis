//! @title Efecto Flanger
//! @file fx_flanger.sv
//! @author [Matias Repila / Nicolas Pirola]
//! @brief Flanger con retardo fraccional y realimentacion.
//!
//! @details
//! Ecuaciones:
//!
//! D(t) = D_center + D_depth * LFO(t)
//! Salida = Audio + Delay(Audio, D(t)) * Wet
//! Memoria = Softclip(Audio + Delay(Audio, D(t)) * Feedback)
//!
//! La FSM multiplexa en el tiempo un unico multiplicador de 32x32 bits
//! para calcular la modulacion, la mezcla wet, el feedback y el soft clip.
//! La interpolacion fraccional se realiza dentro de delay_line.

module fx_flanger #(
    parameter int ADDR_W = 11
)(
    input  logic               clk,
    input  logic               rst_n,
    input  logic               enable,

    input  logic               in_valid,
    output logic               in_ready,
    input  logic signed [31:0] in_data,

    output logic               out_valid,
    input  logic               out_ready,
    output logic signed [31:0] out_data,

    input  logic        [31:0] D_center_16_16,
    input  logic        [31:0] D_depth_16_16,
    input  logic signed [31:0] wet_q1_31,
    input  logic signed [31:0] fb_q1_31,
    input  logic        [31:0] lfo_phase_inc_u32
);

    import fx_dsp_pkg::*;

    localparam int MAX_DELAY_SAMPLES = (1 << ADDR_W) - 8;
    localparam logic [31:0] D_MAX_16_16 =
        {MAX_DELAY_SAMPLES[15:0], 16'd0};

    localparam logic [31:0] D_MIN_16_16 = 32'h0001_0000;

    localparam logic signed [31:0] WET_MAX_Q31 = 32'sh5A82_79A0;
    localparam logic signed [31:0] FB_MAX_Q31  = 32'sh7333_3333;

    localparam logic signed [31:0] SC_T1_Q29 = 32'sh1666_6666;
    localparam logic signed [31:0] SC_T2_Q29 = 32'sh1E66_6666;
    localparam logic signed [31:0] SC_K1_Q31 = 32'sh7333_3333;
    localparam logic signed [31:0] SC_K2_Q31 = 32'sh5999_999A;
    localparam logic signed [31:0] SC_Y2_Q29 = 32'sh1D99_9999;

    typedef enum logic [3:0] {
        ST_IDLE,
        ST_LOAD_DELAY,
        ST_MUL_DELAY,
        ST_REQUEST_DELAY,
        ST_WAIT_DELAY,
        ST_LOAD_WET,
        ST_MUL_WET,
        ST_SAVE_WET,
        ST_LOAD_FB,
        ST_MUL_FB,
        ST_MIX,
        ST_CLIP_PRE,
        ST_MUL_CLIP,
        ST_CLIP_ADD,
        ST_WRITE_DELAY
    } state_t;

    state_t state;

    logic signed [31:0] lfo_q1_31;
    logic signed [31:0] lfo_reg;
    logic               enable_d;

    logic signed [31:0] sample_reg;
    logic        [31:0] center_reg;
    logic signed [31:0] depth_reg;
    logic signed [31:0] wet_reg;
    logic signed [31:0] fb_reg;

    logic signed [31:0] delay_sample_reg;
    logic signed [31:0] wet_term_reg;
    logic signed [31:0] clip_input_reg;
    logic signed [31:0] write_sample_reg;

    logic               clip_negative_reg;
    logic signed [31:0] clip_base_reg;

    logic signed [31:0] mul_a_reg;
    logic signed [31:0] mul_b_reg;
    logic signed [63:0] mul_product_reg;

    logic signed [31:0] mul_result;
    logic signed [31:0] wet_eff;
    logic signed [31:0] fb_eff;
    logic signed [31:0] clip_magnitude;
    logic signed [31:0] clip_result;

    logic        [31:0] delay_value;
    logic signed [31:0] delay_output;
    logic               delay_valid;
    logic               delay_ready;

    logic               request_ready;
    logic               write_ready;
    logic               clear_busy;
    logic               clear_done;

    logic               out_buf_valid;
    logic signed [31:0] out_buf;

    wire enable_rise;
    wire bypass_mode;
    wire can_accept;
    wire in_fire;
    wire out_fire;

    wire lfo_tick;
    wire lfo_clear;

    wire request_valid;
    wire write_valid;
    wire clear_request;

    function automatic logic [31:0] clamp_delay(
        input logic signed [31:0] value
    );
        begin
            if (value < $signed(D_MIN_16_16))
                clamp_delay = D_MIN_16_16;
            else if (value > $signed(D_MAX_16_16))
                clamp_delay = D_MAX_16_16;
            else
                clamp_delay = value[31:0];
        end
    endfunction

    fx_lfo_tri u_lfo (
        .clk           (clk              ),
        .rst_n         (rst_n            ),
        .tick          (lfo_tick         ),
        .phase_inc_u32 (lfo_phase_inc_u32),
        .phase_clear   (lfo_clear        ),
        .lfo_q1_31     (lfo_q1_31        )
    );

    delay_line #(
        .ADDR_W(ADDR_W)
    ) u_delay_line (
        .clk           (clk            ),
        .rst_n         (rst_n          ),

        .req_valid     (request_valid  ),
        .req_ready     (request_ready  ),
        .D_16_16       (delay_value    ),

        .d_out         (delay_output   ),
        .d_valid       (delay_valid    ),
        .d_ready       (delay_ready    ),

        .w_valid       (write_valid    ),
        .w_ready       (write_ready    ),
        .w_in          (write_sample_reg),

        .clear_req     (clear_request  ),
        .clear_busy    (clear_busy     ),
        .clear_done    (clear_done     ),

        .write_ptr_dbg (               )
    );

    assign enable_rise = enable && !enable_d;
    assign bypass_mode = !enable || clear_busy;

    assign can_accept = (state == ST_IDLE) &&
                        !out_buf_valid &&
                        !enable_rise;

    assign in_fire  = in_valid && in_ready;
    assign out_fire = out_valid && out_ready;

    assign lfo_tick  = in_fire && !bypass_mode;
    assign lfo_clear = enable_rise;

    assign request_valid = (state == ST_REQUEST_DELAY);
    assign delay_ready   = (state == ST_WAIT_DELAY);
    assign write_valid   = (state == ST_WRITE_DELAY);
    assign clear_request = enable_rise && (state == ST_IDLE);

    assign in_ready  = can_accept;
    assign out_valid = out_buf_valid;
    assign out_data  = out_buf;

    always_comb begin
        if (wet_q1_31 < 32'sd0)
            wet_eff = 32'sd0;
        else if (wet_q1_31 > WET_MAX_Q31)
            wet_eff = WET_MAX_Q31;
        else
            wet_eff = wet_q1_31;

        if (fb_q1_31 > FB_MAX_Q31)
            fb_eff = FB_MAX_Q31;
        else if (fb_q1_31 < -FB_MAX_Q31)
            fb_eff = -FB_MAX_Q31;
        else
            fb_eff = fb_q1_31;
    end

    always_comb begin
        mul_result = sat32(
            (mul_product_reg + (64'sd1 <<< 30)) >>> 31
        );

        delay_value = clamp_delay(
            $signed(center_reg) + mul_result
        );

        clip_magnitude = $signed(abs32(clip_input_reg));
        clip_result    = sat_add32(clip_base_reg, mul_result);
    end

    always_ff @(posedge clk) begin
        if (!rst_n)
            enable_d <= 1'b0;
        else
            enable_d <= enable;
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state               <= ST_IDLE;

            lfo_reg             <= '0;
            sample_reg          <= '0;
            center_reg          <= '0;
            depth_reg           <= '0;
            wet_reg             <= '0;
            fb_reg              <= '0;

            delay_sample_reg    <= '0;
            wet_term_reg        <= '0;
            clip_input_reg      <= '0;
            write_sample_reg    <= '0;

            clip_negative_reg   <= 1'b0;
            clip_base_reg       <= '0;

            mul_a_reg           <= '0;
            mul_b_reg           <= '0;
            mul_product_reg     <= '0;

            out_buf_valid       <= 1'b0;
            out_buf             <= '0;
        end else begin
            if (out_fire)
                out_buf_valid <= 1'b0;

            if ((state == ST_MUL_DELAY) ||
                (state == ST_MUL_WET)   ||
                (state == ST_MUL_FB)    ||
                (state == ST_MUL_CLIP)) begin

                mul_product_reg <=
                    $signed(mul_a_reg) *
                    $signed(mul_b_reg);
            end

            case (state)
                ST_IDLE: begin
                    if (in_fire) begin
                        if (bypass_mode) begin
                            out_buf       <= in_data;
                            out_buf_valid <= 1'b1;
                        end else begin
                            sample_reg <= in_data;
                            lfo_reg    <= lfo_q1_31;
                            center_reg <= D_center_16_16;
                            depth_reg  <= $signed(D_depth_16_16);
                            wet_reg    <= wet_eff;
                            fb_reg     <= fb_eff;
                            state      <= ST_LOAD_DELAY;
                        end
                    end
                end

                ST_LOAD_DELAY: begin
                    mul_a_reg <= depth_reg;
                    mul_b_reg <= lfo_reg;
                    state     <= ST_MUL_DELAY;
                end

                ST_MUL_DELAY: begin
                    state <= ST_REQUEST_DELAY;
                end

                ST_REQUEST_DELAY: begin
                    if (request_ready)
                        state <= ST_WAIT_DELAY;
                end

                ST_WAIT_DELAY: begin
                    if (delay_valid && delay_ready) begin
                        delay_sample_reg <= delay_output;
                        state            <= ST_LOAD_WET;
                    end
                end

                ST_LOAD_WET: begin
                    mul_a_reg <= delay_sample_reg;
                    mul_b_reg <= wet_reg;
                    state     <= ST_MUL_WET;
                end

                ST_MUL_WET: begin
                    state <= ST_SAVE_WET;
                end

                ST_SAVE_WET: begin
                    wet_term_reg <= mul_result;
                    state        <= ST_LOAD_FB;
                end

                ST_LOAD_FB: begin
                    mul_a_reg <= delay_sample_reg;
                    mul_b_reg <= fb_reg;
                    state     <= ST_MUL_FB;
                end

                ST_MUL_FB: begin
                    state <= ST_MIX;
                end

                ST_MIX: begin
                    out_buf <= sat_add32(sample_reg, wet_term_reg);

                    out_buf_valid <= 1'b1;

                    clip_input_reg <= sat_add32(sample_reg,mul_result);

                    state <= ST_CLIP_PRE;
                end

                ST_CLIP_PRE: begin
                    clip_negative_reg <= clip_input_reg[31];

                    if (clip_magnitude <= SC_T1_Q29) begin
                        write_sample_reg <= clip_input_reg;
                        state            <= ST_WRITE_DELAY;
                    end else if (clip_magnitude <= SC_T2_Q29) begin
                        clip_base_reg <= SC_T1_Q29;
                        mul_a_reg     <= sat_sub32(
                            clip_magnitude,
                            SC_T1_Q29
                        );
                        mul_b_reg     <= SC_K1_Q31;
                        state         <= ST_MUL_CLIP;
                    end else begin
                        clip_base_reg <= SC_Y2_Q29;
                        mul_a_reg     <= sat_sub32(
                            clip_magnitude,
                            SC_T2_Q29
                        );
                        mul_b_reg     <= SC_K2_Q31;
                        state         <= ST_MUL_CLIP;
                    end
                end

                ST_MUL_CLIP: begin
                    state <= ST_CLIP_ADD;
                end

                ST_CLIP_ADD: begin
                    if (clip_negative_reg)
                        write_sample_reg <= -clip_result;
                    else
                        write_sample_reg <= clip_result;

                    state <= ST_WRITE_DELAY;
                end

                ST_WRITE_DELAY: begin
                    if (write_ready)
                        state <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
