-- Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
-- Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2025.1 (win64) Build 6140274 Thu May 22 00:12:29 MDT 2025
-- Date        : Fri Sep 18 20:02:33 2026
-- Host        : DESKTOP-FLN9N0C running 64-bit major release  (build 9200)
-- Command     : write_vhdl -force -mode funcsim
--               x:/Tesis/Passthrough_v1/Passthrough_v1.gen/sources_1/bd/design_1/ip/design_1_axis_tlast_gen_trans_0_0/design_1_axis_tlast_gen_trans_0_0_sim_netlist.vhdl
-- Design      : design_1_axis_tlast_gen_trans_0_0
-- Purpose     : This VHDL netlist is a functional simulation representation of the design and should not be modified or
--               synthesized. This netlist cannot be used for SDF annotated simulation.
-- Device      : xc7z020clg400-1
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library UNISIM;
use UNISIM.VCOMPONENTS.ALL;
entity design_1_axis_tlast_gen_trans_0_0_axis_tlast_gen_transparent is
  port (
    m_axis_tlast : out STD_LOGIC;
    resetn : in STD_LOGIC;
    clk : in STD_LOGIC;
    s_axis_tvalid : in STD_LOGIC;
    m_axis_tready : in STD_LOGIC
  );
  attribute ORIG_REF_NAME : string;
  attribute ORIG_REF_NAME of design_1_axis_tlast_gen_trans_0_0_axis_tlast_gen_transparent : entity is "axis_tlast_gen_transparent";
end design_1_axis_tlast_gen_trans_0_0_axis_tlast_gen_transparent;

architecture STRUCTURE of design_1_axis_tlast_gen_trans_0_0_axis_tlast_gen_transparent is
  signal \count_reg[0]_i_1_n_0\ : STD_LOGIC;
  signal \count_reg[0]_i_2_n_0\ : STD_LOGIC;
  signal \count_reg[0]_i_4_n_0\ : STD_LOGIC;
  signal count_reg_reg : STD_LOGIC_VECTOR ( 15 downto 0 );
  signal \count_reg_reg[0]_i_3_n_0\ : STD_LOGIC;
  signal \count_reg_reg[0]_i_3_n_1\ : STD_LOGIC;
  signal \count_reg_reg[0]_i_3_n_2\ : STD_LOGIC;
  signal \count_reg_reg[0]_i_3_n_3\ : STD_LOGIC;
  signal \count_reg_reg[0]_i_3_n_4\ : STD_LOGIC;
  signal \count_reg_reg[0]_i_3_n_5\ : STD_LOGIC;
  signal \count_reg_reg[0]_i_3_n_6\ : STD_LOGIC;
  signal \count_reg_reg[0]_i_3_n_7\ : STD_LOGIC;
  signal \count_reg_reg[12]_i_1_n_1\ : STD_LOGIC;
  signal \count_reg_reg[12]_i_1_n_2\ : STD_LOGIC;
  signal \count_reg_reg[12]_i_1_n_3\ : STD_LOGIC;
  signal \count_reg_reg[12]_i_1_n_4\ : STD_LOGIC;
  signal \count_reg_reg[12]_i_1_n_5\ : STD_LOGIC;
  signal \count_reg_reg[12]_i_1_n_6\ : STD_LOGIC;
  signal \count_reg_reg[12]_i_1_n_7\ : STD_LOGIC;
  signal \count_reg_reg[4]_i_1_n_0\ : STD_LOGIC;
  signal \count_reg_reg[4]_i_1_n_1\ : STD_LOGIC;
  signal \count_reg_reg[4]_i_1_n_2\ : STD_LOGIC;
  signal \count_reg_reg[4]_i_1_n_3\ : STD_LOGIC;
  signal \count_reg_reg[4]_i_1_n_4\ : STD_LOGIC;
  signal \count_reg_reg[4]_i_1_n_5\ : STD_LOGIC;
  signal \count_reg_reg[4]_i_1_n_6\ : STD_LOGIC;
  signal \count_reg_reg[4]_i_1_n_7\ : STD_LOGIC;
  signal \count_reg_reg[8]_i_1_n_0\ : STD_LOGIC;
  signal \count_reg_reg[8]_i_1_n_1\ : STD_LOGIC;
  signal \count_reg_reg[8]_i_1_n_2\ : STD_LOGIC;
  signal \count_reg_reg[8]_i_1_n_3\ : STD_LOGIC;
  signal \count_reg_reg[8]_i_1_n_4\ : STD_LOGIC;
  signal \count_reg_reg[8]_i_1_n_5\ : STD_LOGIC;
  signal \count_reg_reg[8]_i_1_n_6\ : STD_LOGIC;
  signal \count_reg_reg[8]_i_1_n_7\ : STD_LOGIC;
  signal m_axis_tlast_INST_0_i_1_n_0 : STD_LOGIC;
  signal m_axis_tlast_INST_0_i_2_n_0 : STD_LOGIC;
  signal m_axis_tlast_INST_0_i_3_n_0 : STD_LOGIC;
  signal m_axis_tlast_INST_0_i_4_n_0 : STD_LOGIC;
  signal \NLW_count_reg_reg[12]_i_1_CO_UNCONNECTED\ : STD_LOGIC_VECTOR ( 3 to 3 );
  attribute ADDER_THRESHOLD : integer;
  attribute ADDER_THRESHOLD of \count_reg_reg[0]_i_3\ : label is 11;
  attribute ADDER_THRESHOLD of \count_reg_reg[12]_i_1\ : label is 11;
  attribute ADDER_THRESHOLD of \count_reg_reg[4]_i_1\ : label is 11;
  attribute ADDER_THRESHOLD of \count_reg_reg[8]_i_1\ : label is 11;
