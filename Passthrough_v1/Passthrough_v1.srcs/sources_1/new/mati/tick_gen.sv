module tick_gen #(
  parameter int DIV = 2500   // 50 MHz / 2500 = 20 kHz -> tick cada 50 us
)(
  input  logic clk,
  input  logic rst_n,
  output logic tick
);
  localparam int CW = $clog2(DIV);
  logic [CW-1:0] cnt;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      cnt <= '0; tick <= 1'b0;
    end else if (cnt == DIV-1) begin
      cnt <= '0; tick <= 1'b1;
    end else begin
      cnt <= cnt + 1'b1; tick <= 1'b0;
    end
  end
endmodule