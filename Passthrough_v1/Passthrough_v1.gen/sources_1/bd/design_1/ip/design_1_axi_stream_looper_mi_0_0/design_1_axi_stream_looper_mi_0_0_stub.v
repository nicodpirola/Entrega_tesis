// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2025.1 (win64) Build 6140274 Thu May 22 00:12:29 MDT 2025
// Date        : Fri Sep 18 20:02:33 2026
// Host        : DESKTOP-FLN9N0C running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               x:/Tesis/Passthrough_v1/Passthrough_v1.gen/sources_1/bd/design_1/ip/design_1_axi_stream_looper_mi_0_0/design_1_axi_stream_looper_mi_0_0_stub.v
// Design      : design_1_axi_stream_looper_mi_0_0
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7z020clg400-1
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* CHECK_LICENSE_TYPE = "design_1_axi_stream_looper_mi_0_0,axi_stream_looper_mixer,{}" *) (* CORE_GENERATION_INFO = "design_1_axi_stream_looper_mi_0_0,axi_stream_looper_mixer,{x_ipProduct=Vivado 2025.1,x_ipVendor=xilinx.com,x_ipLibrary=module_ref,x_ipName=axi_stream_looper_mixer,x_ipVersion=1.0,x_ipCoreRevision=1,x_ipLanguage=VERILOG,x_ipSimLanguage=MIXED}" *) (* DowngradeIPIdentifiedWarnings = "yes" *) 
(* IP_DEFINITION_SOURCE = "module_ref" *) (* X_CORE_INFO = "axi_stream_looper_mixer,Vivado 2025.1" *) 
module design_1_axi_stream_looper_mi_0_0(clk, resetn, mode, s0_axis_tdata, s0_axis_tvalid, 
  s0_axis_tlast, s0_axis_tid, s0_axis_tkeep, s0_axis_tready, s1_axis_tdata, s1_axis_tvalid, 
  s1_axis_tlast, s1_axis_tid, s1_axis_tkeep, s1_axis_tready, m_i2s_axis_tdata, 
  m_i2s_axis_tvalid, m_i2s_axis_tlast, m_i2s_axis_tid, m_i2s_axis_tkeep, m_i2s_axis_tready, 
  m_dma_axis_tdata, m_dma_axis_tvalid, m_dma_axis_tlast, m_dma_axis_tid, m_dma_axis_tkeep, 
  m_dma_axis_tready)
/* synthesis syn_black_box black_box_pad_pin="resetn,mode[1:0],s0_axis_tdata[31:0],s0_axis_tvalid,s0_axis_tlast,s0_axis_tid[2:0],s0_axis_tkeep[3:0],s0_axis_tready,s1_axis_tdata[31:0],s1_axis_tvalid,s1_axis_tlast,s1_axis_tid[2:0],s1_axis_tkeep[3:0],s1_axis_tready,m_i2s_axis_tdata[31:0],m_i2s_axis_tvalid,m_i2s_axis_tlast,m_i2s_axis_tid[2:0],m_i2s_axis_tkeep[3:0],m_i2s_axis_tready,m_dma_axis_tdata[31:0],m_dma_axis_tvalid,m_dma_axis_tlast,m_dma_axis_tid[2:0],m_dma_axis_tkeep[3:0],m_dma_axis_tready" */
/* synthesis syn_force_seq_prim="clk" */;
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *) (* X_INTERFACE_MODE = "slave" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME clk, ASSOCIATED_BUSIF m_dma_axis:m_i2s_axis:s0_axis:s1_axis, ASSOCIATED_RESET resetn, FREQ_HZ 50000000, FREQ_TOLERANCE_HZ 0, PHASE 0.0, CLK_DOMAIN design_1_processing_system7_0_0_FCLK_CLK0, INSERT_VIP 0" *) input clk /* synthesis syn_isclock = 1 */;
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
endmodule
