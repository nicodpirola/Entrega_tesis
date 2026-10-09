`timescale 1ns/1ps

// =============================================================================
// fx_pitch_zcd.sv
//
// Detector de periodo por cruces ascendentes por cero.
//
// - contador libre de muestras
// - histeresis para armar el detector
// - interpolacion lineal sub-muestra Q16.16
// - rechazo de cruces demasiado cercanos
// - recuperacion ante periodo demasiado largo
// - mediana de 3 periodos
// =============================================================================

module fx_pitch_zcd #(
    parameter logic [31:0] PERIOD_MIN_Q16 = 32'd8    << 16,
    parameter logic [31:0] PERIOD_MAX_Q16 = 32'd1200 << 16
)(
    input  logic               clk,
    input  logic               rst_n,

    input  logic               sample_valid,
    input  logic signed [31:0] sample_data,

    input  logic               gate,
    input  logic signed [31:0] zc_hyst_q3_29,

    output logic [31:0]        period_16_16,
    output logic               period_valid
);

import fx_dsp_pkg::*;

// =============================================================================
// SAMPLE COUNTER
// =============================================================================

logic [31:0] sample_count;

always_ff @(posedge clk) begin
    if (!rst_n)
        sample_count <= 32'd0;
    else if (sample_valid)
        sample_count <= sample_count + 1'b1;
end

// =============================================================================
// SAMPLE STATE
// =============================================================================

logic signed [31:0] x_prev;
logic signed [31:0] x_cur_r;

logic [31:0] sample_index_r;
logic        zc_armed;

// =============================================================================
// PERIOD STATE
// =============================================================================

logic [31:0] last_cross_q16;
logic        have_last_cross;

logic [31:0] period_0;
logic [31:0] period_1;
logic [31:0] period_2;
logic [1:0]  period_fill;

logic [31:0] cross_now_q16;
logic [31:0] period_raw;

// =============================================================================
// FRACTIONAL CROSSING DIVIDER
//
// frac = |x_prev| / (|x_prev| + x_cur)
//
// Ambos terminos son positivos durante un cruce ascendente.
// =============================================================================

logic        div_start;
logic        div_done;
logic [31:0] div_num;
logic [31:0] div_den;
logic [15:0] div_q;

div_frac16 u_div(
    .clk   (clk),
    .rst_n (rst_n),
    .clear (!gate),

    .start (div_start),
    .num   (div_num),
    .den   (div_den),

    .busy  (),
    .done  (div_done),
    .quot  (div_q)
);

// =============================================================================
// HELPERS
// =============================================================================

function automatic logic [31:0] median3(
    input logic [31:0] a,
    input logic [31:0] b,
    input logic [31:0] c
);
begin
    if ((a <= b && b <= c) || (c <= b && b <= a))
        median3 = b;
    else if ((b <= a && a <= c) || (c <= a && a <= b))
        median3 = a;
    else
        median3 = c;
end
endfunction

function automatic logic [31:0] add_u32_sat(
    input logic [31:0] a,
    input logic [31:0] b
);
logic [32:0] sum;
begin
    sum = {1'b0, a} + {1'b0, b};

    if (sum[32])
        add_u32_sat = 32'hFFFF_FFFF;
    else
        add_u32_sat = sum[31:0];
end
endfunction

// =============================================================================
// FSM
// =============================================================================

typedef enum logic [2:0] {
    ST_IDLE,
    ST_CHECK,
    ST_DIV,
    ST_PERIOD,
    ST_MEDIAN,
    ST_EMIT
} state_t;

state_t state;

always_ff @(posedge clk) begin
    if (!rst_n) begin
        state <= ST_IDLE;

        x_prev <= 32'sd0;
        x_cur_r <= 32'sd0;
        sample_index_r <= 32'd0;

        zc_armed <= 1'b0;

        last_cross_q16 <= 32'd0;
        have_last_cross <= 1'b0;

        period_0 <= 32'd0;
        period_1 <= 32'd0;
        period_2 <= 32'd0;
        period_fill <= 2'd0;

        div_start <= 1'b0;
        div_num <= 32'd0;
        div_den <= 32'd0;

        cross_now_q16 <= 32'd0;
        period_raw <= 32'd0;

        period_16_16 <= 32'd0;
        period_valid <= 1'b0;

    end else if (!gate) begin
        state <= ST_IDLE;

        x_prev <= 32'sd0;
        zc_armed <= 1'b0;

        have_last_cross <= 1'b0;

        period_0 <= 32'd0;
        period_1 <= 32'd0;
        period_2 <= 32'd0;
        period_fill <= 2'd0;

        div_start <= 1'b0;
        period_valid <= 1'b0;

    end else begin
        period_valid <= 1'b0;
        div_start <= 1'b0;

        case (state)

            // -----------------------------------------------------------------
            // Captura de muestra
            // -----------------------------------------------------------------

            ST_IDLE: begin
                if (sample_valid) begin
                    x_cur_r <= sample_data;
                    sample_index_r <= sample_count;
                    state <= ST_CHECK;
                end
            end

            // -----------------------------------------------------------------
            // Histeresis + cruce ascendente
            // -----------------------------------------------------------------

            ST_CHECK: begin
                if (x_cur_r <= -zc_hyst_q3_29)
                    zc_armed <= 1'b1;

                if (
                    zc_armed &&
                    (x_prev < 0) &&
                    (x_cur_r >= 0)
                ) begin
                    zc_armed <= 1'b0;

                    div_num <= abs32(x_prev);

                    div_den <= add_u32_sat(
                        abs32(x_prev),
                        $unsigned(x_cur_r)
                    );

                    div_start <= 1'b1;
                    state <= ST_DIV;

                end else begin
                    x_prev <= x_cur_r;
                    state <= ST_IDLE;
                end
            end

            // -----------------------------------------------------------------
            // Esperar interpolacion
            // -----------------------------------------------------------------

            ST_DIV: begin
                if (div_done) begin
                    // Cruce entre idx-1 e idx:
                    //
                    // position = (idx - 1) + frac
                    //
                    // Q16.16. El contador modulo 2^16 es suficiente porque
                    // los periodos validos son mucho menores a 65536 muestras.
                    cross_now_q16 <= {
                        sample_index_r[15:0] - 16'd1,
                        div_q
                    };

                    state <= ST_PERIOD;
                end
            end

            // -----------------------------------------------------------------
            // Calculo y validacion de periodo
            // -----------------------------------------------------------------

            ST_PERIOD: begin : period_block
                logic [31:0] candidate;

                x_prev <= x_cur_r;

                if (!have_last_cross) begin
                    last_cross_q16 <= cross_now_q16;
                    have_last_cross <= 1'b1;
                    state <= ST_IDLE;

                end else begin
                    candidate =
                        cross_now_q16 -
                        last_cross_q16;

                    if (candidate < PERIOD_MIN_Q16) begin
                        // Cruce espurio.
                        // No movemos la referencia.
                        state <= ST_IDLE;

                    end else if (candidate > PERIOD_MAX_Q16) begin
                        // Perdida de seguimiento.
                        // Este cruce pasa a ser la nueva referencia.
                        last_cross_q16 <= cross_now_q16;

                        period_0 <= 32'd0;
                        period_1 <= 32'd0;
                        period_2 <= 32'd0;
                        period_fill <= 2'd0;

                        state <= ST_IDLE;

                    end else begin
                        period_raw <= candidate;
                        last_cross_q16 <= cross_now_q16;
                        state <= ST_MEDIAN;
                    end
                end
            end

            // -----------------------------------------------------------------
            // Ventana de 3
            // -----------------------------------------------------------------

            ST_MEDIAN: begin
                period_2 <= period_1;
                period_1 <= period_0;
                period_0 <= period_raw;

                if (period_fill < 2'd3)
                    period_fill <= period_fill + 1'b1;

                state <= ST_EMIT;
            end

            // -----------------------------------------------------------------
            // Salida
            // -----------------------------------------------------------------

            ST_EMIT: begin
                if (period_fill == 2'd3) begin
                    period_16_16 <= median3(
                        period_0,
                        period_1,
                        period_2
                    );

                    period_valid <= 1'b1;
                end

                state <= ST_IDLE;
            end

            default:
                state <= ST_IDLE;
        endcase
    end
end

endmodule


// =============================================================================
// div_frac16
//
// Calcula los 16 bits fraccionales de:
//
//     num / den
//
// Para el ZCD siempre num <= den.
// =============================================================================

module div_frac16(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        clear,

    input  logic        start,
    input  logic [31:0] num,
    input  logic [31:0] den,

    output logic        busy,
    output logic        done,
    output logic [15:0] quot
);

logic [31:0] remainder;
logic [31:0] denominator;

logic [15:0] quotient;
logic [4:0]  count;
logic        running;

assign busy = running;

always_ff @(posedge clk) begin
    if (!rst_n || clear) begin
        running <= 1'b0;
        done <= 1'b0;

        quot <= 16'd0;

        remainder <= 32'd0;
        denominator <= 32'd0;
        quotient <= 16'd0;
        count <= 5'd0;

    end else begin
        done <= 1'b0;

        if (start && !running) begin
            remainder <= num;
            denominator <= den;

            quotient <= 16'd0;
            count <= 5'd16;
            running <= 1'b1;

        end else if (running) begin : divide_step
            logic [32:0] shifted;

            shifted = {
                remainder,
                1'b0
            };

            if (
                shifted >=
                {1'b0, denominator}
            ) begin
                remainder <=
                    shifted -
                    {1'b0, denominator};

                quotient <= {
                    quotient[14:0],
                    1'b1
                };

            end else begin
                remainder <= shifted[31:0];

                quotient <= {
                    quotient[14:0],
                    1'b0
                };
            end

            count <= count - 1'b1;

            if (count == 5'd1) begin
                running <= 1'b0;
                done <= 1'b1;

                quot <=
                    (
                        shifted >=
                        {1'b0, denominator}
                    )
                    ? {quotient[14:0], 1'b1}
                    : {quotient[14:0], 1'b0};
            end
        end
    end
end

endmodule