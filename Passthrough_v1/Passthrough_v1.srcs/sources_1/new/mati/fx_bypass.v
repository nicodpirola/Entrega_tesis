module fx_bypass (
  input  wire                clk,
  input  wire                rst_n,
  input  wire                in_valid,
  input  wire signed [31:0]  in_data,
  output wire                in_ready,
  output wire                out_valid,
  output wire signed [31:0]  out_data,
  input  wire                out_ready
);

  assign in_ready  = 1'b1;
  assign out_valid = in_valid;
  assign out_data  = in_data;

endmodule