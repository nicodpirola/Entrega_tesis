-- Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
-- Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2025.1 (win64) Build 6140274 Thu May 22 00:12:29 MDT 2025
-- Date        : Fri Sep 18 20:02:33 2026
-- Host        : DESKTOP-FLN9N0C running 64-bit major release  (build 9200)
-- Command     : write_vhdl -force -mode funcsim
--               x:/Tesis/Passthrough_v1/Passthrough_v1.gen/sources_1/bd/design_1/ip/design_1_axi_stream_looper_mi_0_0/design_1_axi_stream_looper_mi_0_0_sim_netlist.vhdl
-- Design      : design_1_axi_stream_looper_mi_0_0
-- Purpose     : This VHDL netlist is a functional simulation representation of the design and should not be modified or
--               synthesized. This netlist cannot be used for SDF annotated simulation.
-- Device      : xc7z020clg400-1
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library UNISIM;
use UNISIM.VCOMPONENTS.ALL;
entity design_1_axi_stream_looper_mi_0_0_axi_stream_looper_mixer is
  port (
    s1_axis_tready : out STD_LOGIC;
    m_dma_axis_tdata : out STD_LOGIC_VECTOR ( 24 downto 0 );
    s0_axis_tdata : in STD_LOGIC_VECTOR ( 31 downto 0 );
    s1_axis_tvalid : in STD_LOGIC;
    s1_axis_tdata : in STD_LOGIC_VECTOR ( 23 downto 0 );
    mode : in STD_LOGIC_VECTOR ( 0 to 0 );
    clk : in STD_LOGIC;
    s0_axis_tvalid : in STD_LOGIC;
    s0_axis_tid : in STD_LOGIC_VECTOR ( 2 downto 0 );
    m_i2s_axis_tready : in STD_LOGIC;
    resetn : in STD_LOGIC
  );
  attribute ORIG_REF_NAME : string;
  attribute ORIG_REF_NAME of design_1_axi_stream_looper_mi_0_0_axi_stream_looper_mixer : entity is "axi_stream_looper_mixer";
end design_1_axi_stream_looper_mi_0_0_axi_stream_looper_mixer;

architecture STRUCTURE of design_1_axi_stream_looper_mi_0_0_axi_stream_looper_mixer is
  signal \i__carry_i_1_n_3\ : STD_LOGIC;
  signal \i__carry_i_2_n_0\ : STD_LOGIC;
  signal last_ram_audio : STD_LOGIC_VECTOR ( 23 downto 0 );
  signal last_ram_audio0 : STD_LOGIC;
  signal \m_dma_axis_tdata[31]_INST_0_i_1_n_0\ : STD_LOGIC;
  signal \m_dma_axis_tdata[31]_INST_0_i_2_n_0\ : STD_LOGIC;
  signal \m_dma_axis_tdata[31]_INST_0_i_3_n_0\ : STD_LOGIC;
  signal \m_dma_axis_tdata[31]_INST_0_i_4_n_0\ : STD_LOGIC;
  signal \m_dma_axis_tdata[31]_INST_0_i_5_n_0\ : STD_LOGIC;
  signal \m_dma_axis_tdata[31]_INST_0_i_6_n_0\ : STD_LOGIC;
  signal \m_dma_axis_tdata[31]_INST_0_i_7_n_0\ : STD_LOGIC;
  signal \m_dma_axis_tdata[31]_INST_0_i_8_n_0\ : STD_LOGIC;
  signal \m_dma_axis_tdata[31]_INST_0_i_9_n_0\ : STD_LOGIC;
  signal mixed_audio1 : STD_LOGIC;
  signal mixed_audio10_in : STD_LOGIC;
  signal mixed_audio1_carry_i_1_n_0 : STD_LOGIC;
  signal mixed_audio1_carry_i_3_n_0 : STD_LOGIC;
  signal mixed_audio1_carry_n_3 : STD_LOGIC;
  signal \mixed_audio1_inferred__0/i__carry_n_3\ : STD_LOGIC;
  signal mode_sync_1 : STD_LOGIC_VECTOR ( 1 to 1 );
  signal \mode_sync_1[1]_i_1_n_0\ : STD_LOGIC;
  signal mode_sync_2 : STD_LOGIC_VECTOR ( 1 to 1 );
  signal \mode_sync_2[1]_i_1_n_0\ : STD_LOGIC;
  signal p_0_in : STD_LOGIC_VECTOR ( 24 downto 0 );
  signal \sum_carry__0_i_1_n_0\ : STD_LOGIC;
  signal \sum_carry__0_i_2_n_0\ : STD_LOGIC;
  signal \sum_carry__0_i_3_n_0\ : STD_LOGIC;
  signal \sum_carry__0_i_4_n_0\ : STD_LOGIC;
  signal \sum_carry__0_n_0\ : STD_LOGIC;
  signal \sum_carry__0_n_1\ : STD_LOGIC;
  signal \sum_carry__0_n_2\ : STD_LOGIC;
  signal \sum_carry__0_n_3\ : STD_LOGIC;
  signal \sum_carry__1_i_1_n_0\ : STD_LOGIC;
  signal \sum_carry__1_i_2_n_0\ : STD_LOGIC;
  signal \sum_carry__1_i_3_n_0\ : STD_LOGIC;
  signal \sum_carry__1_i_4_n_0\ : STD_LOGIC;
  signal \sum_carry__1_n_0\ : STD_LOGIC;
  signal \sum_carry__1_n_1\ : STD_LOGIC;
  signal \sum_carry__1_n_2\ : STD_LOGIC;
  signal \sum_carry__1_n_3\ : STD_LOGIC;
  signal \sum_carry__2_i_1_n_0\ : STD_LOGIC;
  signal \sum_carry__2_i_2_n_0\ : STD_LOGIC;
  signal \sum_carry__2_i_3_n_0\ : STD_LOGIC;
  signal \sum_carry__2_i_4_n_0\ : STD_LOGIC;
  signal \sum_carry__2_n_0\ : STD_LOGIC;
  signal \sum_carry__2_n_1\ : STD_LOGIC;
  signal \sum_carry__2_n_2\ : STD_LOGIC;
  signal \sum_carry__2_n_3\ : STD_LOGIC;
  signal \sum_carry__3_i_1_n_0\ : STD_LOGIC;
  signal \sum_carry__3_i_2_n_0\ : STD_LOGIC;
  signal \sum_carry__3_i_3_n_0\ : STD_LOGIC;
  signal \sum_carry__3_i_4_n_0\ : STD_LOGIC;
  signal \sum_carry__3_n_0\ : STD_LOGIC;
  signal \sum_carry__3_n_1\ : STD_LOGIC;
  signal \sum_carry__3_n_2\ : STD_LOGIC;
  signal \sum_carry__3_n_3\ : STD_LOGIC;
  signal \sum_carry__4_i_1_n_0\ : STD_LOGIC;
  signal \sum_carry__4_i_2_n_0\ : STD_LOGIC;
  signal \sum_carry__4_i_3_n_0\ : STD_LOGIC;
  signal \sum_carry__4_i_4_n_0\ : STD_LOGIC;
  signal \sum_carry__4_i_5_n_0\ : STD_LOGIC;
  signal \sum_carry__4_n_0\ : STD_LOGIC;
  signal \sum_carry__4_n_1\ : STD_LOGIC;
  signal \sum_carry__4_n_2\ : STD_LOGIC;
  signal \sum_carry__4_n_3\ : STD_LOGIC;
  signal sum_carry_i_1_n_0 : STD_LOGIC;
  signal sum_carry_i_2_n_0 : STD_LOGIC;
  signal sum_carry_i_3_n_0 : STD_LOGIC;
  signal sum_carry_i_4_n_0 : STD_LOGIC;
  signal sum_carry_n_0 : STD_LOGIC;
  signal sum_carry_n_1 : STD_LOGIC;
  signal sum_carry_n_2 : STD_LOGIC;
  signal sum_carry_n_3 : STD_LOGIC;
  signal \NLW_i__carry_i_1_CO_UNCONNECTED\ : STD_LOGIC_VECTOR ( 3 downto 1 );
  signal \NLW_i__carry_i_1_O_UNCONNECTED\ : STD_LOGIC_VECTOR ( 3 downto 0 );
  signal NLW_mixed_audio1_carry_CO_UNCONNECTED : STD_LOGIC_VECTOR ( 3 downto 2 );
  signal NLW_mixed_audio1_carry_O_UNCONNECTED : STD_LOGIC_VECTOR ( 3 downto 0 );
  signal \NLW_mixed_audio1_inferred__0/i__carry_CO_UNCONNECTED\ : STD_LOGIC_VECTOR ( 3 downto 2 );
  signal \NLW_mixed_audio1_inferred__0/i__carry_O_UNCONNECTED\ : STD_LOGIC_VECTOR ( 3 downto 0 );
  attribute COMPARATOR_THRESHOLD : integer;
  attribute COMPARATOR_THRESHOLD of mixed_audio1_carry : label is 11;
  attribute COMPARATOR_THRESHOLD of \mixed_audio1_inferred__0/i__carry\ : label is 11;
