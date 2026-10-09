`timescale 1ns/1ps
module tb_fx_overdrive;
    parameter integer OS_FACTOR = 8;
    parameter string DATA_DIR = "X:/Tesis/Dist_AB/TS9_Yeh/rtl_od/top_vectors";
    localparam integer COUNT = 384, DEPTH = 2561;
    logic clk = 0; always #10 clk = ~clk;
    logic rst_n = 0, iv = 0, ir, ov, ready = 0;
    logic signed [31:0] id = 0, od;
    logic cfg_valid = 0, cfg_ready, cfg_enable = 0, cfg_clear = 0, cfg_bank = 0;
    logic [31:0] cfg [0:11];
    logic wr_en = 0, wr_ready, wr_bank = 1, active_bank, rejected, status_clear = 0;
    logic [11:0] wr_addr = 0;
    logic [31:0] wr_data = 0;
    logic [31:0] samples [0:COUNT-1], expected [0:COUNT-1], table_data [0:DEPTH-1];
    logic monitor = 0, hold_output = 0, stalled = 0;
    logic [31:0] held_data;
    integer received = 0, checked = 0, clock_count = 0;
    time first_accepted, last_accepted;
    string directory, suffix;

    fx_overdrive #(.OS_FACTOR(OS_FACTOR)) dut (
        .clk(clk), .rst_n(rst_n), .in_valid(iv), .in_ready(ir), .in_data(id), .out_valid(ov), .out_ready(ready), .out_data(od),
        .cfg_valid(cfg_valid), .cfg_ready(cfg_ready), .cfg_enable(cfg_enable), .cfg_clear(cfg_clear), .cfg_bank(cfg_bank),
        .cfg_input1_g(cfg[0]), .cfg_input2_g(cfg[1]), .cfg_branch_hp_g(cfg[2]), .cfg_branch_lp_g(cfg[3]), .cfg_branch_gain(cfg[4]),
        .cfg_tone_b0(cfg[5]), .cfg_tone_b1(cfg[6]), .cfg_tone_b2(cfg[7]), .cfg_tone_a1(cfg[8]), .cfg_tone_a2(cfg[9]),
        .cfg_output_g(cfg[10]), .cfg_level_q3_29(cfg[11]),
        .wt_wr_en(wr_en), .wt_wr_ready(wr_ready), .wt_wr_bank(wr_bank), .wt_wr_addr(wr_addr), .wt_wr_data(wr_data),
        .status_clear(status_clear), .write_rejected(rejected), .active_bank(active_bank)
    );

    always @(negedge clk) begin
        clock_count = clock_count+1;
        ready = !hold_output && ((clock_count%7) != 0) && ((clock_count%7) != 1);
    end
    always @(posedge clk) begin
        if (!rst_n) stalled = 0;
        else begin
            if (stalled && (!ov || od !== held_data)) $fatal(1, "Salida cambia mientras esta pausada");
            stalled = ov && !ready;
            held_data = od;
            if (monitor && ov && ready) begin
                if (received >= COUNT) $fatal(1, "Salida de mas");
                if (od !== expected[received]) $fatal(1, "OS%0d muestra %0d: %h esperado %h", OS_FACTOR, received, od, expected[received]);
                received = received+1; checked = checked+1;
            end
        end
    end

    task automatic reset_top;
        @(negedge clk); rst_n = 0; iv = 0; cfg_valid = 0; wr_en = 0; monitor = 0; hold_output = 0;
        repeat (4) @(negedge clk);
        rst_n = 1;
        repeat (3) @(negedge clk);
    endtask

    task automatic load_table(input bit destination);
        @(negedge clk); wr_bank = destination; wr_en = 1;
        for (integer i = 0; i < DEPTH; i = i+1) begin
            wr_addr = i; wr_data = table_data[i];
            @(posedge clk);
            if (!wr_ready) $fatal(1, "Escritura rechazada %0d", i);
            @(negedge clk);
        end
        wr_en = 0;
    endtask

    task automatic apply_config;
        integer timeout_cycles;
        @(negedge clk); cfg_valid = 1; timeout_cycles = 0;
        do begin
            @(posedge clk); timeout_cycles = timeout_cycles+1;
            if (timeout_cycles > 50000) $fatal(1, "No drena configuracion");
        end while (!cfg_ready);
        @(negedge clk); cfg_valid = 0;
        repeat (3) @(negedge clk);
    endtask

    task automatic stream(input bit paced);
        integer timeout_cycles;
        for (integer i = 0; i < COUNT; i = i+1) begin
            @(negedge clk); id = samples[i]; iv = 1; timeout_cycles = 0;
            do begin
                @(posedge clk); timeout_cycles = timeout_cycles+1;
                if (paced && !ir) $fatal(1, "No acepta a 48 kHz en muestra %0d", i);
                if (timeout_cycles > 50000) $fatal(1, "Entrada trabada");
            end while (!ir);
            if (i == 0) first_accepted = $time;
            if (i == COUNT-1) last_accepted = $time;
            @(negedge clk); iv = 0;
            if (paced) repeat (1039) @(negedge clk);
        end
        $display("OS%0d intervalo medio de entrada: %0.2f clocks", OS_FACTOR, real'(last_accepted-first_accepted)/(20.0*(COUNT-1)));
    endtask

    task automatic finish_stream;
        integer timeout_cycles;
        timeout_cycles = 0;
        while (!cfg_ready) begin
            @(negedge clk); timeout_cycles = timeout_cycles+1;
            if (timeout_cycles > 50000) $fatal(1, "Cadena no termina");
        end
        if (received != COUNT) $fatal(1, "Cantidad de salidas %0d", received);
        monitor = 0;
    endtask

    initial begin
        if (!$value$plusargs("DATA_DIR=%s", directory)) directory = DATA_DIR;
        for (integer i = 0; i < 12; i = i+1) cfg[i] = 0;
        $readmemh({directory, "/input.hex"}, samples);
        if ($isunknown(samples[COUNT-1])) $fatal(1, "Vectores incompletos");

        $display("=== BYPASS ===");
        reset_top();
        for (integer i = 0; i < COUNT; i = i+1) expected[i] = samples[i];
        received = 0; monitor = 1; stream(0); finish_stream();

        for (integer test_index = 0; test_index < 3; test_index = test_index+1) begin
            case (test_index) 0: suffix = "0"; 1: suffix = "50"; 2: suffix = "100"; endcase
            $display("=== CADENA OS%0d DRIVE %s ===", OS_FACTOR, suffix);
            reset_top();
            $readmemh({directory, "/table_", suffix, ".mem"}, table_data);
            load_table(1);
            $readmemh($sformatf("%s/cfg_os%0d_d%s.hex", directory, OS_FACTOR, suffix), cfg);
            $readmemh($sformatf("%s/out_os%0d_d%s.hex", directory, OS_FACTOR, suffix), expected);
            cfg_enable = 1; cfg_clear = 1; cfg_bank = 1; apply_config();
            received = 0; monitor = 1;
            // Drive 50 sin pausas de entrada; Drive 0/100 a 48 kHz.
            stream(test_index != 1); finish_stream();
        end

        $display("=== CONFIGURACION CON MUESTRAS PENDIENTES ===");
        reset_top();
        $readmemh({directory, "/table_50.mem"}, table_data); load_table(1);
        $readmemh($sformatf("%s/cfg_os%0d_d50.hex", directory, OS_FACTOR), cfg);
        $readmemh($sformatf("%s/out_os%0d_d50.hex", directory, OS_FACTOR), expected);
        cfg_enable = 1; cfg_clear = 1; cfg_bank = 1; apply_config();
        $readmemh({directory, "/table_100.mem"}, table_data); load_table(0);
        received = 0; monitor = 1;
        stream(0);
        // Bloquea la ultima salida y pide nuevos parametros.
        @(negedge clk); hold_output = 1;
        $readmemh($sformatf("%s/cfg_os%0d_d100.hex", directory, OS_FACTOR), cfg);
        cfg_valid = 1; cfg_clear = 0; cfg_bank = 0;
        repeat (10) begin
            @(negedge clk);
            if (cfg_ready || ir || active_bank != 1) $fatal(1, "Aplica configuracion antes de drenar");
        end
        hold_output = 0;
        do @(posedge clk); while (!cfg_ready);
        @(negedge clk); cfg_valid = 0;
        if (received != COUNT || active_bank != 0) $fatal(1, "Commit incorrecto");
        monitor = 0;
        $readmemh($sformatf("%s/out_os%0d_changed.hex", directory, OS_FACTOR), expected);
        received = 0; monitor = 1; stream(0); finish_stream();

        $display("=== AVISO DE ESCRITURA RECHAZADA ===");
        @(negedge clk); wr_en = 1; wr_bank = active_bank; wr_addr = 0; wr_data = 0;
        @(posedge clk); #1;
        if (wr_ready || !rejected) $fatal(1, "Escritura activa no se informa");
        @(negedge clk); wr_en = 0; status_clear = 1;
        @(posedge clk); #1;
        if (rejected) $fatal(1, "No limpia el aviso");
        @(negedge clk); status_clear = 0;

        $display("=== DESHABILITAR Y VOLVER A HABILITAR ===");
        cfg_enable = 0; cfg_clear = 0; apply_config();
        for (integer i = 0; i < COUNT; i = i+1) expected[i] = samples[i];
        received = 0; monitor = 1; stream(0); finish_stream();
        cfg_enable = 1; apply_config();
        $readmemh($sformatf("%s/out_os%0d_d100.hex", directory, OS_FACTOR), expected);
        received = 0; monitor = 1; stream(0); finish_stream();
        $display("Muestras completas comparadas bit a bit: %0d", checked);
        $display("TB FX OVERDRIVE OS%0d: OK", OS_FACTOR);
        $finish;
    end
    initial begin #200000000; $fatal(1, "TIMEOUT GLOBAL"); end
endmodule
