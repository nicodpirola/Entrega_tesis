`timescale 1ns/1ps

// =============================================================================
// fx_source_router.sv
//
// Seleccion de fuente para la cadena de efectos.
//
// source_select:
//   0 = AUDIO
//   1 = SYNTH
//
// AUDIO:
//   audio_in -> out
//
// SYNTH:
//   cada muestra de audio aceptada dispara un synth_tick.
//   La muestra de ADC no se envia a la salida.
//   Se espera synth_valid y se envia synth_data.
//
// El resultado del synth se captura internamente, por lo que no se pierde
// aunque out_ready este bajo cuando llega synth_valid.
// =============================================================================

module fx_source_router(
    input  logic               clk,
    input  logic               rst_n,

    input  logic               source_select,

    // Audio proveniente del input path
    input  logic               audio_valid,
    output logic               audio_ready,
    input  logic signed [31:0] audio_data,

    // Synth engine
    output logic               synth_tick,
    input  logic               synth_ready,
    input  logic               synth_valid,
    input  logic signed [31:0] synth_data,

    // Fuente seleccionada hacia FX
    output logic               out_valid,
    input  logic               out_ready,
    output logic signed [31:0] out_data
);

typedef enum logic [1:0] {
    ST_IDLE,
    ST_WAIT_SYNTH,
    ST_HOLD_SYNTH
} state_t;

state_t state;

logic signed [31:0] synth_data_r;

// =============================================================================
// COMBINATIONAL ROUTING
// =============================================================================

always_comb begin
    audio_ready = 1'b0;

    synth_tick = 1'b0;

    out_valid = 1'b0;
    out_data  = 32'sd0;

    case (state)

        // ---------------------------------------------------------------------
        // Sin muestra synth pendiente
        // ---------------------------------------------------------------------

        ST_IDLE: begin
            if (!source_select) begin

                // AUDIO: passthrough valid/ready
                audio_ready = out_ready;

                out_valid = audio_valid;
                out_data  = audio_data;

            end else begin

                // SYNTH:
                // la muestra ADC actua solamente como tick temporal.
                audio_ready =
                    synth_ready;

                synth_tick =
                    audio_valid &&
                    synth_ready;
            end
        end

        // ---------------------------------------------------------------------
        // Synth procesando la muestra
        // ---------------------------------------------------------------------

        ST_WAIT_SYNTH: begin
            audio_ready = 1'b0;
        end

        // ---------------------------------------------------------------------
        // Resultado synth esperando al bloque siguiente
        // ---------------------------------------------------------------------

        ST_HOLD_SYNTH: begin
            audio_ready = 1'b0;

            out_valid = 1'b1;
            out_data  = synth_data_r;
        end

        default: begin
            audio_ready = 1'b0;
            synth_tick  = 1'b0;
            out_valid   = 1'b0;
            out_data    = 32'sd0;
        end

    endcase
end

// =============================================================================
// STATE
// =============================================================================

always_ff @(posedge clk) begin
    if (!rst_n) begin
        state        <= ST_IDLE;
        synth_data_r <= 32'sd0;

    end else begin
        case (state)

            ST_IDLE: begin

                // En AUDIO no necesitamos estado.
                //
                // En SYNTH, cuando aceptamos una muestra ADC, el synth_tick
                // se produce en este mismo ciclo y esperamos el resultado.
                if (
                    source_select &&
                    audio_valid &&
                    synth_ready
                ) begin
                    state <= ST_WAIT_SYNTH;
                end
            end

            ST_WAIT_SYNTH: begin
                if (synth_valid) begin
                    synth_data_r <= synth_data;
                    state <= ST_HOLD_SYNTH;
                end
            end

            ST_HOLD_SYNTH: begin
                if (out_ready)
                    state <= ST_IDLE;
            end

            default: begin
                state <= ST_IDLE;
            end

        endcase
    end
end

// =============================================================================
// ASSERTIONS
// =============================================================================

`ifndef SYNTHESIS

always_ff @(posedge clk) begin
    if (
        rst_n &&
        state == ST_WAIT_SYNTH &&
        synth_tick
    ) begin
        $error(
            "fx_source_router: nuevo synth_tick mientras espera resultado"
        );
    end
end

always_ff @(posedge clk) begin
    if (
        rst_n &&
        synth_valid &&
        state != ST_WAIT_SYNTH
    ) begin
        $error(
            "fx_source_router: synth_valid inesperado"
        );
    end
end

`endif

endmodule