begin
\count_reg[0]_i_1\: unisim.vcomponents.LUT6
    generic map(
      INIT => X"40000000FFFFFFFF"
    )
        port map (
      I0 => m_axis_tlast_INST_0_i_1_n_0,
      I1 => m_axis_tlast_INST_0_i_2_n_0,
      I2 => m_axis_tlast_INST_0_i_3_n_0,
      I3 => m_axis_tlast_INST_0_i_4_n_0,
      I4 => \count_reg[0]_i_2_n_0\,
      I5 => resetn,
      O => \count_reg[0]_i_1_n_0\
    );
\count_reg[0]_i_2\: unisim.vcomponents.LUT2
    generic map(
      INIT => X"8"
    )
        port map (
      I0 => s_axis_tvalid,
      I1 => m_axis_tready,
      O => \count_reg[0]_i_2_n_0\
    );
\count_reg[0]_i_4\: unisim.vcomponents.LUT1
    generic map(
      INIT => X"1"
    )
        port map (
      I0 => count_reg_reg(0),
      O => \count_reg[0]_i_4_n_0\
    );
\count_reg_reg[0]\: unisim.vcomponents.FDRE
     port map (
      C => clk,
      CE => \count_reg[0]_i_2_n_0\,
      D => \count_reg_reg[0]_i_3_n_7\,
      Q => count_reg_reg(0),
      R => \count_reg[0]_i_1_n_0\
    );
\count_reg_reg[0]_i_3\: unisim.vcomponents.CARRY4
     port map (
      CI => '0',
      CO(3) => \count_reg_reg[0]_i_3_n_0\,
      CO(2) => \count_reg_reg[0]_i_3_n_1\,
      CO(1) => \count_reg_reg[0]_i_3_n_2\,
      CO(0) => \count_reg_reg[0]_i_3_n_3\,
      CYINIT => '0',
      DI(3 downto 0) => B"0001",
      O(3) => \count_reg_reg[0]_i_3_n_4\,
      O(2) => \count_reg_reg[0]_i_3_n_5\,
      O(1) => \count_reg_reg[0]_i_3_n_6\,
      O(0) => \count_reg_reg[0]_i_3_n_7\,
      S(3 downto 1) => count_reg_reg(3 downto 1),
      S(0) => \count_reg[0]_i_4_n_0\
    );