begin
\i__carry_i_1\: unisim.vcomponents.CARRY4
     port map (
      CI => \sum_carry__4_n_0\,
      CO(3 downto 1) => \NLW_i__carry_i_1_CO_UNCONNECTED\(3 downto 1),
      CO(0) => \i__carry_i_1_n_3\,
      CYINIT => '0',
      DI(3 downto 0) => B"0000",
      O(3 downto 0) => \NLW_i__carry_i_1_O_UNCONNECTED\(3 downto 0),
      S(3 downto 0) => B"0001"
    );
\i__carry_i_2\: unisim.vcomponents.LUT2
    generic map(
      INIT => X"2"
    )
        port map (
      I0 => p_0_in(22),
      I1 => p_0_in(23),
      O => \i__carry_i_2_n_0\
    );
\last_ram_audio[23]_i_1\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"8000"
    )
        port map (
      I0 => s1_axis_tvalid,
      I1 => m_i2s_axis_tready,
      I2 => s0_axis_tvalid,
      I3 => mode_sync_2(1),
      O => last_ram_audio0
    );
\last_ram_audio_reg[0]\: unisim.vcomponents.FDCE
     port map (
      C => clk,
      CE => last_ram_audio0,
      CLR => \mode_sync_1[1]_i_1_n_0\,
      D => s1_axis_tdata(0),
      Q => last_ram_audio(0)
    );
\last_ram_audio_reg[10]\: unisim.vcomponents.FDCE
     port map (
      C => clk,
      CE => last_ram_audio0,
      CLR => \mode_sync_1[1]_i_1_n_0\,
      D => s1_axis_tdata(10),
      Q => last_ram_audio(10)
    );
\last_ram_audio_reg[11]\: unisim.vcomponents.FDCE
     port map (
      C => clk,
      CE => last_ram_audio0,
      CLR => \mode_sync_1[1]_i_1_n_0\,
      D => s1_axis_tdata(11),
      Q => last_ram_audio(11)
    );
\last_ram_audio_reg[12]\: unisim.vcomponents.FDCE
     port map (
      C => clk,
      CE => last_ram_audio0,
      CLR => \mode_sync_1[1]_i_1_n_0\,
      D => s1_axis_tdata(12),
      Q => last_ram_audio(12)
    );
\last_ram_audio_reg[13]\: unisim.vcomponents.FDCE
     port map (
      C => clk,
      CE => last_ram_audio0,
      CLR => \mode_sync_1[1]_i_1_n_0\,
      D => s1_axis_tdata(13),
      Q => last_ram_audio(13)
    );
\last_ram_audio_reg[14]\: unisim.vcomponents.FDCE
     port map (
      C => clk,
      CE => last_ram_audio0,
      CLR => \mode_sync_1[1]_i_1_n_0\,
      D => s1_axis_tdata(14),
      Q => last_ram_audio(14)
    );
\last_ram_audio_reg[15]\: unisim.vcomponents.FDCE
     port map (
      C => clk,
      CE => last_ram_audio0,
      CLR => \mode_sync_1[1]_i_1_n_0\,
      D => s1_axis_tdata(15),
      Q => last_ram_audio(15)
    );
\last_ram_audio_reg[16]\: unisim.vcomponents.FDCE
     port map (
      C => clk,
      CE => last_ram_audio0,
      CLR => \mode_sync_1[1]_i_1_n_0\,
      D => s1_axis_tdata(16),
      Q => last_ram_audio(16)
    );
\last_ram_audio_reg[17]\: unisim.vcomponents.FDCE
     port map (
      C => clk,
      CE => last_ram_audio0,
      CLR => \mode_sync_1[1]_i_1_n_0\,
      D => s1_axis_tdata(17),
      Q => last_ram_audio(17)
    );
\last_ram_audio_reg[18]\: unisim.vcomponents.FDCE
     port map (
      C => clk,
      CE => last_ram_audio0,
      CLR => \mode_sync_1[1]_i_1_n_0\,
      D => s1_axis_tdata(18),
      Q => last_ram_audio(18)
    );
\last_ram_audio_reg[19]\: unisim.vcomponents.FDCE
     port map (
      C => clk,
      CE => last_ram_audio0,
      CLR => \mode_sync_1[1]_i_1_n_0\,
      D => s1_axis_tdata(19),
      Q => last_ram_audio(19)
    );
\last_ram_audio_reg[1]\: unisim.vcomponents.FDCE
     port map (
      C => clk,
      CE => last_ram_audio0,
      CLR => \mode_sync_1[1]_i_1_n_0\,
      D => s1_axis_tdata(1),
      Q => last_ram_audio(1)
    );
\last_ram_audio_reg[20]\: unisim.vcomponents.FDCE
     port map (
      C => clk,
      CE => last_ram_audio0,
      CLR => \mode_sync_1[1]_i_1_n_0\,
      D => s1_axis_tdata(20),
      Q => last_ram_audio(20)
    );
\last_ram_audio_reg[21]\: unisim.vcomponents.FDCE
     port map (
      C => clk,
      CE => last_ram_audio0,
      CLR => \mode_sync_1[1]_i_1_n_0\,
      D => s1_axis_tdata(21),
      Q => last_ram_audio(21)
    );
\last_ram_audio_reg[22]\: unisim.vcomponents.FDCE
     port map (
      C => clk,
      CE => last_ram_audio0,
      CLR => \mode_sync_1[1]_i_1_n_0\,
      D => s1_axis_tdata(22),
      Q => last_ram_audio(22)
    );
