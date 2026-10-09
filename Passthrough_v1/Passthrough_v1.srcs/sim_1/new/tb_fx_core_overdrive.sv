`timescale 1ns/1ps
module tb_fx_core_overdrive;
    import fx_ctrl_pkg::*;
    parameter string DATA_DIR = "X:/Tesis/Dist_AB/TS9_Yeh/integration/vectors";
    parameter string TABLE_DIR = "X:/Tesis/Dist_AB/TS9_Yeh/rtl_od/top_vectors";
    localparam integer COUNT = 384;
    logic clk = 0; always #10 clk = ~clk;
    logic rst_n = 0, fx_on = 1;
    logic [31:0] awaddr = 0, wdata = 0, araddr = 0, rdata;
    logic awvalid = 0, awready, wvalid = 0, wready, bvalid, arvalid = 0, arready, rvalid;
    logic [3:0] wstrb = 15;
    logic [1:0] bresp, rresp;
    logic [31:0] rx_data = 0, tx_data;
    logic [2:0] rx_tid = 0, tx_tid;
    logic rx_valid = 0, rx_ready, tx_valid;
    logic monitor = 0;
    logic [31:0] rx [0:COUNT-1], wet [0:COUNT-1], tx [0:COUNT-1], cfg [0:11], table_data [0:2560];
    integer wet_count = 0, tx_count = 0, checked = 0;
    logic [31:0] got;
    string directory, table_directory;

    fx_core dut (
        .clk(clk), .rst_n(rst_n), .fx_enable(fx_on),
        .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(1'b1),
        .s_axi_araddr(araddr), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(1'b1),
        .s_axis_tdata(rx_data), .s_axis_tid(rx_tid), .s_axis_tvalid(rx_valid), .s_axis_tready(rx_ready),
        .m_axis_tdata(tx_data), .m_axis_tid(tx_tid), .m_axis_tvalid(tx_valid), .m_axis_tready(1'b1),
        .enc_a(6'b111111), .enc_b(6'b111111)
    );

    always @(posedge clk) if (rst_n && monitor) begin
        if (dut.dist_valid && dut.dist_ready) begin
            if (wet_count >= COUNT || dut.dist_data !== wet[wet_count]) $fatal(1, "Wet muestra %0d: %h esperado %h", wet_count, dut.dist_data, wet[wet_count]);
            wet_count = wet_count+1; checked = checked+1;
        end
        if (tx_valid) begin
            if (tx_count >= 2*COUNT || tx_data !== (tx[tx_count/2] | ((tx_count%2) ? 32'd2 : 32'd0)) || tx_tid !== (tx_count%2)) $fatal(1, "TX palabra %0d: %h esperado %h tid=%0d", tx_count, tx_data, tx[tx_count/2], tx_tid);
            tx_count = tx_count+1;
        end
    end

    task automatic write_reg(input logic [31:0] address, value, input logic [3:0] strb);
        @(negedge clk); awaddr = address; awvalid = 1;
        do @(posedge clk); while (!awready);
        @(negedge clk); awvalid = 0; wdata = value; wstrb = strb; wvalid = 1;
        do @(posedge clk); while (!wready);
        @(negedge clk); wvalid = 0;
        while (!bvalid) @(negedge clk);
        if (bresp != 0) $fatal(1, "AXI write error");
        @(negedge clk);
    endtask
    task automatic read_reg(input logic [31:0] address, output logic [31:0] value);
        @(negedge clk); araddr = address; arvalid = 1;
        do @(posedge clk); while (!arready);
        @(negedge clk); arvalid = 0;
        while (!rvalid) @(negedge clk);
        if (rresp != 0) $fatal(1, "AXI read error");
        value = rdata;
        @(negedge clk);
    endtask
    task automatic commit;
        write_reg(REG_CORE_COMMAND, 1, 15);
        repeat (30000) begin
            @(negedge clk);
            if (!dut.core_cfg_busy) return;
        end
        $fatal(1, "Commit global no termina");
    endtask
    task automatic load_table(input bit bank);
        write_reg(REG_DIST_WT_ADDR, bank ? 32'h1000 : 0, 15);
        for (integer i = 0; i < 2561; i = i+1) write_reg(REG_DIST_WT_DATA, table_data[i], 15);
    endtask
    task automatic write_config;
        for (integer i = 0; i < 12; i = i+1) write_reg(REG_OD_INPUT1_G+4*i, cfg[i], 15);
    endtask
    task automatic send_frames;
        for (integer i = 0; i < COUNT; i = i+1) begin
            for (integer channel = 0; channel < 2; channel = channel+1) begin
                @(negedge clk); rx_data = rx[i]; rx_tid = channel; rx_valid = 1;
                do @(posedge clk); while (!rx_ready);
                @(negedge clk); rx_valid = 0;
            end
            if (i != COUNT-1) repeat (1036) @(negedge clk);
        end
    endtask
    task automatic finish_audio;
        repeat (30000) begin
            @(negedge clk);
            if ((tx_count == 2*COUNT) && !dut.core_cfg_busy && dut.adapter_idle) begin
                if (wet_count != COUNT) $fatal(1, "Cantidad wet %0d", wet_count);
                monitor = 0;
                return;
            end
        end
        $fatal(1, "Audio no termina wet=%0d tx=%0d", wet_count, tx_count);
    endtask

    initial begin
        if (!$value$plusargs("DATA_DIR=%s", directory)) directory = DATA_DIR;
        if (!$value$plusargs("TABLE_DIR=%s", table_directory)) table_directory = TABLE_DIR;
        $readmemh({directory, "/rx.hex"}, rx);
        repeat (5) @(negedge clk); rst_n = 1;
        repeat (20) @(negedge clk);
        read_reg(REG_CORE_VERSION, got); if (got != 32'h00010200) $fatal(1, "Version");
        read_reg(REG_OD_INFO, got); if (got != 32'h0A010008) $fatal(1, "Info");

        $display("=== READBACK Y WSTRB ===");
        read_reg(REG_OD_LEVEL_Q3_29, got); if (got != 32'h20000000) $fatal(1, "Level inicial");
        write_reg(REG_OD_LEVEL_Q3_29, 32'h12345678, 4'b0001);
        read_reg(REG_OD_LEVEL_Q3_29, got); if (got != 32'h20000078) $fatal(1, "WSTRB");
        write_reg(REG_OD_LEVEL_Q3_29, 32'h20000000, 15);

        $display("=== BANCO SIN CARGAR: BYPASS ===");
        write_reg(REG_FX_ENABLE, 4, 15); write_reg(REG_OD_CTRL, 1, 15); commit();
        if (dut.u_dist_section.u_overdrive.enable_reg) $fatal(1, "Activa RAM sin cargar");
        $readmemh({table_directory, "/table_50.mem"}, table_data);
        load_table(1);
        read_reg(REG_OD_STATUS, got); if (!(got & 32'h10)) $fatal(1, "No confirma tabla completa");
        $readmemh({directory, "/cfg_50.hex"}, cfg); write_config(); commit();
        if (!dut.u_dist_section.u_overdrive.enable_reg) $fatal(1, "No activa overdrive");

        $display("=== ESCRITURA A BANCO ACTIVO ===");
        write_reg(REG_DIST_WT_ADDR, 32'h1000, 15); write_reg(REG_DIST_WT_DATA, 0, 15);
        read_reg(REG_OD_STATUS, got); if (!(got & 4)) $fatal(1, "No informa rechazo");
        write_reg(REG_OD_COMMAND, 1, 15);
        read_reg(REG_OD_STATUS, got); if (got & 4) $fatal(1, "No limpia rechazo");
        $readmemh({table_directory, "/table_100.mem"}, table_data); load_table(0);

        $display("=== AUDIO I2S Y COMMIT GLOBAL ===");
        $readmemh({directory, "/wet_50.hex"}, wet); $readmemh({directory, "/tx_50.hex"}, tx);
        wet_count = 0; tx_count = 0; monitor = 1; send_frames();
        // Ultima muestra en vuelo: los shadow no modifican el filtro activo.
        $readmemh({directory, "/cfg_100.hex"}, cfg); write_config();
        if (dut.u_dist_section.u_overdrive.bank_reg != 1) $fatal(1, "Banco cambia sin commit");
        write_reg(REG_OD_CTRL, 0, 15); commit(); finish_audio();
        if (dut.u_dist_section.u_overdrive.bank_reg != 0) $fatal(1, "No aplica banco nuevo");

        $display("=== DRIVE NUEVO, ESTADOS CONSERVADOS ===");
        $readmemh({directory, "/wet_100.hex"}, wet); $readmemh({directory, "/tx_100.hex"}, tx);
        wet_count = 0; tx_count = 0; monitor = 1; send_frames(); finish_audio();
        $display("=== SHADOW SIN COMMIT Y ENABLE FISICO ===");
        write_reg(REG_OD_BRANCH_GAIN, 0, 15);
        @(negedge clk); fx_on = 0;
        repeat (5) @(negedge clk);
        while (dut.core_cfg_busy) @(negedge clk);
        if (dut.core_cfg_busy || dut.u_dist_section.u_overdrive.enable_reg) $fatal(1, "No aplica bypass fisico");
        if (dut.u_dist_section.u_overdrive.branch_gain_reg !== cfg[4]) $fatal(1, "Enable aplica shadow sin commit");
        fx_on = 1;
        repeat (5) @(negedge clk);
        while (dut.core_cfg_busy) @(negedge clk);
        if (dut.core_cfg_busy || !dut.u_dist_section.u_overdrive.enable_reg) $fatal(1, "No vuelve del bypass fisico");
        if (dut.u_dist_section.u_overdrive.branch_gain_reg !== cfg[4]) $fatal(1, "Rehabilitar aplica shadow sin commit");
        $display("Muestras completas de overdrive: %0d; I2S verificado en ambos canales", checked);
        $display("TB FX CORE OVERDRIVE: OK");
        $finish;
    end
    initial begin #50000000; $fatal(1, "TIMEOUT GLOBAL"); end
endmodule