\count_reg_reg[10]\: unisim.vcomponents.FDRE
     port map (
      C => clk,
      CE => \count_reg[0]_i_2_n_0\,
      D => \count_reg_reg[8]_i_1_n_5\,
      Q => count_reg_reg(10),
      R => \count_reg[0]_i_1_n_0\
    );
\count_reg_reg[11]\: unisim.vcomponents.FDRE
     port map (
      C => clk,
      CE => \count_reg[0]_i_2_n_0\,
      D => \count_reg_reg[8]_i_1_n_4\,
      Q => count_reg_reg(11),
      R => \count_reg[0]_i_1_n_0\
    );
\count_reg_reg[12]\: unisim.vcomponents.FDRE
     port map (
      C => clk,
      CE => \count_reg[0]_i_2_n_0\,
      D => \count_reg_reg[12]_i_1_n_7\,
      Q => count_reg_reg(12),
      R => \count_reg[0]_i_1_n_0\
    );
\count_reg_reg[12]_i_1\: unisim.vcomponents.CARRY4
     port map (
      CI => \count_reg_reg[8]_i_1_n_0\,
      CO(3) => \NLW_count_reg_reg[12]_i_1_CO_UNCONNECTED\(3),
      CO(2) => \count_reg_reg[12]_i_1_n_1\,
      CO(1) => \count_reg_reg[12]_i_1_n_2\,
      CO(0) => \count_reg_reg[12]_i_1_n_3\,
      CYINIT => '0',
      DI(3 downto 0) => B"0000",
      O(3) => \count_reg_reg[12]_i_1_n_4\,
      O(2) => \count_reg_reg[12]_i_1_n_5\,
      O(1) => \count_reg_reg[12]_i_1_n_6\,
      O(0) => \count_reg_reg[12]_i_1_n_7\,
      S(3 downto 0) => count_reg_reg(15 downto 12)
    );
\count_reg_reg[13]\: unisim.vcomponents.FDRE
     port map (
      C => clk,
      CE => \count_reg[0]_i_2_n_0\,
      D => \count_reg_reg[12]_i_1_n_6\,
      Q => count_reg_reg(13),
      R => \count_reg[0]_i_1_n_0\
    );
\count_reg_reg[14]\: unisim.vcomponents.FDRE
     port map (
      C => clk,
      CE => \count_reg[0]_i_2_n_0\,
      D => \count_reg_reg[12]_i_1_n_5\,
      Q => count_reg_reg(14),
      R => \count_reg[0]_i_1_n_0\
    );
\count_reg_reg[15]\: unisim.vcomponents.FDRE
     port map (
      C => clk,
      CE => \count_reg[0]_i_2_n_0\,
      D => \count_reg_reg[12]_i_1_n_4\,
      Q => count_reg_reg(15),
      R => \count_reg[0]_i_1_n_0\
    );
\count_reg_reg[1]\: unisim.vcomponents.FDRE
     port map (
      C => clk,
      CE => \count_reg[0]_i_2_n_0\,
      D => \count_reg_reg[0]_i_3_n_6\,
      Q => count_reg_reg(1),
      R => \count_reg[0]_i_1_n_0\
    );
\count_reg_reg[2]\: unisim.vcomponents.FDRE
     port map (
      C => clk,
      CE => \count_reg[0]_i_2_n_0\,
      D => \count_reg_reg[0]_i_3_n_5\,
      Q => count_reg_reg(2),
      R => \count_reg[0]_i_1_n_0\
    );
\count_reg_reg[3]\: unisim.vcomponents.FDRE
     port map (
      C => clk,
      CE => \count_reg[0]_i_2_n_0\,
      D => \count_reg_reg[0]_i_3_n_4\,
      Q => count_reg_reg(3),
      R => \count_reg[0]_i_1_n_0\
    );
