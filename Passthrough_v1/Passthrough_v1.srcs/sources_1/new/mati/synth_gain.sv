`timescale 1ns/1ps

module synth_gain(
    input  logic clk,
    input  logic rst_n,

    input  logic               in_valid,
    output logic               in_ready,
    input  logic signed [31:0] sample_in_q3_29,
    input  logic signed [31:0] gain_q1_31,

    output logic               out_valid,
    input  logic               out_ready,
    output logic signed [31:0] sample_out_q3_29,

    output logic busy
);

import fx_dsp_pkg::*;

typedef enum logic [1:0] {
    ST_IDLE,
    ST_CALC,
    ST_HOLD
} state_t;

state_t state;

logic signed [31:0] sample_r;
logic signed [31:0] gain_r;

assign in_ready = (state == ST_IDLE);
assign out_valid = (state == ST_HOLD);
assign busy = (state != ST_IDLE);

always_ff @(posedge clk) begin
    if (!rst_n) begin
        state <= ST_IDLE;
        sample_r <= 32'sd0;
        gain_r <= 32'sd0;
        sample_out_q3_29 <= 32'sd0;
    end else begin
        case (state)
            ST_IDLE: begin
                if (in_valid && in_ready) begin
                    sample_r <= sample_in_q3_29;
                    gain_r <= gain_q1_31;
                    state <= ST_CALC;
                end
            end

            ST_CALC: begin
                sample_out_q3_29 <= mul_aud_q31(sample_r, gain_r);
                state <= ST_HOLD;
            end

            ST_HOLD: begin
                if (out_valid && out_ready)
                    state <= ST_IDLE;
            end

            default: state <= ST_IDLE;
        endcase
    end
end

`ifndef SYNTHESIS
always_ff @(posedge clk) begin
    if (rst_n && in_valid && in_ready) begin
        assert (gain_q1_31 >= 0)
            else $warning("synth_gain: gain negativo");
    end
end
`endif

endmodule