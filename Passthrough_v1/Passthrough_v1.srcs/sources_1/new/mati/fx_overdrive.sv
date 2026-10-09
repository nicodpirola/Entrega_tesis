`timescale 1ns/1ps
//! @title Overdrive simplificado de Yeh
//! @brief HP entrada -> sobremuestreo -> rama/diodos + directo -> tono -> HP salida -> reduccion -> Level.
//! Audio Q3.29. Parametros aplicados juntos con la cadena vacia. No incluye AXI ni suavizado de Drive.
module fx_overdrive #(
    parameter integer OS_FACTOR = 8,
    parameter string TABLE_FILE = ""
)(
    input logic clk, rst_n,
    input logic in_valid, output logic in_ready, input logic signed [31:0] in_data,
    output logic out_valid, input logic out_ready, output logic signed [31:0] out_data,
    input logic cfg_valid, output logic cfg_ready, input logic cfg_enable, cfg_clear, cfg_bank,
    input logic signed [31:0] cfg_input1_g, cfg_input2_g, cfg_branch_hp_g, cfg_branch_lp_g, cfg_branch_gain,
    input logic signed [31:0] cfg_tone_b0, cfg_tone_b1, cfg_tone_b2, cfg_tone_a1, cfg_tone_a2,
    input logic signed [31:0] cfg_output_g, cfg_level_q3_29,
    input logic wt_wr_en, output logic wt_wr_ready, input logic wt_wr_bank,
    input logic [11:0] wt_wr_addr, input logic [31:0] wt_wr_data,
    input logic status_clear, output logic write_rejected, output logic active_bank
);
    import fx_dsp_pkg::*;
    typedef enum logic [1:0] { CORE_IDLE, CORE_WAIT, CORE_SAVE, CORE_OUT } core_state_t;
    typedef enum logic [2:0] { LEVEL_IDLE, LEVEL_MUL, LEVEL_ROUND, LEVEL_OUT } level_state_t;
    core_state_t core_state;
    level_state_t level_state;

    logic enable_reg, bank_reg, restart_reg;
    logic signed [31:0] input1_g_reg, input2_g_reg, branch_hp_g_reg, branch_lp_g_reg, branch_gain_reg;
    logic signed [31:0] tone_b0_reg, tone_b1_reg, tone_b2_reg, tone_a1_reg, tone_a2_reg, output_g_reg, level_reg;
    logic [15:0] pending_reg;
    logic signed [31:0] direct_reg, sum_reg, level_a_reg, level_b_reg, out_buf;
    logic signed [32:0] sum_wide_reg;
    logic signed [63:0] level_product_reg, level_rounded_reg;
    logic out_buf_valid;

    logic input2_v, input2_r, up_v, up_r, branch_v, branch_r, diode_v, diode_r;
    logic sum_v, sum_r, output_hp_v, output_hp_r, down_v, down_r;
    logic input_ready, branch_ready, diode_ready, up_idle, down_idle;
    logic signed [31:0] input2_d, up_d, branch_d, diode_d, output_hp_d, down_d;
    wire filter_rst_n = rst_n && !restart_reg && enable_reg;
    wire diode_rst_n = rst_n && !restart_reg;
    wire in_fire = in_valid && in_ready;
    wire out_fire = out_valid && out_ready;
    wire high_fire = up_v && up_r;
    wire chain_idle = input_ready && up_idle && branch_ready && diode_ready &&
                      (core_state == CORE_IDLE) && sum_r && down_idle;

    // 1. Acoplamientos de entrada a 48 kHz.
    fx_od_hpf #(.ETAPAS(2)) u_filtros_entrada (
        .clk(clk), .rst_n(filter_rst_n), .g_q1_31(input1_g_reg), .g2_q1_31(input2_g_reg),
        .in_valid(in_fire && enable_reg), .in_ready(input_ready), .in_data(in_data),
        .out_valid(input2_v), .out_ready(input2_r), .out_data(input2_d)
    );

    // 2. Sobremuestreo con los FIR existentes.
    fx_od_upsample #(.OS_FACTOR(OS_FACTOR)) u_upsample (
        .clk(clk), .rst_n(rst_n), .state_clear(restart_reg), .idle(up_idle),
        .in_valid(input2_v), .in_ready(input2_r), .in_data(input2_d),
        .out_valid(up_v), .out_ready(up_r), .out_data(up_d)
    );

    // 3. Rama de ganancia. La misma muestra se conserva en direct_reg.
    fx_od_branch u_branch (
        .clk(clk), .rst_n(filter_rst_n), .hp_g_q1_31(branch_hp_g_reg), .lp_g_q1_31(branch_lp_g_reg), .gain_q9_23(branch_gain_reg),
        .in_valid(up_v && (core_state == CORE_IDLE)), .in_ready(branch_ready), .in_data(up_d),
        .out_valid(branch_v), .out_ready(branch_r), .out_data(branch_d)
    );

    // 4. Diodos. La memoria se conserva aunque el efecto este en bypass.
    fx_od_diode #(.TABLE_FILE(TABLE_FILE)) u_diode (
        .clk(clk), .rst_n(diode_rst_n), .active_bank(bank_reg),
        .in_valid(branch_v), .in_ready(branch_r), .in_data(branch_d),
        .out_valid(diode_v), .out_ready(diode_r), .out_data(diode_d),
        .wt_wr_en(wt_wr_en), .wt_wr_ready(wt_wr_ready), .wt_wr_bank(wt_wr_bank), .wt_wr_addr(wt_wr_addr), .wt_wr_data(wt_wr_data)
    );
    assign diode_ready = branch_r;

    // 5. Suma registrada en este top: Vo = Vi + V/V_FS.
    assign up_r = branch_ready && (core_state == CORE_IDLE);
    assign diode_r = (core_state == CORE_WAIT);
    assign sum_v = (core_state == CORE_OUT);

    // 6 y 7. Tono de Yeh y pasaaltos de salida con un multiplicador compartido.
    fx_od_tone #(.HP_SALIDA(1)) u_tono_salida (
        .clk(clk), .rst_n(filter_rst_n),
        .b0_q2_30(tone_b0_reg), .b1_q2_30(tone_b1_reg), .b2_q2_30(tone_b2_reg), .a1_q2_30(tone_a1_reg), .a2_q2_30(tone_a2_reg),
        .g_salida_q1_31(output_g_reg),
        .in_valid(sum_v), .in_ready(sum_r), .in_data(sum_reg),
        .out_valid(output_hp_v), .out_ready(output_hp_r), .out_data(output_hp_d)
    );

    // 8. Reduccion a 48 kHz. Se esperan tambien las muestras descartadas por los FIR.
    fx_od_downsample #(.OS_FACTOR(OS_FACTOR)) u_downsample (
        .clk(clk), .rst_n(rst_n), .state_clear(restart_reg), .idle(down_idle),
        .in_valid(output_hp_v), .in_ready(output_hp_r), .in_data(output_hp_d),
        .out_valid(down_v), .out_ready(down_r), .out_data(down_d)
    );

    // 9. Level, bypass y aplicacion atomica de parametros.
    assign cfg_ready = rst_n && !restart_reg && (pending_reg == 0) && (level_state == LEVEL_IDLE) &&
                       !out_buf_valid && (!enable_reg || chain_idle);
    assign in_ready = rst_n && !restart_reg && !cfg_valid &&
                      (enable_reg ? input_ready : ((level_state == LEVEL_IDLE) && !out_buf_valid));
    assign down_r = (level_state == LEVEL_IDLE) && !out_buf_valid;
    assign out_valid = out_buf_valid;
    assign out_data = out_buf;
    assign active_bank = bank_reg;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            enable_reg <= 0; bank_reg <= 0; restart_reg <= 0; pending_reg <= 0; write_rejected <= 0;
            input1_g_reg <= 0; input2_g_reg <= 0; branch_hp_g_reg <= 0; branch_lp_g_reg <= 0; branch_gain_reg <= 0;
            tone_b0_reg <= 0; tone_b1_reg <= 0; tone_b2_reg <= 0; tone_a1_reg <= 0; tone_a2_reg <= 0; output_g_reg <= 0; level_reg <= 32'sh2000_0000;
            core_state <= CORE_IDLE; direct_reg <= 0; sum_reg <= 0; sum_wide_reg <= 0;
            level_state <= LEVEL_IDLE; level_a_reg <= 0; level_b_reg <= 0; level_product_reg <= 0; level_rounded_reg <= 0;
            out_buf <= 0; out_buf_valid <= 0;
        end else begin
            restart_reg <= 0;
            if (status_clear) write_rejected <= 0;
            if (wt_wr_en && !wt_wr_ready) write_rejected <= 1;
            case ({in_fire, out_fire})
                2'b10: pending_reg <= pending_reg + 1'b1;
                2'b01: pending_reg <= pending_reg - 1'b1;
                default: pending_reg <= pending_reg;
            endcase
            if (cfg_valid && cfg_ready) begin
                enable_reg <= cfg_enable; bank_reg <= cfg_bank;
                restart_reg <= cfg_clear || (cfg_enable != enable_reg);
                input1_g_reg <= cfg_input1_g; input2_g_reg <= cfg_input2_g;
                branch_hp_g_reg <= cfg_branch_hp_g; branch_lp_g_reg <= cfg_branch_lp_g; branch_gain_reg <= cfg_branch_gain;
                tone_b0_reg <= cfg_tone_b0; tone_b1_reg <= cfg_tone_b1; tone_b2_reg <= cfg_tone_b2;
                tone_a1_reg <= cfg_tone_a1; tone_a2_reg <= cfg_tone_a2; output_g_reg <= cfg_output_g;
                level_reg <= cfg_level_q3_29[31] ? 32'sd0 : cfg_level_q3_29;
            end

            if (restart_reg || !enable_reg) core_state <= CORE_IDLE;
            else case (core_state)
                CORE_IDLE: if (high_fire) begin direct_reg <= up_d; core_state <= CORE_WAIT; end
                CORE_WAIT: if (diode_v && diode_r) begin
                    sum_wide_reg <= $signed({direct_reg[31], direct_reg}) + $signed({diode_d[31], diode_d}); core_state <= CORE_SAVE;
                end
                CORE_SAVE: begin
                    sum_reg <= sat32($signed({{31{sum_wide_reg[32]}}, sum_wide_reg})); core_state <= CORE_OUT;
                end
                CORE_OUT: if (sum_r) core_state <= CORE_IDLE;
                default: core_state <= CORE_IDLE;
            endcase

            if (out_fire) out_buf_valid <= 0;
            case (level_state)
                LEVEL_IDLE: begin
                    if (!enable_reg && in_fire) begin out_buf <= in_data; out_buf_valid <= 1; end
                    else if (enable_reg && down_v && down_r) begin level_a_reg <= down_d; level_b_reg <= level_reg; level_state <= LEVEL_MUL; end
                end
                LEVEL_MUL: begin level_product_reg <= $signed(level_a_reg)*$signed(level_b_reg); level_state <= LEVEL_ROUND; end
                LEVEL_ROUND: begin
                    level_rounded_reg <= level_product_reg + (level_product_reg[63] ? 64'sd268435455 : 64'sd268435456); level_state <= LEVEL_OUT;
                end
                LEVEL_OUT: begin out_buf <= sat32(level_rounded_reg >>> 29); out_buf_valid <= 1; level_state <= LEVEL_IDLE; end
                default: level_state <= LEVEL_IDLE;
            endcase
        end
    end
endmodule
