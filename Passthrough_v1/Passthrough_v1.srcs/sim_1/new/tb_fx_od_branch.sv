`timescale 1ns/1ps

module tb_fx_od_branch;
    parameter string VECTOR_DIR = "X:/Tesis/Dist_AB/TS9_Yeh/rtl_od/vectors_v2";
    localparam integer SAMPLE_COUNT = 7552;

    logic clk = 0;
    always #10 clk = ~clk;
    logic rst_n = 0;
    logic in_valid = 0, in_ready, out_valid, out_ready = 0;
    logic signed [31:0] in_data = 0, out_data;
    logic signed [31:0] hp_g = 0, lp_g = 0, gain = 0;
    logic [31:0] input_mem [0:SAMPLE_COUNT-1];
    logic [31:0] output_0 [0:SAMPLE_COUNT-1];
    logic [31:0] output_50 [0:SAMPLE_COUNT-1];
    logic [31:0] output_100 [0:SAMPLE_COUNT-1];
    logic [31:0] output_dynamic [0:511];
    logic [31:0] cfg_mem [0:8];
    logic [31:0] edge_input [0:255], edge_output [0:255], edge_cfg [0:767];
    integer checked = 0, min_latency = 999, max_latency = 0;
    string vector_dir;

    fx_od_branch dut (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_ready(in_ready), .in_data(in_data),
        .out_valid(out_valid), .out_ready(out_ready), .out_data(out_data),
        .hp_g_q1_31(hp_g), .lp_g_q1_31(lp_g), .gain_q9_23(gain)
    );

    task automatic reset_dut;
        begin
            @(negedge clk);
            rst_n = 0; in_valid = 0; out_ready = 0;
            repeat (3) @(negedge clk);
            rst_n = 1;
            @(negedge clk);
            if (out_valid || !in_ready) $fatal(1, "Reset no limpio");
        end
    endtask

    task automatic load_config(input integer cfg_index);
        begin
            hp_g = cfg_mem[3*cfg_index];
            lp_g = cfg_mem[3*cfg_index+1];
            gain = cfg_mem[3*cfg_index+2];
        end
    endtask

    task automatic check_sample(input logic signed [31:0] sample, expected,
                                input integer cfg_index, input bit stall, mutate);
        integer timeout_cycles, latency;
        time accepted_at;
        begin
            @(negedge clk);
            if (!in_ready) $fatal(1, "Entrada no disponible al comenzar muestra");
            if (cfg_index >= 0) load_config(cfg_index);
            in_data = sample; in_valid = 1; out_ready = !stall;
            @(posedge clk);
            if (!in_ready) $fatal(1, "Muestra no aceptada");
            accepted_at = $time;
            @(negedge clk);
            in_valid = 0;
            // Cambiar puertos durante la cuenta no debe alterar la muestra aceptada.
            if (mutate) begin hp_g = 32'sh7FFF_FFFF; lp_g = 0; gain = 0; end
            timeout_cycles = 0;
            while (!out_valid && timeout_cycles < 100) begin
                @(negedge clk);
                timeout_cycles = timeout_cycles+1;
            end
            if (!out_valid) $fatal(1, "TIMEOUT en muestra %0d", checked);
            if (out_data !== expected)
                $fatal(1, "Muestra %0d: obtenido %h, esperado %h", checked, out_data, expected);
            latency = ($time-accepted_at-10)/20;
            if (latency < min_latency) min_latency = latency;
            if (latency > max_latency) max_latency = latency;
            if (latency != 25) $fatal(1, "Latencia inesperada: %0d", latency);
            if (stall) begin
                repeat (4) begin
                    @(negedge clk);
                    if (!out_valid || out_data !== expected || in_ready)
                        $fatal(1, "Salida no retenida al esperar out_ready");
                end
                out_ready = 1;
            end
            @(posedge clk);
            if (!out_valid || !out_ready) $fatal(1, "Salida no aceptada");
            @(negedge clk);
            if (out_valid) $fatal(1, "Salida duplicada");
            checked = checked+1;
        end
    endtask

    // Un productor mantiene in_valid alto: mide el intervalo real de aceptacion.
    task automatic check_continuous_stream;
        integer sent, received, watchdog_cycles, interval_cycles;
        time previous_accept;
        begin
            reset_dut();
            @(negedge clk);
            load_config(1); in_data = input_mem[0]; in_valid = 1; out_ready = 1;
            sent = 0; received = 0; watchdog_cycles = 0; previous_accept = 0;
            while (received < 64 && watchdog_cycles < 2000) begin
                @(posedge clk);
                if (in_valid && in_ready) begin
                    if (sent > 0) begin
                        interval_cycles = ($time-previous_accept)/20;
                        if (interval_cycles != 27) $fatal(1, "Intervalo inesperado: %0d", interval_cycles);
                    end
                    previous_accept = $time;
                    sent = sent+1;
                end
                if (out_valid && out_ready) begin
                    if (out_data !== output_50[received]) $fatal(1, "Error en flujo continuo %0d", received);
                    received = received+1;
                    checked = checked+1;
                end
                watchdog_cycles = watchdog_cycles+1;
                @(negedge clk);
                if (sent < 64) begin in_valid = 1; in_data = input_mem[sent]; end
                else in_valid = 0;
            end
            if (received != 64 || sent != 64) $fatal(1, "Flujo incompleto");
            $display("Flujo continuo: intervalo = 27 clocks por muestra");
        end
    endtask

    task automatic check_reset_in_flight(input bit stalled_output);
        integer timeout_cycles;
        begin
            reset_dut();
            @(negedge clk);
            load_config(0); in_data = input_mem[0]; in_valid = 1; out_ready = 0;
            @(posedge clk);
            @(negedge clk); in_valid = 0;
            if (stalled_output) begin
                timeout_cycles = 0;
                while (!out_valid && timeout_cycles < 100) begin
                    @(negedge clk); timeout_cycles = timeout_cycles+1;
                end
                if (!out_valid) $fatal(1, "TIMEOUT antes de reset");
            end else repeat (4) @(negedge clk);
            rst_n = 0;
            @(posedge clk); #1;
            if (out_valid || dut.hp_state_reg !== 0 || dut.lp_state_reg !== 0)
                $fatal(1, "Reset durante operacion no limpio");
            reset_dut();
            check_sample(input_mem[0], output_0[0], 0, 0, 0);
        end
    endtask

    initial begin
        if (!$value$plusargs("VECTOR_DIR=%s", vector_dir)) vector_dir = VECTOR_DIR;
        $readmemh({vector_dir, "/input_q3_29.hex"}, input_mem);
        $readmemh({vector_dir, "/output_drive_0_q12_20.hex"}, output_0);
        $readmemh({vector_dir, "/output_drive_50_q12_20.hex"}, output_50);
        $readmemh({vector_dir, "/output_drive_100_q12_20.hex"}, output_100);
        $readmemh({vector_dir, "/output_dynamic_q12_20.hex"}, output_dynamic);
        $readmemh({vector_dir, "/coefficients.hex"}, cfg_mem);
        $readmemh({vector_dir, "/edge_input.hex"}, edge_input);
        $readmemh({vector_dir, "/edge_output.hex"}, edge_output);
        $readmemh({vector_dir, "/edge_coefficients.hex"}, edge_cfg);
        if ($isunknown(input_mem[SAMPLE_COUNT-1]) || $isunknown(cfg_mem[8]) ||
            $isunknown(output_0[SAMPLE_COUNT-1]) || $isunknown(output_50[SAMPLE_COUNT-1]) ||
            $isunknown(output_100[SAMPLE_COUNT-1]) || $isunknown(output_dynamic[511]) ||
            $isunknown(edge_input[255]) || $isunknown(edge_output[255]) || $isunknown(edge_cfg[767]))
            $fatal(1, "Vectores incompletos: revisar VECTOR_DIR");

        $display("=== 1. DRIVE 0 / 50 / 100, PAUSAS Y PARAMETROS REGISTRADOS ===");
        for (integer drive_index = 0; drive_index < 3; drive_index = drive_index+1) begin
            reset_dut();
            for (integer i = 0; i < SAMPLE_COUNT; i = i+1) begin
                case (drive_index)
                    0: check_sample(input_mem[i], output_0[i], 0, (i%7)==0, (i%9)==0);
                    1: check_sample(input_mem[i], output_50[i], 1, (i%7)==0, (i%9)==0);
                    2: check_sample(input_mem[i], output_100[i], 2, (i%7)==0, (i%9)==0);
                endcase
                repeat (i%3) @(negedge clk);
            end
        end

        $display("=== 2. CONFIGURACION CAMBIANTE, CONSERVANDO ESTADOS ===");
        reset_dut();
        for (integer i = 0; i < 512; i = i+1)
            check_sample(input_mem[i], output_dynamic[i], (i/31)%3, (i%5)==0, 1);

        $display("=== 3. EXTREMOS SIGNED32 Y SATURACION ===");
        reset_dut();
        for (integer i = 0; i < 256; i = i+1) begin
            hp_g = edge_cfg[3*i]; lp_g = edge_cfg[3*i+1]; gain = edge_cfg[3*i+2];
            check_sample(edge_input[i], edge_output[i], -1, (i%5)==0, 1);
        end

        $display("=== 4. FLUJO CONTINUO ===");
        check_continuous_stream();
        $display("=== 5. RESET DURANTE CUENTA Y SALIDA RETENIDA ===");
        check_reset_in_flight(0);
        check_reset_in_flight(1);

        $display("Muestras comparadas bit a bit: %0d", checked);
        $display("Latencia hasta out_valid: %0d..%0d clocks", min_latency, max_latency);
        $display("TB FX OD BRANCH: OK");
        $finish;
    end

    initial begin
        #50000000;
        $fatal(1, "TIMEOUT GLOBAL");
    end
endmodule
