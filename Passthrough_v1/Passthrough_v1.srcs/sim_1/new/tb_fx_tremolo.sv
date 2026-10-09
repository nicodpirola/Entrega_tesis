`timescale 1ns/1ps

module tb_fx_tremolo;

    localparam logic signed [31:0] SAMPLE = 32'sh1000_0000; // 0.5 en Q3.29

    logic               clk;
    logic               rst_n;
    logic               enable;

    logic               in_valid;
    logic               in_ready;
    logic signed [31:0] in_data;

    logic               out_valid;
    logic               out_ready;
    logic signed [31:0] out_data;

    logic signed [31:0] depth_q1_31;
    logic        [31:0] lfo_phase_inc_u32;

    logic signed [31:0] result;
    logic signed [31:0] held_result;

    //instancia
    fx_tremolo dut (
        .clk               (clk              ),
        .rst_n             (rst_n            ),
        .enable            (enable           ),

        .in_valid          (in_valid         ),
        .in_ready          (in_ready         ),
        .in_data           (in_data          ),

        .out_valid         (out_valid        ),
        .out_ready         (out_ready        ),
        .out_data          (out_data         ),

        .depth_q1_31       (depth_q1_31      ),
        .lfo_phase_inc_u32 (lfo_phase_inc_u32)
    );

    // clock
    initial clk = 1'b0;
    always #10 clk = ~clk; //50MHz


    // tareas
    task automatic send_sample(input logic signed [31:0] sample);
        begin
            @(negedge clk);
            while (!in_ready) @(negedge clk);
            
            in_data  = sample;
            in_valid = 1'b1;
            
            @(negedge clk);
            in_valid = 1'b0;
        end
    endtask

    task automatic receive_sample(output logic signed [31:0] sample);
        begin
            while (!out_valid)
                @(negedge clk);
    
            sample = out_data;
        end
    endtask

    task automatic check_near(
        input logic signed [31:0] measured,
        input logic signed [31:0] expected,
        input integer             tolerance,
        input string              test_name
    );
        longint signed difference;
        begin
            difference = $signed(measured) - $signed(expected);
            if (difference < 0) difference = -difference;

            if (difference > tolerance) begin
                $display("ERROR %s: resultado=%h esperado=%h", test_name, measured, expected);
                $fatal;
            end
        end
    endtask
    
    initial begin
        #100_000;
        $display("ERROR: timeout del testbench");
        $fatal;
    end

    initial begin
        // init
        rst_n             = 1'b0;
        enable            = 1'b0;
        in_valid          = 1'b0;
        in_data           = '0;
        out_ready         = 1'b1;
        depth_q1_31       = '0;
        lfo_phase_inc_u32 = 32'h8000_0000;

        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // 1. prueba de bypass
        send_sample(SAMPLE);
        receive_sample(result);
        check_near(result, SAMPLE, 0, "bypass");

        // 2. prueba depth = 0
        @(negedge clk);
        enable      = 1'b1;
        depth_q1_31 = 32'sd0;
        
        repeat (2) @(posedge clk);
        send_sample(SAMPLE);
        receive_sample(result);
        check_near(result, SAMPLE, 1, "depth cero");

        // 3. reinicio del LFO
        @(negedge clk);
        enable = 1'b0;
        
        repeat (2) @(posedge clk);
        @(negedge clk);
        enable      = 1'b1;
        depth_q1_31 = 32'sh7FFF_FFFF;
        repeat (2) @(posedge clk);

        // ganancia maxima
        send_sample(SAMPLE);
        receive_sample(result);
        check_near(result, SAMPLE, 1, "ganancia maxima");

        // ganancia minima (el LFO salta al extremo opuesto)
        send_sample(SAMPLE);
        receive_sample(result);
        check_near(result, 32'sd0, 2, "ganancia minima");

        // 4. prueba de Backpressure (saturación de salida)
        @(negedge clk);
        enable    = 1'b0;
        out_ready = 1'b0;
        send_sample(SAMPLE);

        @(negedge clk);
        while (!out_valid) @(negedge clk);
        held_result = out_data;

        repeat (3) begin
            @(posedge clk);
            #1;
            if (!out_valid || out_data !== held_result) begin
                $display("ERROR: salida inestable con backpressure");
                $fatal;
            end
        end

        @(negedge clk);
        out_ready = 1'b1;
        repeat (2) @(posedge clk);

        $display("TB FX TREMOLO: OK");
        $finish;
    end

endmodule