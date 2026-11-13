// fx_chorus.sv
// Chorus con retardo modulado y lpf opcional en la rama wet
//
// D[n] = D_center + D_depth * l[n]      (l[n]: LFO triangular, -1 a 1)
// d[n] = w[n - D[n]]                    (w[n] = x[n], sin feedback)
// f[n] = LPF(d[n])                      (si lpf_on = 0, f[n] = d[n])
// y[n] = x[n] + wet * f[n]
//
// lpf tpt de un polo:  v = (d - s) * G,  f = s + v,  s = f + v
//
// un multiplicador de 32x32 bits (mul32_seq, 1 DSP48) compartido por una FSM:
// modulacion del retardo, filtro y mezcla wet. La interpolacion fraccional esta
// en delay_line.

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

    //parametros
    localparam int          MAX_DELAY_SAMPLES = (1 << ADDR_W) - 8;                //margen al final de la memoria
    localparam logic [31:0] D_MIN_16_16 = 32'h0001_0000;                          //1 muestra
    localparam logic [31:0] D_MAX_16_16 = {MAX_DELAY_SAMPLES[15:0], 16'd0};

    localparam logic signed [31:0] WET_MAX_Q31 = 32'sh7FFF_FFFF; //1
    localparam logic signed [31:0] G_MAX_Q31   = 32'sh4000_0000; //0.5, corte maximo fs/4

    //estados
    typedef enum logic [3:0]{
        ST_IDLE,
        ST_LOAD_MOD,
        ST_MUL_MOD,
        ST_REQUEST_DELAY,
        ST_WAIT_DELAY,
        ST_LOAD_LPF,
        ST_MUL_LPF,
        ST_LOAD_WET,
        ST_MUL_WET,
        ST_WRITE_DELAY
    } state_t;

    state_t state; //maquina de estados

    logic signed [31:0] sample_reg;
    logic signed [31:0] lfo_reg;
    logic        [31:0] center_reg;
    logic signed [31:0] depth_reg;
    logic        [31:0] delay_reg;
    logic signed [31:0] wet_reg;
    logic signed [31:0] lpf_g_reg;
    logic               lpf_enable_reg;

    logic signed [31:0] delay_sample_reg;
    logic signed [31:0] wet_sample_reg;
    logic signed [31:0] lpf_state_reg;

    logic signed [31:0] mul_a_reg;
    logic signed [31:0] mul_b_reg;
    logic               mul_start;
    logic               mul_valid;
    logic signed [63:0] mul_p;

    logic signed [31:0] mul_result;
    logic signed [31:0] delay_mod;
    logic signed [31:0] lpf_delta;
    logic signed [31:0] lpf_output;
    logic signed [31:0] lpf_state_next;

    logic signed [31:0] wet_eff;
    logic signed [31:0] lpf_g_eff;

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
        .clk           (clk          ),
        .rst_n         (rst_n        ),

        .req_valid     (request_valid),
        .req_ready     (request_ready),
        .D_16_16       (delay_reg    ),

        .d_out         (delay_output ),
        .d_valid       (delay_valid  ),
        .d_ready       (delay_ready  ),

        .w_valid       (write_valid  ),
        .w_ready       (write_ready  ),
        .w_in          (sample_reg   ),

        .clear_req     (clear_request),
        .clear_busy    (clear_busy   ),
        .clear_done    (             ),

        .write_ptr_dbg (             )
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

    always_comb begin //clamp G 0 a 0.5
        if (lpf_G_q1_31 < 32'sd0)         lpf_g_eff = 32'sd0;
        else if (lpf_G_q1_31 > G_MAX_Q31) lpf_g_eff = G_MAX_Q31;
        else                              lpf_g_eff = lpf_G_q1_31;
    end

    always_comb begin
        mul_result = sat32((mul_p + (64'sd1 <<< 30)) >>> 31); //redondeo

        delay_mod = $signed(center_reg) + mul_result; //D = center + depth * l

        lpf_delta      = sat_sub32(delay_sample_reg, lpf_state_reg);                  //d - s
        lpf_output     = sat_add32(lpf_state_reg, mul_result);                        //f = s + v
        lpf_state_next = sat_add32(lpf_state_reg, sat_add32(mul_result, mul_result)); //s = s + 2v
    end

    //logica secuencial y FSM
    always_ff @(posedge clk) begin
        if (!rst_n) enable_d <= 1'b0;
        else        enable_d <= enable;
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state            <= ST_IDLE;

            sample_reg       <= '0;
            lfo_reg          <= '0;
            center_reg       <= '0;
            depth_reg        <= '0;
            delay_reg        <= '0;
            wet_reg          <= '0;
            lpf_g_reg        <= '0;
            lpf_enable_reg   <= 1'b0;

            delay_sample_reg <= '0;
            wet_sample_reg   <= '0;
            lpf_state_reg    <= '0;

            mul_a_reg        <= '0;
            mul_b_reg        <= '0;
            mul_start        <= 1'b0;

            out_buf_valid    <= 1'b0;
            out_buf          <= '0;
        end
        else begin
            if (out_fire) out_buf_valid <= 1'b0;

            mul_start <= 1'b0; //pulso de un ciclo

            if (enable_rise && (state == ST_IDLE)) lpf_state_reg <= '0;

            case (state)
                ST_IDLE: begin
                    if (in_fire) begin
                        if (bypass_mode) begin
                            out_buf       <= in_data;
                            out_buf_valid <= 1'b1;
                        end
                        else begin
                            sample_reg     <= in_data;
                            lfo_reg        <= lfo_q1_31;
                            center_reg     <= D_center_16_16;
                            depth_reg      <= $signed(D_depth_16_16);
                            wet_reg        <= wet_eff;
                            lpf_g_reg      <= lpf_g_eff;
                            lpf_enable_reg <= lpf_on;
                            state          <= ST_LOAD_MOD;
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

                        if (lpf_enable_reg) begin
                            state <= ST_LOAD_LPF;
                        end
                        else begin
                            wet_sample_reg <= delay_output; //sin filtro: f = d
                            state          <= ST_LOAD_WET;
                        end
                    end
                end

                ST_LOAD_LPF: begin //(d - s) * G
                    mul_a_reg <= lpf_delta;
                    mul_b_reg <= lpf_g_reg;
                    mul_start <= 1'b1;
                    state     <= ST_MUL_LPF;
                end

                ST_MUL_LPF: begin
                    if (mul_valid) begin
                        wet_sample_reg <= lpf_output;
                        lpf_state_reg  <= lpf_state_next;
                        state          <= ST_LOAD_WET;
                    end
                end

                ST_LOAD_WET: begin //wet * f
                    mul_a_reg <= wet_sample_reg;
                    mul_b_reg <= wet_reg;
                    mul_start <= 1'b1;
                    state     <= ST_MUL_WET;
                end

                ST_MUL_WET: begin
                    if (mul_valid) begin
                        out_buf       <= sat_add32(sample_reg, mul_result); //y = x + wet * f
                        out_buf_valid <= 1'b1;
                        state         <= ST_WRITE_DELAY;
                    end
                end

                ST_WRITE_DELAY: begin //w = x
                    if (write_ready) state <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