\last_ram_audio_reg[23]\: unisim.vcomponents.FDCE
     port map (
      C => clk,
      CE => last_ram_audio0,
      CLR => \mode_sync_1[1]_i_1_n_0\,
      D => s1_axis_tdata(23),
      Q => last_ram_audio(23)
    );
\last_ram_audio_reg[2]\: unisim.vcomponents.FDCE
     port map (
      C => clk,
      CE => last_ram_audio0,
      CLR => \mode_sync_1[1]_i_1_n_0\,
      D => s1_axis_tdata(2),
      Q => last_ram_audio(2)
    );
\last_ram_audio_reg[3]\: unisim.vcomponents.FDCE
     port map (
      C => clk,
      CE => last_ram_audio0,
      CLR => \mode_sync_1[1]_i_1_n_0\,
      D => s1_axis_tdata(3),
      Q => last_ram_audio(3)
    );
\last_ram_audio_reg[4]\: unisim.vcomponents.FDCE
     port map (
      C => clk,
      CE => last_ram_audio0,
      CLR => \mode_sync_1[1]_i_1_n_0\,
      D => s1_axis_tdata(4),
      Q => last_ram_audio(4)
    );
\last_ram_audio_reg[5]\: unisim.vcomponents.FDCE
     port map (
      C => clk,
      CE => last_ram_audio0,
      CLR => \mode_sync_1[1]_i_1_n_0\,
      D => s1_axis_tdata(5),
      Q => last_ram_audio(5)
    );
\last_ram_audio_reg[6]\: unisim.vcomponents.FDCE
     port map (
      C => clk,
      CE => last_ram_audio0,
      CLR => \mode_sync_1[1]_i_1_n_0\,
      D => s1_axis_tdata(6),
      Q => last_ram_audio(6)
    );
\last_ram_audio_reg[7]\: unisim.vcomponents.FDCE
     port map (
      C => clk,
      CE => last_ram_audio0,
      CLR => \mode_sync_1[1]_i_1_n_0\,
      D => s1_axis_tdata(7),
      Q => last_ram_audio(7)
    );
\last_ram_audio_reg[8]\: unisim.vcomponents.FDCE
     port map (
      C => clk,
      CE => last_ram_audio0,
      CLR => \mode_sync_1[1]_i_1_n_0\,
      D => s1_axis_tdata(8),
      Q => last_ram_audio(8)
    );
\last_ram_audio_reg[9]\: unisim.vcomponents.FDCE
     port map (
      C => clk,
      CE => last_ram_audio0,
      CLR => \mode_sync_1[1]_i_1_n_0\,
      D => s1_axis_tdata(9),
      Q => last_ram_audio(9)
    );
\m_dma_axis_tdata[10]_INST_0\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FF0CAAAA"
    )
        port map (
      I0 => s0_axis_tdata(10),
      I1 => p_0_in(6),
      I2 => mixed_audio1,
      I3 => mixed_audio10_in,
      I4 => mode_sync_2(1),
      O => m_dma_axis_tdata(6)
    );
\m_dma_axis_tdata[11]_INST_0\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FF0CAAAA"
    )
        port map (
      I0 => s0_axis_tdata(11),
      I1 => p_0_in(7),
      I2 => mixed_audio1,
      I3 => mixed_audio10_in,
      I4 => mode_sync_2(1),
      O => m_dma_axis_tdata(7)
    );
\m_dma_axis_tdata[12]_INST_0\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FF0CAAAA"
    )
        port map (
      I0 => s0_axis_tdata(12),
      I1 => p_0_in(8),
      I2 => mixed_audio1,
      I3 => mixed_audio10_in,
      I4 => mode_sync_2(1),
      O => m_dma_axis_tdata(8)
    );
\m_dma_axis_tdata[13]_INST_0\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FF0CAAAA"
    )
        port map (
      I0 => s0_axis_tdata(13),
      I1 => p_0_in(9),
      I2 => mixed_audio1,
      I3 => mixed_audio10_in,
      I4 => mode_sync_2(1),
      O => m_dma_axis_tdata(9)
    );
\m_dma_axis_tdata[14]_INST_0\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FF0CAAAA"
    )
        port map (
      I0 => s0_axis_tdata(14),
      I1 => p_0_in(10),
      I2 => mixed_audio1,
      I3 => mixed_audio10_in,
      I4 => mode_sync_2(1),
      O => m_dma_axis_tdata(10)
    );
\m_dma_axis_tdata[15]_INST_0\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FF0CAAAA"
    )
        port map (
      I0 => s0_axis_tdata(15),
      I1 => p_0_in(11),
      I2 => mixed_audio1,
      I3 => mixed_audio10_in,
      I4 => mode_sync_2(1),
      O => m_dma_axis_tdata(11)
    );
\m_dma_axis_tdata[16]_INST_0\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FF0CAAAA"
    )
        port map (
      I0 => s0_axis_tdata(16),
      I1 => p_0_in(12),
      I2 => mixed_audio1,
      I3 => mixed_audio10_in,
      I4 => mode_sync_2(1),
      O => m_dma_axis_tdata(12)
    );
\m_dma_axis_tdata[17]_INST_0\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FF0CAAAA"
    )
        port map (
      I0 => s0_axis_tdata(17),
      I1 => p_0_in(13),
      I2 => mixed_audio1,
      I3 => mixed_audio10_in,
      I4 => mode_sync_2(1),
      O => m_dma_axis_tdata(13)
    );
\m_dma_axis_tdata[18]_INST_0\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FF0CAAAA"
    )
        port map (
      I0 => s0_axis_tdata(18),
      I1 => p_0_in(14),
      I2 => mixed_audio1,
      I3 => mixed_audio10_in,
      I4 => mode_sync_2(1),
      O => m_dma_axis_tdata(14)
    );
\m_dma_axis_tdata[19]_INST_0\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FF0CAAAA"
    )
        port map (
      I0 => s0_axis_tdata(19),
      I1 => p_0_in(15),
      I2 => mixed_audio1,
      I3 => mixed_audio10_in,
      I4 => mode_sync_2(1),
      O => m_dma_axis_tdata(15)
    );
\m_dma_axis_tdata[20]_INST_0\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FF0CAAAA"
    )
        port map (
      I0 => s0_axis_tdata(20),
      I1 => p_0_in(16),
      I2 => mixed_audio1,
      I3 => mixed_audio10_in,
      I4 => mode_sync_2(1),
      O => m_dma_axis_tdata(16)
    );
\m_dma_axis_tdata[21]_INST_0\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FF0CAAAA"
    )
        port map (
      I0 => s0_axis_tdata(21),
      I1 => p_0_in(17),
      I2 => mixed_audio1,
      I3 => mixed_audio10_in,
      I4 => mode_sync_2(1),
      O => m_dma_axis_tdata(17)
    );
\m_dma_axis_tdata[22]_INST_0\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FF0CAAAA"
    )
        port map (
      I0 => s0_axis_tdata(22),
      I1 => p_0_in(18),
      I2 => mixed_audio1,
      I3 => mixed_audio10_in,
      I4 => mode_sync_2(1),
      O => m_dma_axis_tdata(18)
    );
