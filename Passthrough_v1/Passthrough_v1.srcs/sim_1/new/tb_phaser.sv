`timescale 1ns/1ps

module tb_phaser;

    logic clk;
    logic rst_n;
    logic enable;

    logic               in_valid;
    logic               in_ready;
    logic signed [31:0] in_data;

    logic               out_valid;
    logic               out_ready;
    logic signed [31:0] out_data;

    logic        [31:0] lfo_phase_inc;
    logic signed [31:0] g_min_q1_31;
    logic signed [31:0] g_max_q1_31;
    logic signed [31:0] fb_q1_31;

    logic signed [31:0] got;
    logic signed [31:0] last_output;

    integer output_count;
    integer i;
    integer errors;

    real PI;
    real input_real;
    real output_abs;
    real envelope_min;
    real envelope_max;
    real window_peak;


    fx_phaser dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .enable        (enable),

        .in_valid      (in_valid),
        .in_ready      (in_ready),
        .in_data       (in_data),

        .out_valid     (out_valid),
        .out_ready     (out_ready),
        .out_data      (out_data),

        .lfo_phase_inc (lfo_phase_inc),
        .g_min_q1_31   (g_min_q1_31),
        .g_max_q1_31   (g_max_q1_31),
        .fb_q1_31      (fb_q1_31)
    );


    initial clk = 1'b0;
    always #10 clk = ~clk;


    function automatic logic signed [31:0] q29(
        input real value
    );
        begin
            q29 = $rtoi(value * 536870912.0);
        end
    endfunction


    always @(posedge clk) begin
        if (!rst_n) begin
            output_count = 0;
            last_output  = '0;
        end else if (out_valid && out_ready) begin
            last_output  = out_data;
            output_count = output_count + 1;
        end
    end


    task automatic push(
        input logic signed [31:0] sample
    );
        integer previous_count;
        integer timeout;

        begin
            previous_count = output_count;

            @(negedge clk);

            timeout = 0;
            while (!in_ready && timeout < 9999) begin
                @(negedge clk);
                timeout = timeout + 1;
            end

            if (!in_ready)
                $fatal("Timeout esperando in_ready");

            in_data  = sample;
            in_valid = 1'b1;

            @(posedge clk);
            @(negedge clk);

            in_valid = 1'b0;

            timeout = 0;
            while ((output_count == previous_count) &&
                   (timeout < 9999)) begin

                @(negedge clk);
                timeout = timeout + 1;
            end

            if (output_count == previous_count)
                $fatal("Timeout esperando out_valid");

            got = last_output;
        end
    endtask


    initial begin
        PI = 3.14159265358979;

        rst_n            = 1'b0;
        enable           = 1'b0;
        in_valid         = 1'b0;
        in_data          = '0;
        out_ready        = 1'b1;

        g_min_q1_31      = 32'sh0277_1680;
        g_max_q1_31      = 32'sh0C2C_7F97;
        fb_q1_31         = 32'sh2666_6666;
        lfo_phase_inc    = 32'd45000;

        repeat (5) @(posedge clk);

        @(negedge clk);
        rst_n = 1'b1;

        repeat (3) @(posedge clk);


        $display("=== 1) Bypass ===");

        errors = 0;

        for (i = 0; i < 8; i = i + 1) begin
            push(q29(0.3));

            if (got !== q29(0.3))
                errors = errors + 1;
        end

        $display(
            "  %0d/8 muestras identicas",
            8 - errors
        );

        if (errors != 0)
            $fatal("Error en bypass");


        $display("=== 2) Phaser habilitado ===");

        @(negedge clk);
        enable = 1'b1;

        repeat (5) @(posedge clk);

        envelope_min = 99.0;
        envelope_max = 0.0;
        window_peak  = 0.0;

        for (i = 0; i < 9600; i = i + 1) begin
            input_real =
                0.4 *
                $sin(
                    2.0 *
                    PI *
                    500.0 *
                    i /
                    48000.0
                );

            push(q29(input_real));

            output_abs =
                $itor($signed(got)) /
                536870912.0;

            if (output_abs < 0.0)
                output_abs = -output_abs;

            if (output_abs > window_peak)
                window_peak = output_abs;

            if ((i % 480) == 479) begin
                if (i >= 960) begin
                    if (window_peak < envelope_min)
                        envelope_min = window_peak;

                    if (window_peak > envelope_max)
                        envelope_max = window_peak;
                end

                window_peak = 0.0;
            end
        end

        $display(
            "  Envolvente: min=%.3f max=%.3f",
            envelope_min,
            envelope_max
        );

        if ((envelope_max - envelope_min) <= 0.02)
            $fatal("El phaser no presenta modulacion suficiente");

        $display("  MODULA OK");
        $display("TB PHASER: OK");

        $finish;
    end


    initial begin
        #400_000_000;
        $fatal("Timeout general del testbench");
    end

endmodule