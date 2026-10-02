// FIR de PRUEBA audible: LPF 5kHz @48k, 32 taps (-58dB en 8k).
// enable=1 -> el audio se escucha "oscuro" = el FIR funciona en hardware.
module fx_fir_lpf5k (
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
  localparam logic [32*32-1:0] LPF5K = 1024'hFFDC8329_FFFBCB4E_003254A7_008054A2_00BF8C3C_00A3B23B_FFE4B399_FE8388E9_FCFFD499_FC511ACE_FD9147A8_01736D2D_07C77E37_0F51BAE7_161A7ED6_1A203118_1A203118_161A7ED6_0F51BAE7_07C77E37_01736D2D_FD9147A8_FC511ACE_FCFFD499_FE8388E9_FFE4B399_00A3B23B_00BF8C3C_008054A2_003254A7_FFFBCB4E_FFDC8329;

  logic f_iv, f_ir, f_ov, f_or;
  logic signed [31:0] f_od;

  logic enable_d, st_clear;
  always_ff @(posedge clk) begin
    if (!rst_n) begin enable_d <= 1'b0; st_clear <= 1'b0; end
    else begin enable_d <= enable; st_clear <= enable && !enable_d; end
  end

  fir_serial #(.N(32), .COEFS(LPF5K)) u_fir (
    .clk(clk), .rst_n(rst_n), .state_clear(st_clear),
    .in_valid(f_iv), .in_ready(f_ir), .in_data(in_data),
    .out_valid(f_ov), .out_ready(f_or), .out_data(f_od)
  );

  assign f_iv      = enable && in_valid;
  assign f_or      = enable && out_ready;
  assign in_ready  = enable ? f_ir : out_ready;
  assign out_valid = enable ? f_ov : in_valid;
  assign out_data  = enable ? f_od : in_data;
endmodule