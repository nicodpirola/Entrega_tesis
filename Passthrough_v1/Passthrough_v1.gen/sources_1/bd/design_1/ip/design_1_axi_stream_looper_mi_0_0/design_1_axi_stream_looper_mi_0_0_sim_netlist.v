// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2025.1 (win64) Build 6140274 Thu May 22 00:12:29 MDT 2025
// Date        : Fri Sep 18 20:02:33 2026
// Host        : DESKTOP-FLN9N0C running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode funcsim
//               x:/Tesis/Passthrough_v1/Passthrough_v1.gen/sources_1/bd/design_1/ip/design_1_axi_stream_looper_mi_0_0/design_1_axi_stream_looper_mi_0_0_sim_netlist.v
// Design      : design_1_axi_stream_looper_mi_0_0
// Purpose     : This verilog netlist is a functional simulation representation of the design and should not be modified
//               or synthesized. This netlist cannot be used for SDF annotated simulation.
// Device      : xc7z020clg400-1
// --------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CHECK_LICENSE_TYPE = "design_1_axi_stream_looper_mi_0_0,axi_stream_looper_mixer,{}" *) (* DowngradeIPIdentifiedWarnings = "yes" *) (* IP_DEFINITION_SOURCE = "module_ref" *) 
(* X_CORE_INFO = "axi_stream_looper_mixer,Vivado 2025.1" *) 
(* NotValidForBitStream *)
module design_1_axi_stream_looper_mi_0_0
   (clk,
    resetn,
    mode,
    s0_axis_tdata,
    s0_axis_tvalid,
    s0_axis_tlast,
    s0_axis_tid,
    s0_axis_tkeep,
    s0_axis_tready,
    s1_axis_tdata,
    s1_axis_tvalid,
    s1_axis_tlast,
    s1_axis_tid,
    s1_axis_tkeep,
    s1_axis_tready,
    m_i2s_axis_tdata,
    m_i2s_axis_tvalid,
    m_i2s_axis_tlast,
    m_i2s_axis_tid,
    m_i2s_axis_tkeep,
    m_i2s_axis_tready,
    m_dma_axis_tdata,
    m_dma_axis_tvalid,
    m_dma_axis_tlast,
    m_dma_axis_tid,
    m_dma_axis_tkeep,
    m_dma_axis_tready);
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *) (* X_INTERFACE_MODE = "slave" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME clk, ASSOCIATED_BUSIF m_dma_axis:m_i2s_axis:s0_axis:s1_axis, ASSOCIATED_RESET resetn, FREQ_HZ 50000000, FREQ_TOLERANCE_HZ 0, PHASE 0.0, CLK_DOMAIN design_1_processing_system7_0_0_FCLK_CLK0, INSERT_VIP 0" *) input clk;
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 resetn RST" *) (* X_INTERFACE_MODE = "slave" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME resetn, POLARITY ACTIVE_LOW, INSERT_VIP 0" *) input resetn;
  input [1:0]mode;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s0_axis TDATA" *) (* X_INTERFACE_MODE = "slave" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME s0_axis, TDATA_NUM_BYTES 4, TDEST_WIDTH 0, TID_WIDTH 3, TUSER_WIDTH 0, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 1, HAS_TLAST 1, FREQ_HZ 50000000, PHASE 0.0, CLK_DOMAIN design_1_processing_system7_0_0_FCLK_CLK0, LAYERED_METADATA undef, INSERT_VIP 0" *) input [31:0]s0_axis_tdata;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s0_axis TVALID" *) input s0_axis_tvalid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s0_axis TLAST" *) input s0_axis_tlast;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s0_axis TID" *) input [2:0]s0_axis_tid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s0_axis TKEEP" *) input [3:0]s0_axis_tkeep;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s0_axis TREADY" *) output s0_axis_tready;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s1_axis TDATA" *) (* X_INTERFACE_MODE = "slave" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME s1_axis, TDATA_NUM_BYTES 4, TDEST_WIDTH 0, TID_WIDTH 3, TUSER_WIDTH 0, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 1, HAS_TLAST 1, FREQ_HZ 50000000, PHASE 0.0, CLK_DOMAIN design_1_processing_system7_0_0_FCLK_CLK0, LAYERED_METADATA undef, INSERT_VIP 0" *) input [31:0]s1_axis_tdata;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s1_axis TVALID" *) input s1_axis_tvalid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s1_axis TLAST" *) input s1_axis_tlast;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s1_axis TID" *) input [2:0]s1_axis_tid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s1_axis TKEEP" *) input [3:0]s1_axis_tkeep;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s1_axis TREADY" *) output s1_axis_tready;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_i2s_axis TDATA" *) (* X_INTERFACE_MODE = "master" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME m_i2s_axis, TDATA_NUM_BYTES 4, TDEST_WIDTH 0, TID_WIDTH 3, TUSER_WIDTH 0, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 1, HAS_TLAST 1, FREQ_HZ 50000000, PHASE 0.0, CLK_DOMAIN design_1_processing_system7_0_0_FCLK_CLK0, LAYERED_METADATA undef, INSERT_VIP 0" *) output [31:0]m_i2s_axis_tdata;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_i2s_axis TVALID" *) output m_i2s_axis_tvalid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_i2s_axis TLAST" *) output m_i2s_axis_tlast;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_i2s_axis TID" *) output [2:0]m_i2s_axis_tid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_i2s_axis TKEEP" *) output [3:0]m_i2s_axis_tkeep;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_i2s_axis TREADY" *) input m_i2s_axis_tready;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_dma_axis TDATA" *) (* X_INTERFACE_MODE = "master" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME m_dma_axis, TDATA_NUM_BYTES 4, TDEST_WIDTH 0, TID_WIDTH 3, TUSER_WIDTH 0, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 1, HAS_TLAST 1, FREQ_HZ 50000000, PHASE 0.0, CLK_DOMAIN design_1_processing_system7_0_0_FCLK_CLK0, LAYERED_METADATA undef, INSERT_VIP 0" *) output [31:0]m_dma_axis_tdata;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_dma_axis TVALID" *) output m_dma_axis_tvalid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_dma_axis TLAST" *) output m_dma_axis_tlast;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_dma_axis TID" *) output [2:0]m_dma_axis_tid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_dma_axis TKEEP" *) output [3:0]m_dma_axis_tkeep;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_dma_axis TREADY" *) input m_dma_axis_tready;

  wire clk;
  wire [31:4]\^m_dma_axis_tdata ;
  wire m_i2s_axis_tready;
  wire [1:0]mode;
  wire resetn;
  wire [31:0]s0_axis_tdata;
  wire [2:0]s0_axis_tid;
  wire [3:0]s0_axis_tkeep;
  wire s0_axis_tlast;
  wire s0_axis_tvalid;
  wire [31:0]s1_axis_tdata;
  wire s1_axis_tready;
  wire s1_axis_tvalid;

  assign m_dma_axis_tdata[31] = \^m_dma_axis_tdata [31];
  assign m_dma_axis_tdata[30:28] = s0_axis_tdata[30:28];
  assign m_dma_axis_tdata[27:4] = \^m_dma_axis_tdata [27:4];
  assign m_dma_axis_tdata[3:0] = s0_axis_tdata[3:0];
  assign m_dma_axis_tid[2:0] = s0_axis_tid;
  assign m_dma_axis_tkeep[3:0] = s0_axis_tkeep;
  assign m_dma_axis_tlast = s0_axis_tlast;
  assign m_dma_axis_tvalid = s0_axis_tvalid;
  assign m_i2s_axis_tdata[31] = \^m_dma_axis_tdata [31];
  assign m_i2s_axis_tdata[30:28] = s0_axis_tdata[30:28];
  assign m_i2s_axis_tdata[27:4] = \^m_dma_axis_tdata [27:4];
  assign m_i2s_axis_tdata[3:0] = s0_axis_tdata[3:0];
  assign m_i2s_axis_tid[2:0] = s0_axis_tid;
  assign m_i2s_axis_tkeep[3:0] = s0_axis_tkeep;
  assign m_i2s_axis_tlast = s0_axis_tlast;
  assign m_i2s_axis_tvalid = s0_axis_tvalid;
  assign s0_axis_tready = m_i2s_axis_tready;
  design_1_axi_stream_looper_mi_0_0_axi_stream_looper_mixer inst
       (.clk(clk),
        .m_dma_axis_tdata({\^m_dma_axis_tdata [31],\^m_dma_axis_tdata [27:4]}),
        .m_i2s_axis_tready(m_i2s_axis_tready),
        .mode(mode[1]),
        .resetn(resetn),
        .s0_axis_tdata(s0_axis_tdata),
        .s0_axis_tid(s0_axis_tid),
        .s0_axis_tvalid(s0_axis_tvalid),
        .s1_axis_tdata(s1_axis_tdata[27:4]),
        .s1_axis_tready(s1_axis_tready),
        .s1_axis_tvalid(s1_axis_tvalid));
