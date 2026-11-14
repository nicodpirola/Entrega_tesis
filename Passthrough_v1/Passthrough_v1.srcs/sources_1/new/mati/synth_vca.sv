// synth_vca.sv
// VCA y volumen master del synth en un solo bloque.
//
// v[n] = x[n] * g_vca[n]        (g_vca: envolvente de la entrada)
// y[n] = v[n] * g_master
//
// Un multiplicador de 32x32 bits (mul32_seq, 1 DSP48) compartido por una FSM.
// Cada producto se redondea por separado, igual que con dos etapas de ganancia.

`timescale 1ns/1ps

module synth_vca(
    input  logic               clk,
    input  logic               rst_n,

    input  logic               in_valid,
    output logic               in_ready,
    input  logic signed [31:0] in_data,

    output logic               out_valid,
    input  logic               out_ready,
    output logic signed [31:0] out_data,

    input  logic signed [31:0] vca_gain_q1_31,
    input  logic signed [31:0] master_q1_31
);

    import fx_dsp_pkg::*;

    //estados
    typedef enum logic [2:0] {
        ST_IDLE,
        ST_LOAD_VCA,
        ST_MUL_VCA,
        ST_LOAD_MASTER,
        ST_MUL_MASTER
    } state_t;

    state_t state;

    //copias de la muestra y de los parametros
    logic signed [31:0] sample_reg;
    logic signed [31:0] vca_reg;
    logic signed [31:0] master_reg;
    logic signed [31:0] vca_out_reg;

    //multiplicador compartido
    logic signed [31:0] mul_a_reg;
    logic signed [31:0] mul_b_reg;
    logic               mul_start;
    logic               mul_valid;
    logic signed [63:0] mul_p;

    logic signed [31:0] mul_result;

    //buffer de salida
    logic signed [31:0] out_buf;
    logic               out_buf_valid;

    wire can_accept;
    wire in_fire;
    wire out_fire;

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
    end

    //logica secuencial y FSM
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            sample_reg    <= '0;
            vca_reg       <= '0;
            master_reg    <= '0;
            vca_out_reg   <= '0;
            mul_a_reg     <= '0;
            mul_b_reg     <= '0;
            mul_start     <= 1'b0;
            out_buf_valid <= 1'b0;
            out_buf       <= '0;
        end
        else begin
            if (out_fire) out_buf_valid <= 1'b0;

            mul_start <= 1'b0; //pulso de un ciclo

            case (state)
                ST_IDLE: begin
                    if (in_fire) begin
                        sample_reg <= in_data;
                        vca_reg    <= vca_gain_q1_31;
                        master_reg <= master_q1_31;
                        state      <= ST_LOAD_VCA;
                    end
                end

                ST_LOAD_VCA: begin //x * g_vca
                    mul_a_reg <= sample_reg;
                    mul_b_reg <= vca_reg;
                    mul_start <= 1'b1;
                    state     <= ST_MUL_VCA;
                end

                ST_MUL_VCA: begin
                    if (mul_valid) begin
                        vca_out_reg <= mul_result;
                        state       <= ST_LOAD_MASTER;
                    end
                end

                ST_LOAD_MASTER: begin //v * g_master
                    mul_a_reg <= vca_out_reg;
                    mul_b_reg <= master_reg;
                    mul_start <= 1'b1;
                    state     <= ST_MUL_MASTER;
                end

                ST_MUL_MASTER: begin
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
