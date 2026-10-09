`timescale 1ns/1ps

module phase_accum(
    input logic         clk,
    input logic         rst_n,
    input logic         tick,
    input logic  [31:0] phase_inc,
    output logic [31:0] phase
);

    always_ff @(posedge clk)begin
        if(!rst_n)begin
            phase <= '0;
        end else if(tick)begin
            phase <= phase + phase_inc;
        end
    end
endmodule
