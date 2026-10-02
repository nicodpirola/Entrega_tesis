// DC blocker con enable/bypass (wrapper de fx_dc_blocker_1pole).
// enable=0 -> pasa transparente. Al habilitar (rise) limpia estado.
module fx_dcb_byp (
  input  logic               clk,
  input  logic               rst_n,
  input  logic               enable,
  input  logic               in_valid,
  output logic               in_ready,
  input  logic signed [31:0] in_data,
  output logic               out_valid,
  input  logic               out_ready,
  output logic signed [31:0] out_data
);
  logic d_iv, d_ir, d_ov, d_or;
  logic signed [31:0] d_od;

  logic enable_d, st_clear;
  always_ff @(posedge clk) begin
    if (!rst_n) begin enable_d <= 1'b0; st_clear <= 1'b0; end
    else begin enable_d <= enable; st_clear <= enable && !enable_d; end
  end

  fx_dc_blocker_1pole u_dcb (
    .clk(clk), .rst_n(rst_n),
    .in_valid(d_iv), .in_ready(d_ir), .in_data(in_data),
    .out_valid(d_ov), .out_ready(d_or), .out_data(d_od),
    .R_q1_31(32'sh7FD5_2286), .state_clear(st_clear)
  );

  // enable=1: ruta por el blocker; enable=0: bypass combinacional puro
  assign d_iv      = enable && in_valid;
  assign d_or      = enable && out_ready;
  assign in_ready  = enable ? d_ir  : out_ready;
  assign out_valid = enable ? d_ov  : in_valid;
  assign out_data  = enable ? d_od  : in_data;
endmodule