endmodule

(* ORIG_REF_NAME = "axi_stream_looper_mixer" *) 
module design_1_axi_stream_looper_mi_0_0_axi_stream_looper_mixer
   (s1_axis_tready,
    m_dma_axis_tdata,
    s0_axis_tdata,
    s1_axis_tvalid,
    s1_axis_tdata,
    mode,
    clk,
    s0_axis_tvalid,
    s0_axis_tid,
    m_i2s_axis_tready,
    resetn);
  output s1_axis_tready;
  output [24:0]m_dma_axis_tdata;
  input [31:0]s0_axis_tdata;
  input s1_axis_tvalid;
  input [23:0]s1_axis_tdata;
  input [0:0]mode;
  input clk;
  input s0_axis_tvalid;
  input [2:0]s0_axis_tid;
  input m_i2s_axis_tready;
  input resetn;

  wire clk;
  wire i__carry_i_1_n_3;
  wire i__carry_i_2_n_0;
  wire [23:0]last_ram_audio;
  wire last_ram_audio0;
  wire [24:0]m_dma_axis_tdata;
  wire \m_dma_axis_tdata[31]_INST_0_i_1_n_0 ;
  wire \m_dma_axis_tdata[31]_INST_0_i_2_n_0 ;
  wire \m_dma_axis_tdata[31]_INST_0_i_3_n_0 ;
  wire \m_dma_axis_tdata[31]_INST_0_i_4_n_0 ;
  wire \m_dma_axis_tdata[31]_INST_0_i_5_n_0 ;
  wire \m_dma_axis_tdata[31]_INST_0_i_6_n_0 ;
  wire \m_dma_axis_tdata[31]_INST_0_i_7_n_0 ;
  wire \m_dma_axis_tdata[31]_INST_0_i_8_n_0 ;
  wire \m_dma_axis_tdata[31]_INST_0_i_9_n_0 ;
  wire m_i2s_axis_tready;
  wire mixed_audio1;
  wire mixed_audio10_in;
  wire mixed_audio1_carry_i_1_n_0;
  wire mixed_audio1_carry_i_3_n_0;
  wire mixed_audio1_carry_n_3;
  wire \mixed_audio1_inferred__0/i__carry_n_3 ;
  wire [0:0]mode;
  wire [1:1]mode_sync_1;
  wire \mode_sync_1[1]_i_1_n_0 ;
  wire [1:1]mode_sync_2;
  wire \mode_sync_2[1]_i_1_n_0 ;
  wire [24:0]p_0_in;
  wire resetn;
  wire [31:0]s0_axis_tdata;
  wire [2:0]s0_axis_tid;
  wire s0_axis_tvalid;
  wire [23:0]s1_axis_tdata;
  wire s1_axis_tready;
  wire s1_axis_tvalid;
  wire sum_carry__0_i_1_n_0;
  wire sum_carry__0_i_2_n_0;
  wire sum_carry__0_i_3_n_0;
  wire sum_carry__0_i_4_n_0;
  wire sum_carry__0_n_0;
  wire sum_carry__0_n_1;
  wire sum_carry__0_n_2;
  wire sum_carry__0_n_3;
  wire sum_carry__1_i_1_n_0;
  wire sum_carry__1_i_2_n_0;
  wire sum_carry__1_i_3_n_0;
  wire sum_carry__1_i_4_n_0;
  wire sum_carry__1_n_0;
  wire sum_carry__1_n_1;
  wire sum_carry__1_n_2;
  wire sum_carry__1_n_3;
  wire sum_carry__2_i_1_n_0;
  wire sum_carry__2_i_2_n_0;
  wire sum_carry__2_i_3_n_0;
  wire sum_carry__2_i_4_n_0;
  wire sum_carry__2_n_0;
  wire sum_carry__2_n_1;
  wire sum_carry__2_n_2;
  wire sum_carry__2_n_3;
  wire sum_carry__3_i_1_n_0;
  wire sum_carry__3_i_2_n_0;
  wire sum_carry__3_i_3_n_0;
  wire sum_carry__3_i_4_n_0;
  wire sum_carry__3_n_0;
  wire sum_carry__3_n_1;
  wire sum_carry__3_n_2;
  wire sum_carry__3_n_3;
  wire sum_carry__4_i_1_n_0;
  wire sum_carry__4_i_2_n_0;
  wire sum_carry__4_i_3_n_0;
  wire sum_carry__4_i_4_n_0;
  wire sum_carry__4_i_5_n_0;
  wire sum_carry__4_n_0;
  wire sum_carry__4_n_1;
  wire sum_carry__4_n_2;
  wire sum_carry__4_n_3;
  wire sum_carry_i_1_n_0;
  wire sum_carry_i_2_n_0;
  wire sum_carry_i_3_n_0;
  wire sum_carry_i_4_n_0;
  wire sum_carry_n_0;
  wire sum_carry_n_1;
  wire sum_carry_n_2;
  wire sum_carry_n_3;
  wire [3:1]NLW_i__carry_i_1_CO_UNCONNECTED;
  wire [3:0]NLW_i__carry_i_1_O_UNCONNECTED;
  wire [3:2]NLW_mixed_audio1_carry_CO_UNCONNECTED;
  wire [3:0]NLW_mixed_audio1_carry_O_UNCONNECTED;
  wire [3:2]\NLW_mixed_audio1_inferred__0/i__carry_CO_UNCONNECTED ;
  wire [3:0]\NLW_mixed_audio1_inferred__0/i__carry_O_UNCONNECTED ;

  CARRY4 i__carry_i_1
       (.CI(sum_carry__4_n_0),
        .CO({NLW_i__carry_i_1_CO_UNCONNECTED[3:1],i__carry_i_1_n_3}),
        .CYINIT(1'b0),
        .DI({1'b0,1'b0,1'b0,1'b0}),
        .O(NLW_i__carry_i_1_O_UNCONNECTED[3:0]),
        .S({1'b0,1'b0,1'b0,1'b1}));
  LUT2 #(
    .INIT(4'h2)) 
    i__carry_i_2
       (.I0(p_0_in[22]),
        .I1(p_0_in[23]),
        .O(i__carry_i_2_n_0));
  LUT4 #(
    .INIT(16'h8000)) 
    \last_ram_audio[23]_i_1 
       (.I0(s1_axis_tvalid),
        .I1(m_i2s_axis_tready),
        .I2(s0_axis_tvalid),
        .I3(mode_sync_2),
        .O(last_ram_audio0));
  FDCE \last_ram_audio_reg[0] 
       (.C(clk),
        .CE(last_ram_audio0),
        .CLR(\mode_sync_1[1]_i_1_n_0 ),
        .D(s1_axis_tdata[0]),
        .Q(last_ram_audio[0]));
  FDCE \last_ram_audio_reg[10] 
       (.C(clk),
        .CE(last_ram_audio0),
        .CLR(\mode_sync_1[1]_i_1_n_0 ),
        .D(s1_axis_tdata[10]),
        .Q(last_ram_audio[10]));
  FDCE \last_ram_audio_reg[11] 
       (.C(clk),
        .CE(last_ram_audio0),
        .CLR(\mode_sync_1[1]_i_1_n_0 ),
        .D(s1_axis_tdata[11]),
        .Q(last_ram_audio[11]));
  FDCE \last_ram_audio_reg[12] 
       (.C(clk),
        .CE(last_ram_audio0),
        .CLR(\mode_sync_1[1]_i_1_n_0 ),
        .D(s1_axis_tdata[12]),
        .Q(last_ram_audio[12]));
  FDCE \last_ram_audio_reg[13] 
       (.C(clk),
        .CE(last_ram_audio0),
        .CLR(\mode_sync_1[1]_i_1_n_0 ),
        .D(s1_axis_tdata[13]),
        .Q(last_ram_audio[13]));
  FDCE \last_ram_audio_reg[14] 
       (.C(clk),
        .CE(last_ram_audio0),
        .CLR(\mode_sync_1[1]_i_1_n_0 ),
        .D(s1_axis_tdata[14]),
        .Q(last_ram_audio[14]));
  FDCE \last_ram_audio_reg[15] 
       (.C(clk),
        .CE(last_ram_audio0),
        .CLR(\mode_sync_1[1]_i_1_n_0 ),
        .D(s1_axis_tdata[15]),
        .Q(last_ram_audio[15]));
  FDCE \last_ram_audio_reg[16] 
       (.C(clk),
        .CE(last_ram_audio0),
        .CLR(\mode_sync_1[1]_i_1_n_0 ),
        .D(s1_axis_tdata[16]),
        .Q(last_ram_audio[16]));
  FDCE \last_ram_audio_reg[17] 
       (.C(clk),
        .CE(last_ram_audio0),
        .CLR(\mode_sync_1[1]_i_1_n_0 ),
        .D(s1_axis_tdata[17]),
        .Q(last_ram_audio[17]));
  FDCE \last_ram_audio_reg[18] 
       (.C(clk),
        .CE(last_ram_audio0),
        .CLR(\mode_sync_1[1]_i_1_n_0 ),
        .D(s1_axis_tdata[18]),
        .Q(last_ram_audio[18]));
  FDCE \last_ram_audio_reg[19] 
       (.C(clk),
        .CE(last_ram_audio0),
        .CLR(\mode_sync_1[1]_i_1_n_0 ),
        .D(s1_axis_tdata[19]),
        .Q(last_ram_audio[19]));
  FDCE \last_ram_audio_reg[1] 
       (.C(clk),
        .CE(last_ram_audio0),
        .CLR(\mode_sync_1[1]_i_1_n_0 ),
        .D(s1_axis_tdata[1]),
        .Q(last_ram_audio[1]));
  FDCE \last_ram_audio_reg[20] 
       (.C(clk),
        .CE(last_ram_audio0),
        .CLR(\mode_sync_1[1]_i_1_n_0 ),
        .D(s1_axis_tdata[20]),
        .Q(last_ram_audio[20]));
  FDCE \last_ram_audio_reg[21] 
       (.C(clk),
        .CE(last_ram_audio0),
        .CLR(\mode_sync_1[1]_i_1_n_0 ),
        .D(s1_axis_tdata[21]),
        .Q(last_ram_audio[21]));
  FDCE \last_ram_audio_reg[22] 
       (.C(clk),
        .CE(last_ram_audio0),
        .CLR(\mode_sync_1[1]_i_1_n_0 ),
        .D(s1_axis_tdata[22]),
        .Q(last_ram_audio[22]));
  FDCE \last_ram_audio_reg[23] 
       (.C(clk),
        .CE(last_ram_audio0),
        .CLR(\mode_sync_1[1]_i_1_n_0 ),
        .D(s1_axis_tdata[23]),
        .Q(last_ram_audio[23]));
  FDCE \last_ram_audio_reg[2] 
       (.C(clk),
        .CE(last_ram_audio0),
        .CLR(\mode_sync_1[1]_i_1_n_0 ),
        .D(s1_axis_tdata[2]),
        .Q(last_ram_audio[2]));
  FDCE \last_ram_audio_reg[3] 
       (.C(clk),
        .CE(last_ram_audio0),
        .CLR(\mode_sync_1[1]_i_1_n_0 ),
        .D(s1_axis_tdata[3]),
        .Q(last_ram_audio[3]));
  FDCE \last_ram_audio_reg[4] 
       (.C(clk),
        .CE(last_ram_audio0),
        .CLR(\mode_sync_1[1]_i_1_n_0 ),
        .D(s1_axis_tdata[4]),
        .Q(last_ram_audio[4]));
  FDCE \last_ram_audio_reg[5] 
       (.C(clk),
        .CE(last_ram_audio0),
        .CLR(\mode_sync_1[1]_i_1_n_0 ),
        .D(s1_axis_tdata[5]),
        .Q(last_ram_audio[5]));
  FDCE \last_ram_audio_reg[6] 
       (.C(clk),
        .CE(last_ram_audio0),
        .CLR(\mode_sync_1[1]_i_1_n_0 ),
        .D(s1_axis_tdata[6]),
        .Q(last_ram_audio[6]));
  FDCE \last_ram_audio_reg[7] 
       (.C(clk),
        .CE(last_ram_audio0),
        .CLR(\mode_sync_1[1]_i_1_n_0 ),
        .D(s1_axis_tdata[7]),
        .Q(last_ram_audio[7]));
  FDCE \last_ram_audio_reg[8] 
       (.C(clk),
        .CE(last_ram_audio0),
        .CLR(\mode_sync_1[1]_i_1_n_0 ),
        .D(s1_axis_tdata[8]),
        .Q(last_ram_audio[8]));
  FDCE \last_ram_audio_reg[9] 
       (.C(clk),
        .CE(last_ram_audio0),
        .CLR(\mode_sync_1[1]_i_1_n_0 ),
        .D(s1_axis_tdata[9]),
        .Q(last_ram_audio[9]));
  LUT5 #(
    .INIT(32'hFF0CAAAA)) 
    \m_dma_axis_tdata[10]_INST_0 
       (.I0(s0_axis_tdata[10]),
        .I1(p_0_in[6]),
        .I2(mixed_audio1),
        .I3(mixed_audio10_in),
        .I4(mode_sync_2),
        .O(m_dma_axis_tdata[6]));
  LUT5 #(
    .INIT(32'hFF0CAAAA)) 
    \m_dma_axis_tdata[11]_INST_0 
       (.I0(s0_axis_tdata[11]),
        .I1(p_0_in[7]),
        .I2(mixed_audio1),
        .I3(mixed_audio10_in),
        .I4(mode_sync_2),
        .O(m_dma_axis_tdata[7]));
  LUT5 #(
    .INIT(32'hFF0CAAAA)) 
    \m_dma_axis_tdata[12]_INST_0 
       (.I0(s0_axis_tdata[12]),
        .I1(p_0_in[8]),
        .I2(mixed_audio1),
        .I3(mixed_audio10_in),
        .I4(mode_sync_2),
        .O(m_dma_axis_tdata[8]));
  LUT5 #(
    .INIT(32'hFF0CAAAA)) 
    \m_dma_axis_tdata[13]_INST_0 
       (.I0(s0_axis_tdata[13]),
        .I1(p_0_in[9]),
        .I2(mixed_audio1),
        .I3(mixed_audio10_in),
        .I4(mode_sync_2),
        .O(m_dma_axis_tdata[9]));
  LUT5 #(
    .INIT(32'hFF0CAAAA)) 
    \m_dma_axis_tdata[14]_INST_0 
       (.I0(s0_axis_tdata[14]),
        .I1(p_0_in[10]),
        .I2(mixed_audio1),
        .I3(mixed_audio10_in),
        .I4(mode_sync_2),
        .O(m_dma_axis_tdata[10]));
  LUT5 #(
    .INIT(32'hFF0CAAAA)) 
    \m_dma_axis_tdata[15]_INST_0 
       (.I0(s0_axis_tdata[15]),
        .I1(p_0_in[11]),
        .I2(mixed_audio1),
        .I3(mixed_audio10_in),
        .I4(mode_sync_2),
        .O(m_dma_axis_tdata[11]));
  LUT5 #(
    .INIT(32'hFF0CAAAA)) 
    \m_dma_axis_tdata[16]_INST_0 
       (.I0(s0_axis_tdata[16]),
        .I1(p_0_in[12]),
        .I2(mixed_audio1),
        .I3(mixed_audio10_in),
        .I4(mode_sync_2),
        .O(m_dma_axis_tdata[12]));
  LUT5 #(
    .INIT(32'hFF0CAAAA)) 
    \m_dma_axis_tdata[17]_INST_0 
       (.I0(s0_axis_tdata[17]),
        .I1(p_0_in[13]),
        .I2(mixed_audio1),
        .I3(mixed_audio10_in),
        .I4(mode_sync_2),
        .O(m_dma_axis_tdata[13]));
  LUT5 #(
    .INIT(32'hFF0CAAAA)) 
    \m_dma_axis_tdata[18]_INST_0 
       (.I0(s0_axis_tdata[18]),
        .I1(p_0_in[14]),
        .I2(mixed_audio1),
        .I3(mixed_audio10_in),
        .I4(mode_sync_2),
        .O(m_dma_axis_tdata[14]));
  LUT5 #(
    .INIT(32'hFF0CAAAA)) 
    \m_dma_axis_tdata[19]_INST_0 
       (.I0(s0_axis_tdata[19]),
        .I1(p_0_in[15]),
        .I2(mixed_audio1),
        .I3(mixed_audio10_in),
        .I4(mode_sync_2),
        .O(m_dma_axis_tdata[15]));
  LUT5 #(
    .INIT(32'hFF0CAAAA)) 
    \m_dma_axis_tdata[20]_INST_0 
       (.I0(s0_axis_tdata[20]),
        .I1(p_0_in[16]),
        .I2(mixed_audio1),
        .I3(mixed_audio10_in),
        .I4(mode_sync_2),
        .O(m_dma_axis_tdata[16]));
  LUT5 #(
    .INIT(32'hFF0CAAAA)) 
    \m_dma_axis_tdata[21]_INST_0 
       (.I0(s0_axis_tdata[21]),
        .I1(p_0_in[17]),
        .I2(mixed_audio1),
        .I3(mixed_audio10_in),
        .I4(mode_sync_2),
        .O(m_dma_axis_tdata[17]));
  LUT5 #(
    .INIT(32'hFF0CAAAA)) 
    \m_dma_axis_tdata[22]_INST_0 
       (.I0(s0_axis_tdata[22]),
        .I1(p_0_in[18]),
        .I2(mixed_audio1),
        .I3(mixed_audio10_in),
        .I4(mode_sync_2),
        .O(m_dma_axis_tdata[18]));
  LUT5 #(
    .INIT(32'hFF0CAAAA)) 
    \m_dma_axis_tdata[23]_INST_0 
       (.I0(s0_axis_tdata[23]),
        .I1(p_0_in[19]),
        .I2(mixed_audio1),
        .I3(mixed_audio10_in),
        .I4(mode_sync_2),
        .O(m_dma_axis_tdata[19]));
  LUT5 #(
    .INIT(32'hFF0CAAAA)) 
    \m_dma_axis_tdata[24]_INST_0 
       (.I0(s0_axis_tdata[24]),
        .I1(p_0_in[20]),
        .I2(mixed_audio1),
        .I3(mixed_audio10_in),
        .I4(mode_sync_2),
        .O(m_dma_axis_tdata[20]));
  LUT5 #(
    .INIT(32'hFF0CAAAA)) 
    \m_dma_axis_tdata[25]_INST_0 
       (.I0(s0_axis_tdata[25]),
        .I1(p_0_in[21]),
        .I2(mixed_audio1),
        .I3(mixed_audio10_in),
        .I4(mode_sync_2),
        .O(m_dma_axis_tdata[21]));
  LUT5 #(
    .INIT(32'hFF0CAAAA)) 
    \m_dma_axis_tdata[26]_INST_0 
       (.I0(s0_axis_tdata[26]),
        .I1(p_0_in[22]),
        .I2(mixed_audio1),
        .I3(mixed_audio10_in),
        .I4(mode_sync_2),
        .O(m_dma_axis_tdata[22]));
  LUT5 #(
    .INIT(32'h3330AAAA)) 
    \m_dma_axis_tdata[27]_INST_0 
       (.I0(s0_axis_tdata[27]),
        .I1(mixed_audio10_in),
        .I2(mixed_audio1),
        .I3(p_0_in[23]),
        .I4(mode_sync_2),
        .O(m_dma_axis_tdata[23]));
  LUT4 #(
    .INIT(16'h3CAA)) 
    \m_dma_axis_tdata[31]_INST_0 
       (.I0(s0_axis_tdata[31]),
        .I1(\m_dma_axis_tdata[31]_INST_0_i_1_n_0 ),
        .I2(\m_dma_axis_tdata[31]_INST_0_i_2_n_0 ),
        .I3(mode_sync_2),
        .O(m_dma_axis_tdata[24]));
  LUT4 #(
    .INIT(16'h6996)) 
    \m_dma_axis_tdata[31]_INST_0_i_1 
       (.I0(\m_dma_axis_tdata[31]_INST_0_i_3_n_0 ),
        .I1(\m_dma_axis_tdata[31]_INST_0_i_4_n_0 ),
        .I2(\m_dma_axis_tdata[31]_INST_0_i_5_n_0 ),
        .I3(\m_dma_axis_tdata[31]_INST_0_i_6_n_0 ),
        .O(\m_dma_axis_tdata[31]_INST_0_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h6996966996696996)) 
    \m_dma_axis_tdata[31]_INST_0_i_2 
       (.I0(\m_dma_axis_tdata[31]_INST_0_i_7_n_0 ),
        .I1(s0_axis_tdata[30]),
        .I2(s0_axis_tdata[28]),
        .I3(s0_axis_tdata[29]),
        .I4(\m_dma_axis_tdata[31]_INST_0_i_8_n_0 ),
        .I5(\m_dma_axis_tdata[31]_INST_0_i_9_n_0 ),
        .O(\m_dma_axis_tdata[31]_INST_0_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h0006000900090006)) 
    \m_dma_axis_tdata[31]_INST_0_i_3 
       (.I0(p_0_in[6]),
        .I1(p_0_in[7]),
        .I2(mixed_audio10_in),
        .I3(mixed_audio1),
        .I4(p_0_in[4]),
        .I5(p_0_in[5]),
        .O(\m_dma_axis_tdata[31]_INST_0_i_3_n_0 ));
  LUT6 #(
    .INIT(64'h0006000900090006)) 
    \m_dma_axis_tdata[31]_INST_0_i_4 
       (.I0(p_0_in[10]),
        .I1(p_0_in[11]),
        .I2(mixed_audio10_in),
        .I3(mixed_audio1),
        .I4(p_0_in[8]),
        .I5(p_0_in[9]),
        .O(\m_dma_axis_tdata[31]_INST_0_i_4_n_0 ));
  LUT4 #(
    .INIT(16'h6996)) 
    \m_dma_axis_tdata[31]_INST_0_i_5 
       (.I0(s0_axis_tdata[2]),
        .I1(s0_axis_tdata[3]),
        .I2(s0_axis_tdata[0]),
        .I3(s0_axis_tdata[1]),
        .O(\m_dma_axis_tdata[31]_INST_0_i_5_n_0 ));
  LUT6 #(
    .INIT(64'h0006000900090006)) 
    \m_dma_axis_tdata[31]_INST_0_i_6 
       (.I0(p_0_in[2]),
        .I1(p_0_in[3]),
        .I2(mixed_audio10_in),
        .I3(mixed_audio1),
        .I4(p_0_in[0]),
        .I5(p_0_in[1]),
        .O(\m_dma_axis_tdata[31]_INST_0_i_6_n_0 ));
  LUT6 #(
    .INIT(64'hFFF6FFF9FFF9FFF6)) 
    \m_dma_axis_tdata[31]_INST_0_i_7 
       (.I0(p_0_in[22]),
        .I1(p_0_in[23]),
        .I2(mixed_audio10_in),
        .I3(mixed_audio1),
        .I4(p_0_in[20]),
        .I5(p_0_in[21]),
        .O(\m_dma_axis_tdata[31]_INST_0_i_7_n_0 ));
  LUT6 #(
    .INIT(64'h0006000900090006)) 
    \m_dma_axis_tdata[31]_INST_0_i_8 
       (.I0(p_0_in[14]),
        .I1(p_0_in[15]),
        .I2(mixed_audio10_in),
        .I3(mixed_audio1),
        .I4(p_0_in[12]),
        .I5(p_0_in[13]),
        .O(\m_dma_axis_tdata[31]_INST_0_i_8_n_0 ));
  LUT6 #(
    .INIT(64'h0006000900090006)) 
    \m_dma_axis_tdata[31]_INST_0_i_9 
       (.I0(p_0_in[18]),
        .I1(p_0_in[19]),
        .I2(mixed_audio10_in),
        .I3(mixed_audio1),
        .I4(p_0_in[16]),
        .I5(p_0_in[17]),
        .O(\m_dma_axis_tdata[31]_INST_0_i_9_n_0 ));
  LUT5 #(
    .INIT(32'hFF0CAAAA)) 
    \m_dma_axis_tdata[4]_INST_0 
       (.I0(s0_axis_tdata[4]),
        .I1(p_0_in[0]),
        .I2(mixed_audio1),
        .I3(mixed_audio10_in),
        .I4(mode_sync_2),
        .O(m_dma_axis_tdata[0]));
  LUT5 #(
    .INIT(32'hFF0CAAAA)) 
    \m_dma_axis_tdata[5]_INST_0 
       (.I0(s0_axis_tdata[5]),
        .I1(p_0_in[1]),
        .I2(mixed_audio1),
        .I3(mixed_audio10_in),
        .I4(mode_sync_2),
        .O(m_dma_axis_tdata[1]));
  LUT5 #(
    .INIT(32'hFF0CAAAA)) 
    \m_dma_axis_tdata[6]_INST_0 
       (.I0(s0_axis_tdata[6]),
        .I1(p_0_in[2]),
        .I2(mixed_audio1),
        .I3(mixed_audio10_in),
        .I4(mode_sync_2),
        .O(m_dma_axis_tdata[2]));
  LUT5 #(
    .INIT(32'hFF0CAAAA)) 
    \m_dma_axis_tdata[7]_INST_0 
       (.I0(s0_axis_tdata[7]),
        .I1(p_0_in[3]),
        .I2(mixed_audio1),
        .I3(mixed_audio10_in),
        .I4(mode_sync_2),
        .O(m_dma_axis_tdata[3]));
  LUT5 #(
    .INIT(32'hFF0CAAAA)) 
    \m_dma_axis_tdata[8]_INST_0 
       (.I0(s0_axis_tdata[8]),
        .I1(p_0_in[4]),
        .I2(mixed_audio1),
        .I3(mixed_audio10_in),
        .I4(mode_sync_2),
        .O(m_dma_axis_tdata[4]));
  LUT5 #(
    .INIT(32'hFF0CAAAA)) 
    \m_dma_axis_tdata[9]_INST_0 
       (.I0(s0_axis_tdata[9]),
        .I1(p_0_in[5]),
        .I2(mixed_audio1),
        .I3(mixed_audio10_in),
        .I4(mode_sync_2),
        .O(m_dma_axis_tdata[5]));
  (* COMPARATOR_THRESHOLD = "11" *) 
  CARRY4 mixed_audio1_carry
       (.CI(1'b0),
        .CO({NLW_mixed_audio1_carry_CO_UNCONNECTED[3:2],mixed_audio1,mixed_audio1_carry_n_3}),
        .CYINIT(1'b0),
        .DI({1'b0,1'b0,1'b0,mixed_audio1_carry_i_1_n_0}),
        .O(NLW_mixed_audio1_carry_O_UNCONNECTED[3:0]),
        .S({1'b0,1'b0,p_0_in[24],mixed_audio1_carry_i_3_n_0}));
  LUT1 #(
    .INIT(2'h1)) 
    mixed_audio1_carry_i_1
       (.I0(p_0_in[23]),
        .O(mixed_audio1_carry_i_1_n_0));
  LUT1 #(
    .INIT(2'h1)) 
    mixed_audio1_carry_i_2
       (.I0(i__carry_i_1_n_3),
        .O(p_0_in[24]));
  LUT2 #(
    .INIT(4'h2)) 
    mixed_audio1_carry_i_3
       (.I0(p_0_in[23]),
        .I1(p_0_in[22]),
        .O(mixed_audio1_carry_i_3_n_0));
  (* COMPARATOR_THRESHOLD = "11" *) 
  CARRY4 \mixed_audio1_inferred__0/i__carry 
       (.CI(1'b0),
        .CO({\NLW_mixed_audio1_inferred__0/i__carry_CO_UNCONNECTED [3:2],mixed_audio10_in,\mixed_audio1_inferred__0/i__carry_n_3 }),
        .CYINIT(1'b0),
        .DI({1'b0,1'b0,1'b0,p_0_in[23]}),
        .O(\NLW_mixed_audio1_inferred__0/i__carry_O_UNCONNECTED [3:0]),
        .S({1'b0,1'b0,i__carry_i_1_n_3,i__carry_i_2_n_0}));
  LUT1 #(
    .INIT(2'h1)) 
    \mode_sync_1[1]_i_1 
       (.I0(resetn),
        .O(\mode_sync_1[1]_i_1_n_0 ));
  FDCE \mode_sync_1_reg[1] 
       (.C(clk),
        .CE(1'b1),
        .CLR(\mode_sync_1[1]_i_1_n_0 ),
        .D(mode),
        .Q(mode_sync_1));
  LUT6 #(
    .INIT(64'hFFFFFFFB00000008)) 
    \mode_sync_2[1]_i_1 
       (.I0(mode_sync_1),
        .I1(s0_axis_tvalid),
        .I2(s0_axis_tid[2]),
        .I3(s0_axis_tid[0]),
        .I4(s0_axis_tid[1]),
        .I5(mode_sync_2),
        .O(\mode_sync_2[1]_i_1_n_0 ));
  FDCE \mode_sync_2_reg[1] 
       (.C(clk),
        .CE(1'b1),
        .CLR(\mode_sync_1[1]_i_1_n_0 ),
        .D(\mode_sync_2[1]_i_1_n_0 ),
        .Q(mode_sync_2));
  LUT3 #(
    .INIT(8'h80)) 
    s1_axis_tready_INST_0
       (.I0(mode_sync_2),
        .I1(s0_axis_tvalid),
        .I2(m_i2s_axis_tready),
        .O(s1_axis_tready));
  CARRY4 sum_carry
       (.CI(1'b0),
        .CO({sum_carry_n_0,sum_carry_n_1,sum_carry_n_2,sum_carry_n_3}),
        .CYINIT(1'b0),
        .DI(s0_axis_tdata[7:4]),
        .O(p_0_in[3:0]),
        .S({sum_carry_i_1_n_0,sum_carry_i_2_n_0,sum_carry_i_3_n_0,sum_carry_i_4_n_0}));
  CARRY4 sum_carry__0
       (.CI(sum_carry_n_0),
        .CO({sum_carry__0_n_0,sum_carry__0_n_1,sum_carry__0_n_2,sum_carry__0_n_3}),
        .CYINIT(1'b0),
        .DI(s0_axis_tdata[11:8]),
        .O(p_0_in[7:4]),
        .S({sum_carry__0_i_1_n_0,sum_carry__0_i_2_n_0,sum_carry__0_i_3_n_0,sum_carry__0_i_4_n_0}));
  LUT4 #(
    .INIT(16'h569A)) 
    sum_carry__0_i_1
       (.I0(s0_axis_tdata[11]),
        .I1(s1_axis_tvalid),
        .I2(last_ram_audio[7]),
        .I3(s1_axis_tdata[7]),
        .O(sum_carry__0_i_1_n_0));
  LUT4 #(
    .INIT(16'h569A)) 
    sum_carry__0_i_2
       (.I0(s0_axis_tdata[10]),
        .I1(s1_axis_tvalid),
        .I2(last_ram_audio[6]),
        .I3(s1_axis_tdata[6]),
        .O(sum_carry__0_i_2_n_0));
  LUT4 #(
    .INIT(16'h569A)) 
    sum_carry__0_i_3
       (.I0(s0_axis_tdata[9]),
        .I1(s1_axis_tvalid),
        .I2(last_ram_audio[5]),
        .I3(s1_axis_tdata[5]),
        .O(sum_carry__0_i_3_n_0));
  LUT4 #(
    .INIT(16'h569A)) 
    sum_carry__0_i_4
       (.I0(s0_axis_tdata[8]),
        .I1(s1_axis_tvalid),
        .I2(last_ram_audio[4]),
        .I3(s1_axis_tdata[4]),
        .O(sum_carry__0_i_4_n_0));
  CARRY4 sum_carry__1
       (.CI(sum_carry__0_n_0),
        .CO({sum_carry__1_n_0,sum_carry__1_n_1,sum_carry__1_n_2,sum_carry__1_n_3}),
        .CYINIT(1'b0),
        .DI(s0_axis_tdata[15:12]),
        .O(p_0_in[11:8]),
        .S({sum_carry__1_i_1_n_0,sum_carry__1_i_2_n_0,sum_carry__1_i_3_n_0,sum_carry__1_i_4_n_0}));
  LUT4 #(
    .INIT(16'h569A)) 
    sum_carry__1_i_1
       (.I0(s0_axis_tdata[15]),
        .I1(s1_axis_tvalid),
        .I2(last_ram_audio[11]),
        .I3(s1_axis_tdata[11]),
        .O(sum_carry__1_i_1_n_0));
  LUT4 #(
    .INIT(16'h569A)) 
    sum_carry__1_i_2
       (.I0(s0_axis_tdata[14]),
        .I1(s1_axis_tvalid),
        .I2(last_ram_audio[10]),
        .I3(s1_axis_tdata[10]),
        .O(sum_carry__1_i_2_n_0));
  LUT4 #(
    .INIT(16'h569A)) 
    sum_carry__1_i_3
       (.I0(s0_axis_tdata[13]),
        .I1(s1_axis_tvalid),
        .I2(last_ram_audio[9]),
        .I3(s1_axis_tdata[9]),
        .O(sum_carry__1_i_3_n_0));
  LUT4 #(
    .INIT(16'h569A)) 
    sum_carry__1_i_4
       (.I0(s0_axis_tdata[12]),
        .I1(s1_axis_tvalid),
        .I2(last_ram_audio[8]),
        .I3(s1_axis_tdata[8]),
        .O(sum_carry__1_i_4_n_0));
  CARRY4 sum_carry__2
       (.CI(sum_carry__1_n_0),
        .CO({sum_carry__2_n_0,sum_carry__2_n_1,sum_carry__2_n_2,sum_carry__2_n_3}),
        .CYINIT(1'b0),
        .DI(s0_axis_tdata[19:16]),
        .O(p_0_in[15:12]),
        .S({sum_carry__2_i_1_n_0,sum_carry__2_i_2_n_0,sum_carry__2_i_3_n_0,sum_carry__2_i_4_n_0}));
  LUT4 #(
    .INIT(16'h569A)) 
    sum_carry__2_i_1
       (.I0(s0_axis_tdata[19]),
        .I1(s1_axis_tvalid),
        .I2(last_ram_audio[15]),
        .I3(s1_axis_tdata[15]),
        .O(sum_carry__2_i_1_n_0));
  LUT4 #(
    .INIT(16'h569A)) 
    sum_carry__2_i_2
       (.I0(s0_axis_tdata[18]),
        .I1(s1_axis_tvalid),
        .I2(last_ram_audio[14]),
        .I3(s1_axis_tdata[14]),
        .O(sum_carry__2_i_2_n_0));
  LUT4 #(
    .INIT(16'h569A)) 
    sum_carry__2_i_3
       (.I0(s0_axis_tdata[17]),
        .I1(s1_axis_tvalid),
        .I2(last_ram_audio[13]),
        .I3(s1_axis_tdata[13]),
        .O(sum_carry__2_i_3_n_0));
  LUT4 #(
    .INIT(16'h569A)) 
    sum_carry__2_i_4
       (.I0(s0_axis_tdata[16]),
        .I1(s1_axis_tvalid),
        .I2(last_ram_audio[12]),
        .I3(s1_axis_tdata[12]),
        .O(sum_carry__2_i_4_n_0));
  CARRY4 sum_carry__3
       (.CI(sum_carry__2_n_0),
        .CO({sum_carry__3_n_0,sum_carry__3_n_1,sum_carry__3_n_2,sum_carry__3_n_3}),
        .CYINIT(1'b0),
        .DI(s0_axis_tdata[23:20]),
        .O(p_0_in[19:16]),
        .S({sum_carry__3_i_1_n_0,sum_carry__3_i_2_n_0,sum_carry__3_i_3_n_0,sum_carry__3_i_4_n_0}));
  LUT4 #(
    .INIT(16'h569A)) 
    sum_carry__3_i_1
       (.I0(s0_axis_tdata[23]),
        .I1(s1_axis_tvalid),
        .I2(last_ram_audio[19]),
        .I3(s1_axis_tdata[19]),
        .O(sum_carry__3_i_1_n_0));
  LUT4 #(
    .INIT(16'h569A)) 
    sum_carry__3_i_2
       (.I0(s0_axis_tdata[22]),
        .I1(s1_axis_tvalid),
        .I2(last_ram_audio[18]),
        .I3(s1_axis_tdata[18]),
        .O(sum_carry__3_i_2_n_0));
  LUT4 #(
    .INIT(16'h569A)) 
    sum_carry__3_i_3
       (.I0(s0_axis_tdata[21]),
        .I1(s1_axis_tvalid),
        .I2(last_ram_audio[17]),
        .I3(s1_axis_tdata[17]),
        .O(sum_carry__3_i_3_n_0));
  LUT4 #(
    .INIT(16'h569A)) 
    sum_carry__3_i_4
       (.I0(s0_axis_tdata[20]),
        .I1(s1_axis_tvalid),
        .I2(last_ram_audio[16]),
        .I3(s1_axis_tdata[16]),
        .O(sum_carry__3_i_4_n_0));
  CARRY4 sum_carry__4
       (.CI(sum_carry__3_n_0),
        .CO({sum_carry__4_n_0,sum_carry__4_n_1,sum_carry__4_n_2,sum_carry__4_n_3}),
        .CYINIT(1'b0),
        .DI({sum_carry__4_i_1_n_0,s0_axis_tdata[26:24]}),
        .O(p_0_in[23:20]),
        .S({sum_carry__4_i_2_n_0,sum_carry__4_i_3_n_0,sum_carry__4_i_4_n_0,sum_carry__4_i_5_n_0}));
  LUT1 #(
    .INIT(2'h1)) 
    sum_carry__4_i_1
       (.I0(s0_axis_tdata[27]),
        .O(sum_carry__4_i_1_n_0));
  LUT4 #(
    .INIT(16'h569A)) 
    sum_carry__4_i_2
       (.I0(s0_axis_tdata[27]),
        .I1(s1_axis_tvalid),
        .I2(last_ram_audio[23]),
        .I3(s1_axis_tdata[23]),
        .O(sum_carry__4_i_2_n_0));
  LUT4 #(
    .INIT(16'h569A)) 
    sum_carry__4_i_3
       (.I0(s0_axis_tdata[26]),
        .I1(s1_axis_tvalid),
        .I2(last_ram_audio[22]),
        .I3(s1_axis_tdata[22]),
        .O(sum_carry__4_i_3_n_0));
  LUT4 #(
    .INIT(16'h569A)) 
    sum_carry__4_i_4
       (.I0(s0_axis_tdata[25]),
        .I1(s1_axis_tvalid),
        .I2(last_ram_audio[21]),
        .I3(s1_axis_tdata[21]),
        .O(sum_carry__4_i_4_n_0));
  LUT4 #(
    .INIT(16'h569A)) 
    sum_carry__4_i_5
       (.I0(s0_axis_tdata[24]),
        .I1(s1_axis_tvalid),
        .I2(last_ram_audio[20]),
        .I3(s1_axis_tdata[20]),
        .O(sum_carry__4_i_5_n_0));
  LUT4 #(
    .INIT(16'h569A)) 
    sum_carry_i_1
       (.I0(s0_axis_tdata[7]),
        .I1(s1_axis_tvalid),
        .I2(last_ram_audio[3]),
        .I3(s1_axis_tdata[3]),
        .O(sum_carry_i_1_n_0));
  LUT4 #(
    .INIT(16'h569A)) 
    sum_carry_i_2
       (.I0(s0_axis_tdata[6]),
        .I1(s1_axis_tvalid),
        .I2(last_ram_audio[2]),
        .I3(s1_axis_tdata[2]),
        .O(sum_carry_i_2_n_0));
  LUT4 #(
    .INIT(16'h569A)) 
    sum_carry_i_3
       (.I0(s0_axis_tdata[5]),
        .I1(s1_axis_tvalid),
        .I2(last_ram_audio[1]),
        .I3(s1_axis_tdata[1]),
        .O(sum_carry_i_3_n_0));
  LUT4 #(
    .INIT(16'h569A)) 
    sum_carry_i_4
       (.I0(s0_axis_tdata[4]),
        .I1(s1_axis_tvalid),
        .I2(last_ram_audio[0]),
        .I3(s1_axis_tdata[0]),
        .O(sum_carry_i_4_n_0));
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
