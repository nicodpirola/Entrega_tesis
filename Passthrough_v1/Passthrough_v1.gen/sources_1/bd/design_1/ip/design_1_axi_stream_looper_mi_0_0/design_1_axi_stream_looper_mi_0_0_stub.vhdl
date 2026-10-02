-- Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
-- Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2025.1 (win64) Build 6140274 Thu May 22 00:12:29 MDT 2025
-- Date        : Fri Sep 18 20:02:33 2026
-- Host        : DESKTOP-FLN9N0C running 64-bit major release  (build 9200)
-- Command     : write_vhdl -force -mode synth_stub
--               x:/Tesis/Passthrough_v1/Passthrough_v1.gen/sources_1/bd/design_1/ip/design_1_axi_stream_looper_mi_0_0/design_1_axi_stream_looper_mi_0_0_stub.vhdl
-- Design      : design_1_axi_stream_looper_mi_0_0
-- Purpose     : Stub declaration of top-level module interface
-- Device      : xc7z020clg400-1
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity design_1_axi_stream_looper_mi_0_0 is
  Port ( 
    clk : in STD_LOGIC;
    resetn : in STD_LOGIC;
    mode : in STD_LOGIC_VECTOR ( 1 downto 0 );
    s0_axis_tdata : in STD_LOGIC_VECTOR ( 31 downto 0 );
    s0_axis_tvalid : in STD_LOGIC;
    s0_axis_tlast : in STD_LOGIC;
    s0_axis_tid : in STD_LOGIC_VECTOR ( 2 downto 0 );
    s0_axis_tkeep : in STD_LOGIC_VECTOR ( 3 downto 0 );
    s0_axis_tready : out STD_LOGIC;
    s1_axis_tdata : in STD_LOGIC_VECTOR ( 31 downto 0 );
    s1_axis_tvalid : in STD_LOGIC;
    s1_axis_tlast : in STD_LOGIC;
    s1_axis_tid : in STD_LOGIC_VECTOR ( 2 downto 0 );
    s1_axis_tkeep : in STD_LOGIC_VECTOR ( 3 downto 0 );
    s1_axis_tready : out STD_LOGIC;
    m_i2s_axis_tdata : out STD_LOGIC_VECTOR ( 31 downto 0 );
    m_i2s_axis_tvalid : out STD_LOGIC;
    m_i2s_axis_tlast : out STD_LOGIC;
    m_i2s_axis_tid : out STD_LOGIC_VECTOR ( 2 downto 0 );
    m_i2s_axis_tkeep : out STD_LOGIC_VECTOR ( 3 downto 0 );
    m_i2s_axis_tready : in STD_LOGIC;
    m_dma_axis_tdata : out STD_LOGIC_VECTOR ( 31 downto 0 );
    m_dma_axis_tvalid : out STD_LOGIC;
    m_dma_axis_tlast : out STD_LOGIC;
    m_dma_axis_tid : out STD_LOGIC_VECTOR ( 2 downto 0 );
    m_dma_axis_tkeep : out STD_LOGIC_VECTOR ( 3 downto 0 );
    m_dma_axis_tready : in STD_LOGIC
  );

  attribute CHECK_LICENSE_TYPE : string;
  attribute CHECK_LICENSE_TYPE of design_1_axi_stream_looper_mi_0_0 : entity is "design_1_axi_stream_looper_mi_0_0,axi_stream_looper_mixer,{}";
  attribute CORE_GENERATION_INFO : string;
  attribute CORE_GENERATION_INFO of design_1_axi_stream_looper_mi_0_0 : entity is "design_1_axi_stream_looper_mi_0_0,axi_stream_looper_mixer,{x_ipProduct=Vivado 2025.1,x_ipVendor=xilinx.com,x_ipLibrary=module_ref,x_ipName=axi_stream_looper_mixer,x_ipVersion=1.0,x_ipCoreRevision=1,x_ipLanguage=VERILOG,x_ipSimLanguage=MIXED}";
  attribute DowngradeIPIdentifiedWarnings : string;
  attribute DowngradeIPIdentifiedWarnings of design_1_axi_stream_looper_mi_0_0 : entity is "yes";
  attribute IP_DEFINITION_SOURCE : string;
  attribute IP_DEFINITION_SOURCE of design_1_axi_stream_looper_mi_0_0 : entity is "module_ref";
