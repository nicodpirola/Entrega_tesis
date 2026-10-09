`timescale 1ns/1ps
//! @title Seccion de overdrive
//! @brief Parametros agrupados, commit coordinado por fx_core y carga de tabla por AXI.
module fx_dist_section (
    input logic clk, rst_n, enable,
    input logic cfg_apply, output logic cfg_ready,
    input logic in_valid, output logic in_ready, input logic signed [31:0] in_data,
    output logic out_valid, input logic out_ready, output logic signed [31:0] out_data,
    input fx_ctrl_pkg::overdrive_cfg_t od_cfg,
    input logic wt_wr_en, output logic wt_wr_ready, input logic wt_wr_bank,
    input logic [11:0] wt_wr_addr, input logic [31:0] wt_wr_data,
    input logic status_clear, output logic [31:0] status
);
    import fx_ctrl_pkg::*;
    logic active_bank, write_rejected;
    logic [1:0] table_loaded;
    logic [11:0] load_count [0:1];

    fx_overdrive #(.OS_FACTOR(FX_OD_OS_FACTOR)) u_overdrive (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_ready(in_ready), .in_data(in_data),
        .out_valid(out_valid), .out_ready(out_ready), .out_data(out_data),
        .cfg_valid(cfg_apply), .cfg_ready(cfg_ready),
        .cfg_enable(enable && table_loaded[od_cfg.ctrl[0]]), .cfg_clear(od_cfg.ctrl[1]),
        .cfg_bank(table_loaded[od_cfg.ctrl[0]] ? od_cfg.ctrl[0] : active_bank),
        .cfg_input1_g(od_cfg.input1_g), .cfg_input2_g(od_cfg.input2_g),
        .cfg_branch_hp_g(od_cfg.branch_hp_g), .cfg_branch_lp_g(od_cfg.branch_lp_g), .cfg_branch_gain(od_cfg.branch_gain),
        .cfg_tone_b0(od_cfg.tone_b0), .cfg_tone_b1(od_cfg.tone_b1), .cfg_tone_b2(od_cfg.tone_b2),
        .cfg_tone_a1(od_cfg.tone_a1), .cfg_tone_a2(od_cfg.tone_a2), .cfg_output_g(od_cfg.output_g), .cfg_level_q3_29(od_cfg.level_q3_29),
        .wt_wr_en(wt_wr_en), .wt_wr_ready(wt_wr_ready), .wt_wr_bank(wt_wr_bank), .wt_wr_addr(wt_wr_addr), .wt_wr_data(wt_wr_data),
        .status_clear(status_clear), .write_rejected(write_rejected), .active_bank(active_bank)
    );

    // Solo una carga completa, consecutiva y aceptada habilita el banco.
    // Evita seleccionar RAM sin inicializar, incluso usando el firmware anterior.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            table_loaded <= 0; load_count[0] <= 0; load_count[1] <= 0;
        end else if (wt_wr_en && wt_wr_ready) begin
            if (wt_wr_addr == 0) begin
                load_count[wt_wr_bank] <= 12'd1;
                table_loaded[wt_wr_bank] <= 0;
            end else if ((load_count[wt_wr_bank] != 0) && (wt_wr_addr == load_count[wt_wr_bank])) begin
                load_count[wt_wr_bank] <= load_count[wt_wr_bank]+1'b1;
                if (wt_wr_addr == 12'd2560) table_loaded[wt_wr_bank] <= 1;
            end else begin
                load_count[wt_wr_bank] <= 0;
                table_loaded[wt_wr_bank] <= 0;
            end
        end
    end
    assign status = {26'd0, cfg_ready, table_loaded[1], table_loaded[0], write_rejected, active_bank, wt_wr_ready};
endmodule
