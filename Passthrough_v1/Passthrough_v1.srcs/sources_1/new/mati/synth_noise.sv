`timescale 1ns/1ps

// =============================================================================
// synth_noise.sv
//
// Generador pseudoaleatorio para ruido blanco.
//
// PRNG:
//   xorshift32
//   periodo 2^32-1 para seed != 0
//
// Salida:
//   signed Q3.29
//   aproximadamente [-1.0, +1.0)
//
// CTRL externo:
//   enable
//   reseed
//   seed
//
// Handshake:
//   in_valid / in_ready
//   out_valid / out_ready
//
// Una muestra en vuelo.
// =============================================================================
module synth_noise(
    input logic clk,
    input logic rst_n,

    input  logic in_valid,
    output logic in_ready,

    input logic        enable,
    input logic        reseed,
    input logic [31:0] seed,

    output logic               out_valid,
    input  logic               out_ready,
    output logic signed [31:0] sample_q3_29
);

// =============================================================================
// PRNG STATE
// =============================================================================

logic [31:0] state_r;

function automatic logic [31:0] xorshift32_next(
    input logic [31:0] s
);
    logic [31:0] x;
begin
    x = s;

    x = x ^ (x << 13);
    x = x ^ (x >> 17);
    x = x ^ (x << 5);

    xorshift32_next = x;
end
endfunction

// =============================================================================
// SEED
// =============================================================================

logic [31:0] seed_safe;

assign seed_safe =
    (seed == 32'd0) ?
    32'h1ACE_B00C :
    seed;

// =============================================================================
// RESEED EDGE
// =============================================================================

logic reseed_d;
logic reseed_rise;

assign reseed_rise =
    reseed &&
    !reseed_d;

// Mientras estamos haciendo reseed no aceptamos una request.
assign in_ready =
    !out_valid &&
    !reseed_rise;

// =============================================================================
// PROCESS
// =============================================================================

always_ff @(posedge clk) begin
    if (!rst_n) begin
        state_r <= 32'h1ACE_B00C;

        reseed_d <= 1'b0;

        out_valid <= 1'b0;
        sample_q3_29 <= 32'sd0;

    end else begin

        reseed_d <= reseed;

        // ---------------------------------------------------------------------
        // Consumir output anterior.
        // ---------------------------------------------------------------------
        if (
            out_valid &&
            out_ready
        )
            out_valid <= 1'b0;

        // ---------------------------------------------------------------------
        // Reseed.
        // ---------------------------------------------------------------------
        if (reseed_rise) begin
            state_r <= seed_safe;

        end else if (
            in_valid &&
            in_ready
        ) begin

            // -------------------------------------------------------------
            // Interpretamos state_r como signed Q1.31.
            //
            // Para expresar el mismo valor en Q3.29:
            //
            //     Q3.29 = Q1.31 >>> 2
            //
            // Por lo tanto:
            //
            //     -1.0 <= sample < +1.0
            // -------------------------------------------------------------

            if (enable)
                sample_q3_29 <=
                    $signed(state_r) >>> 2;
            else
                sample_q3_29 <=
                    32'sd0;

            state_r <=
                xorshift32_next(state_r);

            out_valid <= 1'b1;
        end
    end
end

endmodule