end design_1_axi_stream_looper_mi_0_0;

architecture stub of design_1_axi_stream_looper_mi_0_0 is
  attribute syn_black_box : boolean;
  attribute black_box_pad_pin : string;
  attribute syn_black_box of stub : architecture is true;
  attribute black_box_pad_pin of stub : architecture is "clk,resetn,mode[1:0],s0_axis_tdata[31:0],s0_axis_tvalid,s0_axis_tlast,s0_axis_tid[2:0],s0_axis_tkeep[3:0],s0_axis_tready,s1_axis_tdata[31:0],s1_axis_tvalid,s1_axis_tlast,s1_axis_tid[2:0],s1_axis_tkeep[3:0],s1_axis_tready,m_i2s_axis_tdata[31:0],m_i2s_axis_tvalid,m_i2s_axis_tlast,m_i2s_axis_tid[2:0],m_i2s_axis_tkeep[3:0],m_i2s_axis_tready,m_dma_axis_tdata[31:0],m_dma_axis_tvalid,m_dma_axis_tlast,m_dma_axis_tid[2:0],m_dma_axis_tkeep[3:0],m_dma_axis_tready";
  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_INFO of clk : signal is "xilinx.com:signal:clock:1.0 clk CLK";
  attribute X_INTERFACE_MODE : string;
  attribute X_INTERFACE_MODE of clk : signal is "slave";
  attribute X_INTERFACE_PARAMETER : string;
  attribute X_INTERFACE_PARAMETER of clk : signal is "XIL_INTERFACENAME clk, ASSOCIATED_BUSIF m_dma_axis:m_i2s_axis:s0_axis:s1_axis, ASSOCIATED_RESET resetn, FREQ_HZ 50000000, FREQ_TOLERANCE_HZ 0, PHASE 0.0, CLK_DOMAIN design_1_processing_system7_0_0_FCLK_CLK0, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of resetn : signal is "xilinx.com:signal:reset:1.0 resetn RST";
  attribute X_INTERFACE_MODE of resetn : signal is "slave";
  attribute X_INTERFACE_PARAMETER of resetn : signal is "XIL_INTERFACENAME resetn, POLARITY ACTIVE_LOW, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of s0_axis_tdata : signal is "xilinx.com:interface:axis:1.0 s0_axis TDATA";
  attribute X_INTERFACE_MODE of s0_axis_tdata : signal is "slave";
  attribute X_INTERFACE_PARAMETER of s0_axis_tdata : signal is "XIL_INTERFACENAME s0_axis, TDATA_NUM_BYTES 4, TDEST_WIDTH 0, TID_WIDTH 3, TUSER_WIDTH 0, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 1, HAS_TLAST 1, FREQ_HZ 50000000, PHASE 0.0, CLK_DOMAIN design_1_processing_system7_0_0_FCLK_CLK0, LAYERED_METADATA undef, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of s0_axis_tvalid : signal is "xilinx.com:interface:axis:1.0 s0_axis TVALID";
  attribute X_INTERFACE_INFO of s0_axis_tlast : signal is "xilinx.com:interface:axis:1.0 s0_axis TLAST";
  attribute X_INTERFACE_INFO of s0_axis_tid : signal is "xilinx.com:interface:axis:1.0 s0_axis TID";
  attribute X_INTERFACE_INFO of s0_axis_tkeep : signal is "xilinx.com:interface:axis:1.0 s0_axis TKEEP";
  attribute X_INTERFACE_INFO of s0_axis_tready : signal is "xilinx.com:interface:axis:1.0 s0_axis TREADY";
  attribute X_INTERFACE_INFO of s1_axis_tdata : signal is "xilinx.com:interface:axis:1.0 s1_axis TDATA";
  attribute X_INTERFACE_MODE of s1_axis_tdata : signal is "slave";
  attribute X_INTERFACE_PARAMETER of s1_axis_tdata : signal is "XIL_INTERFACENAME s1_axis, TDATA_NUM_BYTES 4, TDEST_WIDTH 0, TID_WIDTH 3, TUSER_WIDTH 0, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 1, HAS_TLAST 1, FREQ_HZ 50000000, PHASE 0.0, CLK_DOMAIN design_1_processing_system7_0_0_FCLK_CLK0, LAYERED_METADATA undef, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of s1_axis_tvalid : signal is "xilinx.com:interface:axis:1.0 s1_axis TVALID";
  attribute X_INTERFACE_INFO of s1_axis_tlast : signal is "xilinx.com:interface:axis:1.0 s1_axis TLAST";
  attribute X_INTERFACE_INFO of s1_axis_tid : signal is "xilinx.com:interface:axis:1.0 s1_axis TID";
  attribute X_INTERFACE_INFO of s1_axis_tkeep : signal is "xilinx.com:interface:axis:1.0 s1_axis TKEEP";
  attribute X_INTERFACE_INFO of s1_axis_tready : signal is "xilinx.com:interface:axis:1.0 s1_axis TREADY";
  attribute X_INTERFACE_INFO of m_i2s_axis_tdata : signal is "xilinx.com:interface:axis:1.0 m_i2s_axis TDATA";
  attribute X_INTERFACE_MODE of m_i2s_axis_tdata : signal is "master";
  attribute X_INTERFACE_PARAMETER of m_i2s_axis_tdata : signal is "XIL_INTERFACENAME m_i2s_axis, TDATA_NUM_BYTES 4, TDEST_WIDTH 0, TID_WIDTH 3, TUSER_WIDTH 0, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 1, HAS_TLAST 1, FREQ_HZ 50000000, PHASE 0.0, CLK_DOMAIN design_1_processing_system7_0_0_FCLK_CLK0, LAYERED_METADATA undef, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of m_i2s_axis_tvalid : signal is "xilinx.com:interface:axis:1.0 m_i2s_axis TVALID";
  attribute X_INTERFACE_INFO of m_i2s_axis_tlast : signal is "xilinx.com:interface:axis:1.0 m_i2s_axis TLAST";
  attribute X_INTERFACE_INFO of m_i2s_axis_tid : signal is "xilinx.com:interface:axis:1.0 m_i2s_axis TID";
  attribute X_INTERFACE_INFO of m_i2s_axis_tkeep : signal is "xilinx.com:interface:axis:1.0 m_i2s_axis TKEEP";
  attribute X_INTERFACE_INFO of m_i2s_axis_tready : signal is "xilinx.com:interface:axis:1.0 m_i2s_axis TREADY";
  attribute X_INTERFACE_INFO of m_dma_axis_tdata : signal is "xilinx.com:interface:axis:1.0 m_dma_axis TDATA";
  attribute X_INTERFACE_MODE of m_dma_axis_tdata : signal is "master";
  attribute X_INTERFACE_PARAMETER of m_dma_axis_tdata : signal is "XIL_INTERFACENAME m_dma_axis, TDATA_NUM_BYTES 4, TDEST_WIDTH 0, TID_WIDTH 3, TUSER_WIDTH 0, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 1, HAS_TLAST 1, FREQ_HZ 50000000, PHASE 0.0, CLK_DOMAIN design_1_processing_system7_0_0_FCLK_CLK0, LAYERED_METADATA undef, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of m_dma_axis_tvalid : signal is "xilinx.com:interface:axis:1.0 m_dma_axis TVALID";
  attribute X_INTERFACE_INFO of m_dma_axis_tlast : signal is "xilinx.com:interface:axis:1.0 m_dma_axis TLAST";
  attribute X_INTERFACE_INFO of m_dma_axis_tid : signal is "xilinx.com:interface:axis:1.0 m_dma_axis TID";
  attribute X_INTERFACE_INFO of m_dma_axis_tkeep : signal is "xilinx.com:interface:axis:1.0 m_dma_axis TKEEP";
  attribute X_INTERFACE_INFO of m_dma_axis_tready : signal is "xilinx.com:interface:axis:1.0 m_dma_axis TREADY";
  attribute X_CORE_INFO : string;
  attribute X_CORE_INFO of stub : architecture is "axi_stream_looper_mixer,Vivado 2025.1";
begin
end;
