`timescale 1ns/1ps

module tb_fx_flanger;

    localparam int SAMPLES = 128;

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
    logic signed [31:0] fb_q1_31;
    logic        [31:0] lfo_phase_inc_u32;

    logic signed [31:0] no_feedback_output [0:SAMPLES-1];
    logic signed [31:0] positive_output    [0:SAMPLES-1];
    logic signed [31:0] negative_output    [0:SAMPLES-1];

    logic signed [31:0] sent_sample;
    logic signed [31:0] received_sample;

    integer i;
    integer timeout_count;
    integer bypass_errors;
    integer unknown_errors;
    integer positive_differences;
    integer negative_differences;
    integer softclip_differences;

    always #10 clk = ~clk;

    fx_flanger #(
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
        .fb_q1_31          (fb_q1_31         ),
        .lfo_phase_inc_u32 (lfo_phase_inc_u32)
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

    task automatic restart_flanger(
        input logic        [31:0] depth_value,
        input logic signed [31:0] feedback_value
    );
        begin
            @(negedge clk);

            enable   = 1'b0;
            in_valid = 1'b0;

            repeat (4) @(posedge clk);

            @(negedge clk);

            D_depth_16_16 = depth_value;
            fb_q1_31      = feedback_value;
            enable        = 1'b1;

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

        D_center_16_16        = 32'h0006_0000;
        D_depth_16_16         = 32'h0002_0000;

        wet_q1_31             = 32'sh4000_0000;
        fb_q1_31              = 32'sd0;
        lfo_phase_inc_u32     = 32'h0111_1111;

        bypass_errors         = 0;
        unknown_errors        = 0;
        positive_differences  = 0;
        negative_differences  = 0;
        softclip_differences  = 0;

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
        // 2. Flanger modulado sin feedback
        // ---------------------------------------------------------
        $display("=== 2. FLANGER SIN FEEDBACK ===");

        restart_flanger(
            32'h0002_0000,
            32'sd0
        );

        for (i = 0; i < SAMPLES; i = i + 1) begin
            sent_sample = audio_sample(i);
            push_sample(sent_sample);
            no_feedback_output[i] = received_sample;
        end

        // ---------------------------------------------------------
        // 3. Feedback positivo: +0.6
        // ---------------------------------------------------------
        $display("=== 3. FEEDBACK POSITIVO ===");

        restart_flanger(
            32'h0002_0000,
            32'sh4CCC_CCCD
        );

        for (i = 0; i < SAMPLES; i = i + 1) begin
            sent_sample = audio_sample(i);
            push_sample(sent_sample);
            positive_output[i] = received_sample;

            if ((i >= 24) &&
                (received_sample !== no_feedback_output[i])) begin

                positive_differences =
                    positive_differences + 1;
            end
        end

        // ---------------------------------------------------------
        // 4. Feedback negativo: -0.6
        // ---------------------------------------------------------
        $display("=== 4. FEEDBACK NEGATIVO ===");

        restart_flanger(
            32'h0002_0000,
            -32'sh4CCC_CCCD
        );

        for (i = 0; i < SAMPLES; i = i + 1) begin
            sent_sample = audio_sample(i);
            push_sample(sent_sample);
            negative_output[i] = received_sample;

            if ((i >= 24) &&
                (received_sample !== positive_output[i])) begin

                negative_differences =
                    negative_differences + 1;
            end
        end

        // ---------------------------------------------------------
        // 5. Forzar el soft clip
        //
        // Entrada constante = 1.5 en Q3.29.
        // Sin clip, x + 0.5*x daria 2.25 = 0x48000000.
        // La memoria guarda la muestra limitada, por lo que luego del
        // llenado del delay la salida debe diferir de ese valor.
        // ---------------------------------------------------------
        $display("=== 5. SOFT CLIP DEL FEEDBACK ===");

        D_center_16_16 = 32'h0004_0000;

        restart_flanger(
            32'h0000_0000,
            32'sd0
        );

        for (i = 0; i < 48; i = i + 1) begin
            sent_sample = 32'sh3000_0000;
            push_sample(sent_sample);

            if ((i >= 16) &&
                (received_sample !== 32'sh4800_0000)) begin

                softclip_differences =
                    softclip_differences + 1;
            end
        end

        // ---------------------------------------------------------
        // Resultado
        // ---------------------------------------------------------
        $display("");
        $display(
            "Bypass incorrectos            : %0d",
            bypass_errors
        );
        $display(
            "Salidas desconocidas          : %0d",
            unknown_errors
        );
        $display(
            "Diferencias feedback positivo : %0d",
            positive_differences
        );
        $display(
            "Diferencias feedback negativo : %0d",
            negative_differences
        );
        $display(
            "Muestras afectadas por clip   : %0d",
            softclip_differences
        );

        if ((bypass_errors        == 0)  &&
            (unknown_errors       == 0)  &&
            (positive_differences > 32) &&
            (negative_differences > 32) &&
            (softclip_differences > 16)) begin

            $display("");
            $display("TB FX FLANGER: OK");
        end else begin
            $fatal(1, "TB FX FLANGER: ERROR");
        end

        $finish;
    end

    initial begin
        #10_000_000;
        $fatal(1, "TIMEOUT GENERAL DEL TESTBENCH");
    end

endmodule