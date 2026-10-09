`timescale 1ns/1ps

// =============================================================================
// osc_additive.sv - Oscilador aditivo, fase externa
//
// y[n] = sum A[k] * sin(k*phase)
//
// La fase fundamental se recibe desde afuera, igual que osc_va_polyblep.
//
// Formatos:
//   phase / phase_inc : UQ0.32
//   amp_mem           : signed Q1.31
//   CORDIC sin        : signed Q1.31
//   producto          : signed Q2.62
//   acumulador        : signed 70 bits, 62 bits fraccionales
//   salida            : signed Q3.29
//
// Bandlimiting:
//   solo se calculan armonicos con:
//
//       k * phase_inc < 0x80000000
//
//   es decir, frecuencia estrictamente menor a Nyquist.
//
// Handshake:
//   in_valid/in_ready   -> solicita una muestra
//   out_valid/out_ready -> devuelve una muestra
//
// Al aceptar una request se latchean:
//   phase
//   phase_inc
//   n_harmonics
//
// El banco amp_mem sigue siendo escribible desde el PS.
// =============================================================================
module osc_additive(
    input logic clk,
    input logic rst_n,

    // request
    input  logic        in_valid,
    output logic        in_ready,
    input  logic [31:0] phase,
    input  logic [31:0] phase_inc,
    input  logic [5:0]  n_harmonics,

    // escritura del banco desde el PS
    input  logic               amp_we,
    input  logic [4:0]         amp_addr,
    input  logic signed [31:0] amp_wdata,

    // response
    output logic               out_valid,
    input  logic               out_ready,
    output logic signed [31:0] sample_q3_29
);

localparam logic [32:0] NYQUIST_INC = 33'h0_8000_0000;

// ---------------------------------------------------------------------------
// Q?.62 -> Q3.29 con saturacion signed 32 bits
// ---------------------------------------------------------------------------
function automatic logic signed [31:0] sat_acc_to_q329(
    input logic signed [69:0] a
);
    logic signed [69:0] shifted;
    begin
        shifted = a >>> 33;

        if (shifted > 70'sd2147483647)
            sat_acc_to_q329 = 32'sh7FFF_FFFF;
        else if (shifted < -70'sd2147483648)
            sat_acc_to_q329 = 32'sh8000_0000;
        else
            sat_acc_to_q329 = shifted[31:0];
    end
endfunction

// ---------------------------------------------------------------------------
// Banco de amplitudes Q1.31
// ---------------------------------------------------------------------------
logic signed [31:0] amp_mem [0:31];

initial begin
    amp_mem[0] = 32'h7FFF_FFFF;

    for (int i = 1; i < 32; i++) begin
        amp_mem[i] = 32'sd0;
    end
end

always_ff @(posedge clk) begin
    if (amp_we)
        amp_mem[amp_addr] <= amp_wdata;
end

// ---------------------------------------------------------------------------
// CORDIC
// ---------------------------------------------------------------------------
logic cordic_start;
logic cordic_done;
logic signed [31:0] cordic_sin, cordic_cos;
logic [31:0] cordic_phase_in;

cordic_phase u_cordic(
    .clk          (clk),
    .rst_n        (rst_n),
    .start        (cordic_start),
    .phase_u32    (cordic_phase_in),
    .done         (cordic_done),
    .sin_q31      (cordic_sin),
    .cos_q31      (cordic_cos)
);

// ---------------------------------------------------------------------------
// Datos de la transaccion actual
// ---------------------------------------------------------------------------
logic [31:0] base_phase;
logic [31:0] phase_inc_r;
logic [5:0]  n_harmonics_r;

// ---------------------------------------------------------------------------
// Motor armonico
// ---------------------------------------------------------------------------
logic [5:0]  k;
logic [31:0] harmonic_phase;
logic [32:0] harmonic_inc;
logic signed [69:0] acc;
logic signed [63:0] prod;

// ---------------------------------------------------------------------------
// FSM
// ---------------------------------------------------------------------------
typedef enum logic [2:0] {
    ST_IDLE,
    ST_START,
    ST_WAIT,
    ST_MUL,
    ST_ACC,
    ST_OUTPUT,
    ST_HOLD
} state_t;

state_t state;

assign in_ready  = (state == ST_IDLE);
assign out_valid = (state == ST_HOLD);

// ---------------------------------------------------------------------------
// FSM principal
// ---------------------------------------------------------------------------
always_ff @(posedge clk) begin
    if (!rst_n) begin
        state           <= ST_IDLE;
        k               <= 6'd1;
        harmonic_phase  <= '0;
        harmonic_inc    <= '0;
        base_phase      <= '0;
        phase_inc_r     <= '0;
        n_harmonics_r   <= 6'd1;
        acc             <= '0;
        prod            <= '0;
        cordic_start    <= 1'b0;
        cordic_phase_in <= '0;
        sample_q3_29    <= '0;
    end else begin
        cordic_start <= 1'b0;

        case (state)
            // -----------------------------------------------------------------
            // Captura una request.
            // -----------------------------------------------------------------
            ST_IDLE: begin
                if (in_valid && in_ready) begin
                    base_phase     <= phase;
                    phase_inc_r    <= phase_inc;
                    harmonic_phase <= phase;
                    harmonic_inc   <= {1'b0, phase_inc};
                    k              <= 6'd1;
                    acc            <= '0;

                    if (n_harmonics < 6'd1)
                        n_harmonics_r <= 6'd1;
                    else if (n_harmonics > 6'd32)
                        n_harmonics_r <= 6'd32;
                    else
                        n_harmonics_r <= n_harmonics;

                    state <= ST_START;
                end
            end

            // -----------------------------------------------------------------
            // Antes de calcular cada armonico verificamos Nyquist.
            //
            // Como k crece monotonamente, cuando uno alcanza Nyquist todos los
            // siguientes tambien quedan fuera de banda y podemos terminar.
            // -----------------------------------------------------------------
            ST_START: begin
                if (harmonic_inc >= NYQUIST_INC) begin
                    state <= ST_OUTPUT;
                end else begin
                    cordic_phase_in <= harmonic_phase;
                    cordic_start    <= 1'b1;
                    state           <= ST_WAIT;
                end
            end

            // -----------------------------------------------------------------
            // Esperar CORDIC
            // -----------------------------------------------------------------
            ST_WAIT: begin
                if (cordic_done)
                    state <= ST_MUL;
            end

            // -----------------------------------------------------------------
            // Q1.31 x Q1.31 = Q2.62
            // -----------------------------------------------------------------
            ST_MUL: begin
                prod  <= cordic_sin * amp_mem[k-1];
                state <= ST_ACC;
            end

            // -----------------------------------------------------------------
            // Acumular y preparar siguiente armonico
            // -----------------------------------------------------------------
            ST_ACC: begin
                acc <= acc + prod;

                if (k >= n_harmonics_r) begin
                    state <= ST_OUTPUT;
                end else begin
                    k              <= k + 1'b1;
                    harmonic_phase <= harmonic_phase + base_phase;
                    harmonic_inc   <= harmonic_inc + {1'b0, phase_inc_r};
                    state          <= ST_START;
                end
            end

            // -----------------------------------------------------------------
            // Convertir a Q3.29
            // -----------------------------------------------------------------
            ST_OUTPUT: begin
                sample_q3_29 <= sat_acc_to_q329(acc);
                state <= ST_HOLD;
            end

            // -----------------------------------------------------------------
            // Mantener resultado estable hasta handshake
            // -----------------------------------------------------------------
            ST_HOLD: begin
                if (out_valid && out_ready)
                    state <= ST_IDLE;
            end

            default: state <= ST_IDLE;
        endcase
    end
end

// ---------------------------------------------------------------------------
// Asserts de contrato - solo simulacion
// ---------------------------------------------------------------------------
`ifndef SYNTHESIS
always_ff @(posedge clk) begin
    if (rst_n && in_valid && in_ready) begin
        assert (phase_inc < 32'h8000_0000)
            else $error("osc_additive: fundamental >= Nyquist");

        assert ((n_harmonics >= 6'd1) && (n_harmonics <= 6'd32))
            else $warning("osc_additive: n_harmonics fuera de 1..32, se aplica clamp");
    end
end
`endif

endmodule
