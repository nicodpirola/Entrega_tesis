`timescale 1ns/1ps
// Testbench de fx_cabsim: lee estimulos de tb_cab_in.hex / tb_cab_h1.hex,
// escribe las salidas en tb_cab_out.hex; check_tb_cab.py las compara con el
// modelo bit-exacto (golden.py).
module tb_fx_cabsim;
  localparam int NS = 7000;
  logic clk = 0, rst_n = 0, enable = 0;
  logic in_valid = 0, in_ready, out_valid, out_ready = 0;
  logic signed [31:0] in_data = 0, out_data;
  logic signed [31:0] level = 32'h7FFF_FFFF;
  logic coef_we = 0; logic [9:0] coef_addr = 0; logic [17:0] coef_data = 0;

  fx_cabsim dut(.clk, .rst_n, .enable, .in_valid, .in_ready, .in_data,
                .out_valid, .out_ready, .out_data, .level_q1_31(level),
                .coef_we, .coef_addr, .coef_data);

  always #10 clk = ~clk;   // 50 MHz

  logic [31:0] xin [0:NS-1];
  logic [17:0] h1  [0:1023];
  integer fo, n, i, t0, lat_max;

  // respuesta lista para aceptar con probabilidad ~70%
  always @(posedge clk) out_ready <= ($urandom % 10) < 7;

  task automatic send_and_get(input integer idx);
    // retardo aleatorio antes de presentar la muestra
    repeat ($urandom % 4) @(posedge clk);
    in_data <= xin[idx]; in_valid <= 1;
    @(posedge clk); while (!(in_valid && in_ready)) @(posedge clk);
    t0 = $time;
    in_valid <= 0;
    // en bypass la salida sale en el mismo ciclo que la entrada
    if (!enable) begin
      $fwrite(fo, "%08x\n", in_data);   // = lo que vio la salida en ese ciclo
      if (!(out_valid && out_ready) || out_data !== xin[idx]) $display("ERROR bypass n=%0d", idx);
    end else begin
      while (!(out_valid && out_ready)) @(posedge clk);
      $fwrite(fo, "%08x\n", out_data);
      if (($time - t0)/20 > lat_max) lat_max = ($time - t0)/20;
      @(posedge clk);
    end
  endtask

  initial begin
    $readmemh("tb_cab_in.hex", xin);
    $readmemh("tb_cab_h1.hex", h1);
    fo = $fopen("tb_cab_out.hex", "w");
    lat_max = 0;
    repeat (5) @(posedge clk); rst_n <= 1; repeat (2) @(posedge clk);

    for (n = 0; n < NS; n++) begin
      if (n == 1500) enable <= 1;
      if (n == 3500) level  <= 32'h4000_0000;
      if (n == 5000) begin level <= 32'h7FFF_FFFF; enable <= 0; end
      if (n == 5100) begin               // carga de IR nuevo desde el "PS"
        for (i = 0; i < 1024; i++) begin
          @(posedge clk); coef_we <= 1; coef_addr <= i; coef_data <= h1[i];
        end
        @(posedge clk); coef_we <= 0;
      end
      if (n == 5200) enable <= 1;
      @(posedge clk);
      send_and_get(n);
    end
    $fclose(fo);
    $display("TB terminado. Latencia max (ciclos entrada->salida) = %0d", lat_max);
    $finish;
  end
endmodule
