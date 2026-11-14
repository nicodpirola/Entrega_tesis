`timescale 1ns/1ps

// tb_phaser.sv
// Testbench del phaser. Corre tres casos y guarda entrada y salida en un CSV
// para compararlas con el modelo (modelo_phaser.py):
//  caso 0: ruido, corte fijo en 1 kHz (G_min = G_max), fb = 0
//          (sirve para medir la respuesta en frecuencia: dos muescas)
//  caso 1: lo mismo con fb = 0.7
//  caso 2: senoidal de 440 Hz con golpes, barrido de 300 a 1600 Hz, LFO 2 Hz, fb = 0.5

module tb_phaser;

    parameter string ARCHIVO = "X:/Tesis/Verificacion/phaser/phaser_sim.csv";

    localparam real FS = 48000.0;
    localparam real PI = 3.14159265358979;

    logic clk;
    logic rst_n;
    logic enable;

    logic               in_valid;
    logic               in_ready;
    logic signed [31:0] in_data;

    logic               out_valid;
    logic               out_ready;
    logic signed [31:0] out_data;

    logic        [31:0] lfo_phase_inc_u32;
    logic signed [31:0] g_min_q1_31;
    logic signed [31:0] g_max_q1_31;
    logic signed [31:0] fb_q1_31;

    integer archivo;

    fx_phaser dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .enable            (enable),
        .in_valid          (in_valid),
        .in_ready          (in_ready),
        .in_data           (in_data),
        .out_valid         (out_valid),
        .out_ready         (out_ready),
        .out_data          (out_data),
        .lfo_phase_inc_u32 (lfo_phase_inc_u32),
        .g_min_q1_31       (g_min_q1_31),
        .g_max_q1_31       (g_max_q1_31),
        .fb_q1_31          (fb_q1_31)
    );

    initial clk = 1'b0;
    always #10 clk = ~clk;

    //la salida no siempre esta lista: prueba que el phaser retenga la muestra
    always @(negedge clk) out_ready = ($urandom % 4) != 0;

    //G del filtro TPT: g = tan(pi*fc/fs), G = g/(1+g)
    function automatic logic signed [31:0] coef_tpt(input real fc);
        real g;
        begin
            g = $tan(PI * fc / FS);
            coef_tpt = $rtoi(g / (1.0 + g) * 2.0**31);
        end
    endfunction

    //entrada de cada caso, en Q3.29
    function automatic logic signed [31:0] entrada(input integer caso, input integer k);
        real x;
        begin
            if (caso < 2) begin
                x = 0.2 * (($urandom % 65536) / 32768.0 - 1.0);  //ruido uniforme entre -0.2 y 0.2
            end
            else begin
                x = 0.3 * $sin(2.0 * PI * 440.0 * k / FS);       //senoidal
                if (k % 6000 == 0) x = x + 0.3;                  //golpe cada 125 ms
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

    //corre un caso completo: apaga y prende (borra los estados y reinicia el LFO)
    task automatic correr_caso(input integer caso, input integer n_muestras,
                               input real f_min, input real f_max, input real rate, input real fb);
        logic signed [31:0] x;
        logic signed [31:0] y;
        begin
            g_min_q1_31       = coef_tpt(f_min);
            g_max_q1_31       = coef_tpt(f_max);
            lfo_phase_inc_u32 = $rtoi(rate / FS * 2.0**32);
            fb_q1_31          = $rtoi(fb * 2.0**31);

            @(negedge clk);
            enable = 1'b0;
            repeat (5) @(negedge clk);
            enable = 1'b1;
            repeat (5) @(negedge clk);

            for (int n = 0; n < n_muestras; n++) begin
                x = entrada(caso, n);
                procesar(x, y);
                $fdisplay(archivo, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                          caso, g_min_q1_31, g_max_q1_31, lfo_phase_inc_u32,
                          fb_q1_31, n, x, y);
            end
            $display("caso %0d listo", caso);
        end
    endtask

    initial begin
        rst_n    = 1'b0;
        enable   = 1'b0;
        in_valid = 1'b0;
        in_data  = '0;

        archivo = $fopen(ARCHIVO, "w");
        $fdisplay(archivo, "caso,g_min_q1_31,g_max_q1_31,inc_u32,fb_q1_31,n,x,y");

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        //           caso  muestras  f_min   f_max   rate  fb
        correr_caso(0,    24000,    1000.0, 1000.0, 1.0,  0.0);
        correr_caso(1,    24000,    1000.0, 1000.0, 1.0,  0.7);
        correr_caso(2,    24000,    300.0,  1600.0, 2.0,  0.5);

        $fclose(archivo);
        $display("Listo. Correr modelo_phaser.py para comparar con el modelo.");
        $finish;
    end

endmodule
