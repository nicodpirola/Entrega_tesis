`timescale 1ns/1ps

// tb_tremolo.sv
// Testbench del tremolo.
// Entrada: senoidal de 440 Hz con amplitud 0.5. LFO de 5 Hz.
// Se simulan tres profundidades (0, 0.5 y 1) y se guarda entrada y salida en un CSV
// para compararlas con el modelo de referencia (modelo_tremolo.py).
// En bypass la salida tiene que ser igual a la entrada: eso se chequea aca mismo.

module tb_tremolo;

    parameter string ARCHIVO = "X:/Tesis/Verificacion/tremolo/tremolo_sim.csv";

    localparam int  N_MUESTRAS = 24000;   //0.5 s a 48 kHz
    localparam real FS         = 48000.0;
    localparam real F_AUDIO    = 440.0;
    localparam real AMP        = 0.5;
    localparam real F_LFO      = 5.0;
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

    logic signed [31:0] depth_q1_31;
    logic        [31:0] lfo_phase_inc_u32;

    logic signed [31:0] depth_tabla [0:2];

    integer archivo;
    integer errores;
    integer caso;
    integer n;

    fx_tremolo dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .enable            (enable),
        .in_valid          (in_valid),
        .in_ready          (in_ready),
        .in_data           (in_data),
        .out_valid         (out_valid),
        .out_ready         (out_ready),
        .out_data          (out_data),
        .depth_q1_31       (depth_q1_31),
        .lfo_phase_inc_u32 (lfo_phase_inc_u32)
    );

    initial clk = 1'b0;
    always #10 clk = ~clk;

    //la salida no siempre esta lista: prueba que el tremolo retenga la muestra
    always @(negedge clk) out_ready = ($urandom % 4) != 0;

    function automatic logic signed [31:0] senoidal(input integer k);
        senoidal = $rtoi(AMP * $sin(2.0 * PI * F_AUDIO * k / FS) * 2.0**29); //Q3.29
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
        end
    endtask

    //arranca el efecto de cero: el flanco del enable reinicia el LFO
    task automatic reiniciar(input logic en);
        begin
            @(negedge clk);
            enable = 1'b0;
            repeat (5) @(negedge clk);
            enable = en;
            repeat (5) @(negedge clk);
        end
    endtask

    initial begin
        logic signed [31:0] x;
        logic signed [31:0] y;

        depth_tabla[0] = 32'sd0;
        depth_tabla[1] = 32'sh4000_0000;   //0.5
        depth_tabla[2] = 32'sh7FFF_FFFF;   //1

        rst_n             = 1'b0;
        enable            = 1'b0;
        in_valid          = 1'b0;
        in_data           = '0;
        depth_q1_31       = '0;
        lfo_phase_inc_u32 = 32'($rtoi(F_LFO / FS * 2.0**32));
        errores           = 0;

        archivo = $fopen(ARCHIVO, "w");
        $fdisplay(archivo, "caso,depth_q1_31,phase_inc,n,x,y");

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        $display("=== 1) Bypass ===");
        reiniciar(1'b0);
        for (n = 0; n < 2000; n = n + 1) begin
            x = senoidal(n);
            procesar(x, y);
            if (y !== x) errores = errores + 1;
        end
        $display("bypass: %0d diferencias", errores);

        $display("=== 2) Tremolo con tres profundidades ===");
        for (caso = 0; caso < 3; caso = caso + 1) begin
            depth_q1_31 = depth_tabla[caso];
            reiniciar(1'b1);
            for (n = 0; n < N_MUESTRAS; n = n + 1) begin
                x = senoidal(n);
                procesar(x, y);
                $fdisplay(archivo, "%0d,%0d,%0d,%0d,%0d,%0d", caso, depth_q1_31, lfo_phase_inc_u32, n, x, y);
            end
            $display("caso %0d listo", caso);
        end

        $fclose(archivo);
        if (errores == 0) $display("Bypass OK. Correr modelo_tremolo.py para comparar con el modelo.");
        else              $display("ERROR en bypass");
        $finish;
    end

endmodule
