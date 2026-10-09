`timescale 1ns/1ps
//! @title Pasaaltos de entrada y salida del overdrive
//! @brief Uno o dos filtros TPT con un multiplicador compartido de 32x32 bits.
//! Audio Q3.29, memoria del filtro Q5.27 y coeficientes Q1.31.
module fx_od_hpf #(
    parameter integer ETAPAS = 1
)(
    input  logic               clk, rst_n,
    input  logic               in_valid, output logic in_ready, input logic signed [31:0] in_data,
    output logic               out_valid, input logic out_ready, output logic signed [31:0] out_data,
    input  logic signed [31:0]  g_q1_31, g2_q1_31
);
    import fx_dsp_pkg::*;

    // estados
    typedef enum logic [3:0] { ST_ESPERA, ST_CONVERTIR, ST_CARGAR_ENTRADA, ST_MULT_ENTRADA,
                              ST_CARGAR_MEMORIA, ST_MULT_MEMORIA, ST_RESTAR, ST_REDONDEAR,
                              ST_GUARDAR_V, ST_SUMAR, ST_GUARDAR_FILTRO, ST_PASAALTOS, ST_SALIDA } state_t;
    state_t state;

    // registros de las muestras y de cada filtro
    logic signed [31:0] muestra_reg, entrada_reg, memoria_reg, estado_1_reg, estado_2_reg;
    logic signed [31:0] g1_reg, g2_reg, incremento_reg, pasabajos_reg;
    logic etapa_reg;

    // multiplicador compartido y resultados intermedios
    logic signed [31:0] mul_a_reg, mul_b_reg;
    logic signed [63:0] producto_reg, producto_entrada_reg, diferencia_reg, redondeo_reg;
    logic signed [32:0] suma_lp_reg, pasaaltos_reg;
    logic signed [33:0] suma_estado_reg;

    // salida
    logic signed [31:0] salida_reg;
    logic salida_valid;

    function automatic logic signed [31:0] saturar_34(input logic signed [33:0] valor);
        if (!(|(valor[33:32] ^ {2{valor[31]}}))) saturar_34 = valor[31:0];
        else saturar_34 = valor[33] ? 32'sh8000_0000 : 32'sh7FFF_FFFF;
    endfunction

    assign in_ready = rst_n && (state == ST_ESPERA) && !salida_valid;
    assign out_valid = salida_valid;
    assign out_data = salida_reg;

    // logica secuencial y FSM
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= ST_ESPERA; etapa_reg <= 0;
            muestra_reg <= 0; entrada_reg <= 0; memoria_reg <= 0; estado_1_reg <= 0; estado_2_reg <= 0;
            g1_reg <= 0; g2_reg <= 0; incremento_reg <= 0; pasabajos_reg <= 0;
            mul_a_reg <= 0; mul_b_reg <= 0; producto_reg <= 0; producto_entrada_reg <= 0;
            diferencia_reg <= 0; redondeo_reg <= 0; suma_lp_reg <= 0; pasaaltos_reg <= 0; suma_estado_reg <= 0;
            salida_reg <= 0; salida_valid <= 0;
        end else begin
            if (out_valid && out_ready) salida_valid <= 0;
            if ((state == ST_MULT_ENTRADA) || (state == ST_MULT_MEMORIA))
                producto_reg <= $signed(mul_a_reg) * $signed(mul_b_reg);

            case (state)
                ST_ESPERA: if (in_valid && in_ready) begin
                    muestra_reg <= in_data; etapa_reg <= 0;
                    g1_reg <= g_q1_31[31] ? 32'sd0 : g_q1_31;
                    g2_reg <= g2_q1_31[31] ? 32'sd0 : g2_q1_31;
                    state <= ST_CONVERTIR;
                end
                ST_CONVERTIR: begin
                    entrada_reg <= ($signed({muestra_reg[31], muestra_reg}) + (muestra_reg[31] ? 33'sd1 : 33'sd2)) >>> 2;
                    memoria_reg <= etapa_reg ? estado_2_reg : estado_1_reg;
                    state <= ST_CARGAR_ENTRADA;
                end
                ST_CARGAR_ENTRADA: begin
                    mul_a_reg <= entrada_reg; mul_b_reg <= etapa_reg ? g2_reg : g1_reg; state <= ST_MULT_ENTRADA;
                end
                ST_MULT_ENTRADA: state <= ST_CARGAR_MEMORIA;
                ST_CARGAR_MEMORIA: begin
                    producto_entrada_reg <= producto_reg; mul_a_reg <= memoria_reg; state <= ST_MULT_MEMORIA;
                end
                ST_MULT_MEMORIA: state <= ST_RESTAR;
                ST_RESTAR: begin diferencia_reg <= producto_entrada_reg - producto_reg; state <= ST_REDONDEAR; end
                ST_REDONDEAR: begin
                    redondeo_reg <= diferencia_reg + (diferencia_reg[63] ? 64'sd1073741823 : 64'sd1073741824);
                    state <= ST_GUARDAR_V;
                end
                ST_GUARDAR_V: begin incremento_reg <= sat32(redondeo_reg >>> 31); state <= ST_SUMAR; end
                ST_SUMAR: begin
                    suma_lp_reg <= $signed({memoria_reg[31], memoria_reg}) + $signed({incremento_reg[31], incremento_reg});
                    suma_estado_reg <= $signed({{2{memoria_reg[31]}}, memoria_reg}) + ($signed({{2{incremento_reg[31]}}, incremento_reg}) <<< 1);
                    state <= ST_GUARDAR_FILTRO;
                end
                ST_GUARDAR_FILTRO: begin
                    pasabajos_reg <= saturar_34($signed({suma_lp_reg[32], suma_lp_reg}));
                    if (etapa_reg) estado_2_reg <= saturar_34(suma_estado_reg);
                    else estado_1_reg <= saturar_34(suma_estado_reg);
                    state <= ST_PASAALTOS;
                end
                ST_PASAALTOS: begin
                    pasaaltos_reg <= $signed({entrada_reg[31], entrada_reg}) - $signed({pasabajos_reg[31], pasabajos_reg});
                    state <= ST_SALIDA;
                end
                ST_SALIDA: begin
                    // Se conserva el redondeo entre los dos filtros originales.
                    if ((ETAPAS == 2) && !etapa_reg) begin
                        muestra_reg <= sat32($signed({{31{pasaaltos_reg[32]}}, pasaaltos_reg}) <<< 2);
                        etapa_reg <= 1; state <= ST_CONVERTIR;
                    end else begin
                        salida_reg <= sat32($signed({{31{pasaaltos_reg[32]}}, pasaaltos_reg}) <<< 2);
                        salida_valid <= 1; state <= ST_ESPERA;
                    end
                end
                default: state <= ST_ESPERA;
            endcase
        end
    end
endmodule
