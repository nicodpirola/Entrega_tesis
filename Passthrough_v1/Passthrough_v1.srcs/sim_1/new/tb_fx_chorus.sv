`timescale 1ns/1ps

module tb_fx_chorus;

    localparam int SAMPLES = 96;

    logic clk = 1'b0;
    logic rst_n;
    logic enable;

    logic               in_valid;
    logic               in_ready;
    logic signed [31:0] in_data;

    logic               out_valid;
    logic               out_ready;
    logic signed [31:0] out_data;

    logic        [31:0] D_center_16_16;
    logic        [31:0] D_depth_16_16;
    logic signed [31:0] wet_q1_31;
    logic        [31:0] lfo_phase_inc_u32;

    logic               lpf_on;
    logic signed [31:0] lpf_G_q1_31;

    logic signed [31:0] fixed_output [0:SAMPLES-1];
    logic signed [31:0] mod_output   [0:SAMPLES-1];
    logic signed [31:0] lpf_output   [0:SAMPLES-1];

    logic signed [31:0] sent_sample;
    logic signed [31:0] received_sample;

    integer i;
    integer timeout_count;
    integer bypass_errors;
    integer unknown_errors;
    integer modulation_differences;
    integer lpf_differences;

    always #10 clk = ~clk;

    fx_chorus #(
        .ADDR_W(11)
    ) dut (
        .clk               (clk              ),
        .rst_n             (rst_n            ),
        .enable            (enable           ),

        .in_valid          (in_valid         ),
        .in_ready          (in_ready         ),
        .in_data           (in_data          ),

        .out_valid         (out_valid        ),
        .out_ready         (out_ready        ),
        .out_data          (out_data         ),

        .D_center_16_16    (D_center_16_16   ),
        .D_depth_16_16     (D_depth_16_16    ),
        .wet_q1_31         (wet_q1_31        ),
        .lfo_phase_inc_u32 (lfo_phase_inc_u32),

        .lpf_on            (lpf_on           ),
        .lpf_G_q1_31       (lpf_G_q1_31      )
    );

    function automatic logic signed [31:0] audio_sample(
        input integer sample_index
    );
        real value;
        begin
            value =
                0.20 * $sin(
                    2.0 * 3.14159265358979 *
                    700.0 * sample_index / 48000.0
                ) +
                0.10 * $sin(
                    2.0 * 3.14159265358979 *
                    1900.0 * sample_index / 48000.0
                );

            audio_sample = $rtoi(value * 536870912.0);
        end
    endfunction

    task automatic push_sample(
        input logic signed [31:0] sample_in
    );
        begin
            timeout_count = 0;

            while (!in_ready && timeout_count < 10000) begin
                @(posedge clk);
                timeout_count = timeout_count + 1;
            end

            if (timeout_count == 10000)
                $fatal(1, "Timeout esperando in_ready");

            in_data  <= sample_in;
            in_valid <= 1'b1;

            @(posedge clk);
            in_valid <= 1'b0;

            timeout_count = 0;

            while (!out_valid && timeout_count < 10000) begin
                @(posedge clk);
                timeout_count = timeout_count + 1;
            end

            if (timeout_count == 10000)
                $fatal(1, "Timeout esperando out_valid");

            received_sample = out_data;

            if (^out_data === 1'bx)
                unknown_errors = unknown_errors + 1;

            @(posedge clk);
        end
    endtask

    task automatic restart_chorus(
        input logic        [31:0] depth_value,
        input logic               enable_lpf
    );
        begin
            @(negedge clk);
            enable  = 1'b0;
            in_valid = 1'b0;

            repeat (4) @(posedge clk);

            @(negedge clk);
            D_depth_16_16 = depth_value;
            lpf_on         = enable_lpf;
            enable         = 1'b1;

            timeout_count = 0;

            while (!dut.clear_busy && timeout_count < 10000) begin
                @(posedge clk);
                timeout_count = timeout_count + 1;
            end

            if (timeout_count == 10000)
                $fatal(1, "No comenzo el borrado de la memoria");

            timeout_count = 0;

            while (dut.clear_busy && timeout_count < 10000) begin
                @(posedge clk);
                timeout_count = timeout_count + 1;
            end

            if (timeout_count == 10000)
                $fatal(1, "Timeout borrando la memoria");

            repeat (3) @(posedge clk);
        end
    endtask

    initial begin
        rst_n                 = 1'b0;
        enable                = 1'b0;
        in_valid              = 1'b0;
        in_data               = '0;
        out_ready             = 1'b1;

        D_center_16_16        = 32'h0008_0000;
        D_depth_16_16         = 32'h0000_0000;
        wet_q1_31             = 32'sh4000_0000;
        lfo_phase_inc_u32     = 32'h0111_1111;

        lpf_on                = 1'b0;
        lpf_G_q1_31           = 32'sh2000_0000;

        bypass_errors         = 0;
        unknown_errors        = 0;
        modulation_differences = 0;
        lpf_differences       = 0;

        repeat (6) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);

        // ---------------------------------------------------------
        // 1. Bypass transparente
        // ---------------------------------------------------------
        $display("=== 1. BYPASS ===");

        for (i = 0; i < 8; i = i + 1) begin
            sent_sample = (i - 4) * 32'sd1234567;
            push_sample(sent_sample);

            if (received_sample !== sent_sample) begin
                bypass_errors = bypass_errors + 1;

                $display(
                    "Error bypass: entrada=%0d salida=%0d",
                    sent_sample,
                    received_sample
                );
            end
        end

        // ---------------------------------------------------------
        // 2. Chorus con retardo fijo
        // ---------------------------------------------------------
        $display("=== 2. RETARDO FIJO ===");

        restart_chorus(
            32'h0000_0000,
            1'b0
        );

        for (i = 0; i < SAMPLES; i = i + 1) begin
            sent_sample = audio_sample(i);
            push_sample(sent_sample);
            fixed_output[i] = received_sample;
        end

        // ---------------------------------------------------------
        // 3. Chorus modulado sin LPF
        // ---------------------------------------------------------
        $display("=== 3. CHORUS SIN LPF ===");

        restart_chorus(
            32'h0003_0000,
            1'b0
        );

        for (i = 0; i < SAMPLES; i = i + 1) begin
            sent_sample = audio_sample(i);
            push_sample(sent_sample);
            mod_output[i] = received_sample;

            if ((i >= 16) &&
                (received_sample !== fixed_output[i])) begin

                modulation_differences =
                    modulation_differences + 1;
            end
        end

        // ---------------------------------------------------------
        // 4. Chorus modulado con LPF
        // ---------------------------------------------------------
        $display("=== 4. CHORUS CON LPF ===");

        restart_chorus(
            32'h0003_0000,
            1'b1
        );

        for (i = 0; i < SAMPLES; i = i + 1) begin
            sent_sample = audio_sample(i);
            push_sample(sent_sample);
            lpf_output[i] = received_sample;

            if ((i >= 16) &&
                (received_sample !== mod_output[i])) begin

                lpf_differences =
                    lpf_differences + 1;
            end
        end

        // ---------------------------------------------------------
        // Resultado
        // ---------------------------------------------------------
        $display("");
        $display("Bypass incorrectos       : %0d", bypass_errors);
        $display("Salidas desconocidas     : %0d", unknown_errors);
        $display("Diferencias por modulacion: %0d",
                 modulation_differences);
        $display("Diferencias por LPF       : %0d",
                 lpf_differences);

        if ((bypass_errors == 0)          &&
            (unknown_errors == 0)         &&
            (modulation_differences > 16) &&
            (lpf_differences > 16)) begin

            $display("");
            $display("TB FX CHORUS: OK");
        end else begin
            $fatal(1, "TB FX CHORUS: ERROR");
        end

        $finish;
    end

    initial begin
        #5_000_000;
        $fatal(1, "TIMEOUT GENERAL DEL TESTBENCH");
    end

endmodule