//! @title Efecto Chorus
//! @file fx_chorus.sv
//! @author [Matias Repila / Nicolas Pirola]
//! @brief Chorus con retardo fraccional y filtro pasabajos opcional.
//!
//! @details
//! Ecuaciones:
//!
//! D(t) = D_center + D_depth * LFO(t)
//! Wet  = LPF(Delay(Audio, D(t)))
//! Salida = Audio + Wet * Wet_level
//!
//! La FSM multiplexa en el tiempo un unico multiplicador de 32x32 bits
//! para calcular la modulacion del retardo, el filtro y la mezcla wet.
//! La interpolacion fraccional se realiza dentro de delay_line.

module fx_chorus #(
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
    input  logic        [31:0] lfo_phase_inc_u32,

    input  logic               lpf_on,
    input  logic signed [31:0] lpf_G_q1_31
);

    import fx_dsp_pkg::*;

    localparam int MAX_DELAY_SAMPLES = (1 << ADDR_W) - 8;
    localparam logic [31:0] D_MAX_16_16 = {MAX_DELAY_SAMPLES[15:0], 16'd0};

    localparam logic [31:0] D_MIN_16_16 = 32'h0001_0000;
    localparam logic signed [31:0] WET_MAX_Q31 = 32'sh5A82_79A0;

    typedef enum logic [3:0] {
        ST_IDLE,
        ST_LOAD_DELAY,
        ST_MUL_DELAY,
        ST_REQUEST_DELAY,
        ST_WAIT_DELAY,
        ST_LOAD_LPF,
        ST_MUL_LPF,
        ST_SAVE_LPF,
        ST_LOAD_WET,
        ST_MUL_WET,
        ST_SAVE_OUTPUT,
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
    logic signed [31:0] lpf_g_reg;
    logic               lpf_enable_reg;

    logic signed [31:0] delay_sample_reg;
    logic signed [31:0] wet_sample_reg;
    logic signed [31:0] lpf_state_reg;

    logic signed [31:0] mul_a_reg;
    logic signed [31:0] mul_b_reg;
    logic signed [63:0] mul_product_reg;

    logic signed [31:0] mul_result;
    logic signed [31:0] lpf_delta;
    logic signed [31:0] lpf_output;
    logic signed [31:0] lpf_state_next;
    logic signed [31:0] wet_eff;

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

    function automatic logic [31:0] clamp_delay(input logic signed [31:0] value);
        begin
            if (value < $signed(D_MIN_16_16)) clamp_delay = D_MIN_16_16;
            else if (value > $signed(D_MAX_16_16)) clamp_delay = D_MAX_16_16;
            else clamp_delay = value[31:0];
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
        .w_in          (sample_reg     ),

        .clear_req     (clear_request  ),
        .clear_busy    (clear_busy     ),
        .clear_done    (clear_done     ),

        .write_ptr_dbg (               )
    );

    assign enable_rise = enable && !enable_d;
    assign bypass_mode = !enable || clear_busy;

    assign can_accept = (state == ST_IDLE) && !out_buf_valid && !enable_rise;

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
    end

    always_comb begin
        mul_result = sat32((mul_product_reg + (64'sd1 <<< 30)) >>> 31);

        delay_value = clamp_delay($signed(center_reg) + mul_result);

        lpf_delta = sat_sub32(delay_sample_reg, lpf_state_reg);

        lpf_output = sat_add32(lpf_state_reg, mul_result);

        lpf_state_next = sat_add32(lpf_state_reg, sat_add32(mul_result, mul_result));
    end

    always_ff @(posedge clk) begin
        if (!rst_n)
            enable_d <= 1'b0;
        else
            enable_d <= enable;
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state             <= ST_IDLE;

            lfo_reg           <= '0;
            sample_reg        <= '0;
            center_reg        <= '0;
            depth_reg         <= '0;
            wet_reg           <= '0;
            lpf_g_reg         <= '0;
            lpf_enable_reg    <= 1'b0;

            delay_sample_reg  <= '0;
            wet_sample_reg    <= '0;
            lpf_state_reg     <= '0;

            mul_a_reg         <= '0;
            mul_b_reg         <= '0;
            mul_product_reg   <= '0;

            out_buf_valid     <= 1'b0;
            out_buf           <= '0;
        end else begin
            if (out_fire)
                out_buf_valid <= 1'b0;

            if (enable_rise && (state == ST_IDLE))
                lpf_state_reg <= '0;

            if ((state == ST_MUL_DELAY) ||
                (state == ST_MUL_LPF)   ||
                (state == ST_MUL_WET)) begin

                mul_product_reg <= $signed(mul_a_reg) * $signed(mul_b_reg);
            end

            case (state)
                ST_IDLE: begin
                    if (in_fire) begin
                        if (bypass_mode) begin
                            out_buf       <= in_data;
                            out_buf_valid <= 1'b1;
                        end else begin
                            sample_reg     <= in_data;
                            lfo_reg        <= lfo_q1_31;
                            center_reg     <= D_center_16_16;
                            depth_reg      <= $signed(D_depth_16_16);
                            wet_reg        <= wet_eff;
                            lpf_g_reg      <= lpf_G_q1_31;
                            lpf_enable_reg <= lpf_on;
                            state          <= ST_LOAD_DELAY;
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

                        if (lpf_enable_reg) begin
                            state <= ST_LOAD_LPF;
                        end else begin
                            wet_sample_reg <= delay_output;
                            state          <= ST_LOAD_WET;
                        end
                    end
                end

                ST_LOAD_LPF: begin
                    mul_a_reg <= lpf_delta;
                    mul_b_reg <= lpf_g_reg;
                    state     <= ST_MUL_LPF;
                end

                ST_MUL_LPF: begin
                    state <= ST_SAVE_LPF;
                end

                ST_SAVE_LPF: begin
                    wet_sample_reg <= lpf_output;
                    lpf_state_reg  <= lpf_state_next;
                    state          <= ST_LOAD_WET;
                end

                ST_LOAD_WET: begin
                    mul_a_reg <= wet_sample_reg;
                    mul_b_reg <= wet_reg;
                    state     <= ST_MUL_WET;
                end

                ST_MUL_WET: begin
                    state <= ST_SAVE_OUTPUT;
                end

                ST_SAVE_OUTPUT: begin
                    out_buf       <= sat_add32(sample_reg, mul_result);
                    out_buf_valid <= 1'b1;
                    state         <= ST_WRITE_DELAY;
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