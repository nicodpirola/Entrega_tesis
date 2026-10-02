`timescale 1ns / 1ps

module pedal_to_switch (
    input  wire clk,
    input  wire pedal_in,
    output wire [1:0] s_req_suppress
);
    
    reg aux = 1'b0;
    reg sync = 1'b0;

    always @(posedge clk) begin
        aux <= pedal_in;
        sync <= aux;
    end
    
    assign s_req_suppress = sync ? 2'b01 : 2'b10;

endmodule