// fx_tremolo.sv
// Tremolo: modulacion de amplitud con un LFO triangular.
//
// y[n] = x[n] * g[n]
// g[n] = 1 - d/2 * (l[n] + 1)
//
// Un multiplicador de 32x32 bits (mul32_seq, 1 DSP48) compartido por una FSM.

module fx_tremolo(
    input  logic               clk,
    input  logic               rst_n,
    input  logic               enable,

    input  logic               in_valid,
    output logic               in_ready,
    input  logic signed [31:0] in_data,

    output logic               out_valid,
    input  logic               out_ready,
    output logic signed [31:0] out_data,

    input  logic signed [31:0] depth_q1_31,
    input  logic        [31:0] lfo_phase_inc_u32
);

    import fx_dsp_pkg::*;

    //parametros
    localparam logic signed [31:0] UNO_Q1_31 = 32'sh7FFF_FFFF;

    //estados
    typedef enum logic [2:0]{
        ST_IDLE,
        ST_LOAD_GAIN,
        ST_MUL_GAIN,
        ST_LOAD_AUDIO,
        ST_MUL_AUDIO,
        ST_SAVE_OUTPUT
    } state_t;

    state_t state; //maquina de estados

    logic signed [31:0] sample_reg;
    logic signed [31:0] depth_reg;
    logic signed [31:0] lfo_reg;

    logic signed [31:0] mul_a_reg;
    logic signed [31:0] mul_b_reg;
    logic               mul_start;
    logic               mul_busy;
    logic               mul_valid;
    logic signed [63:0] mul_p;

    logic               out_buf_valid;
    logic signed [31:0] out_buf;
    logic               enable_d;

    logic signed [31:0] depth_eff;
    logic signed [31:0] half_lfo;
    logic signed [31:0] mul_result;
    logic signed [31:0] gain_next;

    logic signed [31:0] lfo_q1_31;
    logic               lfo_tick;
    logic               lfo_clear;

    wire in_fire;
    wire out_fire;
    wire bypass_mode;
    wire can_accept;
    wire enable_rise;

    //instancias
    mul32_seq u_mul (
        .clk   (clk      ),
        .rst_n (rst_n    ),
        .start (mul_start),
        .a     (mul_a_reg),
        .b     (mul_b_reg),
        .busy  (mul_busy ),
        .valid (mul_valid),
        .p     (mul_p    )
    );

    fx_lfo_tri u_lfo (
        .clk           (clk              ),
        .rst_n         (rst_n            ),
        .tick          (lfo_tick         ),
        .phase_inc_u32 (lfo_phase_inc_u32),
        .phase_clear   (lfo_clear        ),
        .lfo_q1_31     (lfo_q1_31        )
    );

    //assigns
    assign bypass_mode = !enable;
    assign enable_rise = enable && !enable_d;

    assign can_accept = (state == ST_IDLE) && !out_buf_valid;

    assign in_fire  = in_valid  && in_ready;
    assign out_fire = out_valid && out_ready;

    assign lfo_tick = !bypass_mode && (state == ST_IDLE) && in_fire;
    assign lfo_clear = enable_rise && (state == ST_IDLE) && !out_buf_valid;

    //salidas
    assign out_valid = out_buf_valid;
    assign out_data  = out_buf;
    assign in_ready = can_accept;

    //logica combinacional
    always_comb begin //clamp depth 0 a 1
        if(depth_q1_31 < 32'sd0) depth_eff = 32'sd0;
        else if (depth_q1_31 > UNO_Q1_31) depth_eff = UNO_Q1_31;
        else depth_eff = depth_q1_31;
    end

    always_comb begin
        half_lfo = (lfo_reg >>> 1) + 32'sh4000_0000; //lfo/2 + 1/2
        //Se suma 0.5 antes de desplazar para redondear.
        mul_result = sat32((mul_p + (64'sd1 <<< 30)) >>> 31); //redondeo
        gain_next  = sat_sub32( UNO_Q1_31, mul_result);
    end

    //logica secuencial y FSM
    always_ff @(posedge clk)begin
        if(!rst_n)
            enable_d <= 1'b0;
        else
            enable_d <= enable;
    end

    always_ff @(posedge clk)begin
        if(!rst_n)begin
            state <= ST_IDLE;

            out_buf_valid   <= 1'b0;
            out_buf         <= '0;

            sample_reg      <= '0;
            lfo_reg         <= '0;
            depth_reg       <= '0;

            mul_a_reg       <= '0;
            mul_b_reg       <= '0;
            mul_start       <= 1'b0;
        end
        else begin
            if(out_fire) out_buf_valid <= 1'b0;

            mul_start <= 1'b0; //pulso de un ciclo

            if(bypass_mode)begin
                state <= ST_IDLE;

                if(in_fire)begin
                    out_buf <= in_data;
                    out_buf_valid <= 1'b1;
                end
            end
            else begin
                case (state)
                    ST_IDLE: begin
                        if(in_fire) begin
                            sample_reg <= in_data;
                            lfo_reg    <= lfo_q1_31;
                            depth_reg  <= depth_eff;
                            state      <= ST_LOAD_GAIN;
                        end
                    end

                    ST_LOAD_GAIN: begin
                        if(!mul_busy) begin
                            mul_a_reg <= depth_reg;
                            mul_b_reg <= half_lfo;
                            mul_start <= 1'b1;
                            state <= ST_MUL_GAIN;
                        end
                    end

                    ST_MUL_GAIN: begin
                        if(mul_valid) state <= ST_LOAD_AUDIO;
                    end

                    ST_LOAD_AUDIO:begin
                        mul_a_reg <= sample_reg;
                        mul_b_reg <= gain_next;
                        mul_start <= 1'b1;
                        state <= ST_MUL_AUDIO;
                    end

                    ST_MUL_AUDIO: begin
                        if(mul_valid) state <= ST_SAVE_OUTPUT;
                    end

                    ST_SAVE_OUTPUT: begin
                        out_buf       <= mul_result;
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