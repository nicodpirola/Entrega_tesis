// synth_oscillators.sv
// Banco de dos osciladores del synth, con acumulador de fase propio cada uno.
//
// OSC1: aditivo, sierra subiendo, sierra bajando o pulso (osc1_mode 0..3)
// OSC2: sierra subiendo, sierra bajando o pulso (osc2_waveform 0..2), con detune
//
// inc1 = base * R1                     R: range 32'=1/4, 16'=1/2, 8'=1, 4'=2, 2'=4
// inc2 = base * R2 * detune            detune en Q2.30 sin signo (1.0 = 2^30)
// Un oscilador se apaga en la muestra si su incremento queda en 0 o >= 2^31 (Nyquist).
//
// El producto del detune usa un multiplicador de 32x32 bits (mul32_seq, 1 DSP48).
// Los dos osciladores arrancan en el mismo flanco y la salida espera a ambos.

`timescale 1ns/1ps

module synth_oscillators(
    input  logic               clk,
    input  logic               rst_n,

    input  logic               in_valid,
    output logic               in_ready,

    output logic               out_valid,
    input  logic               out_ready,
    output logic signed [31:0] osc1_sample_q3_29,
    output logic signed [31:0] osc2_sample_q3_29,

    input  logic        [31:0] base_phase_inc,
    input  logic        [1:0]  osc1_mode,
    input  logic        [2:0]  osc1_range,
    input  logic        [31:0] osc1_pulse_width,
    input  logic        [5:0]  osc1_n_harmonics,
    input  logic               amp_we,
    input  logic        [4:0]  amp_addr,
    input  logic signed [31:0] amp_wdata,
    input  logic        [1:0]  osc2_waveform,
    input  logic        [2:0]  osc2_range,
    input  logic        [31:0] osc2_pulse_width,
    input  logic        [31:0] osc2_detune_q2_30
);

    localparam logic [1:0] OSC1_ADDITIVE = 2'd0;
    localparam logic [1:0] OSC1_SAW_UP   = 2'd1;
    localparam logic [1:0] OSC1_SAW_DOWN = 2'd2;
    localparam logic [1:0] OSC1_PULSE    = 2'd3;

    localparam logic [1:0] VA_SAW_UP   = 2'd0;
    localparam logic [1:0] VA_SAW_DOWN = 2'd1;
    localparam logic [1:0] VA_PULSE    = 2'd2;

    localparam logic [2:0] RANGE_32 = 3'd0;
    localparam logic [2:0] RANGE_16 = 3'd1;
    localparam logic [2:0] RANGE_8  = 3'd2;
    localparam logic [2:0] RANGE_4  = 3'd3;
    localparam logic [2:0] RANGE_2  = 3'd4;

    localparam logic [35:0] NYQUIST_INC_36 = 36'h0_8000_0000;

    //estados
    typedef enum logic [2:0] {
        ST_IDLE,
        ST_CALC,        //incremento de osc1 y arranque del producto del detune
        ST_MUL_DETUNE,  //espera el producto
        ST_CHECK_OSC2,  //incremento de osc2
        ST_START,       //lanza los motores activos
        ST_WAIT,        //espera los resultados
        ST_HOLD
    } state_t;

    state_t state;

    //copias de los parametros
    logic        [31:0] base_phase_inc_reg;
    logic        [1:0]  osc1_mode_reg;
    logic        [2:0]  osc1_range_reg;
    logic        [31:0] osc1_pulse_width_reg;
    logic        [5:0]  osc1_n_harmonics_reg;
    logic        [1:0]  osc2_waveform_reg;
    logic        [2:0]  osc2_range_reg;
    logic        [31:0] osc2_pulse_width_reg;
    logic        [31:0] osc2_detune_reg;

    //incrementos efectivos
    logic        [31:0] osc1_phase_inc_reg;
    logic        [31:0] osc2_phase_inc_reg;
    logic               osc1_active_reg;
    logic               osc2_active_reg;
    logic               osc1_done_reg;
    logic               osc2_done_reg;

    //multiplicador compartido
    logic signed [31:0] mul_a_reg;
    logic signed [31:0] mul_b_reg;
    logic               mul_start;
    logic               mul_valid;
    logic signed [63:0] mul_p;
    logic        [63:0] detune_prod_reg;  //base * R2 (sin el corrimiento a izquierda) * detune

    //resultados combinacionales
    logic        [33:0] osc1_range_inc;
    logic               osc1_range_valid;
    logic               osc2_range_valid;
    logic        [31:0] osc2_mul_a;       //base con el corrimiento a derecha del range ya aplicado
    logic        [1:0]  osc2_shift_left;  //corrimiento a izquierda del range (4' y 2')
    logic        [63:0] mul_p_unsigned;
    logic        [65:0] osc2_detune_full;
    logic        [35:0] osc2_detune_inc;
    logic        [1:0]  va1_waveform;

    //acumuladores de fase
    logic        [31:0] phase1;
    logic        [31:0] phase2;
    logic               phase1_tick;
    logic               phase2_tick;

    //motores
    logic               add_in_valid,  add_in_ready,  add_out_valid,  add_out_ready;
    logic               va1_in_valid,  va1_in_ready,  va1_out_valid,  va1_out_ready;
    logic               va2_in_valid,  va2_in_ready,  va2_out_valid,  va2_out_ready;
    logic signed [31:0] add_sample;
    logic signed [31:0] va1_sample;
    logic signed [31:0] va2_sample;
    logic               osc1_engine_ready;
    logic               osc2_engine_ready;

    wire launch_fire;
    wire add_out_fire;
    wire va1_out_fire;
    wire va2_out_fire;

    //range con 34 bits para no perder el desborde de base << 2
    function automatic logic [33:0] apply_range_wide(input logic [31:0] base, input logic [2:0] range_sel);
        case (range_sel)
            RANGE_32: apply_range_wide = {2'b00, base} >> 2;
            RANGE_16: apply_range_wide = {2'b00, base} >> 1;
            RANGE_8:  apply_range_wide = {2'b00, base};
            RANGE_4:  apply_range_wide = {2'b00, base} << 1;
            RANGE_2:  apply_range_wide = {2'b00, base} << 2;
            default:  apply_range_wide = 34'd0;
        endcase
    endfunction

    //instancias
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

    phase_accum u_phase1 (
        .clk       (clk               ),
        .rst_n     (rst_n             ),
        .tick      (phase1_tick       ),
        .phase_inc (osc1_phase_inc_reg),
        .phase     (phase1            )
    );

    phase_accum u_phase2 (
        .clk       (clk               ),
        .rst_n     (rst_n             ),
        .tick      (phase2_tick       ),
        .phase_inc (osc2_phase_inc_reg),
        .phase     (phase2            )
    );

    osc_additive u_additive (
        .clk          (clk                 ),
        .rst_n        (rst_n               ),
        .in_valid     (add_in_valid        ),
        .in_ready     (add_in_ready        ),
        .phase        (phase1              ),
        .phase_inc    (osc1_phase_inc_reg  ),
        .n_harmonics  (osc1_n_harmonics_reg),
        .out_valid    (add_out_valid       ),
        .out_ready    (add_out_ready       ),
        .sample_q3_29 (add_sample          ),
        .amp_we       (amp_we              ),
        .amp_addr     (amp_addr            ),
        .amp_wdata    (amp_wdata           )
    );

    osc_va_polyblep u_va1 (
        .clk          (clk                 ),
        .rst_n        (rst_n               ),
        .in_valid     (va1_in_valid        ),
        .in_ready     (va1_in_ready        ),
        .phase        (phase1              ),
        .phase_inc    (osc1_phase_inc_reg  ),
        .waveform     (va1_waveform        ),
        .pulse_width  (osc1_pulse_width_reg),
        .out_valid    (va1_out_valid       ),
        .out_ready    (va1_out_ready       ),
        .sample_q3_29 (va1_sample          )
    );

    osc_va_polyblep u_va2 (
        .clk          (clk                 ),
        .rst_n        (rst_n               ),
        .in_valid     (va2_in_valid        ),
        .in_ready     (va2_in_ready        ),
        .phase        (phase2              ),
        .phase_inc    (osc2_phase_inc_reg  ),
        .waveform     (osc2_waveform_reg   ),
        .pulse_width  (osc2_pulse_width_reg),
        .out_valid    (va2_out_valid       ),
        .out_ready    (va2_out_ready       ),
        .sample_q3_29 (va2_sample          )
    );

    //assigns
    assign in_ready  = (state == ST_IDLE);
    assign out_valid = (state == ST_HOLD);

    //los motores activos arrancan juntos, y en ese flanco avanzan los acumuladores:
    //el motor recibe phi[n] y el acumulador queda en phi[n+1]
    assign launch_fire  = (state == ST_START) && osc1_engine_ready && osc2_engine_ready;
    assign add_in_valid = launch_fire && osc1_active_reg && (osc1_mode_reg == OSC1_ADDITIVE);
    assign va1_in_valid = launch_fire && osc1_active_reg && (osc1_mode_reg != OSC1_ADDITIVE);
    assign va2_in_valid = launch_fire && osc2_active_reg;
    assign phase1_tick  = launch_fire && osc1_active_reg;
    assign phase2_tick  = launch_fire && osc2_active_reg;

    assign add_out_ready = (state == ST_WAIT) && osc1_active_reg && !osc1_done_reg && (osc1_mode_reg == OSC1_ADDITIVE);
    assign va1_out_ready = (state == ST_WAIT) && osc1_active_reg && !osc1_done_reg && (osc1_mode_reg != OSC1_ADDITIVE);
    assign va2_out_ready = (state == ST_WAIT) && osc2_active_reg && !osc2_done_reg;

    assign add_out_fire = add_out_valid && add_out_ready;
    assign va1_out_fire = va1_out_valid && va1_out_ready;
    assign va2_out_fire = va2_out_valid && va2_out_ready;

    //logica combinacional
    always_comb begin
        osc1_range_inc   = apply_range_wide(base_phase_inc_reg, osc1_range_reg);
        osc1_range_valid = (osc1_range_reg <= RANGE_2);
        osc2_range_valid = (osc2_range_reg <= RANGE_2);

        //(base * R2) * detune = ((base >> k) * detune) << m: el corrimiento a derecha entra
        //antes del producto (trunca igual que antes) y el de izquierda se aplica despues
        case (osc2_range_reg)
            RANGE_32: begin osc2_mul_a = base_phase_inc_reg >> 2; osc2_shift_left = 2'd0; end
            RANGE_16: begin osc2_mul_a = base_phase_inc_reg >> 1; osc2_shift_left = 2'd0; end
            RANGE_8:  begin osc2_mul_a = base_phase_inc_reg;      osc2_shift_left = 2'd0; end
            RANGE_4:  begin osc2_mul_a = base_phase_inc_reg;      osc2_shift_left = 2'd1; end
            RANGE_2:  begin osc2_mul_a = base_phase_inc_reg;      osc2_shift_left = 2'd2; end
            default:  begin osc2_mul_a = 32'd0;                   osc2_shift_left = 2'd0; end
        endcase

        //mul32_seq multiplica con signo: para operandos sin signo se corrige la mitad alta
        //A*B = As*Bs + 2^32 * (a31*B + b31*A)   (modulo 2^64)
        mul_p_unsigned = $unsigned(mul_p)
                       + ({32'd0, (mul_a_reg[31] ? $unsigned(mul_b_reg) : 32'd0)} << 32)
                       + ({32'd0, (mul_b_reg[31] ? $unsigned(mul_a_reg) : 32'd0)} << 32);

        //producto en 66 bits con 62 fraccionales; >>30 da el incremento con 32 fraccionales
        osc2_detune_full = {2'b00, detune_prod_reg} << osc2_shift_left;
        osc2_detune_inc  = osc2_detune_full[65:30];

        case (osc1_mode_reg)
            OSC1_SAW_UP:   va1_waveform = VA_SAW_UP;
            OSC1_SAW_DOWN: va1_waveform = VA_SAW_DOWN;
            OSC1_PULSE:    va1_waveform = VA_PULSE;
            default:       va1_waveform = VA_SAW_UP;
        endcase

        if (!osc1_active_reg)                     osc1_engine_ready = 1'b1;
        else if (osc1_mode_reg == OSC1_ADDITIVE)  osc1_engine_ready = add_in_ready;
        else                                      osc1_engine_ready = va1_in_ready;

        osc2_engine_ready = !osc2_active_reg || va2_in_ready;
    end

    //logica secuencial y FSM
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state                <= ST_IDLE;
            base_phase_inc_reg   <= '0;
            osc1_mode_reg        <= OSC1_ADDITIVE;
            osc1_range_reg       <= RANGE_8;
            osc1_pulse_width_reg <= 32'h8000_0000;
            osc1_n_harmonics_reg <= 6'd1;
            osc2_waveform_reg    <= VA_SAW_UP;
            osc2_range_reg       <= RANGE_8;
            osc2_pulse_width_reg <= 32'h8000_0000;
            osc2_detune_reg      <= 32'h4000_0000;
            osc1_phase_inc_reg   <= '0;
            osc2_phase_inc_reg   <= '0;
            osc1_active_reg      <= 1'b0;
            osc2_active_reg      <= 1'b0;
            osc1_done_reg        <= 1'b0;
            osc2_done_reg        <= 1'b0;
            mul_a_reg            <= '0;
            mul_b_reg            <= '0;
            mul_start            <= 1'b0;
            detune_prod_reg      <= '0;
            osc1_sample_q3_29    <= '0;
            osc2_sample_q3_29    <= '0;
        end
        else begin
            mul_start <= 1'b0; //pulso de un ciclo

            case (state)
                ST_IDLE: begin //captura todos los controles de la muestra
                    if (in_valid && in_ready) begin
                        base_phase_inc_reg   <= base_phase_inc;
                        osc1_mode_reg        <= osc1_mode;
                        osc1_range_reg       <= osc1_range;
                        osc1_pulse_width_reg <= osc1_pulse_width;
                        osc1_n_harmonics_reg <= osc1_n_harmonics;
                        osc2_waveform_reg    <= osc2_waveform;
                        osc2_range_reg       <= osc2_range;
                        osc2_pulse_width_reg <= osc2_pulse_width;
                        osc2_detune_reg      <= osc2_detune_q2_30;
                        state                <= ST_CALC;
                    end
                end

                ST_CALC: begin
                    //osc1: base * R1, valido si queda entre 0 y Nyquist
                    if (osc1_range_valid && (osc1_range_inc != 34'd0) && (osc1_range_inc < 34'h0_8000_0000)) begin
                        osc1_phase_inc_reg <= osc1_range_inc[31:0];
                        osc1_active_reg    <= 1'b1;
                        osc1_done_reg      <= 1'b0;
                    end
                    else begin
                        osc1_phase_inc_reg <= 32'd0;
                        osc1_active_reg    <= 1'b0;
                        osc1_done_reg      <= 1'b1;
                        osc1_sample_q3_29  <= 32'sd0;
                    end

                    //osc2: (base >> k) * detune
                    mul_a_reg <= $signed(osc2_mul_a);
                    mul_b_reg <= $signed(osc2_detune_reg);
                    mul_start <= 1'b1;
                    state     <= ST_MUL_DETUNE;
                end

                ST_MUL_DETUNE: begin
                    if (mul_valid) begin
                        detune_prod_reg <= mul_p_unsigned;
                        state           <= ST_CHECK_OSC2;
                    end
                end

                ST_CHECK_OSC2: begin //osc2 valido si el incremento queda entre 0 y Nyquist
                    if (osc2_range_valid && (osc2_waveform_reg <= VA_PULSE) &&
                        (osc2_detune_inc != 36'd0) && (osc2_detune_inc < NYQUIST_INC_36)) begin
                        osc2_phase_inc_reg <= osc2_detune_inc[31:0];
                        osc2_active_reg    <= 1'b1;
                        osc2_done_reg      <= 1'b0;
                    end
                    else begin
                        osc2_phase_inc_reg <= 32'd0;
                        osc2_active_reg    <= 1'b0;
                        osc2_done_reg      <= 1'b1;
                        osc2_sample_q3_29  <= 32'sd0;
                    end
                    state <= ST_START;
                end

                ST_START: begin
                    if (!osc1_active_reg && !osc2_active_reg) state <= ST_HOLD;
                    else if (launch_fire)                     state <= ST_WAIT;
                end

                ST_WAIT: begin //cada oscilador guarda su resultado; se sale cuando estan los dos
                    if (add_out_fire) begin
                        osc1_sample_q3_29 <= add_sample;
                        osc1_done_reg     <= 1'b1;
                    end
                    if (va1_out_fire) begin
                        osc1_sample_q3_29 <= va1_sample;
                        osc1_done_reg     <= 1'b1;
                    end
                    if (va2_out_fire) begin
                        osc2_sample_q3_29 <= va2_sample;
                        osc2_done_reg     <= 1'b1;
                    end
                    if ((osc1_done_reg || add_out_fire || va1_out_fire) && (osc2_done_reg || va2_out_fire))
                        state <= ST_HOLD;
                end

                ST_HOLD: begin
                    if (out_valid && out_ready) state <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
