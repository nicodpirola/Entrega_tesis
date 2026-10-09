// =============================================================================
// polyblep_edge.sv
//
// Motor de corrección PolyBLEP para discontinuidades (edges) en osciladores.
//
// OPTIMIZACIÓN ALGEBRAICA (Implementación DSP):
// El algoritmo PolyBLEP estándar dicta dos curvas de corrección:
//   - Región 1 (después del edge): correction = 2r - r^2 - 1
//   - Región 2 (antes del edge):   correction = (1 - q)^2
//
// Para minimizar el uso de bloques DSP48 y acortar la ruta crítica,
// la Región 1 se factorizó matemáticamente: -(1 - 2r + r^2) = -(1 - r)^2.
// Esto permite que el datapath calcule una única magnitud (1 - x)^2
// y simplemente asigne el signo correspondiente según la región.
// =============================================================================

module polyblep_edge (
    input  logic               clk,
    input  logic               rst_n,

    input  logic               in_valid,
    output logic               in_ready,
    input  logic [31:0]        phase,
    input  logic [31:0]        edge_phase,
    input  logic [31:0]        phase_inc,

    output logic               out_valid,
    input  logic               out_ready,
    output logic signed [31:0] correction_q31
);

    typedef enum logic [2:0] {
        S_IDLE     = 3'd0,
        S_DIV_REQ  = 3'd1,
        S_DIV_WAIT = 3'd2,
        S_MUL      = 3'd3,
        S_FINISH   = 3'd4,
        S_HOLD     = 3'd5
    } state_t;

    state_t state;

    logic [31:0] d_after;
    logic [31:0] d_before;

    // Distancias modulares: Al ser variables unsigned de 32 bits,
    // las restas ejecutan un wrap-around (módulo 2^32) automático a costo cero.
    assign d_after  = phase - edge_phase;
    assign d_before = edge_phase - phase;

    logic [31:0] div_num;
    logic [31:0] div_den;
    logic        negative_side;

    logic        div_in_valid;
    logic        div_in_ready;
    logic        div_out_valid;
    logic        div_out_ready;
    logic [31:0] div_quotient_q31;

    assign div_in_valid  = (state == S_DIV_REQ);
    assign div_out_ready = (state == S_DIV_WAIT);

    frac_div_u32 u_div (
        .clk          (clk),
        .rst_n        (rst_n),
        .in_valid     (div_in_valid),
        .in_ready     (div_in_ready),
        .numerator    (div_num),
        .denominator  (div_den),
        .out_valid    (div_out_valid),
        .out_ready    (div_out_ready),
        .quotient_q31 (div_quotient_q31)
    );

    logic [31:0] delta_q31;
    logic [63:0] square_q62;
    logic [31:0] magnitude_q31;

    assign magnitude_q31 = square_q62[62:31];
    assign in_ready      = (state == S_IDLE);
    assign out_valid     = (state == S_HOLD);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            div_num        <= '0;
            div_den        <= '0;
            negative_side  <= 1'b0;
            delta_q31      <= '0;
            square_q62     <= '0;
            correction_q31 <= '0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (in_valid && in_ready) begin
                        if ((phase_inc == 32'd0) || (phase_inc >= 32'h8000_0000)) begin
                            correction_q31 <= 32'sd0;
                            state <= S_HOLD;

                        // NOTA ARQUITECTÓNICA - Clasificación del Edge:
                        // En el instante exacto del salto (phase == edge_phase),
                        // tanto d_after como d_before valen 0. Al evaluar primero
                        // d_after, forzamos que el edge exacto caiga en el lado AFTER
                        // (negative_side = 1). Esto es matemáticamente estricto para
                        // aplicar la corrección máxima negativa requerida en t=0.
                        end else if (d_after < phase_inc) begin
                            div_num       <= d_after;
                            div_den       <= phase_inc;
                            negative_side <= 1'b1;
                            state         <= S_DIV_REQ;
                        end else if (d_before < phase_inc) begin
                            div_num       <= d_before;
                            div_den       <= phase_inc;
                            negative_side <= 1'b0;
                            state         <= S_DIV_REQ;
                        end else begin
                            correction_q31 <= 32'sd0;
                            state <= S_HOLD;
                        end
                    end
                end

                S_DIV_REQ: begin
                    if (div_in_valid && div_in_ready)
                        state <= S_DIV_WAIT;
                end

                S_DIV_WAIT: begin
                    if (div_out_valid && div_out_ready) begin
                        delta_q31 <= 32'h8000_0000 - div_quotient_q31;
                        state <= S_MUL;
                    end
                end

                S_MUL: begin
                    square_q62 <= delta_q31 * delta_q31;
                    state <= S_FINISH;
                end

                S_FINISH: begin
                    // NOTA ARQUITECTÓNICA - Caso Borde y Complemento a 2:
                    // Si r=0 (instante del edge), delta_q31 = 0x8000_0000 (1.0).
                    // Tras el cuadrado y el shift, magnitude_q31 = 0x8000_0000.
                    // En aritmética signed Q1.31, este valor representa -1.0.
                    // Si negative_side = 1, la negación en complemento a 2
                    // (~0x8000_0000 + 1) resulta matemáticamente en 0x8000_0000.
                    // Esto garantiza que el borde crítico entregue -1.0 exacto
                    // sin requerir lógica condicional adicional.
                    if (negative_side)
                        correction_q31 <= $signed(~magnitude_q31 + 1'b1);
                    else
                        correction_q31 <= $signed(magnitude_q31);

                    state <= S_HOLD;
                end

                S_HOLD: begin
                    if (out_valid && out_ready)
                        state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n && in_valid && in_ready) begin
            assert (phase_inc != 32'd0)
                else $error("polyblep_edge: phase_inc == 0");
            assert (phase_inc < 32'h8000_0000)
                else $error("polyblep_edge: phase_inc >= Nyquist");
        end
    end
`endif

endmodule
