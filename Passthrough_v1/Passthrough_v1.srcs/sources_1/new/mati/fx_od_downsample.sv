`timescale 1ns/1ps
module fx_od_downsample #(parameter integer OS_FACTOR = 8) (
    input logic clk, rst_n, state_clear,
    input logic in_valid, output logic in_ready, input logic signed [31:0] in_data,
    output logic out_valid, input logic out_ready, output logic signed [31:0] out_data,
    output logic idle
);
    import fx_od_fir_pkg::*;
    localparam integer STAGES = $clog2(OS_FACTOR);
    logic [STAGES:0] valid_link, ready_link;
    logic signed [31:0] data_link [0:STAGES];
    assign valid_link[0] = in_valid;
    assign data_link[0] = in_data;
    assign in_ready = ready_link[0];
    assign out_valid = valid_link[STAGES];
    assign out_data = data_link[STAGES];
    assign ready_link[STAGES] = out_ready;
    assign idle = (&ready_link[STAGES-1:0]) && !(|valid_link[STAGES:1]);
    for (genvar i = 0; i < STAGES; i = i+1) begin : g_stage
        os_down2x #(.N((i == STAGES-1) ? 32 : 16), .COEFS((i == STAGES-1) ? DECIM1 : DECIM2)) u_stage (
            .clk(clk), .rst_n(rst_n), .state_clear(state_clear),
            .in_valid(valid_link[i]), .in_ready(ready_link[i]), .in_data(data_link[i]),
            .out_valid(valid_link[i+1]), .out_ready(ready_link[i+1]), .out_data(data_link[i+1])
        );
    end
    initial begin
        if ((OS_FACTOR != 2) && (OS_FACTOR != 4) && (OS_FACTOR != 8)) $fatal(1, "OS_FACTOR debe ser 2, 4 u 8");
    end
endmodule
