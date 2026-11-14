`timescale 1ns/1ps

// tb_delay.sv
// Testbench del delay. Corre tres casos y guarda entrada y salida en un CSV
// para compararlas con el modelo (modelo_delay.py):
//  caso 0: impulso, D = 480 muestras (10 ms), fb = 0.7, sin pasabajos
//  caso 1: el mismo impulso con el pasabajos de 2 kHz en el lazo
//  caso 2: senoidal de 440 Hz con golpes, D = 1234.37 muestras, fb = 0.9, pasabajos de 4 kHz

module tb_delay;

    parameter string ARCHIVO = "X:/Tesis/Verificacion/delay/delay_sim.csv";

    localparam int  N_MUESTRAS = 9600;   //200 ms a 48 kHz
    localparam real FS         = 48000.0;
    localparam real PI         = 3.14159265358979;

    logic clk;
    logic rst_n;
    logic enable;

    logic               in_valid;
    logic               in_ready;
    logic signed [31:0] in_data;

    logic               out_valid;
    logic               out_ready;
    logic signed [31:0] out_data;

    logic        [31:0] D_16_16;
    logic signed [31:0] fb_q1_31;
    logic signed [31:0] wet_q1_31;
    logic               lpf_on;
    logic signed [31:0] lpf_G_q1_31;

    integer archivo;

    fx_delay #(
        .ADDR_W (15)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .enable      (enable),
        .in_valid    (in_valid),
        .in_ready    (in_ready),
        .in_data     (in_data),
        .out_valid   (out_valid),
        .out_ready   (out_ready),
        .out_data    (out_data),
        .D_16_16     (D_16_16),
        .fb_q1_31    (fb_q1_31),
        .wet_q1_31   (wet_q1_31),
        .lpf_on      (lpf_on),
        .lpf_G_q1_31 (lpf_G_q1_31)
    );

    initial clk = 1'b0;
    always #10 clk = ~clk;

    //la salida no siempre esta lista: prueba que el delay retenga la muestra
    always @(negedge clk) out_ready = ($urandom % 4) != 0;

    //G del pasabajos TPT: g = tan(pi*fc/fs), G = g/(1+g)
    function automatic logic signed [31:0] coef_lpf(input real fc);
        real g;
        begin
            g = $tan(PI * fc / FS);
            coef_lpf = $rtoi(g / (1.0 + g) * 2.0**31);
        end
    endfunction

    //entrada de cada caso, en Q3.29
    function automatic logic signed [31:0] entrada(input integer caso, input integer k);
        real x;
        begin
            if (caso < 2) begin
                x = (k == 0) ? 0.5 : 0.0;                         //impulso
            end
            else begin
                x = 0.2 * $sin(2.0 * PI * 440.0 * k / FS);        //senoidal
                if (k % 4000 == 0) x = x + 0.3;                   //golpe cada 4000 muestras
            end
            entrada = $rtoi(x * 2.0**29);
        end
    endfunction

    //manda una muestra y espera la salida
    task automatic procesar(input logic signed [31:0] x, output logic signed [31:0] y);
        begin
            @(negedge clk);
            in_valid = 1'b1;
            in_data  = x;
            do @(posedge clk); while (!in_ready);
            @(negedge clk);
            in_valid = 1'b0;
            do @(posedge clk); while (!(out_valid && out_ready));
            y = out_data;
            repeat (20) @(negedge clk);
        end
    endtask

    //corre un caso completo: apaga y prende (borra la memoria) y procesa N_MUESTRAS
    task automatic correr_caso(input integer caso, input logic [31:0] D, input real fb, input logic con_lpf, input real fc);
        logic signed [31:0] x;
        logic signed [31:0] y;
        begin
            D_16_16     = D;
            fb_q1_31    = $rtoi(fb * 2.0**31);
            lpf_on      = con_lpf;
            lpf_G_q1_31 = coef_lpf(fc);

            @(negedge clk);
            enable = 1'b0;
            repeat (5) @(negedge clk);
            enable = 1'b1;
            repeat (40000) @(negedge clk);   //borrado de la memoria: 2^15 ciclos

            for (int n = 0; n < N_MUESTRAS; n++) begin
                x = entrada(caso, n);
                procesar(x, y);
                $fdisplay(archivo, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                          caso, D_16_16, fb_q1_31, wet_q1_31, lpf_on, lpf_G_q1_31, n, x, y);
            end
            $display("caso %0d listo", caso);
        end
    endtask

    initial begin
        rst_n     = 1'b0;
        enable    = 1'b0;
        in_valid  = 1'b0;
        in_data   = '0;
        wet_q1_31 = $rtoi(0.8 * 2.0**31);

        archivo = $fopen(ARCHIVO, "w");
        $fdisplay(archivo, "caso,D_16_16,fb_q1_31,wet_q1_31,lpf_on,lpf_G_q1_31,n,x,y");

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        //           caso  D (16.16)       fb   lpf   fc [Hz]
        correr_caso(0,    32'h01E0_0000,  0.7, 1'b0, 2000.0);
        correr_caso(1,    32'h01E0_0000,  0.7, 1'b1, 2000.0);
        correr_caso(2,    32'h04D2_5EB8,  0.9, 1'b1, 4000.0);

        $fclose(archivo);
        $display("Listo. Correr modelo_delay.py para comparar con el modelo.");
        $finish;
    end

endmodule
