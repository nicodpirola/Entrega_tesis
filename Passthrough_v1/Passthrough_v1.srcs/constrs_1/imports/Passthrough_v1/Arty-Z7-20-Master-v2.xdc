## =============================================================================
## ARTY Z7-20 Rev.B - Master Constraints File (Versión Final con Nuevos Periféricos)
## =============================================================================
## Periféricos configurados:
## - TFT ILI9341 (SPI / Control)
## - 6 Encoders Rotativos (Canales A, B)
## - sys_input[12:0] (Pedal + 6 Switches de Encoder + 6 Switches Generales)
## - PMOD A: DAC I2S (PCM5102)
## - PMOD B: ADC I2S (PCM1808)
## =============================================================================

## Clock Signal (125 MHz)
set_property -dict { PACKAGE_PIN H16    IOSTANDARD LVCMOS33 } [get_ports { sys_clock }]; #IO_L13P_T2_MRCC_35 Sch=SYSCLK
create_clock -add -name sys_clk_pin -period 8.00 -waveform {0 4} [get_ports { sys_clock }];


## =============================================================================
## 1. PANTALLA TFT (ILI9341)
## =============================================================================
## IO26 (CK_IO26 / U5)  : MOSI
## IO0  (CK_IO0  / T14) : SCK
## IO1  (CK_IO1  / U12) : DC (Data/Command)
## IO2  (CK_IO2  / U13) : RESET
## IO3  (CK_IO3  / V13) : CS (Chip Select)
## =============================================================================
set_property -dict { PACKAGE_PIN U5    IOSTANDARD LVCMOS33 } [get_ports { io0_o_0 }];         # IO26 / TFT MOSI
set_property -dict { PACKAGE_PIN T14   IOSTANDARD LVCMOS33 } [get_ports { sck_o_0 }];         # IO0  / TFT SCK
set_property -dict { PACKAGE_PIN U12   IOSTANDARD LVCMOS33 } [get_ports { GPIO_tri_io[0] }];  # IO1  / TFT DC
set_property -dict { PACKAGE_PIN U13   IOSTANDARD LVCMOS33 } [get_ports { GPIO_tri_io[1] }];  # IO2  / TFT RESET
set_property -dict { PACKAGE_PIN V13   IOSTANDARD LVCMOS33 } [get_ports { ss_o_0[0] }];       # IO3  / TFT CS


## =============================================================================
## 2. ENCODERS ROTATIVOS (1 al 6) - CANALES A y B
## =============================================================================
## Encoder 1: E1A -> IO10 (T16), E1B -> IO8  (V17)
## Encoder 2: E2A -> IO11 (R17), E2B -> IO13 (N17)
## Encoder 3: E3A -> IO40 (W9),  E3B -> IO41 (Y9)
## Encoder 4: E4A -> SPI SS (F16), E4B -> SPI MISO (W15)
## Encoder 5: E5A -> IO29 (U7),  E5B -> SPI SCK (H15)
## Encoder 6: E6A -> IO32 (V8),  E6B -> IO31 (U8)
## =============================================================================
# Encoder 1 (E1A, E1B)
set_property -dict { PACKAGE_PIN T16   IOSTANDARD LVCMOS33 PULLTYPE PULLUP } [get_ports { enc_a_0[0] }]; # IO10 / E1A
set_property -dict { PACKAGE_PIN V17   IOSTANDARD LVCMOS33 PULLTYPE PULLUP } [get_ports { enc_b_0[0] }]; # IO8  / E1B

# Encoder 2 (E2A, E2B)
set_property -dict { PACKAGE_PIN R17   IOSTANDARD LVCMOS33 PULLTYPE PULLUP } [get_ports { enc_a_0[1] }]; # IO11 / E2A
set_property -dict { PACKAGE_PIN N17   IOSTANDARD LVCMOS33 PULLTYPE PULLUP } [get_ports { enc_b_0[1] }]; # IO13 / E2B