\count_reg_reg[4]\: unisim.vcomponents.FDRE
     port map (
      C => clk,
      CE => \count_reg[0]_i_2_n_0\,
      D => \count_reg_reg[4]_i_1_n_7\,
      Q => count_reg_reg(4),
      R => \count_reg[0]_i_1_n_0\
    );
\count_reg_reg[4]_i_1\: unisim.vcomponents.CARRY4
     port map (
      CI => \count_reg_reg[0]_i_3_n_0\,
      CO(3) => \count_reg_reg[4]_i_1_n_0\,
      CO(2) => \count_reg_reg[4]_i_1_n_1\,
      CO(1) => \count_reg_reg[4]_i_1_n_2\,
      CO(0) => \count_reg_reg[4]_i_1_n_3\,
      CYINIT => '0',
      DI(3 downto 0) => B"0000",
      O(3) => \count_reg_reg[4]_i_1_n_4\,
      O(2) => \count_reg_reg[4]_i_1_n_5\,
      O(1) => \count_reg_reg[4]_i_1_n_6\,
      O(0) => \count_reg_reg[4]_i_1_n_7\,
      S(3 downto 0) => count_reg_reg(7 downto 4)
    );
\count_reg_reg[5]\: unisim.vcomponents.FDRE
     port map (
      C => clk,
      CE => \count_reg[0]_i_2_n_0\,
      D => \count_reg_reg[4]_i_1_n_6\,
      Q => count_reg_reg(5),
      R => \count_reg[0]_i_1_n_0\
    );
\count_reg_reg[6]\: unisim.vcomponents.FDRE
     port map (
      C => clk,
      CE => \count_reg[0]_i_2_n_0\,
      D => \count_reg_reg[4]_i_1_n_5\,
      Q => count_reg_reg(6),
      R => \count_reg[0]_i_1_n_0\
    );
\count_reg_reg[7]\: unisim.vcomponents.FDRE
     port map (
      C => clk,
      CE => \count_reg[0]_i_2_n_0\,
      D => \count_reg_reg[4]_i_1_n_4\,
      Q => count_reg_reg(7),
      R => \count_reg[0]_i_1_n_0\
    );
\count_reg_reg[8]\: unisim.vcomponents.FDRE
     port map (
      C => clk,
      CE => \count_reg[0]_i_2_n_0\,
      D => \count_reg_reg[8]_i_1_n_7\,
      Q => count_reg_reg(8),
      R => \count_reg[0]_i_1_n_0\
    );
\count_reg_reg[8]_i_1\: unisim.vcomponents.CARRY4
     port map (
      CI => \count_reg_reg[4]_i_1_n_0\,
      CO(3) => \count_reg_reg[8]_i_1_n_0\,
      CO(2) => \count_reg_reg[8]_i_1_n_1\,
      CO(1) => \count_reg_reg[8]_i_1_n_2\,
      CO(0) => \count_reg_reg[8]_i_1_n_3\,
      CYINIT => '0',
      DI(3 downto 0) => B"0000",
      O(3) => \count_reg_reg[8]_i_1_n_4\,
      O(2) => \count_reg_reg[8]_i_1_n_5\,
      O(1) => \count_reg_reg[8]_i_1_n_6\,
      O(0) => \count_reg_reg[8]_i_1_n_7\,
      S(3 downto 0) => count_reg_reg(11 downto 8)
    );
\count_reg_reg[9]\: unisim.vcomponents.FDRE
     port map (
      C => clk,
      CE => \count_reg[0]_i_2_n_0\,
      D => \count_reg_reg[8]_i_1_n_6\,
      Q => count_reg_reg(9),
      R => \count_reg[0]_i_1_n_0\
    );
