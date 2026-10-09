`timescale 1ns/1ps

// =============================================================================
// synth_mixer.sv
//
// Mixer lineal del sintetizador.
//
// Entradas:
//   OSC1  : signed Q3.29
//   OSC2  : signed Q3.29
//   NOISE : signed Q3.29
//
// Levels:
//   unsigned Q1.31
//   0.0 = 0x00000000
//   1.0 = 0x7FFFFFFF
//
// Cadena:
//
//   OSC1  * level1 ─┐
//   OSC2  * level2 ─┼─> SUM WIDE -> SAT Q3.29 -> REG -> BUS_TRIM -> OUT
//   NOISE * levelN ─┘
//
// IMPORTANTE:
//   - No se divide por cantidad de fuentes.
//   - Los levels son independientes.
//   - El softclip fue retirado del datapath.
//   - Los puertos del softclip se conservan para no cambiar interfaces.
//   - La unica saturacion interna es NUMERICA para evitar overflow Q3.29.
//   - BUS_TRIM controla el nivel nominal hacia la siguiente etapa.
//
// Timing:
//   Cada operacion pesada queda separada por registros.
//
// Un sample en vuelo.
// =============================================================================

module synth_mixer(
    input logic clk,
    input logic rst_n,

    input  logic in_valid,
    output logic in_ready,

    input logic signed [31:0] osc1_sample_q3_29,
    input logic signed [31:0] osc2_sample_q3_29,
    input logic signed [31:0] noise_sample_q3_29,

    input logic [31:0] osc1_level_q1_31,
    input logic [31:0] osc2_level_q1_31,
    input logic [31:0] noise_level_q1_31,

    // -------------------------------------------------------------------------
    // Se conservan por compatibilidad con regmap/core.
    // Actualmente NO forman parte del datapath.
    // -------------------------------------------------------------------------
    input logic               softclip_enable,
    input logic [31:0]        bus_trim_q1_31,

    input logic signed [31:0] softclip_t1_q3_29,
    input logic signed [31:0] softclip_t2_q3_29,
    input logic signed [31:0] softclip_k1_q1_31,
    input logic signed [31:0] softclip_k2_q1_31,

    output logic               out_valid,
    input  logic               out_ready,
    output logic signed [31:0] sample_q3_29,

    // Debug
    output logic overdrive,
    output logic clip
);

import fx_dsp_pkg::*;

// =============================================================================
// CLAMP DE GANANCIAS
//
// Levels y BUS_TRIM son unsigned 0...1.
//
// 0x7FFFFFFF = aproximadamente unity.
//
// Si desde PS llega bit31=1, lo limitamos a unity.
// =============================================================================

function automatic logic signed [31:0] safe_level(
    input logic [31:0] x
);
begin
    if (x[31])
        safe_level = 32'sh7FFF_FFFF;
    else
        safe_level = $signed(x);
end
endfunction

// =============================================================================
// FSM
// =============================================================================

typedef enum logic [2:0] {
    S_IDLE,
    S_MUL,
    S_SUM,
    S_LIMIT,
    S_TRIM,
    S_HOLD
} state_t;

state_t state;

assign in_ready  = (state == S_IDLE);
assign out_valid = (state == S_HOLD);

// =============================================================================
// INPUT REGISTERS
// =============================================================================

logic signed [31:0] x1_r;
logic signed [31:0] x2_r;
logic signed [31:0] xn_r;

logic signed [31:0] level1_r;
logic signed [31:0] level2_r;
logic signed [31:0] leveln_r;

logic signed [31:0] trim_r;

// T1 solamente se conserva para el indicador overdrive.
// NO afecta el audio.
logic signed [31:0] t1_r;

// =============================================================================
// WEIGHTED SOURCES
//
// Q3.29 * Q1.31 -> Q3.29
// =============================================================================

logic signed [31:0] weighted1_r;
logic signed [31:0] weighted2_r;
logic signed [31:0] weightedn_r;

// =============================================================================
// WIDE SUM
//
// 3 x signed 32 bit -> signed 34 bit.
//
// Continuan siendo 29 bits fraccionales.
// =============================================================================

logic signed [33:0] sum_r;

// =============================================================================
// NUMERIC LIMIT
//
// El mixer interno trabaja con suma wide.
//
// Antes de volver a 32-bit Q3.29:
//   max = +2147483647
//   min = -2147483648
//
// Esto NO pretende ser una saturacion musical.
// Es exclusivamente proteccion numerica.
// =============================================================================

logic signed [31:0] limited_w;

always_comb begin

    if (sum_r > 34'sd2147483647)
        limited_w = 32'sh7FFF_FFFF;

    else if (sum_r < -34'sd2147483648)
        limited_w = 32'sh8000_0000;

    else
        limited_w = sum_r[31:0];

end

// Registro que corta el camino entre SUM y BUS_TRIM.
logic signed [31:0] limited_r;

// =============================================================================
// OVERDRIVE THRESHOLD
//
// Se mantiene solo como indicador de debug.
//
// El audio sigue siendo completamente lineal mientras no haya overflow
// numerico.
//
// T1 ya NO activa ningun waveshaper.
// =============================================================================

logic signed [33:0] t1_ext;

assign t1_ext =
    {{2{t1_r[31]}}, t1_r};

// =============================================================================
// FSM
// =============================================================================

always_ff @(posedge clk) begin

    if (!rst_n) begin

        state <= S_IDLE;

        x1_r <= 32'sd0;
        x2_r <= 32'sd0;
        xn_r <= 32'sd0;

        level1_r <= 32'sd0;
        level2_r <= 32'sd0;
        leveln_r <= 32'sd0;

        trim_r <= 32'sd0;
        t1_r   <= 32'sd0;

        weighted1_r <= 32'sd0;
        weighted2_r <= 32'sd0;
        weightedn_r <= 32'sd0;

        sum_r <= 34'sd0;

        limited_r <= 32'sd0;

        sample_q3_29 <= 32'sd0;

        overdrive <= 1'b0;
        clip      <= 1'b0;

    end else begin

        case (state)

            // =================================================================
            // Captura atomica de inputs + niveles.
            // =================================================================

            S_IDLE: begin

                if (in_valid && in_ready) begin

                    x1_r <= osc1_sample_q3_29;
                    x2_r <= osc2_sample_q3_29;
                    xn_r <= noise_sample_q3_29;

                    level1_r <=
                        safe_level(osc1_level_q1_31);

                    level2_r <=
                        safe_level(osc2_level_q1_31);

                    leveln_r <=
                        safe_level(noise_level_q1_31);

                    trim_r <=
                        safe_level(bus_trim_q1_31);

                    // Solamente para indicador overdrive.
                    t1_r <=
                        softclip_t1_q3_29;

                    overdrive <= 1'b0;
                    clip      <= 1'b0;

                    state <= S_MUL;
                end
            end

            // =================================================================
            // Aplicar levels individuales.
            //
            // Tres multiplicaciones paralelas.
            //
            //   Q3.29 * Q1.31 -> Q3.29
            // =================================================================

            S_MUL: begin

                weighted1_r <=
                    mul_aud_q31(
                        x1_r,
                        level1_r
                    );

                weighted2_r <=
                    mul_aud_q31(
                        x2_r,
                        level2_r
                    );

                weightedn_r <=
                    mul_aud_q31(
                        xn_r,
                        leveln_r
                    );

                state <= S_SUM;
            end

            // =================================================================
            // Suma de las tres fuentes en 34 bits.
            // =================================================================

            S_SUM: begin

                sum_r <=
                    {{2{weighted1_r[31]}}, weighted1_r} +
                    {{2{weighted2_r[31]}}, weighted2_r} +
                    {{2{weightedn_r[31]}}, weightedn_r};

                state <= S_LIMIT;
            end

            // =================================================================
            // Limite NUMERICO.
            //
            // limited_w es solamente:
            //
            //   if sum > MAX -> MAX
            //   if sum < MIN -> MIN
            //   else         -> sum
            //
            // NO hay softclip.
            // NO hay multiplicadores.
            // NO hay waveshaper.
            // =================================================================

            S_LIMIT: begin

                // -------------------------------------------------------------
                // Indicador informativo de nivel > T1.
                // No modifica la señal.
                // -------------------------------------------------------------

                if (
                    (sum_r > t1_ext) ||
                    (sum_r < -t1_ext)
                )
                    overdrive <= 1'b1;
                else
                    overdrive <= 1'b0;

                // -------------------------------------------------------------
                // Overflow numerico real.
                // -------------------------------------------------------------

                if (
                    (sum_r > 34'sd2147483647) ||
                    (sum_r < -34'sd2147483648)
                )
                    clip <= 1'b1;
                else
                    clip <= 1'b0;

                // -------------------------------------------------------------
                // PIPELINE REGISTER
                // -------------------------------------------------------------

                limited_r <= limited_w;

                state <= S_TRIM;
            end

            // =================================================================
            // BUS TRIM
            //
            // Q3.29 * Q1.31 -> Q3.29
            //
            // El multiplicador parte de limited_r registrado.
            // =================================================================

            S_TRIM: begin

                sample_q3_29 <=
                    mul_aud_q31(
                        limited_r,
                        trim_r
                    );

                state <= S_HOLD;
            end

            // =================================================================
            // Mantener resultado hasta handshake.
            // =================================================================

            S_HOLD: begin

                if (out_valid && out_ready)
                    state <= S_IDLE;
            end

            default: begin
                state <= S_IDLE;
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
        in_valid &&
        in_ready
    ) begin

        assert (!osc1_level_q1_31[31])
            else $warning(
                "synth_mixer: OSC1 level > 1.0, clamp a unity"
            );

        assert (!osc2_level_q1_31[31])
            else $warning(
                "synth_mixer: OSC2 level > 1.0, clamp a unity"
            );

        assert (!noise_level_q1_31[31])
            else $warning(
                "synth_mixer: NOISE level > 1.0, clamp a unity"
            );

        assert (!bus_trim_q1_31[31])
            else $warning(
                "synth_mixer: BUS_TRIM > 1.0, clamp a unity"
            );

    end

end

`endif

// =============================================================================
// UNUSED SOFTCLIP PORTS
//
// Se mantienen en la interfaz para que synth_hw_test / core / regmap sigan
// siendo compatibles.
//
// Vivado los optimizara porque no afectan ninguna salida.
// =============================================================================

logic unused_softclip_ports;

always_comb begin
    unused_softclip_ports =
        softclip_enable ^
        ^softclip_t2_q3_29 ^
        ^softclip_k1_q1_31 ^
        ^softclip_k2_q1_31;
end

endmodule