\m_dma_axis_tdata[23]_INST_0\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FF0CAAAA"
    )
        port map (
      I0 => s0_axis_tdata(23),
      I1 => p_0_in(19),
      I2 => mixed_audio1,
      I3 => mixed_audio10_in,
      I4 => mode_sync_2(1),
      O => m_dma_axis_tdata(19)
    );
\m_dma_axis_tdata[24]_INST_0\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FF0CAAAA"
    )
        port map (
      I0 => s0_axis_tdata(24),
      I1 => p_0_in(20),
      I2 => mixed_audio1,
      I3 => mixed_audio10_in,
      I4 => mode_sync_2(1),
      O => m_dma_axis_tdata(20)
    );
\m_dma_axis_tdata[25]_INST_0\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FF0CAAAA"
    )
        port map (
      I0 => s0_axis_tdata(25),
      I1 => p_0_in(21),
      I2 => mixed_audio1,
      I3 => mixed_audio10_in,
      I4 => mode_sync_2(1),
      O => m_dma_axis_tdata(21)
    );
\m_dma_axis_tdata[26]_INST_0\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FF0CAAAA"
    )
        port map (
      I0 => s0_axis_tdata(26),
      I1 => p_0_in(22),
      I2 => mixed_audio1,
      I3 => mixed_audio10_in,
      I4 => mode_sync_2(1),
      O => m_dma_axis_tdata(22)
    );
\m_dma_axis_tdata[27]_INST_0\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"3330AAAA"
    )
        port map (
      I0 => s0_axis_tdata(27),
      I1 => mixed_audio10_in,
      I2 => mixed_audio1,
      I3 => p_0_in(23),
      I4 => mode_sync_2(1),
      O => m_dma_axis_tdata(23)
    );
\m_dma_axis_tdata[31]_INST_0\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"3CAA"
    )
        port map (
      I0 => s0_axis_tdata(31),
      I1 => \m_dma_axis_tdata[31]_INST_0_i_1_n_0\,
      I2 => \m_dma_axis_tdata[31]_INST_0_i_2_n_0\,
      I3 => mode_sync_2(1),
      O => m_dma_axis_tdata(24)
    );
\m_dma_axis_tdata[31]_INST_0_i_1\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"6996"
    )
        port map (
      I0 => \m_dma_axis_tdata[31]_INST_0_i_3_n_0\,
      I1 => \m_dma_axis_tdata[31]_INST_0_i_4_n_0\,
      I2 => \m_dma_axis_tdata[31]_INST_0_i_5_n_0\,
      I3 => \m_dma_axis_tdata[31]_INST_0_i_6_n_0\,
      O => \m_dma_axis_tdata[31]_INST_0_i_1_n_0\
    );
\m_dma_axis_tdata[31]_INST_0_i_2\: unisim.vcomponents.LUT6
    generic map(
      INIT => X"6996966996696996"
    )
        port map (
      I0 => \m_dma_axis_tdata[31]_INST_0_i_7_n_0\,
      I1 => s0_axis_tdata(30),
      I2 => s0_axis_tdata(28),
      I3 => s0_axis_tdata(29),
      I4 => \m_dma_axis_tdata[31]_INST_0_i_8_n_0\,
      I5 => \m_dma_axis_tdata[31]_INST_0_i_9_n_0\,
      O => \m_dma_axis_tdata[31]_INST_0_i_2_n_0\
    );
\m_dma_axis_tdata[31]_INST_0_i_3\: unisim.vcomponents.LUT6
    generic map(
      INIT => X"0006000900090006"
    )
        port map (
      I0 => p_0_in(6),
      I1 => p_0_in(7),
      I2 => mixed_audio10_in,
      I3 => mixed_audio1,
      I4 => p_0_in(4),
      I5 => p_0_in(5),
      O => \m_dma_axis_tdata[31]_INST_0_i_3_n_0\
    );
\m_dma_axis_tdata[31]_INST_0_i_4\: unisim.vcomponents.LUT6
    generic map(
      INIT => X"0006000900090006"
    )
        port map (
      I0 => p_0_in(10),
      I1 => p_0_in(11),
      I2 => mixed_audio10_in,
      I3 => mixed_audio1,
      I4 => p_0_in(8),
      I5 => p_0_in(9),
      O => \m_dma_axis_tdata[31]_INST_0_i_4_n_0\
    );
\m_dma_axis_tdata[31]_INST_0_i_5\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"6996"
    )
        port map (
      I0 => s0_axis_tdata(2),
      I1 => s0_axis_tdata(3),
      I2 => s0_axis_tdata(0),
      I3 => s0_axis_tdata(1),
      O => \m_dma_axis_tdata[31]_INST_0_i_5_n_0\
    );
\m_dma_axis_tdata[31]_INST_0_i_6\: unisim.vcomponents.LUT6
    generic map(
      INIT => X"0006000900090006"
    )
        port map (
      I0 => p_0_in(2),
      I1 => p_0_in(3),
      I2 => mixed_audio10_in,
      I3 => mixed_audio1,
      I4 => p_0_in(0),
      I5 => p_0_in(1),
      O => \m_dma_axis_tdata[31]_INST_0_i_6_n_0\
    );
\m_dma_axis_tdata[31]_INST_0_i_7\: unisim.vcomponents.LUT6
    generic map(
      INIT => X"FFF6FFF9FFF9FFF6"
    )
        port map (
      I0 => p_0_in(22),
      I1 => p_0_in(23),
      I2 => mixed_audio10_in,
      I3 => mixed_audio1,
      I4 => p_0_in(20),
      I5 => p_0_in(21),
      O => \m_dma_axis_tdata[31]_INST_0_i_7_n_0\
    );
\m_dma_axis_tdata[31]_INST_0_i_8\: unisim.vcomponents.LUT6
    generic map(
      INIT => X"0006000900090006"
    )
        port map (
      I0 => p_0_in(14),
      I1 => p_0_in(15),
      I2 => mixed_audio10_in,
      I3 => mixed_audio1,
      I4 => p_0_in(12),
      I5 => p_0_in(13),
      O => \m_dma_axis_tdata[31]_INST_0_i_8_n_0\
    );
\m_dma_axis_tdata[31]_INST_0_i_9\: unisim.vcomponents.LUT6
    generic map(
      INIT => X"0006000900090006"
    )
        port map (
      I0 => p_0_in(18),
      I1 => p_0_in(19),
      I2 => mixed_audio10_in,
      I3 => mixed_audio1,
      I4 => p_0_in(16),
      I5 => p_0_in(17),
      O => \m_dma_axis_tdata[31]_INST_0_i_9_n_0\
    );
\m_dma_axis_tdata[4]_INST_0\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FF0CAAAA"
    )
        port map (
      I0 => s0_axis_tdata(4),
      I1 => p_0_in(0),
      I2 => mixed_audio1,
      I3 => mixed_audio10_in,
      I4 => mode_sync_2(1),
      O => m_dma_axis_tdata(0)
    );
\m_dma_axis_tdata[5]_INST_0\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FF0CAAAA"
    )
        port map (
      I0 => s0_axis_tdata(5),
      I1 => p_0_in(1),
      I2 => mixed_audio1,
      I3 => mixed_audio10_in,
      I4 => mode_sync_2(1),
      O => m_dma_axis_tdata(1)
    );
