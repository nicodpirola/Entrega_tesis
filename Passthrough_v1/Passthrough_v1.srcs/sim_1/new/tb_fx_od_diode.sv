`timescale 1ns/1ps

module tb_fx_od_diode;
    parameter string DATA_DIR = "X:/Tesis/Dist_AB/TS9_Yeh/rtl_od/diode_vectors";
    localparam integer COUNT = 8192, DEPTH = 2561;
    logic clk = 0; always #10 clk = ~clk;
    logic rst_n = 0, iv = 0, ir, ov, ready = 0, bank = 0;
    logic signed [31:0] id = 0, od;
    logic wr_en = 0, wr_ready, wr_bank = 0;
    logic [11:0] wr_addr = 0;
    logic [31:0] wr_data = 0;
    logic [31:0] samples [0:COUNT-1], expected [0:COUNT-1], table_data [0:DEPTH-1];
    integer checked = 0;
    string directory, suffix;

    fx_od_diode dut (
        .clk(clk), .rst_n(rst_n), .in_valid(iv), .in_ready(ir), .in_data(id),
        .out_valid(ov), .out_ready(ready), .out_data(od), .active_bank(bank),
        .wt_wr_en(wr_en), .wt_wr_ready(wr_ready), .wt_wr_bank(wr_bank),
        .wt_wr_addr(wr_addr), .wt_wr_data(wr_data)
    );

    task automatic load_table(input bit destination);
        begin
            @(negedge clk); wr_bank = destination; wr_en = 1;
            for (integer i = 0; i < DEPTH; i = i+1) begin
                wr_addr = i; wr_data = table_data[i];
                @(posedge clk);
                if (!wr_ready) $fatal(1, "Escritura rechazada en %0d", i);
                @(negedge clk);
            end
            wr_en = 0;
        end
    endtask

    task automatic check_sample(input integer index, input bit stall, change_bank);
        integer timeout_cycles;
        time accepted_at;
        begin
            @(negedge clk);
            if (!ir) $fatal(1, "Entrada ocupada");
            id = samples[index]; iv = 1; ready = !stall;
            @(posedge clk); accepted_at = $time;
            @(negedge clk); iv = 0;
            if (change_bank) bank = !bank;
            timeout_cycles = 0;
            while (!ov && timeout_cycles < 100) begin @(negedge clk); timeout_cycles = timeout_cycles+1; end
            if (!ov) $fatal(1, "Timeout");
            if (od !== expected[index]) $fatal(1, "Muestra %0d: %h esperado %h", index, od, expected[index]);
            if (($time-accepted_at-10)/20 != 14) $fatal(1, "Latencia inesperada");
            if (stall) begin
                repeat (3) begin
                    @(negedge clk);
                    if (!ov || od !== expected[index] || ir) $fatal(1, "Salida no retenida");
                end
                ready = 1;
            end
            @(posedge clk);
            @(negedge clk);
            if (ov) $fatal(1, "Salida duplicada");
            if (change_bank) bank = !bank;
            checked = checked+1;
        end
    endtask

    initial begin
        if (!$value$plusargs("DATA_DIR=%s", directory)) directory = DATA_DIR;
        $readmemh({directory, "/input_u_q12_20.hex"}, samples);
        if ($isunknown(samples[COUNT-1])) $fatal(1, "Vectores incompletos");
        repeat (3) @(negedge clk); rst_n = 1;

        for (integer drive_index = 0; drive_index < 3; drive_index = drive_index+1) begin
            case (drive_index) 0: suffix = "0"; 1: suffix = "50"; 2: suffix = "100"; endcase
            $readmemh({directory, "/ts9_diodes_drive_", suffix, ".mem"}, table_data);
            $readmemh({directory, "/output_drive_", suffix, "_q3_29.hex"}, expected);
            if ($isunknown(table_data[DEPTH-1]) || $isunknown(expected[COUNT-1])) $fatal(1, "Tabla incompleta");
            load_table(!bank);
            bank = !bank;
            $display("=== DRIVE %s ===", suffix);
            for (integer i = 0; i < COUNT; i = i+1)
                check_sample(i, (i%7)==0, (i%11)==0);
        end

        // La tabla activa no acepta escrituras.
        @(negedge clk); wr_en = 1; wr_bank = bank; wr_addr = 0; wr_data = 32'd123;
        @(posedge clk);
        if (wr_ready) $fatal(1, "Permite escribir tabla activa");
        @(negedge clk); wr_en = 0;
        check_sample(2, 0, 0); // u=0 debe seguir dando cero.

        // Incluso si cambia active_bank, se protege el banco de la muestra en curso.
        @(negedge clk); id = samples[0]; iv = 1; ready = 0;
        @(posedge clk);
        @(negedge clk); iv = 0; bank = !bank; wr_bank = !bank; wr_en = 1;
        @(posedge clk);
        if (wr_ready) $fatal(1, "Permite modificar la tabla que esta leyendo");
        @(negedge clk); wr_en = 0;
        while (!ov) @(negedge clk);
        if (od !== expected[0]) $fatal(1, "Banco de muestra no retenido");
        ready = 1; @(posedge clk); @(negedge clk); bank = !bank; checked = checked+1;

        // Escritura a banco inactivo simultanea con una muestra activa.
        @(negedge clk); id = samples[0]; iv = 1; ready = 0;
        wr_bank = !bank; wr_en = 1; wr_addr = 0; wr_data = 0;
        @(posedge clk);
        if (!ir || !wr_ready) $fatal(1, "Lectura/escritura a bancos distintos no disponible");
        @(negedge clk); iv = 0; wr_en = 0;
        while (!ov) @(negedge clk);
        if (od !== expected[0]) $fatal(1, "Escritura inactiva afecta salida");
        rst_n = 0; @(posedge clk); #1;
        if (ov) $fatal(1, "Reset no descarta salida pendiente");
        @(negedge clk); rst_n = 1; ready = 1;
        check_sample(0, 0, 0); // Reset conserva las tablas cargadas.

        $display("Muestras comparadas bit a bit: %0d", checked);
        $display("Latencia: 14 clocks");
        $display("TB FX OD DIODE: OK");
        $finish;
    end

    initial begin #50000000; $fatal(1, "TIMEOUT GLOBAL"); end
endmodule
