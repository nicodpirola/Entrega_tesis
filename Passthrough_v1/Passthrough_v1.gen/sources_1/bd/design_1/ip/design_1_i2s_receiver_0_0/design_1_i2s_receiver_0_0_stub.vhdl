-- Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
-- Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2025.1 (win64) Build 6140274 Thu May 22 00:12:29 MDT 2025
-- Date        : Sat Jun 20 22:13:35 2026
-- Host        : DESKTOP-FLN9N0C running 64-bit major release  (build 9200)
-- Command     : write_vhdl -force -mode synth_stub -rename_top design_1_i2s_receiver_0_0 -prefix
--               design_1_i2s_receiver_0_0_ design_1_i2s_receiver_0_0_stub.vhdl
-- Design      : design_1_i2s_receiver_0_0
-- Purpose     : Stub declaration of top-level module interface
-- Device      : xc7z020clg400-1
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity design_1_i2s_receiver_0_0 is
  Port ( 
    s_axi_ctrl_aclk : in STD_LOGIC;
    s_axi_ctrl_aresetn : in STD_LOGIC;
    aud_mclk : in STD_LOGIC;
    aud_mrst : in STD_LOGIC;
    m_axis_aud_aclk : in STD_LOGIC;
    m_axis_aud_aresetn : in STD_LOGIC;
    s_axi_ctrl_awvalid : in STD_LOGIC;
    s_axi_ctrl_awready : out STD_LOGIC;
    s_axi_ctrl_awaddr : in STD_LOGIC_VECTOR ( 7 downto 0 );
    s_axi_ctrl_wvalid : in STD_LOGIC;
    s_axi_ctrl_wready : out STD_LOGIC;
    s_axi_ctrl_wdata : in STD_LOGIC_VECTOR ( 31 downto 0 );
    s_axi_ctrl_bvalid : out STD_LOGIC;
    s_axi_ctrl_bready : in STD_LOGIC;
    s_axi_ctrl_bresp : out STD_LOGIC_VECTOR ( 1 downto 0 );
    s_axi_ctrl_arvalid : in STD_LOGIC;
    s_axi_ctrl_arready : out STD_LOGIC;
    s_axi_ctrl_araddr : in STD_LOGIC_VECTOR ( 7 downto 0 );
    s_axi_ctrl_rvalid : out STD_LOGIC;
    s_axi_ctrl_rready : in STD_LOGIC;
    s_axi_ctrl_rdata : out STD_LOGIC_VECTOR ( 31 downto 0 );
    s_axi_ctrl_rresp : out STD_LOGIC_VECTOR ( 1 downto 0 );
    irq : out STD_LOGIC;
    lrclk_out : out STD_LOGIC;
    sclk_out : out STD_LOGIC;
    sdata_0_in : in STD_LOGIC;
    m_axis_aud_tdata : out STD_LOGIC_VECTOR ( 31 downto 0 );
    m_axis_aud_tid : out STD_LOGIC_VECTOR ( 2 downto 0 );
    m_axis_aud_tvalid : out STD_LOGIC;
    m_axis_aud_tready : in STD_LOGIC
  );

  attribute CHECK_LICENSE_TYPE : string;
  attribute CHECK_LICENSE_TYPE of design_1_i2s_receiver_0_0 : entity is "design_1_i2s_receiver_0_0,i2s_receiver_v1_0_10,{}";
  attribute CORE_GENERATION_INFO : string;
  attribute CORE_GENERATION_INFO of design_1_i2s_receiver_0_0 : entity is "design_1_i2s_receiver_0_0,i2s_receiver_v1_0_10,{x_ipProduct=Vivado 2025.1,x_ipVendor=xilinx.com,x_ipLibrary=ip,x_ipName=i2s_receiver,x_ipVersion=1.0,x_ipCoreRevision=10,x_ipLanguage=VERILOG,x_ipSimLanguage=MIXED,C_IS_MASTER=1,C_NUM_CHANNELS=1,C_DWIDTH=24,C_32BIT_LR=1,C_DEPTH=128}";
  attribute DowngradeIPIdentifiedWarnings : string;
  attribute DowngradeIPIdentifiedWarnings of design_1_i2s_receiver_0_0 : entity is "yes";
end design_1_i2s_receiver_0_0;