\m_dma_axis_tdata[6]_INST_0\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FF0CAAAA"
    )
        port map (
      I0 => s0_axis_tdata(6),
      I1 => p_0_in(2),
      I2 => mixed_audio1,
      I3 => mixed_audio10_in,
      I4 => mode_sync_2(1),
      O => m_dma_axis_tdata(2)
    );
\m_dma_axis_tdata[7]_INST_0\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FF0CAAAA"
    )
        port map (
      I0 => s0_axis_tdata(7),
      I1 => p_0_in(3),
      I2 => mixed_audio1,
      I3 => mixed_audio10_in,
      I4 => mode_sync_2(1),
      O => m_dma_axis_tdata(3)
    );
\m_dma_axis_tdata[8]_INST_0\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FF0CAAAA"
    )
        port map (
      I0 => s0_axis_tdata(8),
      I1 => p_0_in(4),
      I2 => mixed_audio1,
      I3 => mixed_audio10_in,
      I4 => mode_sync_2(1),
      O => m_dma_axis_tdata(4)
    );
\m_dma_axis_tdata[9]_INST_0\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FF0CAAAA"
    )
        port map (
      I0 => s0_axis_tdata(9),
      I1 => p_0_in(5),
      I2 => mixed_audio1,
      I3 => mixed_audio10_in,
      I4 => mode_sync_2(1),
      O => m_dma_axis_tdata(5)
    );
mixed_audio1_carry: unisim.vcomponents.CARRY4
     port map (
      CI => '0',
      CO(3 downto 2) => NLW_mixed_audio1_carry_CO_UNCONNECTED(3 downto 2),
      CO(1) => mixed_audio1,
      CO(0) => mixed_audio1_carry_n_3,
      CYINIT => '0',
      DI(3 downto 1) => B"000",
      DI(0) => mixed_audio1_carry_i_1_n_0,
      O(3 downto 0) => NLW_mixed_audio1_carry_O_UNCONNECTED(3 downto 0),
      S(3 downto 2) => B"00",
      S(1) => p_0_in(24),
      S(0) => mixed_audio1_carry_i_3_n_0
    );
mixed_audio1_carry_i_1: unisim.vcomponents.LUT1
    generic map(
      INIT => X"1"
    )
        port map (
      I0 => p_0_in(23),
      O => mixed_audio1_carry_i_1_n_0
    );
mixed_audio1_carry_i_2: unisim.vcomponents.LUT1
    generic map(
      INIT => X"1"
    )
        port map (
      I0 => \i__carry_i_1_n_3\,
      O => p_0_in(24)
    );
mixed_audio1_carry_i_3: unisim.vcomponents.LUT2
    generic map(
      INIT => X"2"
    )
        port map (
      I0 => p_0_in(23),
      I1 => p_0_in(22),
      O => mixed_audio1_carry_i_3_n_0
    );
\mixed_audio1_inferred__0/i__carry\: unisim.vcomponents.CARRY4
     port map (
      CI => '0',
      CO(3 downto 2) => \NLW_mixed_audio1_inferred__0/i__carry_CO_UNCONNECTED\(3 downto 2),
      CO(1) => mixed_audio10_in,
      CO(0) => \mixed_audio1_inferred__0/i__carry_n_3\,
      CYINIT => '0',
      DI(3 downto 1) => B"000",
      DI(0) => p_0_in(23),
      O(3 downto 0) => \NLW_mixed_audio1_inferred__0/i__carry_O_UNCONNECTED\(3 downto 0),
      S(3 downto 2) => B"00",
      S(1) => \i__carry_i_1_n_3\,
      S(0) => \i__carry_i_2_n_0\
    );
\mode_sync_1[1]_i_1\: unisim.vcomponents.LUT1
    generic map(
      INIT => X"1"
    )
        port map (
      I0 => resetn,
      O => \mode_sync_1[1]_i_1_n_0\
    );
\mode_sync_1_reg[1]\: unisim.vcomponents.FDCE
     port map (
      C => clk,
      CE => '1',
      CLR => \mode_sync_1[1]_i_1_n_0\,
      D => mode(0),
      Q => mode_sync_1(1)
    );
\mode_sync_2[1]_i_1\: unisim.vcomponents.LUT6
    generic map(
      INIT => X"FFFFFFFB00000008"
    )
        port map (
      I0 => mode_sync_1(1),
      I1 => s0_axis_tvalid,
      I2 => s0_axis_tid(2),
      I3 => s0_axis_tid(0),
      I4 => s0_axis_tid(1),
      I5 => mode_sync_2(1),
      O => \mode_sync_2[1]_i_1_n_0\
    );
\mode_sync_2_reg[1]\: unisim.vcomponents.FDCE
     port map (
      C => clk,
      CE => '1',
      CLR => \mode_sync_1[1]_i_1_n_0\,
      D => \mode_sync_2[1]_i_1_n_0\,
      Q => mode_sync_2(1)
    );
s1_axis_tready_INST_0: unisim.vcomponents.LUT3
    generic map(
      INIT => X"80"
    )
        port map (
      I0 => mode_sync_2(1),
      I1 => s0_axis_tvalid,
      I2 => m_i2s_axis_tready,
      O => s1_axis_tready
    );
sum_carry: unisim.vcomponents.CARRY4
     port map (
      CI => '0',
      CO(3) => sum_carry_n_0,
      CO(2) => sum_carry_n_1,
      CO(1) => sum_carry_n_2,
      CO(0) => sum_carry_n_3,
      CYINIT => '0',
      DI(3 downto 0) => s0_axis_tdata(7 downto 4),
      O(3 downto 0) => p_0_in(3 downto 0),
      S(3) => sum_carry_i_1_n_0,
      S(2) => sum_carry_i_2_n_0,
      S(1) => sum_carry_i_3_n_0,
      S(0) => sum_carry_i_4_n_0
    );
\sum_carry__0\: unisim.vcomponents.CARRY4
     port map (
      CI => sum_carry_n_0,
      CO(3) => \sum_carry__0_n_0\,
      CO(2) => \sum_carry__0_n_1\,
      CO(1) => \sum_carry__0_n_2\,
      CO(0) => \sum_carry__0_n_3\,
      CYINIT => '0',
      DI(3 downto 0) => s0_axis_tdata(11 downto 8),
      O(3 downto 0) => p_0_in(7 downto 4),
      S(3) => \sum_carry__0_i_1_n_0\,
      S(2) => \sum_carry__0_i_2_n_0\,
      S(1) => \sum_carry__0_i_3_n_0\,
      S(0) => \sum_carry__0_i_4_n_0\
    );
\sum_carry__0_i_1\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"569A"
    )
        port map (
      I0 => s0_axis_tdata(11),
      I1 => s1_axis_tvalid,
      I2 => last_ram_audio(7),
      I3 => s1_axis_tdata(7),
      O => \sum_carry__0_i_1_n_0\
    );
\sum_carry__0_i_2\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"569A"
    )
        port map (
      I0 => s0_axis_tdata(10),
      I1 => s1_axis_tvalid,
      I2 => last_ram_audio(6),
      I3 => s1_axis_tdata(6),
      O => \sum_carry__0_i_2_n_0\
    );
