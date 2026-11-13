// fx_flanger.sv
// Flanger con retardo modulado corto y feedback
//
// D[n] = D_center + D_depth * l[n]      (l[n]: LFO triangular, -1 a 1)
// d[n] = w[n - D[n]]
// y[n] = x[n] + wet * d[n]
// w[n] = SC(x[n] + fb * d[n])           (fb puede ser negativo)
//
// SC: soft clip lineal por tramos, limita la senal que vuelve a la memoria
//   |u| <= T1        ->  u
//   T1 < |u| <= T2   ->  T1 + K1 * (|u| - T1)
//   |u| > T2         ->  Y2 + K2 * (|u| - T2)      (Y2 = T1 + K1 * (T2 - T1))
//
// un multiplicador de 32x32 bits (mul32_seq, 1 DSP48) compartido por una FSM:
// modulacion del retardo, mezcla wet, feedback y soft clip. La interpolacion
// fraccional esta en delay_line.

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

    //parametros
    localparam int          MAX_DELAY_SAMPLES = (1 << ADDR_W) - 8;                //margen al final de la memoria
    localparam logic [31:0] D_MIN_16_16 = 32'h0001_0000;                          //1 muestra
    localparam logic [31:0] D_MAX_16_16 = {MAX_DELAY_SAMPLES[15:0], 16'd0};

    localparam logic signed [31:0] WET_MAX_Q31 = 32'sh7FFF_FFFF; //1
    localparam logic signed [31:0] FB_MAX_Q31  = 32'sh7333_3333; //0.9, el feedback va de -0.9 a 0.9

    localparam logic signed [31:0] SC_T1_Q29 = 32'sh1666_6666; //0.7
    localparam logic signed [31:0] SC_T2_Q29 = 32'sh1E66_6666; //0.95
    localparam logic signed [31:0] SC_K1_Q31 = 32'sh7333_3333; //0.9
    localparam logic signed [31:0] SC_K2_Q31 = 32'sh5999_999A; //0.7
    localparam logic signed [31:0] SC_Y2_Q29 = 32'sh1D99_9999; //0.925

    //estados
    typedef enum logic [3:0]{
        ST_IDLE,
        ST_LOAD_MOD,
        ST_MUL_MOD,
        ST_REQUEST_DELAY,
        ST_WAIT_DELAY,
        ST_LOAD_WET,
        ST_MUL_WET,
        ST_LOAD_FB,
        ST_MUL_FB,
        ST_CLIP,
        ST_MUL_CLIP,
        ST_WRITE_DELAY
    } state_t;

    state_t state; //maquina de estados

    logic signed [31:0] sample_reg;
    logic signed [31:0] lfo_reg;
    logic        [31:0] center_reg;
    logic signed [31:0] depth_reg;
    logic        [31:0] delay_reg;
    logic signed [31:0] wet_reg;
    logic signed [31:0] fb_reg;

    logic signed [31:0] delay_sample_reg;
    logic signed [31:0] clip_input_reg;
    logic               clip_negative_reg;
    logic signed [31:0] clip_base_reg;
    logic signed [31:0] write_sample_reg;

    logic signed [31:0] mul_a_reg;
    logic signed [31:0] mul_b_reg;
    logic               mul_start;
    logic               mul_valid;
    logic signed [63:0] mul_p;

    logic signed [31:0] mul_result;
    logic signed [31:0] delay_mod;
    logic signed [31:0] clip_magnitude;
    logic signed [31:0] clip_result;

    logic signed [31:0] wet_eff;
    logic signed [31:0] fb_eff;

    logic signed [31:0] lfo_q1_31;

    logic signed [31:0] delay_output;
    logic               delay_valid;
    logic               delay_ready;
    logic               request_ready;
    logic               write_ready;
    logic               clear_busy;

    logic               out_buf_valid;
    logic signed [31:0] out_buf;
    logic               enable_d;

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

    //instancias
    fx_lfo_tri u_lfo (
        .clk           (clk              ),
        .rst_n         (rst_n            ),
        .tick          (lfo_tick         ),
        .phase_inc_u32 (lfo_phase_inc_u32),
        .phase_clear   (lfo_clear        ),
        .lfo_q1_31     (lfo_q1_31        )
    );

    delay_line #(
        .ADDR_W (ADDR_W)
    ) u_delay_line (
        .clk           (clk             ),
        .rst_n         (rst_n           ),

        .req_valid     (request_valid   ),
        .req_ready     (request_ready   ),
        .D_16_16       (delay_reg       ),

        .d_out         (delay_output    ),
        .d_valid       (delay_valid     ),
        .d_ready       (delay_ready     ),

        .w_valid       (write_valid     ),
        .w_ready       (write_ready     ),
        .w_in          (write_sample_reg),

        .clear_req     (clear_request   ),
        .clear_busy    (clear_busy      ),
        .clear_done    (                ),

        .write_ptr_dbg (                )
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
    assign enable_rise = enable && !enable_d;
    assign bypass_mode = !enable || clear_busy;

    assign can_accept = (state == ST_IDLE) && !out_buf_valid && !enable_rise;

    assign in_fire  = in_valid && in_ready;
    assign out_fire = out_valid && out_ready;

    assign lfo_tick  = in_fire && !bypass_mode; //el LFO avanza una vez por muestra procesada
    assign lfo_clear = enable_rise;

    assign request_valid = (state == ST_REQUEST_DELAY);
    assign delay_ready   = (state == ST_WAIT_DELAY);
    assign write_valid   = (state == ST_WRITE_DELAY);
    assign clear_request = enable_rise && (state == ST_IDLE); //borra la memoria al habilitar

    //salidas
    assign in_ready  = can_accept;
    assign out_valid = out_buf_valid;
    assign out_data  = out_buf;

    //logica combinacional
    always_comb begin //clamp wet 0 a 1
        if (wet_q1_31 < 32'sd0)          wet_eff = 32'sd0;
        else if (wet_q1_31 > WET_MAX_Q31) wet_eff = WET_MAX_Q31;
        else                              wet_eff = wet_q1_31;
    end

    always_comb begin //clamp fb -0.9 a 0.9
        if (fb_q1_31 > FB_MAX_Q31)       fb_eff = FB_MAX_Q31;
        else if (fb_q1_31 < -FB_MAX_Q31) fb_eff = -FB_MAX_Q31;
        else                             fb_eff = fb_q1_31;
    end

    always_comb begin
        mul_result = sat32((mul_p + (64'sd1 <<< 30)) >>> 31); //redondeo

        delay_mod = $signed(center_reg) + mul_result; //D = center + depth * l

        clip_magnitude = $signed(abs32(clip_input_reg)); //|u|
        clip_result    = sat_add32(clip_base_reg, mul_result);
    end

    //logica secuencial y FSM
    always_ff @(posedge clk) begin
        if (!rst_n) enable_d <= 1'b0;
        else        enable_d <= enable;
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state             <= ST_IDLE;

            sample_reg        <= '0;
            lfo_reg           <= '0;
            center_reg        <= '0;
            depth_reg         <= '0;
            delay_reg         <= '0;
            wet_reg           <= '0;
            fb_reg            <= '0;

            delay_sample_reg  <= '0;
            clip_input_reg    <= '0;
            clip_negative_reg <= 1'b0;
            clip_base_reg     <= '0;
            write_sample_reg  <= '0;

            mul_a_reg         <= '0;
            mul_b_reg         <= '0;
            mul_start         <= 1'b0;

            out_buf_valid     <= 1'b0;
            out_buf           <= '0;
        end
        else begin
            if (out_fire) out_buf_valid <= 1'b0;

            mul_start <= 1'b0; //pulso de un ciclo

            case (state)
                ST_IDLE: begin
                    if (in_fire) begin
                        if (bypass_mode) begin
                            out_buf       <= in_data;
                            out_buf_valid <= 1'b1;
                        end
                        else begin
                            sample_reg <= in_data;
                            lfo_reg    <= lfo_q1_31;
                            center_reg <= D_center_16_16;
                            depth_reg  <= $signed(D_depth_16_16);
                            wet_reg    <= wet_eff;
                            fb_reg     <= fb_eff;
                            state      <= ST_LOAD_MOD;
                        end
                    end
                end

                ST_LOAD_MOD: begin //depth * l
                    mul_a_reg <= depth_reg;
                    mul_b_reg <= lfo_reg;
                    mul_start <= 1'b1;
                    state     <= ST_MUL_MOD;
                end

                ST_MUL_MOD: begin
                    if (mul_valid) begin
                        if (delay_mod < $signed(D_MIN_16_16))      delay_reg <= D_MIN_16_16; //clamp del retardo
                        else if (delay_mod > $signed(D_MAX_16_16)) delay_reg <= D_MAX_16_16;
                        else                                        delay_reg <= delay_mod;
                        state <= ST_REQUEST_DELAY;
                    end
                end

                ST_REQUEST_DELAY: begin
                    if (request_ready) state <= ST_WAIT_DELAY;
                end

                ST_WAIT_DELAY: begin
                    if (delay_valid && delay_ready) begin
                        delay_sample_reg <= delay_output;
                        state            <= ST_LOAD_WET;
                    end
                end

                ST_LOAD_WET: begin //wet * d
                    mul_a_reg <= delay_sample_reg;
                    mul_b_reg <= wet_reg;
                    mul_start <= 1'b1;
                    state     <= ST_MUL_WET;
                end

                ST_MUL_WET: begin
                    if (mul_valid) begin
                        out_buf       <= sat_add32(sample_reg, mul_result); //y = x + wet * d
                        out_buf_valid <= 1'b1;
                        state         <= ST_LOAD_FB;
                    end
                end

                ST_LOAD_FB: begin //fb * d
                    mul_a_reg <= delay_sample_reg;
                    mul_b_reg <= fb_reg;
                    mul_start <= 1'b1;
                    state     <= ST_MUL_FB;
                end

                ST_MUL_FB: begin
                    if (mul_valid) begin
                        clip_input_reg <= sat_add32(sample_reg, mul_result); //u = x + fb * d
                        state          <= ST_CLIP;
                    end
                end

                ST_CLIP: begin //elige el tramo del soft clip
                    clip_negative_reg <= clip_input_reg[31];

                    if (clip_magnitude <= SC_T1_Q29) begin //tramo lineal: w = u
                        write_sample_reg <= clip_input_reg;
                        state            <= ST_WRITE_DELAY;
                    end
                    else if (clip_magnitude <= SC_T2_Q29) begin //K1 * (|u| - T1)
                        clip_base_reg <= SC_T1_Q29;
                        mul_a_reg     <= sat_sub32(clip_magnitude, SC_T1_Q29);
                        mul_b_reg     <= SC_K1_Q31;
                        mul_start     <= 1'b1;
                        state         <= ST_MUL_CLIP;
                    end
                    else begin //K2 * (|u| - T2)
                        clip_base_reg <= SC_Y2_Q29;
                        mul_a_reg     <= sat_sub32(clip_magnitude, SC_T2_Q29);
                        mul_b_reg     <= SC_K2_Q31;
                        mul_start     <= 1'b1;
                        state         <= ST_MUL_CLIP;
                    end
                end

                ST_MUL_CLIP: begin
                    if (mul_valid) begin
                        if (clip_negative_reg) write_sample_reg <= -clip_result; //recupera el signo
                        else                   write_sample_reg <= clip_result;
                        state <= ST_WRITE_DELAY;
                    end
                end

                ST_WRITE_DELAY: begin
                    if (write_ready) state <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
