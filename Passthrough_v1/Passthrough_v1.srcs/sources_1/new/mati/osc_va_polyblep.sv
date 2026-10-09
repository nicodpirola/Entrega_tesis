// =============================================================================
// osc_va_polyblep.sv - Oscilador VA con anti-aliasing PolyBLEP
//
// Recibe la fase desde afuera. No posee acumulador de fase interno.
// Reusa UNA unica instancia de polyblep_edge.
//
// Formas:
//   0 = SAW_UP
//   1 = SAW_DOWN
//   2 = PULSE / PWM
//
// Formatos:
//   phase        : UQ0.32
//   phase_inc    : UQ0.32
//   pulse_width  : UQ0.32
//   naive/BLEP   : signed Q1.31
//   acumulador   : signed 34 bits, 31 bits fraccionales
//   sample       : signed Q3.29
//
// SAW_UP:
//   naive = (phase XOR 0x80000000) signed
//   y = naive - BLEP(edge=0)
//
// SAW_DOWN:
//   y = -(naive - BLEP(edge=0))
//
// PULSE:
//   naive = +1 si phase < pulse_width, -1 si no
//   y = naive + BLEP(edge=0) - BLEP(edge=pulse_width)
//
// Al aceptar una request se latchean:
//   phase, phase_inc, waveform y pulse_width.
// Las entradas externas pueden cambiar durante el calculo sin afectar la muestra.
// =============================================================================
module osc_va_polyblep (
input  logic               clk,
input  logic               rst_n,

// request de una muestra
input  logic               in_valid,
output logic               in_ready,
input  logic [31:0]        phase,
input  logic [31:0]        phase_inc,
input  logic [1:0]         waveform,
input  logic [31:0]        pulse_width,

// response
output logic               out_valid,
input  logic               out_ready,
output logic signed [31:0] sample_q3_29
);

localparam logic [1:0] WAVE_SAW_UP   = 2'd0;
localparam logic [1:0] WAVE_SAW_DOWN = 2'd1;
localparam logic [1:0] WAVE_PULSE    = 2'd2;

localparam logic signed [31:0] Q31_MAX = 32'sh7FFF_FFFF;
localparam logic signed [31:0] Q31_MIN = 32'sh8000_0000;

// ---------------------------------------------------------------------------
// FSM
// ---------------------------------------------------------------------------
typedef enum logic [2:0] {
P_IDLE,
P_E0_REQ,
P_E0_WAIT,
P_EPW_REQ,
P_EPW_WAIT,
P_DONE,
P_HOLD
} pstate_t;

pstate_t pstate;

// ---------------------------------------------------------------------------
// Parametros latcheados de la muestra actual
// ---------------------------------------------------------------------------
logic [31:0] phase_r;
logic [31:0] phase_inc_r;
logic [31:0] pulse_width_r;
logic [1:0]  waveform_r;

// ---------------------------------------------------------------------------
// Forma naive y acumulador
//
// acc_r mantiene 31 bits fraccionales.
// 34 bits permiten margen para naive +/- dos correcciones BLEP.
// ---------------------------------------------------------------------------
logic signed [31:0] naive_r;
logic signed [33:0] acc_r;
logic signed [31:0] saw_naive_in;