\sum_carry__0_i_3\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"569A"
    )
        port map (
      I0 => s0_axis_tdata(9),
      I1 => s1_axis_tvalid,
      I2 => last_ram_audio(5),
      I3 => s1_axis_tdata(5),
      O => \sum_carry__0_i_3_n_0\
    );
\sum_carry__0_i_4\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"569A"
    )
        port map (
      I0 => s0_axis_tdata(8),
      I1 => s1_axis_tvalid,
      I2 => last_ram_audio(4),
      I3 => s1_axis_tdata(4),
      O => \sum_carry__0_i_4_n_0\
    );
\sum_carry__1\: unisim.vcomponents.CARRY4
     port map (
      CI => \sum_carry__0_n_0\,
      CO(3) => \sum_carry__1_n_0\,
      CO(2) => \sum_carry__1_n_1\,
      CO(1) => \sum_carry__1_n_2\,
      CO(0) => \sum_carry__1_n_3\,
      CYINIT => '0',
      DI(3 downto 0) => s0_axis_tdata(15 downto 12),
      O(3 downto 0) => p_0_in(11 downto 8),
      S(3) => \sum_carry__1_i_1_n_0\,
      S(2) => \sum_carry__1_i_2_n_0\,
      S(1) => \sum_carry__1_i_3_n_0\,
      S(0) => \sum_carry__1_i_4_n_0\
    );
\sum_carry__1_i_1\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"569A"
    )
        port map (
      I0 => s0_axis_tdata(15),
      I1 => s1_axis_tvalid,
      I2 => last_ram_audio(11),
      I3 => s1_axis_tdata(11),
      O => \sum_carry__1_i_1_n_0\
    );
\sum_carry__1_i_2\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"569A"
    )
        port map (
      I0 => s0_axis_tdata(14),
      I1 => s1_axis_tvalid,
      I2 => last_ram_audio(10),
      I3 => s1_axis_tdata(10),
      O => \sum_carry__1_i_2_n_0\
    );
\sum_carry__1_i_3\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"569A"
    )
        port map (
      I0 => s0_axis_tdata(13),
      I1 => s1_axis_tvalid,
      I2 => last_ram_audio(9),
      I3 => s1_axis_tdata(9),
      O => \sum_carry__1_i_3_n_0\
    );
\sum_carry__1_i_4\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"569A"
    )
        port map (
      I0 => s0_axis_tdata(12),
      I1 => s1_axis_tvalid,
      I2 => last_ram_audio(8),
      I3 => s1_axis_tdata(8),
      O => \sum_carry__1_i_4_n_0\
    );
\sum_carry__2\: unisim.vcomponents.CARRY4
     port map (
      CI => \sum_carry__1_n_0\,
      CO(3) => \sum_carry__2_n_0\,
      CO(2) => \sum_carry__2_n_1\,
      CO(1) => \sum_carry__2_n_2\,
      CO(0) => \sum_carry__2_n_3\,
      CYINIT => '0',
      DI(3 downto 0) => s0_axis_tdata(19 downto 16),
      O(3 downto 0) => p_0_in(15 downto 12),
      S(3) => \sum_carry__2_i_1_n_0\,
      S(2) => \sum_carry__2_i_2_n_0\,
      S(1) => \sum_carry__2_i_3_n_0\,
      S(0) => \sum_carry__2_i_4_n_0\
    );
\sum_carry__2_i_1\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"569A"
    )
        port map (
      I0 => s0_axis_tdata(19),
      I1 => s1_axis_tvalid,
      I2 => last_ram_audio(15),
      I3 => s1_axis_tdata(15),
      O => \sum_carry__2_i_1_n_0\
    );
\sum_carry__2_i_2\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"569A"
    )
        port map (
      I0 => s0_axis_tdata(18),
      I1 => s1_axis_tvalid,
      I2 => last_ram_audio(14),
      I3 => s1_axis_tdata(14),
      O => \sum_carry__2_i_2_n_0\
    );
\sum_carry__2_i_3\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"569A"
    )
        port map (
      I0 => s0_axis_tdata(17),
      I1 => s1_axis_tvalid,
      I2 => last_ram_audio(13),
      I3 => s1_axis_tdata(13),
      O => \sum_carry__2_i_3_n_0\
    );
\sum_carry__2_i_4\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"569A"
    )
        port map (
      I0 => s0_axis_tdata(16),
      I1 => s1_axis_tvalid,
      I2 => last_ram_audio(12),
      I3 => s1_axis_tdata(12),
      O => \sum_carry__2_i_4_n_0\
    );
\sum_carry__3\: unisim.vcomponents.CARRY4
     port map (
      CI => \sum_carry__2_n_0\,
      CO(3) => \sum_carry__3_n_0\,
      CO(2) => \sum_carry__3_n_1\,
      CO(1) => \sum_carry__3_n_2\,
      CO(0) => \sum_carry__3_n_3\,
      CYINIT => '0',
      DI(3 downto 0) => s0_axis_tdata(23 downto 20),
      O(3 downto 0) => p_0_in(19 downto 16),
      S(3) => \sum_carry__3_i_1_n_0\,
      S(2) => \sum_carry__3_i_2_n_0\,
      S(1) => \sum_carry__3_i_3_n_0\,
      S(0) => \sum_carry__3_i_4_n_0\
    );
\sum_carry__3_i_1\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"569A"
    )
        port map (
      I0 => s0_axis_tdata(23),
      I1 => s1_axis_tvalid,
      I2 => last_ram_audio(19),
      I3 => s1_axis_tdata(19),
      O => \sum_carry__3_i_1_n_0\
    );
\sum_carry__3_i_2\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"569A"
    )
        port map (
      I0 => s0_axis_tdata(22),
      I1 => s1_axis_tvalid,
      I2 => last_ram_audio(18),
      I3 => s1_axis_tdata(18),
      O => \sum_carry__3_i_2_n_0\
    );
\sum_carry__3_i_3\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"569A"
    )
        port map (
      I0 => s0_axis_tdata(21),
      I1 => s1_axis_tvalid,
      I2 => last_ram_audio(17),
      I3 => s1_axis_tdata(17),
      O => \sum_carry__3_i_3_n_0\
    );
\sum_carry__3_i_4\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"569A"
    )
        port map (
      I0 => s0_axis_tdata(20),
      I1 => s1_axis_tvalid,
      I2 => last_ram_audio(16),
      I3 => s1_axis_tdata(16),
      O => \sum_carry__3_i_4_n_0\
    );
\sum_carry__4\: unisim.vcomponents.CARRY4
     port map (
      CI => \sum_carry__3_n_0\,
      CO(3) => \sum_carry__4_n_0\,
      CO(2) => \sum_carry__4_n_1\,
      CO(1) => \sum_carry__4_n_2\,
      CO(0) => \sum_carry__4_n_3\,
      CYINIT => '0',
      DI(3) => \sum_carry__4_i_1_n_0\,
      DI(2 downto 0) => s0_axis_tdata(26 downto 24),
      O(3 downto 0) => p_0_in(23 downto 20),
      S(3) => \sum_carry__4_i_2_n_0\,
      S(2) => \sum_carry__4_i_3_n_0\,
      S(1) => \sum_carry__4_i_4_n_0\,
      S(0) => \sum_carry__4_i_5_n_0\
    );
