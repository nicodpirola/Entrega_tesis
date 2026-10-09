`timescale 1ns/1ps

module synth_svf(
    input  logic clk,
    input  logic rst_n,
    input  logic clear_state,

    input  logic               in_valid,
    output logic               in_ready,
    input  logic signed [31:0] sample_in_q3_29,

    input  logic [1:0]         filter_mode,
    input  logic signed [31:0] a1_q1_31,
    input  logic signed [31:0] a2_q1_31,
    input  logic signed [31:0] a3_q1_31,
    input  logic signed [31:0] k_q3_29,

    output logic               out_valid,
    input  logic               out_ready,
    output logic signed [31:0] sample_out_q3_29,

    output logic signed [31:0] lp_q3_29,
    output logic signed [31:0] bp_q3_29,
    output logic signed [31:0] hp_q3_29,
    output logic               busy
);

localparam logic [1:0] MODE_LP     = 2'd0;
localparam logic [1:0] MODE_BP     = 2'd1;
localparam logic [1:0] MODE_HP     = 2'd2;
localparam logic [1:0] MODE_BYPASS = 2'd3;

typedef enum logic [3:0] {
    S_IDLE,
    S_MUL_A1_IC1,
    S_USE_A1_IC1,
    S_MUL_A2_V3,
    S_USE_A2_V3,
    S_MUL_A2_IC1,
    S_USE_A2_IC1,
    S_MUL_A3_V3,
    S_USE_A3_V3,
    S_MUL_K_V1,
    S_USE_K_V1,
    S_HOLD
} state_t;

state_t state;

logic signed [31:0] x_r;
logic signed [31:0] a1_r, a2_r, a3_r, k_r;
logic [1:0] mode_r;

logic signed [31:0] ic1eq_r, ic2eq_r;
logic signed [31:0] v3_r, v1_r, v2_r;
logic signed [31:0] term_r;

logic signed [31:0] mul_a_r, mul_b_r;
logic signed [63:0] mul_product_r;
logic mul_capture;

logic signed [63:0] rounded_q31_w;
logic signed [63:0] rounded_q29_w;
logic signed [31:0] mul_q31_w;
logic signed [31:0] mul_q29_w;

logic signed [63:0] v1_ext_w;
logic signed [63:0] v2_ext_w;
logic signed [63:0] ic1_next_ext_w;
logic signed [63:0] ic2_next_ext_w;
logic signed [63:0] hp_ext_w;

logic signed [31:0] v1_w;
logic signed [31:0] v2_w;
logic signed [31:0] ic1_next_w;
logic signed [31:0] ic2_next_w;
logic signed [31:0] hp_w;

function automatic logic signed [31:0] sat32(input logic signed [63:0] value);
begin
    if (value > 64'sh0000_0000_7FFF_FFFF)
        sat32 = 32'sh7FFF_FFFF;
    else if (value < -64'sh0000_0000_8000_0000)
        sat32 = 32'sh8000_0000;
    else
        sat32 = value[31:0];
end
endfunction

function automatic logic signed [63:0] round_shift31(input logic signed [63:0] value);
logic signed [63:0] magnitude;
begin
    if (value >= 0)
        round_shift31 = (value + (64'sd1 <<< 30)) >>> 31;
    else begin
        magnitude = -value;
        round_shift31 = -((magnitude + (64'sd1 <<< 30)) >>> 31);
    end
end
endfunction

function automatic logic signed [63:0] round_shift29(input logic signed [63:0] value);
logic signed [63:0] magnitude;
begin
    if (value >= 0)
        round_shift29 = (value + (64'sd1 <<< 28)) >>> 29;
    else begin
        magnitude = -value;
        round_shift29 = -((magnitude + (64'sd1 <<< 28)) >>> 29);
    end
end
endfunction

assign in_ready = (state == S_IDLE);
assign out_valid = (state == S_HOLD);
assign busy = (state != S_IDLE);

// El multiplicador se usa solamente en estos estados.
// El producto queda registrado antes de hacer redondeo, suma o saturacion.
always_comb begin
    case (state)
        S_MUL_A1_IC1,
        S_MUL_A2_V3,
        S_MUL_A2_IC1,
        S_MUL_A3_V3,
        S_MUL_K_V1:
            mul_capture = 1'b1;

        default:
            mul_capture = 1'b0;
    endcase
end

always_ff @(posedge clk) begin
    if (!rst_n)
        mul_product_r <= 64'sd0;
    else if (clear_state)
        mul_product_r <= 64'sd0;
    else if (mul_capture)
        mul_product_r <= $signed(mul_a_r) * $signed(mul_b_r);
end

assign rounded_q31_w = round_shift31(mul_product_r);
assign rounded_q29_w = round_shift29(mul_product_r);

assign mul_q31_w = sat32(rounded_q31_w);
assign mul_q29_w = sat32(rounded_q29_w);

// v1 = a1*ic1 + a2*v3
assign v1_ext_w =
    $signed(term_r) +
    $signed(mul_q31_w);

assign v1_w = sat32(v1_ext_w);

// v2 = ic2 + a2*ic1 + a3*v3
assign v2_ext_w =
    $signed(ic2eq_r) +
    $signed(term_r) +
    $signed(mul_q31_w);

assign v2_w = sat32(v2_ext_w);

// Estados de los integradores.
// La multiplicacion por 2 se hace a 64 bits para no perder overflow
// antes de entrar al saturador.
assign ic1_next_ext_w =
    (64'sd2 * $signed(v1_r)) -
    $signed(ic1eq_r);

assign ic2_next_ext_w =
    (64'sd2 * $signed(v2_r)) -
    $signed(ic2eq_r);

assign ic1_next_w = sat32(ic1_next_ext_w);
assign ic2_next_w = sat32(ic2_next_ext_w);

// HP = x - k*v1 - v2
assign hp_ext_w =
    $signed(x_r) -
    $signed(mul_q29_w) -
    $signed(v2_r);

assign hp_w = sat32(hp_ext_w);

always_ff @(posedge clk) begin
    if (!rst_n) begin
        state <= S_IDLE;

        x_r <= '0;
        a1_r <= '0;
        a2_r <= '0;
        a3_r <= '0;
        k_r <= '0;
        mode_r <= MODE_LP;

        ic1eq_r <= '0;
        ic2eq_r <= '0;

        v3_r <= '0;
        v1_r <= '0;
        v2_r <= '0;
        term_r <= '0;

        mul_a_r <= '0;
        mul_b_r <= '0;

        lp_q3_29 <= '0;
        bp_q3_29 <= '0;
        hp_q3_29 <= '0;
        sample_out_q3_29 <= '0;
    end else if (clear_state) begin
        state <= S_IDLE;

        ic1eq_r <= '0;
        ic2eq_r <= '0;

        v3_r <= '0;
        v1_r <= '0;
        v2_r <= '0;
        term_r <= '0;

        mul_a_r <= '0;
        mul_b_r <= '0;

        lp_q3_29 <= '0;
        bp_q3_29 <= '0;
        hp_q3_29 <= '0;
        sample_out_q3_29 <= '0;
    end else begin
        case (state)

            S_IDLE: begin
                if (in_valid && in_ready) begin
                    x_r <= sample_in_q3_29;

                    a1_r <= a1_q1_31;
                    a2_r <= a2_q1_31;
                    a3_r <= a3_q1_31;
                    k_r <= k_q3_29;
                    mode_r <= filter_mode;

                    // v3 = x - ic2
                    v3_r <= sat32(
                        $signed(sample_in_q3_29) -
                        $signed(ic2eq_r)
                    );

                    // Primera operacion: a1 * ic1
                    mul_a_r <= ic1eq_r;
                    mul_b_r <= a1_q1_31;

                    state <= S_MUL_A1_IC1;
                end
            end

            S_MUL_A1_IC1: begin
                // mul_product_r captura a1 * ic1
                state <= S_USE_A1_IC1;
            end

            S_USE_A1_IC1: begin
                term_r <= mul_q31_w;

                // Siguiente operacion: a2 * v3
                mul_a_r <= v3_r;
                mul_b_r <= a2_r;

                state <= S_MUL_A2_V3;
            end

            S_MUL_A2_V3: begin
                // mul_product_r captura a2 * v3
                state <= S_USE_A2_V3;
            end

            S_USE_A2_V3: begin
                // v1 = a1*ic1 + a2*v3
                v1_r <= v1_w;

                // Siguiente operacion: a2 * ic1
                mul_a_r <= ic1eq_r;
                mul_b_r <= a2_r;

                state <= S_MUL_A2_IC1;
            end

            S_MUL_A2_IC1: begin
                // mul_product_r captura a2 * ic1
                state <= S_USE_A2_IC1;
            end

            S_USE_A2_IC1: begin
                term_r <= mul_q31_w;

                // Siguiente operacion: a3 * v3
                mul_a_r <= v3_r;
                mul_b_r <= a3_r;

                state <= S_MUL_A3_V3;
            end

            S_MUL_A3_V3: begin
                // mul_product_r captura a3 * v3
                state <= S_USE_A3_V3;
            end

            S_USE_A3_V3: begin
                // v2 = ic2 + a2*ic1 + a3*v3
                v2_r <= v2_w;

                // Siguiente operacion: k * v1
                mul_a_r <= v1_r;
                mul_b_r <= k_r;

                state <= S_MUL_K_V1;
            end

            S_MUL_K_V1: begin
                // mul_product_r captura k * v1
                state <= S_USE_K_V1;
            end

            S_USE_K_V1: begin
                lp_q3_29 <= v2_r;
                bp_q3_29 <= v1_r;
                hp_q3_29 <= hp_w;

                ic1eq_r <= ic1_next_w;
                ic2eq_r <= ic2_next_w;

                case (mode_r)
                    MODE_LP:
                        sample_out_q3_29 <= v2_r;

                    MODE_BP:
                        sample_out_q3_29 <= v1_r;

                    MODE_HP:
                        sample_out_q3_29 <= hp_w;

                    default:
                        sample_out_q3_29 <= x_r;
                endcase

                state <= S_HOLD;
            end

            S_HOLD: begin
                if (out_valid && out_ready)
                    state <= S_IDLE;
            end

            default:
                state <= S_IDLE;
        endcase
    end
end

`ifndef SYNTHESIS

always_ff @(posedge clk) begin
    if (rst_n && in_valid && in_ready) begin
        assert (a1_q1_31 >= 0)
            else $warning("synth_svf: a1 negativo");

        assert (a2_q1_31 >= 0)
            else $warning("synth_svf: a2 negativo");

        assert (a3_q1_31 >= 0)
            else $warning("synth_svf: a3 negativo");

        assert (k_q3_29 >= 0)
            else $warning("synth_svf: k negativo");
    end
end

`endif

endmodule