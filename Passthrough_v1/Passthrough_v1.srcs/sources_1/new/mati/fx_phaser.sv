// fx_phaser.sv
// Phaser de cuatro etapas pasatodo con feedback
//
// G[n] = G_min + (G_max - G_min) * (l[n] + 1) / 2     (l[n]: LFO triangular, -1 a 1)
// u[n] = x[n] + fb * a[n-1]                           (a: salida de las cuatro etapas)
// a[n] = AP4(AP3(AP2(AP1(u[n]))))
// y[n] = (x[n] + a[n]) / 2
//
// cada etapa es un pasatodo de un polo armado con el lpf tpt:
//   v = (u - s) * G,  p = s + v,  s = p + v,  ap = 2p - u
//
// un multiplicador de 32x32 bits (mul32_seq, 1 DSP48) compartido por una FSM:
// G, feedback y las cuatro etapas.

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

    input  logic        [31:0] lfo_phase_inc_u32,
    input  logic signed [31:0] g_min_q1_31,
    input  logic signed [31:0] g_max_q1_31,
    input  logic signed [31:0] fb_q1_31
);

    import fx_dsp_pkg::*;

    //parametros
    localparam logic signed [31:0] G_MAX_Q31  = 32'sh4000_0000; //0.5, corte maximo fs/4
    localparam logic signed [31:0] FB_MAX_Q31 = 32'sh7333_3333; //0.9, el feedback va de -0.9 a 0.9

    //estados
    typedef enum logic [2:0]{
        ST_IDLE,
        ST_LOAD_G,
        ST_MUL_G,
        ST_LOAD_FB,
        ST_MUL_FB,
        ST_LOAD_STAGE,
        ST_MUL_STAGE,
        ST_MIX
    } state_t;

    state_t state; //maquina de estados

    logic signed [31:0] sample_reg;
    logic signed [31:0] lfo_reg;
    logic signed [31:0] g_min_reg;
    logic signed [31:0] g_max_reg;
    logic signed [31:0] fb_reg;
    logic signed [31:0] g_reg;

    logic signed [31:0] ap_state_0;
    logic signed [31:0] ap_state_1;
    logic signed [31:0] ap_state_2;
    logic signed [31:0] ap_state_3;
    logic        [1:0]  stage_index;

    logic signed [31:0] stage_input_reg;
    logic signed [31:0] allpass_output_reg;
    logic signed [31:0] feedback_reg;

    logic signed [31:0] mul_a_reg;
    logic signed [31:0] mul_b_reg;
    logic               mul_start;
    logic               mul_valid;
    logic signed [63:0] mul_p;

    logic signed [31:0] mul_result;
    logic signed [31:0] lfo_unipolar;
    logic signed [31:0] g_range;
    logic signed [31:0] g_next;
    logic signed [31:0] feedback_input;

    logic signed [31:0] stage_state;
    logic signed [31:0] stage_lp;
    logic signed [31:0] stage_state_next;
    logic signed [31:0] stage_output;
    logic signed [31:0] mix_value;

    logic signed [31:0] g_min_eff;
    logic signed [31:0] g_max_eff;
    logic signed [31:0] fb_eff;

    logic signed [31:0] lfo_q1_31;

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

    //instancias
    fx_lfo_tri u_lfo (
        .clk           (clk              ),
        .rst_n         (rst_n            ),
        .tick          (lfo_tick         ),
        .phase_inc_u32 (lfo_phase_inc_u32),
        .phase_clear   (lfo_clear        ),
        .lfo_q1_31     (lfo_q1_31        )
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
    assign bypass_mode = !enable;

    assign can_accept = (state == ST_IDLE) && !out_buf_valid && !enable_rise;

    assign in_fire  = in_valid && in_ready;
    assign out_fire = out_valid && out_ready;

    assign lfo_tick  = in_fire && !bypass_mode; //el LFO avanza una vez por muestra procesada
    assign lfo_clear = enable_rise;

    //salidas
    assign in_ready  = can_accept;
    assign out_valid = out_buf_valid;
    assign out_data  = out_buf;

    //logica combinacional
    always_comb begin //clamp G_min y G_max 0 a 0.5
        if (g_min_q1_31 < 32'sd0)         g_min_eff = 32'sd0;
        else if (g_min_q1_31 > G_MAX_Q31) g_min_eff = G_MAX_Q31;
        else                              g_min_eff = g_min_q1_31;

        if (g_max_q1_31 < 32'sd0)         g_max_eff = 32'sd0;
        else if (g_max_q1_31 > G_MAX_Q31) g_max_eff = G_MAX_Q31;
        else                              g_max_eff = g_max_q1_31;
    end

    always_comb begin //clamp fb -0.9 a 0.9
        if (fb_q1_31 > FB_MAX_Q31)       fb_eff = FB_MAX_Q31;
        else if (fb_q1_31 < -FB_MAX_Q31) fb_eff = -FB_MAX_Q31;
        else                             fb_eff = fb_q1_31;
    end

    always_comb begin
        mul_result = sat32((mul_p + (64'sd1 <<< 30)) >>> 31); //redondeo

        lfo_unipolar = (lfo_reg >>> 1) + 32'sh4000_0000; //(l + 1) / 2
        g_range      = sat_sub32(g_max_reg, g_min_reg);
        g_next       = sat_add32(g_min_reg, mul_result);  //G = G_min + (G_max - G_min) * (l + 1) / 2

        feedback_input = sat_add32(sample_reg, mul_result); //u = x + fb * a[n-1]

        case (stage_index)
            2'd0:    stage_state = ap_state_0;
            2'd1:    stage_state = ap_state_1;
            2'd2:    stage_state = ap_state_2;
            default: stage_state = ap_state_3;
        endcase

        stage_lp         = sat_add32(stage_state, mul_result);                    //p = s + v
        stage_state_next = sat_add32(stage_lp, mul_result);                       //s = p + v
        stage_output     = sat_sub32(sat_add32(stage_lp, stage_lp), stage_input_reg); //ap = 2p - u

        mix_value = sat_add32(sample_reg >>> 1, allpass_output_reg >>> 1); //y = (x + a) / 2
    end

    //logica secuencial y FSM
    always_ff @(posedge clk) begin
        if (!rst_n) enable_d <= 1'b0;
        else        enable_d <= enable;
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state              <= ST_IDLE;

            sample_reg         <= '0;
            lfo_reg            <= '0;
            g_min_reg          <= '0;
            g_max_reg          <= '0;
            fb_reg             <= '0;
            g_reg              <= '0;

            ap_state_0         <= '0;
            ap_state_1         <= '0;
            ap_state_2         <= '0;
            ap_state_3         <= '0;
            stage_index        <= '0;

            stage_input_reg    <= '0;
            allpass_output_reg <= '0;
            feedback_reg       <= '0;

            mul_a_reg          <= '0;
            mul_b_reg          <= '0;
            mul_start          <= 1'b0;

            out_buf_valid      <= 1'b0;
            out_buf            <= '0;
        end
        else begin
            if (out_fire) out_buf_valid <= 1'b0;

            mul_start <= 1'b0; //pulso de un ciclo

            if (enable_rise) begin //al habilitar se borran los estados de las etapas
                state        <= ST_IDLE;
                ap_state_0   <= '0;
                ap_state_1   <= '0;
                ap_state_2   <= '0;
                ap_state_3   <= '0;
                feedback_reg <= '0;
            end
            else begin
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
                                g_min_reg  <= g_min_eff;
                                g_max_reg  <= g_max_eff;
                                fb_reg     <= fb_eff;
                                state      <= ST_LOAD_G;
                            end
                        end
                    end

                    ST_LOAD_G: begin //(G_max - G_min) * (l + 1) / 2
                        mul_a_reg <= lfo_unipolar;
                        mul_b_reg <= g_range;
                        mul_start <= 1'b1;
                        state     <= ST_MUL_G;
                    end

                    ST_MUL_G: begin
                        if (mul_valid) begin
                            g_reg <= g_next;
                            state <= ST_LOAD_FB;
                        end
                    end

                    ST_LOAD_FB: begin //fb * a[n-1]
                        mul_a_reg <= feedback_reg;
                        mul_b_reg <= fb_reg;
                        mul_start <= 1'b1;
                        state     <= ST_MUL_FB;
                    end

                    ST_MUL_FB: begin
                        if (mul_valid) begin
                            stage_input_reg <= feedback_input;
                            stage_index     <= 2'd0;
                            state           <= ST_LOAD_STAGE;
                        end
                    end

                    ST_LOAD_STAGE: begin //(u - s) * G
                        mul_a_reg <= sat_sub32(stage_input_reg, stage_state);
                        mul_b_reg <= g_reg;
                        mul_start <= 1'b1;
                        state     <= ST_MUL_STAGE;
                    end

                    ST_MUL_STAGE: begin
                        if (mul_valid) begin
                            case (stage_index)
                                2'd0:    ap_state_0 <= stage_state_next;
                                2'd1:    ap_state_1 <= stage_state_next;
                                2'd2:    ap_state_2 <= stage_state_next;
                                default: ap_state_3 <= stage_state_next;
                            endcase

                            if (stage_index == 2'd3) begin //ultima etapa
                                allpass_output_reg <= stage_output;
                                state              <= ST_MIX;
                            end
                            else begin //la salida de una etapa es la entrada de la siguiente
                                stage_input_reg <= stage_output;
                                stage_index     <= stage_index + 2'd1;
                                state           <= ST_LOAD_STAGE;
                            end
                        end
                    end

                    ST_MIX: begin
                        out_buf       <= mix_value;
                        out_buf_valid <= 1'b1;
                        feedback_reg  <= allpass_output_reg; //se usa en la muestra siguiente
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