\sum_carry__4_i_1\: unisim.vcomponents.LUT1
    generic map(
      INIT => X"1"
    )
        port map (
      I0 => s0_axis_tdata(27),
      O => \sum_carry__4_i_1_n_0\
    );
\sum_carry__4_i_2\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"569A"
    )
        port map (
      I0 => s0_axis_tdata(27),
      I1 => s1_axis_tvalid,
      I2 => last_ram_audio(23),
      I3 => s1_axis_tdata(23),
      O => \sum_carry__4_i_2_n_0\
    );
\sum_carry__4_i_3\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"569A"
    )
        port map (
      I0 => s0_axis_tdata(26),
      I1 => s1_axis_tvalid,
      I2 => last_ram_audio(22),
      I3 => s1_axis_tdata(22),
      O => \sum_carry__4_i_3_n_0\
    );
\sum_carry__4_i_4\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"569A"
    )
        port map (
      I0 => s0_axis_tdata(25),
      I1 => s1_axis_tvalid,
      I2 => last_ram_audio(21),
      I3 => s1_axis_tdata(21),
      O => \sum_carry__4_i_4_n_0\
    );
\sum_carry__4_i_5\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"569A"
    )
        port map (
      I0 => s0_axis_tdata(24),
      I1 => s1_axis_tvalid,
      I2 => last_ram_audio(20),
      I3 => s1_axis_tdata(20),
      O => \sum_carry__4_i_5_n_0\
    );
sum_carry_i_1: unisim.vcomponents.LUT4
    generic map(
      INIT => X"569A"
    )
        port map (
      I0 => s0_axis_tdata(7),
      I1 => s1_axis_tvalid,
      I2 => last_ram_audio(3),
      I3 => s1_axis_tdata(3),
      O => sum_carry_i_1_n_0
    );
sum_carry_i_2: unisim.vcomponents.LUT4
    generic map(
      INIT => X"569A"
    )
        port map (
      I0 => s0_axis_tdata(6),
      I1 => s1_axis_tvalid,
      I2 => last_ram_audio(2),
      I3 => s1_axis_tdata(2),
      O => sum_carry_i_2_n_0
    );
sum_carry_i_3: unisim.vcomponents.LUT4
    generic map(
      INIT => X"569A"
    )
        port map (
      I0 => s0_axis_tdata(5),
      I1 => s1_axis_tvalid,
      I2 => last_ram_audio(1),
      I3 => s1_axis_tdata(1),
      O => sum_carry_i_3_n_0
    );
sum_carry_i_4: unisim.vcomponents.LUT4
    generic map(
      INIT => X"569A"
    )
        port map (
      I0 => s0_axis_tdata(4),
      I1 => s1_axis_tvalid,
      I2 => last_ram_audio(0),
      I3 => s1_axis_tdata(0),
      O => sum_carry_i_4_n_0
    );