always_comb begin
    saw_naive_in = $signed(phase ^ 32'h8000_0000);
end

// ---------------------------------------------------------------------------
// PolyBLEP edge unico, reutilizado para edge 0 y edge pulse_width
// ---------------------------------------------------------------------------
logic               edge_in_valid;
logic               edge_in_ready;
logic [31:0]        edge_phase_sel;
logic               edge_out_valid;
logic               edge_out_ready;
logic signed [31:0] edge_correction;

assign edge_in_valid  = (pstate == P_E0_REQ) || (pstate == P_EPW_REQ);
assign edge_out_ready = (pstate == P_E0_WAIT) || (pstate == P_EPW_WAIT);

always_comb begin
    if ((pstate == P_EPW_REQ) || (pstate == P_EPW_WAIT))
        edge_phase_sel = pulse_width_r;
    else
        edge_phase_sel = 32'd0;
end

polyblep_edge u_edge (
    .clk            (clk),
    .rst_n          (rst_n),
    .in_valid       (edge_in_valid),
    .in_ready       (edge_in_ready),
    .phase          (phase_r),
    .edge_phase     (edge_phase_sel),
    .phase_inc      (phase_inc_r),
    .out_valid      (edge_out_valid),
    .out_ready      (edge_out_ready),
    .correction_q31 (edge_correction)
);

// ---------------------------------------------------------------------------
// Extension de signo de la correccion BLEP
// ---------------------------------------------------------------------------
logic signed [33:0] edge_correction_ext;

always_comb begin
    edge_correction_ext = {{2{edge_correction[31]}}, edge_correction};
end

// ---------------------------------------------------------------------------
// Resultado final
//
// Para SAW_DOWN primero se invierte el resultado completo en Q?.31.
// Luego todos los waveforms pasan de 31 a 29 bits fraccionales.
//
// Q?.31 -> Q3.29 : >>> 2
// ---------------------------------------------------------------------------
logic signed [33:0] final_acc_q31;
logic signed [33:0] final_q3_29_wide;

always_comb begin
    if (waveform_r == WAVE_SAW_DOWN)
        final_acc_q31 = -acc_r;
    else
        final_acc_q31 = acc_r;

    final_q3_29_wide = final_acc_q31 >>> 2;
end

// ---------------------------------------------------------------------------
// Handshake externo
// ---------------------------------------------------------------------------
assign in_ready  = (pstate == P_IDLE);
assign out_valid = (pstate == P_HOLD);

// ---------------------------------------------------------------------------
// FSM
// ---------------------------------------------------------------------------
always_ff @(posedge clk) begin
if (!rst_n) begin
    pstate        <= P_IDLE;
    phase_r       <= '0;
    phase_inc_r   <= '0;
    pulse_width_r <= 32'h8000_0000;
    waveform_r    <= WAVE_SAW_UP;
    naive_r       <= '0;
    acc_r         <= '0;
    sample_q3_29  <= '0;
end else begin
    case (pstate)

        // -------------------------------------------------------------------
        // Acepta una muestra y congela TODOS los parametros.
        // -------------------------------------------------------------------
        P_IDLE: begin
            if (in_valid && in_ready) begin
                phase_r       <= phase;
                phase_inc_r   <= phase_inc;
                pulse_width_r <= pulse_width;
                waveform_r    <= waveform;

                // Proteccion frente a parametros invalidos.
                if ((phase_inc == 32'd0) || (phase_inc >= 32'h8000_0000)) begin
                    naive_r      <= 32'sd0;
                    acc_r        <= 34'sd0;
                    sample_q3_29 <= 32'sd0;
                    pstate       <= P_HOLD;
                end else begin
                    case (waveform)

                        // ---------------------------------------------------
                        // SAW naive:
                        // phase=0          -> -1
                        // phase=0x80000000 ->  0
                        // phase~2^32       -> +1
                        //
                        // SAW_UP y SAW_DOWN comparten exactamente el mismo
                        // calculo PolyBLEP. SAW_DOWN se invierte al final.
                        // ---------------------------------------------------
                        WAVE_SAW_UP,
                        WAVE_SAW_DOWN: begin
                            naive_r <= saw_naive_in;
                            acc_r   <= {{2{saw_naive_in[31]}}, saw_naive_in};
                            pstate  <= P_E0_REQ;
                        end

                        // ---------------------------------------------------
                        // Pulse naive:
                        // phase < PW -> +1
                        // resto      -> -1
                        // ---------------------------------------------------
                        WAVE_PULSE: begin
                            if (phase < pulse_width) begin
                                naive_r <= Q31_MAX;
                                acc_r   <= $signed({{2{Q31_MAX[31]}}, Q31_MAX});
                            end else begin
                                naive_r <= Q31_MIN;
                                acc_r   <= $signed({{2{Q31_MIN[31]}}, Q31_MIN});
                            end
                            pstate <= P_E0_REQ;
                        end

                        default: begin
                            naive_r      <= 32'sd0;
                            acc_r        <= 34'sd0;
                            sample_q3_29 <= 32'sd0;
                            pstate       <= P_HOLD;
                        end
                    endcase
                end
            end
        end

        // -------------------------------------------------------------------
        // Solicita BLEP del edge en fase 0
        // -------------------------------------------------------------------
        P_E0_REQ: begin
            if (edge_in_valid && edge_in_ready)
                pstate <= P_E0_WAIT;
        end

        // -------------------------------------------------------------------
        // SAW:
        //   acc = naive - BLEP(0)
        //
        // PULSE:
        //   acc = naive + BLEP(0)
        // -------------------------------------------------------------------
        P_E0_WAIT: begin
            if (edge_out_valid && edge_out_ready) begin
                if (waveform_r == WAVE_PULSE) begin
                    acc_r  <= acc_r + edge_correction_ext;
                    pstate <= P_EPW_REQ;
                end else begin
                    acc_r  <= acc_r - edge_correction_ext;
                    pstate <= P_DONE;
                end
            end
        end

        // -------------------------------------------------------------------
        // PULSE: solicita BLEP del segundo edge, ubicado en pulse_width
        // -------------------------------------------------------------------
        P_EPW_REQ: begin
            if (edge_in_valid && edge_in_ready)
                pstate <= P_EPW_WAIT;
        end

        // -------------------------------------------------------------------
        // PULSE:
        //   acc = naive + BLEP(0) - BLEP(PW)
        // -------------------------------------------------------------------
        P_EPW_WAIT: begin
            if (edge_out_valid && edge_out_ready) begin
                acc_r  <= acc_r - edge_correction_ext;
                pstate <= P_DONE;
            end
        end

        // -------------------------------------------------------------------
        // Resultado:
        //
        // SAW_UP   ->  acc
        // SAW_DOWN -> -acc
        // PULSE    ->  acc
        //
        // Q?.31 -> Q3.29 mediante >>> 2.
        // -------------------------------------------------------------------
        P_DONE: begin
            sample_q3_29 <= final_q3_29_wide[31:0];
            pstate <= P_HOLD;
        end

        // -------------------------------------------------------------------
        // Mantener salida estable hasta que sea consumida.
        // -------------------------------------------------------------------
        P_HOLD: begin
            if (out_valid && out_ready)
                pstate <= P_IDLE;
        end

        default: pstate <= P_IDLE;
    endcase
end
end

// ---------------------------------------------------------------------------
// Asserts de contrato - solo simulacion
// ---------------------------------------------------------------------------
`ifndef SYNTHESIS
always_ff @(posedge clk) begin
    if (rst_n && in_valid && in_ready) begin
        assert (phase_inc != 32'd0)
            else $error("osc_va_polyblep: phase_inc == 0");

        assert (phase_inc < 32'h8000_0000)
            else $error("osc_va_polyblep: phase_inc >= Nyquist");

        assert (
            (waveform == WAVE_SAW_UP) ||
            (waveform == WAVE_SAW_DOWN) ||
            (waveform == WAVE_PULSE)
        )
            else $error("osc_va_polyblep: waveform invalido");
    end
end

always_ff @(posedge clk) begin
    if (rst_n && pstate == P_DONE) begin
        assert (
            (final_q3_29_wide[33:31] == 3'b000) ||
            (final_q3_29_wide[33:31] == 3'b111)
        )
            else $error("osc_va_polyblep: overflow al convertir a Q3.29");
    end
end
`endif

endmodule
