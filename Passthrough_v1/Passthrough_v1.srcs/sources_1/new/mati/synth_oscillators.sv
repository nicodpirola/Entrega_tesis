`timescale 1ns/1ps

// =============================================================================
// synth_oscillators.sv
//
// Banco de osciladores:
//
//   OSC1:
//     - ADDITIVE
//     - PolyBLEP SAW_UP
//     - PolyBLEP SAW_DOWN
//     - PolyBLEP PULSE
//
//     ADDITIVE y VA comparten el mismo phase accumulator.
//
//   OSC2:
//     - PolyBLEP SAW_UP
//     - PolyBLEP SAW_DOWN
//     - PolyBLEP PULSE
//
//     Tiene phase accumulator independiente y detune fino.
//
// Los dos osciladores arrancan en paralelo.
//
// Formatos:
//   base_phase_inc       : UQ0.32
//   phase_inc            : UQ0.32
//   phase                : UQ0.32
//   pulse_width          : UQ0.32
//   osc2_detune_q2_30    : unsigned Q2.30
//   samples              : signed Q3.29
//
// Range:
//   0 = 32' -> /4
//   1 = 16' -> /2
//   2 =  8' -> x1
//   3 =  4' -> x2
//   4 =  2' -> x4
//
// OSC1:
//   0 = ADDITIVE
//   1 = SAW_UP
//   2 = SAW_DOWN
//   3 = PULSE
//
// OSC2:
//   0 = SAW_UP
//   1 = SAW_DOWN
//   2 = PULSE
//   3 = reservado -> mute
//
// Un phase_inc efectivo valido cumple:
//
//       0 < phase_inc < 0x80000000
//
// Si queda fuera de ese rango, el oscilador se mutea durante esa muestra.
// =============================================================================
module synth_oscillators(
    input logic clk,
    input logic rst_n,

    input  logic        in_valid,
    output logic        in_ready,
    input  logic [31:0] base_phase_inc,

    // OSC1
    input logic [1:0]  osc1_mode,
    input logic [2:0]  osc1_range,
    input logic [31:0] osc1_pulse_width,
    input logic [5:0]  osc1_n_harmonics,

    // Banco aditivo
    input logic               amp_we,
    input logic [4:0]         amp_addr,
    input logic signed [31:0] amp_wdata,

    // OSC2
    input logic [1:0]  osc2_waveform,
    input logic [2:0]  osc2_range,
    input logic [31:0] osc2_pulse_width,
    input logic [31:0] osc2_detune_q2_30,

    // Resultado
    output logic               out_valid,
    input  logic               out_ready,
    output logic signed [31:0] osc1_sample_q3_29,
    output logic signed [31:0] osc2_sample_q3_29
);

// =============================================================================
// CONSTANTES
// =============================================================================
localparam logic [1:0] OSC1_ADDITIVE = 2'd0;
localparam logic [1:0] OSC1_SAW_UP   = 2'd1;
localparam logic [1:0] OSC1_SAW_DOWN = 2'd2;
localparam logic [1:0] OSC1_PULSE    = 2'd3;

localparam logic [1:0] VA_SAW_UP     = 2'd0;
localparam logic [1:0] VA_SAW_DOWN   = 2'd1;
localparam logic [1:0] VA_PULSE      = 2'd2;

localparam logic [2:0] RANGE_32 = 3'd0;
localparam logic [2:0] RANGE_16 = 3'd1;
localparam logic [2:0] RANGE_8  = 3'd2;
localparam logic [2:0] RANGE_4  = 3'd3;
localparam logic [2:0] RANGE_2  = 3'd4;

localparam logic [35:0] NYQUIST_INC_36 = 36'h0_8000_0000;
// =============================================================================
// RANGE
//
// 34 bits permiten representar:
//     base << 2
//
// sin perder los bits de overflow.
// =============================================================================
function automatic logic [33:0] apply_range_wide(
    input logic [31:0] base,
    input logic [2:0]  range_sel
);
    begin
        case (range_sel)
            RANGE_32:
                apply_range_wide = {2'b00, base} >> 2;

            RANGE_16:
                apply_range_wide = {2'b00, base} >> 1;

            RANGE_8:
                apply_range_wide = {2'b00, base};

            RANGE_4:
                apply_range_wide = {2'b00, base} << 1;

            RANGE_2:
                apply_range_wide = {2'b00, base} << 2;

            default:
                apply_range_wide = 34'd0;
        endcase
    end
endfunction

// =============================================================================
// FSM
// =============================================================================
typedef enum logic [2:0] {
    S_IDLE,
    S_CALC,
    S_START,
    S_WAIT,
    S_HOLD
} state_t;

state_t state;

assign in_ready  = (state == S_IDLE);
assign out_valid = (state == S_HOLD);

// =============================================================================
// PARAMETROS LATCHEADOS
// =============================================================================
logic [31:0] base_phase_inc_r;

logic [1:0]  osc1_mode_r;
logic [2:0]  osc1_range_r;
logic [31:0] osc1_pulse_width_r;
logic [5:0]  osc1_n_harmonics_r;

logic [1:0]  osc2_waveform_r;
logic [2:0]  osc2_range_r;
logic [31:0] osc2_pulse_width_r;
logic [31:0] osc2_detune_r;

// =============================================================================
// RANGE CALC
// =============================================================================
logic [33:0] osc1_range_inc_calc;
logic [33:0] osc2_range_inc_calc;

logic osc1_range_valid;
logic osc2_range_valid;

assign osc1_range_inc_calc = apply_range_wide(
    base_phase_inc_r,
    osc1_range_r
);

assign osc2_range_inc_calc = apply_range_wide(
    base_phase_inc_r,
    osc2_range_r
);

assign osc1_range_valid = (osc1_range_r <= RANGE_2);
assign osc2_range_valid = (osc2_range_r <= RANGE_2);

// =============================================================================
// DETUNE OSC2
//
// range_inc        : hasta 34 bits, 32 bits fraccionales
// detune           : unsigned Q2.30
//
// Producto         : hasta 66 bits, 62 bits fraccionales
//
// >>30:
// resultado        : 36 bits, 32 bits fraccionales
//
// Importante:
// Primero se calcula TODO el detune y DESPUES se comprueba Nyquist.
// =============================================================================
logic [65:0] osc2_detune_full;
logic [35:0] osc2_detune_inc_calc;

assign osc2_detune_full =
    osc2_range_inc_calc * osc2_detune_r;

assign osc2_detune_inc_calc =
    osc2_detune_full[65:30];

// =============================================================================
// PHASE INC EFECTIVOS
// =============================================================================
logic [31:0] osc1_phase_inc_r;
logic [31:0] osc2_phase_inc_r;

logic osc1_active_r;
logic osc2_active_r;

// =============================================================================
// PHASE ACCUMULATORS
// =============================================================================
logic [31:0] phase1;
logic [31:0] phase2;

logic phase1_tick;
logic phase2_tick;

phase_accum u_phase1(
    .clk       (clk),
    .rst_n     (rst_n),
    .tick      (phase1_tick),
    .phase_inc (osc1_phase_inc_r),
    .phase     (phase1)
);

phase_accum u_phase2(
    .clk       (clk),
    .rst_n     (rst_n),
    .tick      (phase2_tick),
    .phase_inc (osc2_phase_inc_r),
    .phase     (phase2)
);

// =============================================================================
// OSC1 ADDITIVE
// =============================================================================
logic add_in_valid;
logic add_in_ready;

logic add_out_valid;
logic add_out_ready;

logic signed [31:0] add_sample;

osc_additive u_additive(
    .clk          (clk),
    .rst_n        (rst_n),

    .in_valid     (add_in_valid),
    .in_ready     (add_in_ready),

    .phase        (phase1),
    .phase_inc    (osc1_phase_inc_r),
    .n_harmonics  (osc1_n_harmonics_r),

    .amp_we       (amp_we),
    .amp_addr     (amp_addr),
    .amp_wdata    (amp_wdata),

    .out_valid    (add_out_valid),
    .out_ready    (add_out_ready),
    .sample_q3_29 (add_sample)
);

// =============================================================================
// OSC1 VA
// =============================================================================
logic va1_in_valid;
logic va1_in_ready;

logic va1_out_valid;
logic va1_out_ready;

logic [1:0] va1_waveform;

logic signed [31:0] va1_sample;

always_comb begin
    case (osc1_mode_r)
        OSC1_SAW_UP:
            va1_waveform = VA_SAW_UP;

        OSC1_SAW_DOWN:
            va1_waveform = VA_SAW_DOWN;

        OSC1_PULSE:
            va1_waveform = VA_PULSE;

        default:
            va1_waveform = VA_SAW_UP;
    endcase
end

osc_va_polyblep u_va1(
    .clk          (clk),
    .rst_n        (rst_n),

    .in_valid     (va1_in_valid),
    .in_ready     (va1_in_ready),

    .phase        (phase1),
    .phase_inc    (osc1_phase_inc_r),
    .waveform     (va1_waveform),
    .pulse_width  (osc1_pulse_width_r),

    .out_valid    (va1_out_valid),
    .out_ready    (va1_out_ready),
    .sample_q3_29 (va1_sample)
);

// =============================================================================
// OSC2 VA
// =============================================================================
logic va2_in_valid;
logic va2_in_ready;

logic va2_out_valid;
logic va2_out_ready;

logic signed [31:0] va2_sample;

osc_va_polyblep u_va2(
    .clk          (clk),
    .rst_n        (rst_n),

    .in_valid     (va2_in_valid),
    .in_ready     (va2_in_ready),

    .phase        (phase2),
    .phase_inc    (osc2_phase_inc_r),
    .waveform     (osc2_waveform_r),
    .pulse_width  (osc2_pulse_width_r),

    .out_valid    (va2_out_valid),
    .out_ready    (va2_out_ready),
    .sample_q3_29 (va2_sample)
);

// =============================================================================
// SELECCION DE READY PARA OSC1
// =============================================================================
logic osc1_engine_ready;
logic osc2_engine_ready;

always_comb begin
    if (!osc1_active_r)
        osc1_engine_ready = 1'b1;
    else if (osc1_mode_r == OSC1_ADDITIVE)
        osc1_engine_ready = add_in_ready;
    else
        osc1_engine_ready = va1_in_ready;
end

assign osc2_engine_ready =
    !osc2_active_r || va2_in_ready;

// =============================================================================
// LANZAMIENTO SINCRONIZADO
//
// Los motores activos arrancan TODOS en el mismo flanco.
//
// Si alguno no esta ready, no arranca ninguno.
//
// En ese mismo flanco:
//   - los motores capturan phase1 / phase2 actuales
//   - los phase accumulators avanzan a la siguiente muestra
//
// Debido a NBA:
//   motores reciben phi[n]
//   accumulators quedan con phi[n+1]
// =============================================================================
logic launch_fire;

assign launch_fire =
    (state == S_START) &&
    osc1_engine_ready &&
    osc2_engine_ready;

assign add_in_valid =
    launch_fire &&
    osc1_active_r &&
    (osc1_mode_r == OSC1_ADDITIVE);

assign va1_in_valid =
    launch_fire &&
    osc1_active_r &&
    (osc1_mode_r != OSC1_ADDITIVE);

assign va2_in_valid =
    launch_fire &&
    osc2_active_r;

assign phase1_tick =
    launch_fire &&
    osc1_active_r;

assign phase2_tick =
    launch_fire &&
    osc2_active_r;

// =============================================================================
// OUTPUT READY HACIA LOS MOTORES
// =============================================================================
logic osc1_done_r;
logic osc2_done_r;

logic add_out_fire;
logic va1_out_fire;
logic va2_out_fire;

assign add_out_ready =
    (state == S_WAIT) &&
    osc1_active_r &&
    !osc1_done_r &&
    (osc1_mode_r == OSC1_ADDITIVE);

assign va1_out_ready =
    (state == S_WAIT) &&
    osc1_active_r &&
    !osc1_done_r &&
    (osc1_mode_r != OSC1_ADDITIVE);

assign va2_out_ready =
    (state == S_WAIT) &&
    osc2_active_r &&
    !osc2_done_r;

assign add_out_fire =
    add_out_valid && add_out_ready;

assign va1_out_fire =
    va1_out_valid && va1_out_ready;

assign va2_out_fire =
    va2_out_valid && va2_out_ready;

// =============================================================================
// FSM PRINCIPAL
// =============================================================================
always_ff @(posedge clk) begin
    if (!rst_n) begin
        state <= S_IDLE;

        base_phase_inc_r <= '0;

        osc1_mode_r        <= OSC1_ADDITIVE;
        osc1_range_r       <= RANGE_8;
        osc1_pulse_width_r <= 32'h8000_0000;
        osc1_n_harmonics_r <= 6'd1;

        osc2_waveform_r    <= VA_SAW_UP;
        osc2_range_r       <= RANGE_8;
        osc2_pulse_width_r <= 32'h8000_0000;
        osc2_detune_r      <= 32'h4000_0000;

        osc1_phase_inc_r <= '0;
        osc2_phase_inc_r <= '0;

        osc1_active_r <= 1'b0;
        osc2_active_r <= 1'b0;

        osc1_done_r <= 1'b0;
        osc2_done_r <= 1'b0;

        osc1_sample_q3_29 <= '0;
        osc2_sample_q3_29 <= '0;
    end else begin
        case (state)

            // =================================================================
            // Captura atomica de TODOS los controles de esta muestra.
            // =================================================================
            S_IDLE: begin
                if (in_valid && in_ready) begin
                    base_phase_inc_r <= base_phase_inc;

                    osc1_mode_r        <= osc1_mode;
                    osc1_range_r       <= osc1_range;
                    osc1_pulse_width_r <= osc1_pulse_width;
                    osc1_n_harmonics_r <= osc1_n_harmonics;

                    osc2_waveform_r    <= osc2_waveform;
                    osc2_range_r       <= osc2_range;
                    osc2_pulse_width_r <= osc2_pulse_width;
                    osc2_detune_r      <= osc2_detune_q2_30;

                    state <= S_CALC;
                end
            end

            // =================================================================
            // Resolver range, detune y validez.
            // =================================================================
            S_CALC: begin
                if (
                    osc1_range_valid &&
                    (osc1_range_inc_calc != 34'd0) &&
                    (osc1_range_inc_calc < 34'h0_8000_0000)
                ) begin
                    osc1_phase_inc_r <= osc1_range_inc_calc[31:0];
                    osc1_active_r    <= 1'b1;
                    osc1_done_r      <= 1'b0;
                end else begin
                    osc1_phase_inc_r   <= 32'd0;
                    osc1_active_r      <= 1'b0;
                    osc1_done_r        <= 1'b1;
                    osc1_sample_q3_29  <= 32'sd0;
                end

                if (
                    osc2_range_valid &&
                    (osc2_waveform_r <= VA_PULSE) &&
                    (osc2_detune_inc_calc != 36'd0) &&
                    (osc2_detune_inc_calc < NYQUIST_INC_36)
                ) begin
                    osc2_phase_inc_r <= osc2_detune_inc_calc[31:0];
                    osc2_active_r    <= 1'b1;
                    osc2_done_r      <= 1'b0;
                end else begin
                    osc2_phase_inc_r   <= 32'd0;
                    osc2_active_r      <= 1'b0;
                    osc2_done_r        <= 1'b1;
                    osc2_sample_q3_29  <= 32'sd0;
                end

                state <= S_START;
            end

            // =================================================================
            // Esperar que TODOS los motores necesarios esten ready.
            //
            // Cuando eso ocurre:
            //   - se lanza cada motor activo
            //   - avanza cada phase accumulator activo
            //   - ambos arrancan exactamente en el mismo flanco
            // =================================================================
            S_START: begin
                if (!osc1_active_r && !osc2_active_r) begin
                    state <= S_HOLD;
                end else if (launch_fire) begin
                    state <= S_WAIT;
                end
            end

            // =================================================================
            // Esperar resultados independientemente.
            //
            // El rapido puede terminar primero y queda guardado.
            // El wrapper sale cuando terminaron ambos.
            // =================================================================
            S_WAIT: begin
                if (add_out_fire) begin
                    osc1_sample_q3_29 <= add_sample;
                    osc1_done_r        <= 1'b1;
                end

                if (va1_out_fire) begin
                    osc1_sample_q3_29 <= va1_sample;
                    osc1_done_r        <= 1'b1;
                end

                if (va2_out_fire) begin
                    osc2_sample_q3_29 <= va2_sample;
                    osc2_done_r        <= 1'b1;
                end

                if (
                    (osc1_done_r || add_out_fire || va1_out_fire) &&
                    (osc2_done_r || va2_out_fire)
                ) begin
                    state <= S_HOLD;
                end
            end

            // =================================================================
            // Mantener ambos resultados estables hasta que los acepte el
            // siguiente bloque.
            // =================================================================
            S_HOLD: begin
                if (out_valid && out_ready)
                    state <= S_IDLE;
            end

            default: state <= S_IDLE;
        endcase
    end
end

// =============================================================================
// ASSERTS - SOLO SIMULACION
// =============================================================================
`ifndef SYNTHESIS

always_ff @(posedge clk) begin
    if (rst_n && in_valid && in_ready) begin
        assert (osc1_range <= RANGE_2)
            else $warning(
                "synth_oscillators: osc1_range invalido"
            );

        assert (osc2_range <= RANGE_2)
            else $warning(
                "synth_oscillators: osc2_range invalido"
            );

        assert (osc2_waveform <= VA_PULSE)
            else $warning(
                "synth_oscillators: osc2_waveform reservado"
            );
    end
end

`endif

endmodule