end STRUCTURE;
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library UNISIM;
use UNISIM.VCOMPONENTS.ALL;
entity design_1_axi_stream_looper_mi_0_0 is
  port (
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
  attribute NotValidForBitStream : boolean;
  attribute NotValidForBitStream of design_1_axi_stream_looper_mi_0_0 : entity is true;
  attribute CHECK_LICENSE_TYPE : string;
  attribute CHECK_LICENSE_TYPE of design_1_axi_stream_looper_mi_0_0 : entity is "design_1_axi_stream_looper_mi_0_0,axi_stream_looper_mixer,{}";
  attribute DowngradeIPIdentifiedWarnings : string;
  attribute DowngradeIPIdentifiedWarnings of design_1_axi_stream_looper_mi_0_0 : entity is "yes";
  attribute IP_DEFINITION_SOURCE : string;
  attribute IP_DEFINITION_SOURCE of design_1_axi_stream_looper_mi_0_0 : entity is "module_ref";
  attribute X_CORE_INFO : string;
  attribute X_CORE_INFO of design_1_axi_stream_looper_mi_0_0 : entity is "axi_stream_looper_mixer,Vivado 2025.1";
end design_1_axi_stream_looper_mi_0_0;

architecture STRUCTURE of design_1_axi_stream_looper_mi_0_0 is
  signal \^m_dma_axis_tdata\ : STD_LOGIC_VECTOR ( 31 downto 4 );
  signal \^m_i2s_axis_tready\ : STD_LOGIC;
  signal \^s0_axis_tdata\ : STD_LOGIC_VECTOR ( 31 downto 0 );
  signal \^s0_axis_tid\ : STD_LOGIC_VECTOR ( 2 downto 0 );
  signal \^s0_axis_tkeep\ : STD_LOGIC_VECTOR ( 3 downto 0 );
  signal \^s0_axis_tlast\ : STD_LOGIC;
  signal \^s0_axis_tvalid\ : STD_LOGIC;
  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_INFO of clk : signal is "xilinx.com:signal:clock:1.0 clk CLK";
  attribute X_INTERFACE_MODE : string;
  attribute X_INTERFACE_MODE of clk : signal is "slave";
  attribute X_INTERFACE_PARAMETER : string;
  attribute X_INTERFACE_PARAMETER of clk : signal is "XIL_INTERFACENAME clk, ASSOCIATED_BUSIF m_dma_axis:m_i2s_axis:s0_axis:s1_axis, ASSOCIATED_RESET resetn, FREQ_HZ 50000000, FREQ_TOLERANCE_HZ 0, PHASE 0.0, CLK_DOMAIN design_1_processing_system7_0_0_FCLK_CLK0, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of m_dma_axis_tlast : signal is "xilinx.com:interface:axis:1.0 m_dma_axis TLAST";
  attribute X_INTERFACE_INFO of m_dma_axis_tready : signal is "xilinx.com:interface:axis:1.0 m_dma_axis TREADY";
  attribute X_INTERFACE_INFO of m_dma_axis_tvalid : signal is "xilinx.com:interface:axis:1.0 m_dma_axis TVALID";
  attribute X_INTERFACE_INFO of m_i2s_axis_tlast : signal is "xilinx.com:interface:axis:1.0 m_i2s_axis TLAST";
  attribute X_INTERFACE_INFO of m_i2s_axis_tready : signal is "xilinx.com:interface:axis:1.0 m_i2s_axis TREADY";
  attribute X_INTERFACE_INFO of m_i2s_axis_tvalid : signal is "xilinx.com:interface:axis:1.0 m_i2s_axis TVALID";
  attribute X_INTERFACE_INFO of resetn : signal is "xilinx.com:signal:reset:1.0 resetn RST";
  attribute X_INTERFACE_MODE of resetn : signal is "slave";
  attribute X_INTERFACE_PARAMETER of resetn : signal is "XIL_INTERFACENAME resetn, POLARITY ACTIVE_LOW, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of s0_axis_tlast : signal is "xilinx.com:interface:axis:1.0 s0_axis TLAST";
  attribute X_INTERFACE_INFO of s0_axis_tready : signal is "xilinx.com:interface:axis:1.0 s0_axis TREADY";
  attribute X_INTERFACE_INFO of s0_axis_tvalid : signal is "xilinx.com:interface:axis:1.0 s0_axis TVALID";
  attribute X_INTERFACE_INFO of s1_axis_tlast : signal is "xilinx.com:interface:axis:1.0 s1_axis TLAST";
  attribute X_INTERFACE_INFO of s1_axis_tready : signal is "xilinx.com:interface:axis:1.0 s1_axis TREADY";
  attribute X_INTERFACE_INFO of s1_axis_tvalid : signal is "xilinx.com:interface:axis:1.0 s1_axis TVALID";
  attribute X_INTERFACE_INFO of m_dma_axis_tdata : signal is "xilinx.com:interface:axis:1.0 m_dma_axis TDATA";
  attribute X_INTERFACE_MODE of m_dma_axis_tdata : signal is "master";
  attribute X_INTERFACE_PARAMETER of m_dma_axis_tdata : signal is "XIL_INTERFACENAME m_dma_axis, TDATA_NUM_BYTES 4, TDEST_WIDTH 0, TID_WIDTH 3, TUSER_WIDTH 0, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 1, HAS_TLAST 1, FREQ_HZ 50000000, PHASE 0.0, CLK_DOMAIN design_1_processing_system7_0_0_FCLK_CLK0, LAYERED_METADATA undef, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of m_dma_axis_tid : signal is "xilinx.com:interface:axis:1.0 m_dma_axis TID";
  attribute X_INTERFACE_INFO of m_dma_axis_tkeep : signal is "xilinx.com:interface:axis:1.0 m_dma_axis TKEEP";
  attribute X_INTERFACE_INFO of m_i2s_axis_tdata : signal is "xilinx.com:interface:axis:1.0 m_i2s_axis TDATA";
  attribute X_INTERFACE_MODE of m_i2s_axis_tdata : signal is "master";
  attribute X_INTERFACE_PARAMETER of m_i2s_axis_tdata : signal is "XIL_INTERFACENAME m_i2s_axis, TDATA_NUM_BYTES 4, TDEST_WIDTH 0, TID_WIDTH 3, TUSER_WIDTH 0, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 1, HAS_TLAST 1, FREQ_HZ 50000000, PHASE 0.0, CLK_DOMAIN design_1_processing_system7_0_0_FCLK_CLK0, LAYERED_METADATA undef, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of m_i2s_axis_tid : signal is "xilinx.com:interface:axis:1.0 m_i2s_axis TID";
  attribute X_INTERFACE_INFO of m_i2s_axis_tkeep : signal is "xilinx.com:interface:axis:1.0 m_i2s_axis TKEEP";
  attribute X_INTERFACE_INFO of s0_axis_tdata : signal is "xilinx.com:interface:axis:1.0 s0_axis TDATA";
  attribute X_INTERFACE_MODE of s0_axis_tdata : signal is "slave";
  attribute X_INTERFACE_PARAMETER of s0_axis_tdata : signal is "XIL_INTERFACENAME s0_axis, TDATA_NUM_BYTES 4, TDEST_WIDTH 0, TID_WIDTH 3, TUSER_WIDTH 0, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 1, HAS_TLAST 1, FREQ_HZ 50000000, PHASE 0.0, CLK_DOMAIN design_1_processing_system7_0_0_FCLK_CLK0, LAYERED_METADATA undef, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of s0_axis_tid : signal is "xilinx.com:interface:axis:1.0 s0_axis TID";
  attribute X_INTERFACE_INFO of s0_axis_tkeep : signal is "xilinx.com:interface:axis:1.0 s0_axis TKEEP";
  attribute X_INTERFACE_INFO of s1_axis_tdata : signal is "xilinx.com:interface:axis:1.0 s1_axis TDATA";
  attribute X_INTERFACE_MODE of s1_axis_tdata : signal is "slave";
  attribute X_INTERFACE_PARAMETER of s1_axis_tdata : signal is "XIL_INTERFACENAME s1_axis, TDATA_NUM_BYTES 4, TDEST_WIDTH 0, TID_WIDTH 3, TUSER_WIDTH 0, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 1, HAS_TLAST 1, FREQ_HZ 50000000, PHASE 0.0, CLK_DOMAIN design_1_processing_system7_0_0_FCLK_CLK0, LAYERED_METADATA undef, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of s1_axis_tid : signal is "xilinx.com:interface:axis:1.0 s1_axis TID";
  attribute X_INTERFACE_INFO of s1_axis_tkeep : signal is "xilinx.com:interface:axis:1.0 s1_axis TKEEP";
begin
  \^m_i2s_axis_tready\ <= m_i2s_axis_tready;
  \^s0_axis_tdata\(31 downto 0) <= s0_axis_tdata(31 downto 0);
  \^s0_axis_tid\(2 downto 0) <= s0_axis_tid(2 downto 0);
  \^s0_axis_tkeep\(3 downto 0) <= s0_axis_tkeep(3 downto 0);
  \^s0_axis_tlast\ <= s0_axis_tlast;
  \^s0_axis_tvalid\ <= s0_axis_tvalid;
  m_dma_axis_tdata(31) <= \^m_dma_axis_tdata\(31);
  m_dma_axis_tdata(30 downto 28) <= \^s0_axis_tdata\(30 downto 28);
  m_dma_axis_tdata(27 downto 4) <= \^m_dma_axis_tdata\(27 downto 4);
  m_dma_axis_tdata(3 downto 0) <= \^s0_axis_tdata\(3 downto 0);
  m_dma_axis_tid(2 downto 0) <= \^s0_axis_tid\(2 downto 0);
  m_dma_axis_tkeep(3 downto 0) <= \^s0_axis_tkeep\(3 downto 0);
  m_dma_axis_tlast <= \^s0_axis_tlast\;
  m_dma_axis_tvalid <= \^s0_axis_tvalid\;
  m_i2s_axis_tdata(31) <= \^m_dma_axis_tdata\(31);
  m_i2s_axis_tdata(30 downto 28) <= \^s0_axis_tdata\(30 downto 28);
  m_i2s_axis_tdata(27 downto 4) <= \^m_dma_axis_tdata\(27 downto 4);
  m_i2s_axis_tdata(3 downto 0) <= \^s0_axis_tdata\(3 downto 0);
  m_i2s_axis_tid(2 downto 0) <= \^s0_axis_tid\(2 downto 0);
  m_i2s_axis_tkeep(3 downto 0) <= \^s0_axis_tkeep\(3 downto 0);
  m_i2s_axis_tlast <= \^s0_axis_tlast\;
  m_i2s_axis_tvalid <= \^s0_axis_tvalid\;
  s0_axis_tready <= \^m_i2s_axis_tready\;
inst: entity work.design_1_axi_stream_looper_mi_0_0_axi_stream_looper_mixer
     port map (
      clk => clk,
      m_dma_axis_tdata(24) => \^m_dma_axis_tdata\(31),
      m_dma_axis_tdata(23 downto 0) => \^m_dma_axis_tdata\(27 downto 4),
      m_i2s_axis_tready => \^m_i2s_axis_tready\,
      mode(0) => mode(1),
      resetn => resetn,
      s0_axis_tdata(31 downto 0) => \^s0_axis_tdata\(31 downto 0),
      s0_axis_tid(2 downto 0) => \^s0_axis_tid\(2 downto 0),
      s0_axis_tvalid => \^s0_axis_tvalid\,
      s1_axis_tdata(23 downto 0) => s1_axis_tdata(27 downto 4),
      s1_axis_tready => s1_axis_tready,
      s1_axis_tvalid => s1_axis_tvalid
    );
end STRUCTURE;
