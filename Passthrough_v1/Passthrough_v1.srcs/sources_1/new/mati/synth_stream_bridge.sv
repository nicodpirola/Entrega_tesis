`timescale 1ns/1ps

module synth_stream_bridge (
    input  logic               clk,
    input  logic               rst_n,

    // adapter -> bridge
    input  logic               in_valid,
    input  logic signed [31:0] in_data,
    output logic               in_ready,

    // bridge -> adapter
    output logic               out_valid,
    output logic signed [31:0] out_data,
    input  logic               out_ready,

    // bridge -> synth
    output logic               synth_tick,

    // synth -> bridge
    input  logic signed [31:0] synth_sample,
    input  logic               synth_valid
);

    typedef enum logic [1:0] {
        B_WAIT = 2'd0,
        B_GEN  = 2'd1,
        B_OUT  = 2'd2
    } bstate_t;

    bstate_t bstate;

    logic signed [31:0] sample_hold;

    logic in_fire;
    logic out_fire;

    // ------------------------------------------------------------
    // Handshake combinacional
    // ------------------------------------------------------------

    assign in_ready  = (bstate == B_WAIT);

    assign out_valid = (bstate == B_OUT);
    assign out_data  = sample_hold;

    assign in_fire  = in_valid  && in_ready;
    assign out_fire = out_valid && out_ready;

    // Tick de un ciclo cuando aceptamos la muestra del adapter
    assign synth_tick = in_fire;


    // ------------------------------------------------------------
    // FSM
    // ------------------------------------------------------------

    always_ff @(posedge clk) begin
        if (!rst_n) begin

            bstate      <= B_WAIT;
            sample_hold <= '0;

        end else begin

            case (bstate)

                B_WAIT: begin
                    if (in_fire) begin
                        bstate <= B_GEN;
                    end
                end


                B_GEN: begin
                    if (synth_valid) begin

                        sample_hold <= synth_sample;
                        bstate      <= B_OUT;

                    end
                end


                B_OUT: begin
                    if (out_fire) begin
                        bstate <= B_WAIT;
                    end
                end


                default: begin
                    bstate <= B_WAIT;
                end

            endcase
        end
    end

endmodule