m_axis_tlast_INST_0: unisim.vcomponents.LUT4
    generic map(
      INIT => X"4000"
    )
        port map (
      I0 => m_axis_tlast_INST_0_i_1_n_0,
      I1 => m_axis_tlast_INST_0_i_2_n_0,
      I2 => m_axis_tlast_INST_0_i_3_n_0,
      I3 => m_axis_tlast_INST_0_i_4_n_0,
      O => m_axis_tlast
    );
m_axis_tlast_INST_0_i_1: unisim.vcomponents.LUT4
    generic map(
      INIT => X"FFFB"
    )
        port map (
      I0 => count_reg_reg(9),
      I1 => count_reg_reg(8),
      I2 => count_reg_reg(11),
      I3 => count_reg_reg(10),
      O => m_axis_tlast_INST_0_i_1_n_0
    );
m_axis_tlast_INST_0_i_2: unisim.vcomponents.LUT4
    generic map(
      INIT => X"0001"
    )
        port map (
      I0 => count_reg_reg(14),
      I1 => count_reg_reg(15),
      I2 => count_reg_reg(13),
      I3 => count_reg_reg(12),
      O => m_axis_tlast_INST_0_i_2_n_0
    );
m_axis_tlast_INST_0_i_3: unisim.vcomponents.LUT4
    generic map(
      INIT => X"8000"
    )
        port map (
      I0 => count_reg_reg(5),
      I1 => count_reg_reg(4),
      I2 => count_reg_reg(7),
      I3 => count_reg_reg(6),
      O => m_axis_tlast_INST_0_i_3_n_0
    );
m_axis_tlast_INST_0_i_4: unisim.vcomponents.LUT4
    generic map(
      INIT => X"8000"
    )
        port map (
      I0 => count_reg_reg(1),
      I1 => count_reg_reg(0),
      I2 => count_reg_reg(3),
      I3 => count_reg_reg(2),
      O => m_axis_tlast_INST_0_i_4_n_0
    );
end STRUCTURE;
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library UNISIM;
use UNISIM.VCOMPONENTS.ALL;
entity design_1_axis_tlast_gen_trans_0_0 is
  port (
    clk : in STD_LOGIC;
    resetn : in STD_LOGIC;
    s_axis_tdata : in STD_LOGIC_VECTOR ( 31 downto 0 );
    s_axis_tvalid : in STD_LOGIC;
    s_axis_tready : out STD_LOGIC;
    m_axis_tdata : out STD_LOGIC_VECTOR ( 31 downto 0 );
    m_axis_tvalid : out STD_LOGIC;
    m_axis_tlast : out STD_LOGIC;
    m_axis_tready : in STD_LOGIC
  );
  attribute NotValidForBitStream : boolean;
  attribute NotValidForBitStream of design_1_axis_tlast_gen_trans_0_0 : entity is true;
  attribute CHECK_LICENSE_TYPE : string;
  attribute CHECK_LICENSE_TYPE of design_1_axis_tlast_gen_trans_0_0 : entity is "design_1_axis_tlast_gen_trans_0_0,axis_tlast_gen_transparent,{}";
  attribute DowngradeIPIdentifiedWarnings : string;
  attribute DowngradeIPIdentifiedWarnings of design_1_axis_tlast_gen_trans_0_0 : entity is "yes";
  attribute IP_DEFINITION_SOURCE : string;
  attribute IP_DEFINITION_SOURCE of design_1_axis_tlast_gen_trans_0_0 : entity is "module_ref";
  attribute X_CORE_INFO : string;
  attribute X_CORE_INFO of design_1_axis_tlast_gen_trans_0_0 : entity is "axis_tlast_gen_transparent,Vivado 2025.1";
end design_1_axis_tlast_gen_trans_0_0;

