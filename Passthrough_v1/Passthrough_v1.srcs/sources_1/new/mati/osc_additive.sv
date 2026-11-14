// osc_additive.sv
// Oscilador aditivo: suma de armonicos con amplitud programable, fase externa.
//
// y[n] = sum_{k=1..N} A[k] * sin(k * phase[n])
//
// Solo se suman armonicos con k*phase_inc < 2^31 (por debajo de Nyquist), asi la
// senal no tiene aliasing por construccion. N va de 1 a 32. Las amplitudes A[k]
// (Q1.31) las escribe el PS en amp_mem.
//
// El seno de cada armonico sale de cordic_phase (16 iteraciones, sin DSP).
// Un multiplicador de 32x32 bits (mul32_seq, 1 DSP48): el producto del armonico k
// se calcula mientras el CORDIC calcula el seno del armonico k+1.

`timescale 1ns/1ps

module osc_additive(
    input  logic               clk,
    input  logic               rst_n,

    input  logic               in_valid,
    output logic               in_ready,
    input  logic        [31:0] phase,
    input  logic        [31:0] phase_inc,
    input  logic        [5:0]  n_harmonics,

    output logic               out_valid,
    input  logic               out_ready,
    output logic signed [31:0] sample_q3_29,

    input  logic               amp_we,
    input  logic        [4:0]  amp_addr,
    input  logic signed [31:0] amp_wdata
);

    import fx_dsp_pkg::*;

    localparam logic [32:0] NYQUIST_INC = 33'h0_8000_0000;

    //estados
    typedef enum logic [2:0] {
        ST_IDLE,
        ST_START,      //primer armonico
        ST_WAIT_SIN,   //espera el seno del armonico k (y el producto del anterior)
        ST_WAIT_LAST,  //espera el ultimo producto
        ST_OUTPUT
    } state_t;

    state_t state;

    //tabla de amplitudes
    logic signed [31:0] amp_mem [0:31];

    //copias de la entrada
    logic        [31:0] base_phase_reg;
    logic        [31:0] phase_inc_reg;
    logic        [5:0]  n_harmonics_reg;

    //armonico actual
    logic        [5:0]  k;
    logic        [31:0] harmonic_phase;
    logic        [32:0] harmonic_inc;
    logic signed [69:0] acc;

    //CORDIC
    logic               cordic_start;
    logic               cordic_done;
    logic        [31:0] cordic_phase_in;
    logic signed [31:0] cordic_sin;

    //multiplicador compartido
    logic signed [31:0] mul_a_reg;
    logic signed [31:0] mul_b_reg;
    logic               mul_start;
    logic               mul_valid;
    logic               mul_pending;
    logic signed [63:0] mul_p;

    //resultados combinacionales
    logic        [31:0] next_phase;
    logic        [32:0] next_inc;
    logic               hay_siguiente;  //quedan armonicos por calcular
    logic signed [31:0] acc_q3_29;

    //buffer de salida
    logic               out_buf_valid;

    wire in_fire;
    wire out_fire;

    //instancias
    cordic_phase u_cordic (
        .clk       (clk            ),
        .rst_n     (rst_n          ),
        .start     (cordic_start   ),
        .phase_u32 (cordic_phase_in),
        .done      (cordic_done    ),
        .sin_q31   (cordic_sin     ),
        .cos_q31   (               )
    );

    mul32_seq u_mul (
        .clk   (clk      ),
        .rst_n (rst_n    ),
        .start (mul_start),
        .a     (mul_a_reg),
        .b     (mul_b_reg),
        .busy  (         ),
        .valid (mul_valid),
        .p     (mul_p    )
    );

    //assigns
    assign in_ready  = (state == ST_IDLE) && !out_buf_valid;
    assign in_fire   = in_valid && in_ready;
    assign out_fire  = out_valid && out_ready;
    assign out_valid = out_buf_valid;

    //logica combinacional
    always_comb begin
        next_phase    = harmonic_phase + base_phase_reg;          //fase del armonico k+1
        next_inc      = harmonic_inc + {1'b0, phase_inc_reg};     //incremento del armonico k+1
        hay_siguiente = (k < n_harmonics_reg) && (next_inc < NYQUIST_INC);

        //acumulador con 62 bits fraccionales -> Q3.29 saturado
        if ((acc >>> 33) > 70'sd2147483647)       acc_q3_29 = 32'sh7FFF_FFFF;
        else if ((acc >>> 33) < -70'sd2147483648) acc_q3_29 = 32'sh8000_0000;
        else                                      acc_q3_29 = 32'(acc >>> 33);
    end

    //tabla de amplitudes: la escribe el PS, por defecto solo la fundamental
    initial begin
        amp_mem[0] = 32'sh7FFF_FFFF;
        for (int i = 1; i < 32; i++) amp_mem[i] = 32'sd0;
    end

    always_ff @(posedge clk) begin
        if (amp_we) amp_mem[amp_addr] <= amp_wdata;
    end

    //logica secuencial y FSM
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state           <= ST_IDLE;
            base_phase_reg  <= '0;
            phase_inc_reg   <= '0;
            n_harmonics_reg <= 6'd1;
            k               <= 6'd1;
            harmonic_phase  <= '0;
            harmonic_inc    <= '0;
            acc             <= '0;
            cordic_start    <= 1'b0;
            cordic_phase_in <= '0;
            mul_a_reg       <= '0;
            mul_b_reg       <= '0;
            mul_start       <= 1'b0;
            mul_pending     <= 1'b0;
            out_buf_valid   <= 1'b0;
            sample_q3_29    <= '0;
        end
        else begin
            if (out_fire) out_buf_valid <= 1'b0;

            cordic_start <= 1'b0; //pulsos de un ciclo
            mul_start    <= 1'b0;

            //cada producto que termina se suma al acumulador
            if (mul_valid) begin
                acc         <= acc + 70'(mul_p);
                mul_pending <= 1'b0;
            end

            case (state)
                ST_IDLE: begin
                    if (in_fire) begin
                        base_phase_reg <= phase;
                        phase_inc_reg  <= phase_inc;
                        harmonic_phase <= phase;
                        harmonic_inc   <= {1'b0, phase_inc};
                        k              <= 6'd1;
                        acc            <= '0;
                        if (n_harmonics < 6'd1)       n_harmonics_reg <= 6'd1;
                        else if (n_harmonics > 6'd32) n_harmonics_reg <= 6'd32;
                        else                          n_harmonics_reg <= n_harmonics;
                        state          <= ST_START;
                    end
                end

                ST_START: begin //seno de la fundamental, si esta debajo de Nyquist
                    if (harmonic_inc >= NYQUIST_INC) begin
                        state <= ST_OUTPUT;
                    end
                    else begin
                        cordic_phase_in <= harmonic_phase;
                        cordic_start    <= 1'b1;
                        state           <= ST_WAIT_SIN;
                    end
                end

                ST_WAIT_SIN: begin
                    if (cordic_done) begin
                        //producto del armonico k: A[k] * sin(k * phase)
                        mul_a_reg   <= cordic_sin;
                        mul_b_reg   <= amp_mem[5'(k - 6'd1)];
                        mul_start   <= 1'b1;
                        mul_pending <= 1'b1;

                        //mientras tanto, el seno del armonico k+1
                        if (hay_siguiente) begin
                            k               <= k + 6'd1;
                            harmonic_phase  <= next_phase;
                            harmonic_inc    <= next_inc;
                            cordic_phase_in <= next_phase;
                            cordic_start    <= 1'b1;
                        end
                        else begin
                            state <= ST_WAIT_LAST;
                        end
                    end
                end

                ST_WAIT_LAST: begin
                    if (!mul_pending && !mul_start) begin
                        state <= ST_OUTPUT;
                    end
                end

                ST_OUTPUT: begin
                    sample_q3_29  <= acc_q3_29;
                    out_buf_valid <= 1'b1;
                    state         <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