# Encoder 3 (E3A, E3B)
set_property -dict { PACKAGE_PIN W9    IOSTANDARD LVCMOS33 PULLTYPE PULLUP } [get_ports { enc_a_0[2] }]; # IO40 / E3A
set_property -dict { PACKAGE_PIN Y9    IOSTANDARD LVCMOS33 PULLTYPE PULLUP } [get_ports { enc_b_0[2] }]; # IO41 / E3B

# Encoder 4 (E4A, E4B)
set_property -dict { PACKAGE_PIN F16   IOSTANDARD LVCMOS33 PULLTYPE PULLUP } [get_ports { enc_a_0[3] }]; # SPI SS   / E4A
set_property -dict { PACKAGE_PIN W15   IOSTANDARD LVCMOS33 PULLTYPE PULLUP } [get_ports { enc_b_0[3] }]; # SPI MISO / E4B

# Encoder 5 (E5A, E5B)
set_property -dict { PACKAGE_PIN U7    IOSTANDARD LVCMOS33 PULLTYPE PULLUP } [get_ports { enc_a_0[4] }]; # IO29    / E5A
set_property -dict { PACKAGE_PIN H15   IOSTANDARD LVCMOS33 PULLTYPE PULLUP } [get_ports { enc_b_0[4] }]; # SPI SCK / E5B

# Encoder 6 (E6A, E6B)
set_property -dict { PACKAGE_PIN V8    IOSTANDARD LVCMOS33 PULLTYPE PULLUP } [get_ports { enc_a_0[5] }]; # IO32 / E6A
set_property -dict { PACKAGE_PIN U8    IOSTANDARD LVCMOS33 PULLTYPE PULLUP } [get_ports { enc_b_0[5] }]; # IO31 / E6B

# Timing false path para entradas asíncronas de encoders
set_false_path -from [get_ports {enc_a_0[*] enc_b_0[*]}]


## =============================================================================
## 3. SYS_INPUT (13 BITS: Pedal + 6 Switches de Encoder + 6 Switches Generales)
## =============================================================================
## [0]  : Pedal de Loop       -> IO5      (T15)
## [1]  : Switch Encoder 1 ES1 -> IO12     (P18)
## [2]  : Switch Encoder 2 ES2 -> IO9      (V18)
## [3]  : Switch Encoder 3 ES3 -> IO39     (Y8)
## [4]  : Switch Encoder 4 ES4 -> IO28     (V6)
## [5]  : Switch Encoder 5 ES5 -> SPI MOSI (T12)
## [6]  : Switch Encoder 6 ES6 -> IO30     (V7)
## [7]  : Switch General 1 SW1 -> IO37     (Y7)
## [8]  : Switch General 2 SW2 -> IO36     (Y6)
## [9]  : Switch General 3 SW3 -> IO35     (W6)
## [10] : Switch General 4 SW4 -> IO34     (W10)
## [11] : Switch General 5 SW5 -> IO33     (V10)
## [12] : Switch General 6 SW6 -> IO38     (W8)
## =============================================================================

# Pedal de Loop
set_property -dict { PACKAGE_PIN U17   IOSTANDARD LVCMOS33 PULLUP true } [get_ports { sys_input[0] }];  # IO7      / Pedal

# Pulsadores Integrados de Encoders (ES1 .. ES6)
set_property -dict { PACKAGE_PIN P18   IOSTANDARD LVCMOS33 PULLUP true } [get_ports { sys_input[1] }];  # IO12     / ES1
set_property -dict { PACKAGE_PIN V18   IOSTANDARD LVCMOS33 PULLUP true } [get_ports { sys_input[2] }];  # IO9      / ES2
set_property -dict { PACKAGE_PIN Y8    IOSTANDARD LVCMOS33 PULLUP true } [get_ports { sys_input[3] }];  # IO39     / ES3
set_property -dict { PACKAGE_PIN V6    IOSTANDARD LVCMOS33 PULLUP true } [get_ports { sys_input[4] }];  # IO28     / ES4
set_property -dict { PACKAGE_PIN T12   IOSTANDARD LVCMOS33 PULLUP true } [get_ports { sys_input[5] }];  # SPI MOSI / ES5
set_property -dict { PACKAGE_PIN V7    IOSTANDARD LVCMOS33 PULLUP true } [get_ports { sys_input[6] }];  # IO30     / ES6

