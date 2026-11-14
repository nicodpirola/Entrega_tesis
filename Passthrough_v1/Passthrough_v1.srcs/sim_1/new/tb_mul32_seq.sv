`timescale 1ns/1ps

// tb_mul32_seq.sv
// Testbench de mul32_seq. Compara cada resultado contra el producto de 64 bits de SystemVerilog:
// 1) casos borde (todos contra todos), 2) pares aleatorios,
// 3) start durante el calculo (se tiene que ignorar).
// Ademas chequea la latencia y que p quede estable despues de valid.

module tb_mul32_seq;

    localparam int N_RANDOM = 200000;
    localparam int LATENCIA = 5;

    logic clk;
    logic rst_n;

    logic               start;
    logic signed [31:0] a;
    logic signed [31:0] b;

    logic               busy;
    logic               valid;
    logic signed [63:0] p;

    logic signed [31:0] borde [0:16];

    integer errors;
    integer count;
    integer i;
    integer j;

    mul32_seq dut (
        .clk   (clk),
        .rst_n (rst_n),
        .start (start),
        .a     (a),
        .b     (b),
        .busy  (busy),
        .valid (valid),
        .p     (p)
    );

    initial clk = 1'b0;
    always #10 clk = ~clk;

    task automatic check(
        input logic signed [31:0] x,
        input logic signed [31:0] y
    );
        logic signed [63:0] ref_p;
        integer ciclos;
        begin
            ref_p = 64'(x) * 64'(y);

            @(negedge clk);
            a     = x;
            b     = y;
            start = 1'b1;

            @(negedge clk);
            start = 1'b0;
            a     = $urandom(); //se cambian las entradas mientras calcula
            b     = $urandom();
            ciclos = 1;

            while (!valid && ciclos < 20) begin
                @(negedge clk);
                ciclos = ciclos + 1;
            end

            if (p !== ref_p || ciclos != LATENCIA) begin
                if (errors < 10)
                    $display("ERROR a=%0d b=%0d p=%0d esperado=%0d ciclos=%0d", x, y, p, ref_p, ciclos);
                errors = errors + 1;
            end

            repeat (2) @(negedge clk); //p tiene que quedar quieto
            if (p !== ref_p) begin
                if (errors < 10)
                    $display("ERROR p no estable a=%0d b=%0d", x, y);
                errors = errors + 1;
            end

            count = count + 1;
        end
    endtask

    initial begin
        borde[0]  = 32'sd0;
        borde[1]  = 32'sd1;
        borde[2]  = -32'sd1;
        borde[3]  = 32'sd2;
        borde[4]  = -32'sd2;
        borde[5]  = 32'sh7FFF_FFFF;     //maximo
        borde[6]  = 32'sh8000_0000;     //minimo
        borde[7]  = 32'sh8000_0001;
        borde[8]  = 32'sh0001_FFFF;     //parte baja llena
        borde[9]  = 32'sh0002_0000;     //primer bit de la parte alta
        borde[10] = -32'sh0002_0000;
        borde[11] = -32'sh0001_FFFF;
        borde[12] = 32'sh0000_FFFF;
        borde[13] = 32'sh7FFF_0000;
        borde[14] = 32'sh8001_0000;
        borde[15] = 32'sd12345;
        borde[16] = -32'sd67890;

        errors = 0;
        count  = 0;
        rst_n  = 1'b0;
        start  = 1'b0;
        a      = '0;
        b      = '0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        $display("=== 1) Casos borde ===");
        for (i = 0; i < 17; i = i + 1)
            for (j = 0; j < 17; j = j + 1)
                check(borde[i], borde[j]);

        $display("=== 2) Aleatorios ===");
        for (i = 0; i < N_RANDOM; i = i + 1)
            check($urandom(), $urandom());

        $display("=== 3) Start durante el calculo ===");
        @(negedge clk);
        a = 32'sd1000; b = 32'sd1000; start = 1'b1;
        @(negedge clk);
        a = 32'sd5;    b = 32'sd5;    //start sigue en 1, se tiene que ignorar
        @(negedge clk);
        start = 1'b0;
        while (!valid) @(negedge clk);
        if (p !== 64'sd1000000) begin
            $display("ERROR start durante el calculo: p=%0d", p);
            errors = errors + 1;
        end

        $display("casos=%0d errores=%0d", count, errors);
        if (errors == 0) $display("=== OK ===");
        else             $display("=== FALLA ===");
        $finish;
    end

endmodule
