// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2025.1 (win64) Build 6140274 Thu May 22 00:12:29 MDT 2025
// Date        : Fri Sep 18 20:02:33 2026
// Host        : DESKTOP-FLN9N0C running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode funcsim
//               x:/Tesis/Passthrough_v1/Passthrough_v1.gen/sources_1/bd/design_1/ip/design_1_axis_tlast_gen_trans_0_0/design_1_axis_tlast_gen_trans_0_0_sim_netlist.v
// Design      : design_1_axis_tlast_gen_trans_0_0
// Purpose     : This verilog netlist is a functional simulation representation of the design and should not be modified
//               or synthesized. This netlist cannot be used for SDF annotated simulation.
// Device      : xc7z020clg400-1
// --------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CHECK_LICENSE_TYPE = "design_1_axis_tlast_gen_trans_0_0,axis_tlast_gen_transparent,{}" *) (* DowngradeIPIdentifiedWarnings = "yes" *) (* IP_DEFINITION_SOURCE = "module_ref" *) 
(* X_CORE_INFO = "axis_tlast_gen_transparent,Vivado 2025.1" *) 
(* NotValidForBitStream *)
module design_1_axis_tlast_gen_trans_0_0
   (clk,
    resetn,
    s_axis_tdata,
    s_axis_tvalid,
    s_axis_tready,
    m_axis_tdata,
    m_axis_tvalid,
    m_axis_tlast,
    m_axis_tready);
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *) (* X_INTERFACE_MODE = "slave" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME clk, ASSOCIATED_BUSIF m_axis:s_axis, ASSOCIATED_RESET resetn, FREQ_HZ 50000000, FREQ_TOLERANCE_HZ 0, PHASE 0.0, CLK_DOMAIN design_1_processing_system7_0_0_FCLK_CLK0, INSERT_VIP 0" *) input clk;
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 resetn RST" *) (* X_INTERFACE_MODE = "slave" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME resetn, POLARITY ACTIVE_LOW, INSERT_VIP 0" *) input resetn;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TDATA" *) (* X_INTERFACE_MODE = "slave" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME s_axis, TDATA_NUM_BYTES 4, TDEST_WIDTH 0, TID_WIDTH 0, TUSER_WIDTH 0, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 0, HAS_TLAST 0, FREQ_HZ 50000000, PHASE 0.0, CLK_DOMAIN design_1_processing_system7_0_0_FCLK_CLK0, LAYERED_METADATA undef, INSERT_VIP 0" *) input [31:0]s_axis_tdata;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TVALID" *) input s_axis_tvalid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TREADY" *) output s_axis_tready;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TDATA" *) (* X_INTERFACE_MODE = "master" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME m_axis, TDATA_NUM_BYTES 4, TDEST_WIDTH 0, TID_WIDTH 0, TUSER_WIDTH 0, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 0, HAS_TLAST 1, FREQ_HZ 50000000, PHASE 0.0, CLK_DOMAIN design_1_processing_system7_0_0_FCLK_CLK0, LAYERED_METADATA undef, INSERT_VIP 0" *) output [31:0]m_axis_tdata;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TVALID" *) output m_axis_tvalid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TLAST" *) output m_axis_tlast;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TREADY" *) input m_axis_tready;

  wire clk;
  wire m_axis_tlast;
  wire m_axis_tready;
  wire resetn;
  wire [31:0]s_axis_tdata;
  wire s_axis_tvalid;

  assign m_axis_tdata[31:0] = s_axis_tdata;
  assign m_axis_tvalid = s_axis_tvalid;
  assign s_axis_tready = m_axis_tready;
  design_1_axis_tlast_gen_trans_0_0_axis_tlast_gen_transparent inst
       (.clk(clk),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tready(m_axis_tready),
        .resetn(resetn),
        .s_axis_tvalid(s_axis_tvalid));
endmodule