# Switches Generales (SW1 .. SW6)
set_property -dict { PACKAGE_PIN Y7    IOSTANDARD LVCMOS33 PULLUP true } [get_ports { sys_input[7] }];  # IO37     / SW1
set_property -dict { PACKAGE_PIN Y6    IOSTANDARD LVCMOS33 PULLUP true } [get_ports { sys_input[8] }];  # IO36     / SW2
set_property -dict { PACKAGE_PIN W6    IOSTANDARD LVCMOS33 PULLUP true } [get_ports { sys_input[9] }];  # IO35     / SW3
set_property -dict { PACKAGE_PIN W10   IOSTANDARD LVCMOS33 PULLUP true } [get_ports { sys_input[10] }]; # IO34     / SW4
set_property -dict { PACKAGE_PIN V10   IOSTANDARD LVCMOS33 PULLUP true } [get_ports { sys_input[11] }]; # IO33     / SW5
set_property -dict { PACKAGE_PIN W8    IOSTANDARD LVCMOS33 PULLUP true } [get_ports { sys_input[12] }]; # IO38     / SW6


## =============================================================================
## 4. PMOD A (JA) - DAC (PCM5102A)
## =============================================================================
## Pin 1 (JA1_P / Y18) : BCLK (SCLK / Bit Clock 3.072 MHz)
## Pin 3 (JA2_P / Y16) : SDATA (Serial Data DAC In)
## Pin 7 (JA3_P / U18) : MCLK (Master Clock 12.288 MHz)
## Pin 9 (JA4_P / W18) : LRCLK (Word Clock 48 kHz)
## =============================================================================
set_property -dict { PACKAGE_PIN Y18   IOSTANDARD LVCMOS33 } [get_ports { sclk_out_1 }];    # JA1 - DAC BCLK 3.072 MHz
set_property -dict { PACKAGE_PIN Y16   IOSTANDARD LVCMOS33 } [get_ports { sdata_0_out_0 }]; # JA3 - DAC SDATA
set_property -dict { PACKAGE_PIN U18   IOSTANDARD LVCMOS33 } [get_ports { mclk_out_dac }];  # JA7 - DAC MCLK 12.288 MHz
set_property -dict { PACKAGE_PIN W18   IOSTANDARD LVCMOS33 } [get_ports { lrclk_out_1 }];   # JA9 - DAC LRCLK 48 kHz


## =============================================================================
## 5. PMOD B (JB) - ADC (PCM1808)
## =============================================================================
## Pin 1 (JB1_P / W14) : MCLK (Master Clock 12.288 MHz)
## Pin 3 (JB2_P / T11) : SDATA (Serial Data ADC Out)
## Pin 7 (JB3_P / V16) : LRCLK (Word Clock 48 kHz)
## Pin 9 (JB4_P / V12) : BCLK (SCLK / Bit Clock 3.072 MHz)
## =============================================================================
set_property -dict { PACKAGE_PIN W14   IOSTANDARD LVCMOS33 } [get_ports { mclk_out_adc }];  # JB1 - ADC MCLK 12.288 MHz
set_property -dict { PACKAGE_PIN T11   IOSTANDARD LVCMOS33 } [get_ports { sdata_0_in_0 }];  # JB3 - ADC SDATA
set_property -dict { PACKAGE_PIN V16   IOSTANDARD LVCMOS33 } [get_ports { lrclk_out_0 }];   # JB7 - ADC LRCLK 48 kHz
set_property -dict { PACKAGE_PIN V12   IOSTANDARD LVCMOS33 } [get_ports { sclk_out_0 }];    # JB9 - ADC BCLK 3.072 MHz

