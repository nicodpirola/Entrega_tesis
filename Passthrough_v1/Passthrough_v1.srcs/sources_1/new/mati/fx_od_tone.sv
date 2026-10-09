`timescale 1ns/1ps
//! @title Tono y acoplamiento de salida del overdrive
//! @brief Biquad DF-I y pasaaltos TPT con un multiplicador compartido de 32x32 bits.
//! Audio Q3.29, tono Q2.30, coeficiente del pasaaltos Q1.31 y memoria Q5.27.
module fx_od_tone #(
    parameter integer HP_SALIDA = 0
)(
    input logic clk, rst_n,
    input logic in_valid, output logic in_ready, input logic signed [31:0] in_data,
    output logic out_valid, input logic out_ready, output logic signed [31:0] out_data,
    input logic signed [31:0] b0_q2_30, b1_q2_30, b2_q2_30, a1_q2_30, a2_q2_30,
    input logic signed [31:0] g_salida_q1_31
);
    import fx_dsp_pkg::*;

    // estados
    typedef enum logic [4:0] { ST_ESPERA, ST_CARGAR_TONO, ST_MULT_TONO, ST_ACUMULAR_TONO,
                              ST_REDONDEAR_TONO, ST_GUARDAR_TONO, ST_CONVERTIR_HP, ST_CARGAR_ENTRADA,
                              ST_MULT_ENTRADA, ST_CARGAR_MEMORIA, ST_MULT_MEMORIA, ST_RESTAR_HP,
                              ST_REDONDEAR_HP, ST_GUARDAR_V, ST_SUMAR_HP, ST_GUARDAR_HP, ST_PASAALTOS, ST_SALIDA } state_t;
    state_t state;

    // muestras, coeficientes y memorias del tono
    logic [2:0] termino_reg;
    logic signed [31:0] muestra_reg, entrada_1_reg, entrada_2_reg, salida_1_reg, salida_2_reg;
    logic signed [31:0] b0_reg, b1_reg, b2_reg, a1_reg, a2_reg;
    logic signed [66:0] acumulado_reg, redondeo_tono_reg;
    logic signed [31:0] resultado_tono;

    // muestra y memoria del pasaaltos
    logic signed [31:0] muestra_hp_reg, entrada_hp_reg, memoria_hp_reg, g_hp_reg, incremento_reg, pasabajos_reg;
    logic signed [63:0] producto_entrada_reg, diferencia_reg, redondeo_hp_reg;
    logic signed [32:0] suma_lp_reg, pasaaltos_reg;
    logic signed [33:0] suma_estado_reg;

    // multiplicador compartido y salida
    logic signed [31:0] mul_a_reg, mul_b_reg, salida_reg;
    logic signed [63:0] producto_reg;
    logic salida_valid;

    function automatic logic signed [31:0] saturar_tono(input logic signed [66:0] valor);
        logic signed [66:0] desplazado;
        begin
            desplazado = valor >>> 30;
            if (!(|(desplazado[66:32] ^ {35{desplazado[31]}}))) saturar_tono = desplazado[31:0];
            else saturar_tono = desplazado[66] ? 32'sh8000_0000 : 32'sh7FFF_FFFF;
        end
    endfunction

    function automatic logic signed [31:0] saturar_34(input logic signed [33:0] valor);
        if (!(|(valor[33:32] ^ {2{valor[31]}}))) saturar_34 = valor[31:0];
        else saturar_34 = valor[33] ? 32'sh8000_0000 : 32'sh7FFF_FFFF;
    endfunction

    assign in_ready = rst_n && (state == ST_ESPERA) && !salida_valid;
    assign out_valid = salida_valid;
    assign out_data = salida_reg;
    assign resultado_tono = saturar_tono(redondeo_tono_reg);

    // logica secuencial y FSM
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= ST_ESPERA; termino_reg <= 0;
            muestra_reg <= 0; entrada_1_reg <= 0; entrada_2_reg <= 0; salida_1_reg <= 0; salida_2_reg <= 0;
            b0_reg <= 0; b1_reg <= 0; b2_reg <= 0; a1_reg <= 0; a2_reg <= 0;
            acumulado_reg <= 0; redondeo_tono_reg <= 0;
            muestra_hp_reg <= 0; entrada_hp_reg <= 0; memoria_hp_reg <= 0; g_hp_reg <= 0;
            incremento_reg <= 0; pasabajos_reg <= 0; producto_entrada_reg <= 0; diferencia_reg <= 0; redondeo_hp_reg <= 0;
            suma_lp_reg <= 0; pasaaltos_reg <= 0; suma_estado_reg <= 0;
            mul_a_reg <= 0; mul_b_reg <= 0; producto_reg <= 0; salida_reg <= 0; salida_valid <= 0;
        end else begin
            if (out_valid && out_ready) salida_valid <= 0;
            if ((state == ST_MULT_TONO) || (state == ST_MULT_ENTRADA) || (state == ST_MULT_MEMORIA))
                producto_reg <= $signed(mul_a_reg) * $signed(mul_b_reg);

            case (state)
                ST_ESPERA: if (in_valid && in_ready) begin
                    muestra_reg <= in_data; termino_reg <= 0; acumulado_reg <= 0;
                    b0_reg <= b0_q2_30; b1_reg <= b1_q2_30; b2_reg <= b2_q2_30; a1_reg <= a1_q2_30; a2_reg <= a2_q2_30;
                    g_hp_reg <= g_salida_q1_31[31] ? 32'sd0 : g_salida_q1_31;
                    state <= ST_CARGAR_TONO;
                end
                ST_CARGAR_TONO: begin
                    case (termino_reg)
                        0: begin mul_a_reg <= muestra_reg; mul_b_reg <= b0_reg; end
                        1: begin mul_a_reg <= entrada_1_reg; mul_b_reg <= b1_reg; end
                        2: begin mul_a_reg <= entrada_2_reg; mul_b_reg <= b2_reg; end
                        3: begin mul_a_reg <= salida_1_reg; mul_b_reg <= a1_reg; end
                        4: begin mul_a_reg <= salida_2_reg; mul_b_reg <= a2_reg; end
                        default: begin mul_a_reg <= 0; mul_b_reg <= 0; end
                    endcase
                    state <= ST_MULT_TONO;
                end
                ST_MULT_TONO: state <= ST_ACUMULAR_TONO;
                ST_ACUMULAR_TONO: begin
                    if (termino_reg < 3) acumulado_reg <= acumulado_reg + $signed({{3{producto_reg[63]}}, producto_reg});
                    else acumulado_reg <= acumulado_reg - $signed({{3{producto_reg[63]}}, producto_reg});
                    if (termino_reg == 4) state <= ST_REDONDEAR_TONO;
                    else begin termino_reg <= termino_reg + 1'b1; state <= ST_CARGAR_TONO; end
                end
                ST_REDONDEAR_TONO: begin
                    redondeo_tono_reg <= acumulado_reg + (acumulado_reg[66] ? 67'sd536870911 : 67'sd536870912);
                    state <= ST_GUARDAR_TONO;
                end
                ST_GUARDAR_TONO: begin
                    // La realimentacion del tono usa su propia salida, antes del pasaaltos.
                    entrada_2_reg <= entrada_1_reg; entrada_1_reg <= muestra_reg;
                    salida_2_reg <= salida_1_reg; salida_1_reg <= resultado_tono;
                    if (HP_SALIDA != 0) begin muestra_hp_reg <= resultado_tono; state <= ST_CONVERTIR_HP; end
                    else begin salida_reg <= resultado_tono; salida_valid <= 1; state <= ST_ESPERA; end
                end
                ST_CONVERTIR_HP: begin
                    entrada_hp_reg <= ($signed({muestra_hp_reg[31], muestra_hp_reg}) + (muestra_hp_reg[31] ? 33'sd1 : 33'sd2)) >>> 2;
                    state <= ST_CARGAR_ENTRADA;
                end
                ST_CARGAR_ENTRADA: begin mul_a_reg <= entrada_hp_reg; mul_b_reg <= g_hp_reg; state <= ST_MULT_ENTRADA; end
                ST_MULT_ENTRADA: state <= ST_CARGAR_MEMORIA;
                ST_CARGAR_MEMORIA: begin producto_entrada_reg <= producto_reg; mul_a_reg <= memoria_hp_reg; state <= ST_MULT_MEMORIA; end
                ST_MULT_MEMORIA: state <= ST_RESTAR_HP;
                ST_RESTAR_HP: begin diferencia_reg <= producto_entrada_reg - producto_reg; state <= ST_REDONDEAR_HP; end
                ST_REDONDEAR_HP: begin
                    redondeo_hp_reg <= diferencia_reg + (diferencia_reg[63] ? 64'sd1073741823 : 64'sd1073741824);
                    state <= ST_GUARDAR_V;
                end
                ST_GUARDAR_V: begin incremento_reg <= sat32(redondeo_hp_reg >>> 31); state <= ST_SUMAR_HP; end
                ST_SUMAR_HP: begin
                    suma_lp_reg <= $signed({memoria_hp_reg[31], memoria_hp_reg}) + $signed({incremento_reg[31], incremento_reg});
                    suma_estado_reg <= $signed({{2{memoria_hp_reg[31]}}, memoria_hp_reg}) + ($signed({{2{incremento_reg[31]}}, incremento_reg}) <<< 1);
                    state <= ST_GUARDAR_HP;
                end
                ST_GUARDAR_HP: begin
                    pasabajos_reg <= saturar_34($signed({suma_lp_reg[32], suma_lp_reg})); memoria_hp_reg <= saturar_34(suma_estado_reg);
                    state <= ST_PASAALTOS;
                end
                ST_PASAALTOS: begin
                    pasaaltos_reg <= $signed({entrada_hp_reg[31], entrada_hp_reg}) - $signed({pasabajos_reg[31], pasabajos_reg});
                    state <= ST_SALIDA;
                end
                ST_SALIDA: begin
                    salida_reg <= sat32($signed({{31{pasaaltos_reg[32]}}, pasaaltos_reg}) <<< 2);
                    salida_valid <= 1; state <= ST_ESPERA;
                end
                default: state <= ST_ESPERA;
            endcase
        end
    end
endmodule
