module fx_gain_test(
  input logic                clk,
  input logic                rst_n,
  input logic                enable,

  input logic                in_valid,
  output logic               in_ready,
  input logic signed [31:0]  in_data,

  output logic               out_valid,
  input logic                out_ready,
  output logic signed [31:0] out_data
);

  wire in_fire  = in_valid && in_ready;
  wire out_fire = out_valid && out_ready;

  // Acepto input cuando NO tengo salida pendiente
  assign in_ready = !out_valid;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      out_valid <= 1'b0;
      out_data  <= '0;
    end else begin
      if (out_fire)
        out_valid <= 1'b0;

      if (in_fire) begin
        out_valid <= 1'b1;
        out_data  <= enable ? (in_data >>> 1) : in_data;
      end
    end
  end
endmodule