architecture stub of design_1_i2s_receiver_0_0 is
  attribute syn_black_box : boolean;
  attribute black_box_pad_pin : string;
  attribute syn_black_box of stub : architecture is true;
  attribute black_box_pad_pin of stub : architecture is "s_axi_ctrl_aclk,s_axi_ctrl_aresetn,aud_mclk,aud_mrst,m_axis_aud_aclk,m_axis_aud_aresetn,s_axi_ctrl_awvalid,s_axi_ctrl_awready,s_axi_ctrl_awaddr[7:0],s_axi_ctrl_wvalid,s_axi_ctrl_wready,s_axi_ctrl_wdata[31:0],s_axi_ctrl_bvalid,s_axi_ctrl_bready,s_axi_ctrl_bresp[1:0],s_axi_ctrl_arvalid,s_axi_ctrl_arready,s_axi_ctrl_araddr[7:0],s_axi_ctrl_rvalid,s_axi_ctrl_rready,s_axi_ctrl_rdata[31:0],s_axi_ctrl_rresp[1:0],irq,lrclk_out,sclk_out,sdata_0_in,m_axis_aud_tdata[31:0],m_axis_aud_tid[2:0],m_axis_aud_tvalid,m_axis_aud_tready";
  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_INFO of s_axi_ctrl_aclk : signal is "xilinx.com:signal:clock:1.0 s_axi_ctrl_aclk CLK";
  attribute X_INTERFACE_MODE : string;
  attribute X_INTERFACE_MODE of s_axi_ctrl_aclk : signal is "slave";
  attribute X_INTERFACE_PARAMETER : string;
  attribute X_INTERFACE_PARAMETER of s_axi_ctrl_aclk : signal is "XIL_INTERFACENAME s_axi_ctrl_aclk, ASSOCIATED_BUSIF s_axi_ctrl, ASSOCIATED_RESET s_axi_ctrl_aresetn, FREQ_HZ 50000000, FREQ_TOLERANCE_HZ 0, PHASE 0.0, CLK_DOMAIN design_1_processing_system7_0_0_FCLK_CLK0, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of s_axi_ctrl_aresetn : signal is "xilinx.com:signal:reset:1.0 s_axi_ctrl_aresetn RST";
  attribute X_INTERFACE_MODE of s_axi_ctrl_aresetn : signal is "slave";
  attribute X_INTERFACE_PARAMETER of s_axi_ctrl_aresetn : signal is "XIL_INTERFACENAME s_axi_ctrl_aresetn, POLARITY ACTIVE_LOW, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of aud_mclk : signal is "xilinx.com:signal:clock:1.0 aud_mclk CLK";
  attribute X_INTERFACE_MODE of aud_mclk : signal is "slave";
  attribute X_INTERFACE_PARAMETER of aud_mclk : signal is "XIL_INTERFACENAME aud_mclk, ASSOCIATED_RESET aud_mrst, FREQ_HZ 12286002, FREQ_TOLERANCE_HZ 0, PHASE 0.0, CLK_DOMAIN /clk_wiz_0_clk_out1, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of aud_mrst : signal is "xilinx.com:signal:reset:1.0 aud_mrst RST";
  attribute X_INTERFACE_MODE of aud_mrst : signal is "slave";
  attribute X_INTERFACE_PARAMETER of aud_mrst : signal is "XIL_INTERFACENAME aud_mrst, POLARITY ACTIVE_HIGH, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of m_axis_aud_aclk : signal is "xilinx.com:signal:clock:1.0 m_axis_aud_aclk CLK";
  attribute X_INTERFACE_MODE of m_axis_aud_aclk : signal is "slave";
  attribute X_INTERFACE_PARAMETER of m_axis_aud_aclk : signal is "XIL_INTERFACENAME m_axis_aud_aclk, ASSOCIATED_BUSIF m_axis_aud, ASSOCIATED_RESET m_axis_aud_aresetn, FREQ_HZ 50000000, FREQ_TOLERANCE_HZ 0, PHASE 0.0, CLK_DOMAIN design_1_processing_system7_0_0_FCLK_CLK0, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of m_axis_aud_aresetn : signal is "xilinx.com:signal:reset:1.0 m_axis_aud_aresetn RST";
  attribute X_INTERFACE_MODE of m_axis_aud_aresetn : signal is "slave";
  attribute X_INTERFACE_PARAMETER of m_axis_aud_aresetn : signal is "XIL_INTERFACENAME m_axis_aud_aresetn, POLARITY ACTIVE_LOW, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of s_axi_ctrl_awvalid : signal is "xilinx.com:interface:aximm:1.0 s_axi_ctrl AWVALID";
  attribute X_INTERFACE_MODE of s_axi_ctrl_awvalid : signal is "slave";
  attribute X_INTERFACE_PARAMETER of s_axi_ctrl_awvalid : signal is "XIL_INTERFACENAME s_axi_ctrl, DATA_WIDTH 32, PROTOCOL AXI4LITE, FREQ_HZ 50000000, ID_WIDTH 0, ADDR_WIDTH 8, AWUSER_WIDTH 0, ARUSER_WIDTH 0, WUSER_WIDTH 0, RUSER_WIDTH 0, BUSER_WIDTH 0, READ_WRITE_MODE READ_WRITE, HAS_BURST 0, HAS_LOCK 0, HAS_PROT 0, HAS_CACHE 0, HAS_QOS 0, HAS_REGION 0, HAS_WSTRB 0, HAS_BRESP 1, HAS_RRESP 1, SUPPORTS_NARROW_BURST 0, NUM_READ_OUTSTANDING 8, NUM_WRITE_OUTSTANDING 8, MAX_BURST_LENGTH 1, PHASE 0.0, CLK_DOMAIN design_1_processing_system7_0_0_FCLK_CLK0, NUM_READ_THREADS 1, NUM_WRITE_THREADS 1, RUSER_BITS_PER_BYTE 0, WUSER_BITS_PER_BYTE 0, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of s_axi_ctrl_awready : signal is "xilinx.com:interface:aximm:1.0 s_axi_ctrl AWREADY";
  attribute X_INTERFACE_INFO of s_axi_ctrl_awaddr : signal is "xilinx.com:interface:aximm:1.0 s_axi_ctrl AWADDR";
  attribute X_INTERFACE_INFO of s_axi_ctrl_wvalid : signal is "xilinx.com:interface:aximm:1.0 s_axi_ctrl WVALID";
  attribute X_INTERFACE_INFO of s_axi_ctrl_wready : signal is "xilinx.com:interface:aximm:1.0 s_axi_ctrl WREADY";
  attribute X_INTERFACE_INFO of s_axi_ctrl_wdata : signal is "xilinx.com:interface:aximm:1.0 s_axi_ctrl WDATA";
  attribute X_INTERFACE_INFO of s_axi_ctrl_bvalid : signal is "xilinx.com:interface:aximm:1.0 s_axi_ctrl BVALID";
  attribute X_INTERFACE_INFO of s_axi_ctrl_bready : signal is "xilinx.com:interface:aximm:1.0 s_axi_ctrl BREADY";
  attribute X_INTERFACE_INFO of s_axi_ctrl_bresp : signal is "xilinx.com:interface:aximm:1.0 s_axi_ctrl BRESP";
  attribute X_INTERFACE_INFO of s_axi_ctrl_arvalid : signal is "xilinx.com:interface:aximm:1.0 s_axi_ctrl ARVALID";
  attribute X_INTERFACE_INFO of s_axi_ctrl_arready : signal is "xilinx.com:interface:aximm:1.0 s_axi_ctrl ARREADY";
  attribute X_INTERFACE_INFO of s_axi_ctrl_araddr : signal is "xilinx.com:interface:aximm:1.0 s_axi_ctrl ARADDR";
  attribute X_INTERFACE_INFO of s_axi_ctrl_rvalid : signal is "xilinx.com:interface:aximm:1.0 s_axi_ctrl RVALID";
  attribute X_INTERFACE_INFO of s_axi_ctrl_rready : signal is "xilinx.com:interface:aximm:1.0 s_axi_ctrl RREADY";
  attribute X_INTERFACE_INFO of s_axi_ctrl_rdata : signal is "xilinx.com:interface:aximm:1.0 s_axi_ctrl RDATA";
  attribute X_INTERFACE_INFO of s_axi_ctrl_rresp : signal is "xilinx.com:interface:aximm:1.0 s_axi_ctrl RRESP";
  attribute X_INTERFACE_INFO of irq : signal is "xilinx.com:signal:interrupt:1.0 irq INTERRUPT";
  attribute X_INTERFACE_MODE of irq : signal is "master";
  attribute X_INTERFACE_PARAMETER of irq : signal is "XIL_INTERFACENAME irq, SENSITIVITY LEVEL_HIGH, PortWidth 1";
  attribute X_INTERFACE_INFO of m_axis_aud_tdata : signal is "xilinx.com:interface:axis:1.0 m_axis_aud TDATA";
  attribute X_INTERFACE_MODE of m_axis_aud_tdata : signal is "master";
  attribute X_INTERFACE_PARAMETER of m_axis_aud_tdata : signal is "XIL_INTERFACENAME m_axis_aud, TDATA_NUM_BYTES 4, TDEST_WIDTH 0, TID_WIDTH 3, TUSER_WIDTH 0, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 0, HAS_TLAST 0, FREQ_HZ 50000000, PHASE 0.0, CLK_DOMAIN design_1_processing_system7_0_0_FCLK_CLK0, LAYERED_METADATA undef, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of m_axis_aud_tid : signal is "xilinx.com:interface:axis:1.0 m_axis_aud TID";
  attribute X_INTERFACE_INFO of m_axis_aud_tvalid : signal is "xilinx.com:interface:axis:1.0 m_axis_aud TVALID";
  attribute X_INTERFACE_INFO of m_axis_aud_tready : signal is "xilinx.com:interface:axis:1.0 m_axis_aud TREADY";
  attribute X_CORE_INFO : string;
  attribute X_CORE_INFO of stub : architecture is "i2s_receiver_v1_0_10,Vivado 2025.1";
begin
end;