architecture STRUCTURE of design_1_axis_tlast_gen_trans_0_0 is
  signal \^m_axis_tready\ : STD_LOGIC;
  signal \^s_axis_tdata\ : STD_LOGIC_VECTOR ( 31 downto 0 );
  signal \^s_axis_tvalid\ : STD_LOGIC;
  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_INFO of clk : signal is "xilinx.com:signal:clock:1.0 clk CLK";
  attribute X_INTERFACE_MODE : string;
  attribute X_INTERFACE_MODE of clk : signal is "slave";
  attribute X_INTERFACE_PARAMETER : string;
  attribute X_INTERFACE_PARAMETER of clk : signal is "XIL_INTERFACENAME clk, ASSOCIATED_BUSIF m_axis:s_axis, ASSOCIATED_RESET resetn, FREQ_HZ 50000000, FREQ_TOLERANCE_HZ 0, PHASE 0.0, CLK_DOMAIN design_1_processing_system7_0_0_FCLK_CLK0, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of m_axis_tlast : signal is "xilinx.com:interface:axis:1.0 m_axis TLAST";
  attribute X_INTERFACE_INFO of m_axis_tready : signal is "xilinx.com:interface:axis:1.0 m_axis TREADY";
  attribute X_INTERFACE_INFO of m_axis_tvalid : signal is "xilinx.com:interface:axis:1.0 m_axis TVALID";
  attribute X_INTERFACE_INFO of resetn : signal is "xilinx.com:signal:reset:1.0 resetn RST";
  attribute X_INTERFACE_MODE of resetn : signal is "slave";
  attribute X_INTERFACE_PARAMETER of resetn : signal is "XIL_INTERFACENAME resetn, POLARITY ACTIVE_LOW, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of s_axis_tready : signal is "xilinx.com:interface:axis:1.0 s_axis TREADY";
  attribute X_INTERFACE_INFO of s_axis_tvalid : signal is "xilinx.com:interface:axis:1.0 s_axis TVALID";
  attribute X_INTERFACE_INFO of m_axis_tdata : signal is "xilinx.com:interface:axis:1.0 m_axis TDATA";
  attribute X_INTERFACE_MODE of m_axis_tdata : signal is "master";
  attribute X_INTERFACE_PARAMETER of m_axis_tdata : signal is "XIL_INTERFACENAME m_axis, TDATA_NUM_BYTES 4, TDEST_WIDTH 0, TID_WIDTH 0, TUSER_WIDTH 0, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 0, HAS_TLAST 1, FREQ_HZ 50000000, PHASE 0.0, CLK_DOMAIN design_1_processing_system7_0_0_FCLK_CLK0, LAYERED_METADATA undef, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of s_axis_tdata : signal is "xilinx.com:interface:axis:1.0 s_axis TDATA";
  attribute X_INTERFACE_MODE of s_axis_tdata : signal is "slave";
  attribute X_INTERFACE_PARAMETER of s_axis_tdata : signal is "XIL_INTERFACENAME s_axis, TDATA_NUM_BYTES 4, TDEST_WIDTH 0, TID_WIDTH 0, TUSER_WIDTH 0, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 0, HAS_TLAST 0, FREQ_HZ 50000000, PHASE 0.0, CLK_DOMAIN design_1_processing_system7_0_0_FCLK_CLK0, LAYERED_METADATA undef, INSERT_VIP 0";
begin
  \^m_axis_tready\ <= m_axis_tready;
  \^s_axis_tdata\(31 downto 0) <= s_axis_tdata(31 downto 0);
  \^s_axis_tvalid\ <= s_axis_tvalid;
  m_axis_tdata(31 downto 0) <= \^s_axis_tdata\(31 downto 0);
  m_axis_tvalid <= \^s_axis_tvalid\;
  s_axis_tready <= \^m_axis_tready\;
inst: entity work.design_1_axis_tlast_gen_trans_0_0_axis_tlast_gen_transparent
     port map (
      clk => clk,
      m_axis_tlast => m_axis_tlast,
      m_axis_tready => \^m_axis_tready\,
      resetn => resetn,
      s_axis_tvalid => \^s_axis_tvalid\
    );
end STRUCTURE;