(* ORIG_REF_NAME = "axis_tlast_gen_transparent" *) 
module design_1_axis_tlast_gen_trans_0_0_axis_tlast_gen_transparent
   (m_axis_tlast,
    resetn,
    clk,
    s_axis_tvalid,
    m_axis_tready);
  output m_axis_tlast;
  input resetn;
  input clk;
  input s_axis_tvalid;
  input m_axis_tready;

  wire clk;
  wire \count_reg[0]_i_1_n_0 ;
  wire \count_reg[0]_i_2_n_0 ;
  wire \count_reg[0]_i_4_n_0 ;
  wire [15:0]count_reg_reg;
  wire \count_reg_reg[0]_i_3_n_0 ;
  wire \count_reg_reg[0]_i_3_n_1 ;
  wire \count_reg_reg[0]_i_3_n_2 ;
  wire \count_reg_reg[0]_i_3_n_3 ;
  wire \count_reg_reg[0]_i_3_n_4 ;
  wire \count_reg_reg[0]_i_3_n_5 ;
  wire \count_reg_reg[0]_i_3_n_6 ;
  wire \count_reg_reg[0]_i_3_n_7 ;
  wire \count_reg_reg[12]_i_1_n_1 ;
  wire \count_reg_reg[12]_i_1_n_2 ;
  wire \count_reg_reg[12]_i_1_n_3 ;
  wire \count_reg_reg[12]_i_1_n_4 ;
  wire \count_reg_reg[12]_i_1_n_5 ;
  wire \count_reg_reg[12]_i_1_n_6 ;
  wire \count_reg_reg[12]_i_1_n_7 ;
  wire \count_reg_reg[4]_i_1_n_0 ;
  wire \count_reg_reg[4]_i_1_n_1 ;
  wire \count_reg_reg[4]_i_1_n_2 ;
  wire \count_reg_reg[4]_i_1_n_3 ;
  wire \count_reg_reg[4]_i_1_n_4 ;
  wire \count_reg_reg[4]_i_1_n_5 ;
  wire \count_reg_reg[4]_i_1_n_6 ;
  wire \count_reg_reg[4]_i_1_n_7 ;
  wire \count_reg_reg[8]_i_1_n_0 ;
  wire \count_reg_reg[8]_i_1_n_1 ;
  wire \count_reg_reg[8]_i_1_n_2 ;
  wire \count_reg_reg[8]_i_1_n_3 ;
  wire \count_reg_reg[8]_i_1_n_4 ;
  wire \count_reg_reg[8]_i_1_n_5 ;
  wire \count_reg_reg[8]_i_1_n_6 ;
  wire \count_reg_reg[8]_i_1_n_7 ;
  wire m_axis_tlast;
  wire m_axis_tlast_INST_0_i_1_n_0;
  wire m_axis_tlast_INST_0_i_2_n_0;
  wire m_axis_tlast_INST_0_i_3_n_0;
  wire m_axis_tlast_INST_0_i_4_n_0;
  wire m_axis_tready;
  wire resetn;
  wire s_axis_tvalid;
  wire [3:3]\NLW_count_reg_reg[12]_i_1_CO_UNCONNECTED ;

  LUT6 #(
    .INIT(64'h40000000FFFFFFFF)) 
    \count_reg[0]_i_1 
       (.I0(m_axis_tlast_INST_0_i_1_n_0),
        .I1(m_axis_tlast_INST_0_i_2_n_0),
        .I2(m_axis_tlast_INST_0_i_3_n_0),
        .I3(m_axis_tlast_INST_0_i_4_n_0),
        .I4(\count_reg[0]_i_2_n_0 ),
        .I5(resetn),
        .O(\count_reg[0]_i_1_n_0 ));
  LUT2 #(
    .INIT(4'h8)) 
    \count_reg[0]_i_2 
       (.I0(s_axis_tvalid),
        .I1(m_axis_tready),
        .O(\count_reg[0]_i_2_n_0 ));
  LUT1 #(
    .INIT(2'h1)) 
    \count_reg[0]_i_4 
       (.I0(count_reg_reg[0]),
        .O(\count_reg[0]_i_4_n_0 ));
  FDRE \count_reg_reg[0] 
       (.C(clk),
        .CE(\count_reg[0]_i_2_n_0 ),
        .D(\count_reg_reg[0]_i_3_n_7 ),
        .Q(count_reg_reg[0]),
        .R(\count_reg[0]_i_1_n_0 ));
  (* ADDER_THRESHOLD = "11" *) 
  CARRY4 \count_reg_reg[0]_i_3 
       (.CI(1'b0),
        .CO({\count_reg_reg[0]_i_3_n_0 ,\count_reg_reg[0]_i_3_n_1 ,\count_reg_reg[0]_i_3_n_2 ,\count_reg_reg[0]_i_3_n_3 }),
        .CYINIT(1'b0),
        .DI({1'b0,1'b0,1'b0,1'b1}),
        .O({\count_reg_reg[0]_i_3_n_4 ,\count_reg_reg[0]_i_3_n_5 ,\count_reg_reg[0]_i_3_n_6 ,\count_reg_reg[0]_i_3_n_7 }),
        .S({count_reg_reg[3:1],\count_reg[0]_i_4_n_0 }));
  FDRE \count_reg_reg[10] 
       (.C(clk),
        .CE(\count_reg[0]_i_2_n_0 ),
        .D(\count_reg_reg[8]_i_1_n_5 ),
        .Q(count_reg_reg[10]),
        .R(\count_reg[0]_i_1_n_0 ));
  FDRE \count_reg_reg[11] 
       (.C(clk),
        .CE(\count_reg[0]_i_2_n_0 ),
        .D(\count_reg_reg[8]_i_1_n_4 ),
        .Q(count_reg_reg[11]),
        .R(\count_reg[0]_i_1_n_0 ));
  FDRE \count_reg_reg[12] 
       (.C(clk),
        .CE(\count_reg[0]_i_2_n_0 ),
        .D(\count_reg_reg[12]_i_1_n_7 ),
        .Q(count_reg_reg[12]),
        .R(\count_reg[0]_i_1_n_0 ));
  (* ADDER_THRESHOLD = "11" *) 
  CARRY4 \count_reg_reg[12]_i_1 
       (.CI(\count_reg_reg[8]_i_1_n_0 ),
        .CO({\NLW_count_reg_reg[12]_i_1_CO_UNCONNECTED [3],\count_reg_reg[12]_i_1_n_1 ,\count_reg_reg[12]_i_1_n_2 ,\count_reg_reg[12]_i_1_n_3 }),
        .CYINIT(1'b0),
        .DI({1'b0,1'b0,1'b0,1'b0}),
        .O({\count_reg_reg[12]_i_1_n_4 ,\count_reg_reg[12]_i_1_n_5 ,\count_reg_reg[12]_i_1_n_6 ,\count_reg_reg[12]_i_1_n_7 }),
        .S(count_reg_reg[15:12]));
  FDRE \count_reg_reg[13] 
       (.C(clk),
        .CE(\count_reg[0]_i_2_n_0 ),
        .D(\count_reg_reg[12]_i_1_n_6 ),
        .Q(count_reg_reg[13]),
        .R(\count_reg[0]_i_1_n_0 ));
  FDRE \count_reg_reg[14] 
       (.C(clk),
        .CE(\count_reg[0]_i_2_n_0 ),
        .D(\count_reg_reg[12]_i_1_n_5 ),
        .Q(count_reg_reg[14]),
        .R(\count_reg[0]_i_1_n_0 ));
  FDRE \count_reg_reg[15] 
       (.C(clk),
        .CE(\count_reg[0]_i_2_n_0 ),
        .D(\count_reg_reg[12]_i_1_n_4 ),
        .Q(count_reg_reg[15]),
        .R(\count_reg[0]_i_1_n_0 ));
  FDRE \count_reg_reg[1] 
       (.C(clk),
        .CE(\count_reg[0]_i_2_n_0 ),
        .D(\count_reg_reg[0]_i_3_n_6 ),
        .Q(count_reg_reg[1]),
        .R(\count_reg[0]_i_1_n_0 ));
  FDRE \count_reg_reg[2] 
       (.C(clk),
        .CE(\count_reg[0]_i_2_n_0 ),
        .D(\count_reg_reg[0]_i_3_n_5 ),
        .Q(count_reg_reg[2]),
        .R(\count_reg[0]_i_1_n_0 ));
  FDRE \count_reg_reg[3] 
       (.C(clk),
        .CE(\count_reg[0]_i_2_n_0 ),
        .D(\count_reg_reg[0]_i_3_n_4 ),
        .Q(count_reg_reg[3]),
        .R(\count_reg[0]_i_1_n_0 ));
  FDRE \count_reg_reg[4] 
       (.C(clk),
        .CE(\count_reg[0]_i_2_n_0 ),
        .D(\count_reg_reg[4]_i_1_n_7 ),
        .Q(count_reg_reg[4]),
        .R(\count_reg[0]_i_1_n_0 ));
  (* ADDER_THRESHOLD = "11" *) 
  CARRY4 \count_reg_reg[4]_i_1 
       (.CI(\count_reg_reg[0]_i_3_n_0 ),
        .CO({\count_reg_reg[4]_i_1_n_0 ,\count_reg_reg[4]_i_1_n_1 ,\count_reg_reg[4]_i_1_n_2 ,\count_reg_reg[4]_i_1_n_3 }),
        .CYINIT(1'b0),
        .DI({1'b0,1'b0,1'b0,1'b0}),
        .O({\count_reg_reg[4]_i_1_n_4 ,\count_reg_reg[4]_i_1_n_5 ,\count_reg_reg[4]_i_1_n_6 ,\count_reg_reg[4]_i_1_n_7 }),
        .S(count_reg_reg[7:4]));
  FDRE \count_reg_reg[5] 
       (.C(clk),
        .CE(\count_reg[0]_i_2_n_0 ),
        .D(\count_reg_reg[4]_i_1_n_6 ),
        .Q(count_reg_reg[5]),
        .R(\count_reg[0]_i_1_n_0 ));
  FDRE \count_reg_reg[6] 
       (.C(clk),
        .CE(\count_reg[0]_i_2_n_0 ),
        .D(\count_reg_reg[4]_i_1_n_5 ),
        .Q(count_reg_reg[6]),
        .R(\count_reg[0]_i_1_n_0 ));
  FDRE \count_reg_reg[7] 
       (.C(clk),
        .CE(\count_reg[0]_i_2_n_0 ),
        .D(\count_reg_reg[4]_i_1_n_4 ),
        .Q(count_reg_reg[7]),
        .R(\count_reg[0]_i_1_n_0 ));
  FDRE \count_reg_reg[8] 
       (.C(clk),
        .CE(\count_reg[0]_i_2_n_0 ),
        .D(\count_reg_reg[8]_i_1_n_7 ),
        .Q(count_reg_reg[8]),
        .R(\count_reg[0]_i_1_n_0 ));
  (* ADDER_THRESHOLD = "11" *) 
  CARRY4 \count_reg_reg[8]_i_1 
       (.CI(\count_reg_reg[4]_i_1_n_0 ),
        .CO({\count_reg_reg[8]_i_1_n_0 ,\count_reg_reg[8]_i_1_n_1 ,\count_reg_reg[8]_i_1_n_2 ,\count_reg_reg[8]_i_1_n_3 }),
        .CYINIT(1'b0),
        .DI({1'b0,1'b0,1'b0,1'b0}),
        .O({\count_reg_reg[8]_i_1_n_4 ,\count_reg_reg[8]_i_1_n_5 ,\count_reg_reg[8]_i_1_n_6 ,\count_reg_reg[8]_i_1_n_7 }),
        .S(count_reg_reg[11:8]));
  FDRE \count_reg_reg[9] 
       (.C(clk),
        .CE(\count_reg[0]_i_2_n_0 ),
        .D(\count_reg_reg[8]_i_1_n_6 ),
        .Q(count_reg_reg[9]),
        .R(\count_reg[0]_i_1_n_0 ));
  LUT4 #(
    .INIT(16'h4000)) 
    m_axis_tlast_INST_0
       (.I0(m_axis_tlast_INST_0_i_1_n_0),
        .I1(m_axis_tlast_INST_0_i_2_n_0),
        .I2(m_axis_tlast_INST_0_i_3_n_0),
        .I3(m_axis_tlast_INST_0_i_4_n_0),
        .O(m_axis_tlast));
  LUT4 #(
    .INIT(16'hFFFB)) 
    m_axis_tlast_INST_0_i_1
       (.I0(count_reg_reg[9]),
        .I1(count_reg_reg[8]),
        .I2(count_reg_reg[11]),
        .I3(count_reg_reg[10]),
        .O(m_axis_tlast_INST_0_i_1_n_0));
  LUT4 #(
    .INIT(16'h0001)) 
    m_axis_tlast_INST_0_i_2
       (.I0(count_reg_reg[14]),
        .I1(count_reg_reg[15]),
        .I2(count_reg_reg[13]),
        .I3(count_reg_reg[12]),
        .O(m_axis_tlast_INST_0_i_2_n_0));
  LUT4 #(
    .INIT(16'h8000)) 
    m_axis_tlast_INST_0_i_3
       (.I0(count_reg_reg[5]),
        .I1(count_reg_reg[4]),
        .I2(count_reg_reg[7]),
        .I3(count_reg_reg[6]),
        .O(m_axis_tlast_INST_0_i_3_n_0));
  LUT4 #(
    .INIT(16'h8000)) 
    m_axis_tlast_INST_0_i_4
       (.I0(count_reg_reg[1]),
        .I1(count_reg_reg[0]),
        .I2(count_reg_reg[3]),
        .I3(count_reg_reg[2]),
        .O(m_axis_tlast_INST_0_i_4_n_0));
endmodule
`ifndef GLBL
`define GLBL
`timescale  1 ps / 1 ps

module glbl ();

    parameter ROC_WIDTH = 100000;
    parameter TOC_WIDTH = 0;
    parameter GRES_WIDTH = 10000;
    parameter GRES_START = 10000;

//--------   STARTUP Globals --------------
    wire GSR;
    wire GTS;
    wire GWE;
    wire PRLD;
    wire GRESTORE;
    tri1 p_up_tmp;
    tri (weak1, strong0) PLL_LOCKG = p_up_tmp;

    wire PROGB_GLBL;
    wire CCLKO_GLBL;
    wire FCSBO_GLBL;
    wire [3:0] DO_GLBL;
    wire [3:0] DI_GLBL;
   
    reg GSR_int;
    reg GTS_int;
    reg PRLD_int;
    reg GRESTORE_int;

//--------   JTAG Globals --------------
    wire JTAG_TDO_GLBL;
    wire JTAG_TCK_GLBL;
    wire JTAG_TDI_GLBL;
    wire JTAG_TMS_GLBL;
    wire JTAG_TRST_GLBL;

    reg JTAG_CAPTURE_GLBL;
    reg JTAG_RESET_GLBL;
    reg JTAG_SHIFT_GLBL;
    reg JTAG_UPDATE_GLBL;
    reg JTAG_RUNTEST_GLBL;

    reg JTAG_SEL1_GLBL = 0;
    reg JTAG_SEL2_GLBL = 0 ;
    reg JTAG_SEL3_GLBL = 0;
    reg JTAG_SEL4_GLBL = 0;

    reg JTAG_USER_TDO1_GLBL = 1'bz;
    reg JTAG_USER_TDO2_GLBL = 1'bz;
    reg JTAG_USER_TDO3_GLBL = 1'bz;
    reg JTAG_USER_TDO4_GLBL = 1'bz;

    assign (strong1, weak0) GSR = GSR_int;
    assign (strong1, weak0) GTS = GTS_int;
    assign (weak1, weak0) PRLD = PRLD_int;
    assign (strong1, weak0) GRESTORE = GRESTORE_int;

    initial begin
	GSR_int = 1'b1;
	PRLD_int = 1'b1;
	#(ROC_WIDTH)
	GSR_int = 1'b0;
	PRLD_int = 1'b0;
    end

    initial begin
	GTS_int = 1'b1;
	#(TOC_WIDTH)
	GTS_int = 1'b0;
    end

    initial begin 
	GRESTORE_int = 1'b0;
	#(GRES_START);
	GRESTORE_int = 1'b1;
	#(GRES_WIDTH);
	GRESTORE_int = 1'b0;
    end

endmodule
`endif
