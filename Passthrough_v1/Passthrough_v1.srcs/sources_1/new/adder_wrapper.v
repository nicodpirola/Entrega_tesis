`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10.03.2026 17:38:28
// Design Name: 
// Module Name: adder_wrapper
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.02 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module axi_stream_looper_mixer (
    input clk,
    input resetn,

    // Control de modo (Manejado desde C via AXI GPIO)
    // 2'b00: IDLE, 2'b01: RECORD, 2'b10: PLAY, 2'b11: OVERDUB
    input [1:0]  mode,

    // Entrada 0: Audio en Vivo (Desde I2S RX)
    input [31:0] s0_axis_tdata,
    input        s0_axis_tvalid,
    input        s0_axis_tlast,
    input [2:0]  s0_axis_tid,
    input [3:0]  s0_axis_tkeep,
    output       s0_axis_tready,

    // Entrada 1: Audio de la RAM (Desde DMA MM2S)
    input [31:0] s1_axis_tdata,
    input        s1_axis_tvalid,
    input        s1_axis_tlast,
    input [2:0]  s1_axis_tid,
    input [3:0]  s1_axis_tkeep,
    output       s1_axis_tready,

    // Salida 0: Al Parlante (Hacia I2S TX)
    output [31:0] m_i2s_axis_tdata,
    output        m_i2s_axis_tvalid,
    output        m_i2s_axis_tlast,
    output [2:0]  m_i2s_axis_tid,
    output [3:0]  m_i2s_axis_tkeep,
    input         m_i2s_axis_tready,

    // Salida 1: De vuelta a la RAM (Hacia DMA S2MM)
    output [31:0] m_dma_axis_tdata,
    output        m_dma_axis_tvalid,
    output        m_dma_axis_tlast,
    output [2:0]  m_dma_axis_tid,
    output [3:0]  m_dma_axis_tkeep,
    input         m_dma_axis_tready
);

    // ==========================================
    // 1. SINCRONIZADOR DE RELOJ (CDC) PARA 'MODE'
    // ==========================================
    // Sincronizamos clk del GPIO de los modos (50MHz) con el de auido (12.288MHz))
    reg [1:0] mode_sync_1, mode_sync_2;
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            mode_sync_1 <= 2'b00;
            mode_sync_2 <= 2'b00;
        end else begin
            mode_sync_1 <= mode;
            // Solo aplicamos el cambio de modo cuando estamos 
            // exactamente en la muestra del canal izquierdo (tid == 0)
            if (s0_axis_tvalid && s0_axis_tid == 3'd0) begin
                mode_sync_2 <= mode_sync_1;
            end
        end
    end

    // ==========================================
    // 2. LOGICA DE DATOS
    // ==========================================
    // FORMATO I2S SUB-FRAME (32 bits):
    //   [31]    P  - Parity
    //   [30]    C  - Channel Status
    //   [29]    U  - User bit
    //   [28]    V  - Validity (0=valido)
    //   [27:4]  Audio Sample (24-bit signed)
    //   [3:0]   Preamble code (identifica L/R y bloques)

    // Se usa la metadata del I2S RX en vivo
    wire [3:0]  live_meta_hi  = s0_axis_tdata[31:28]; // P, C, U, V
    wire [3:0]  live_preamble = s0_axis_tdata[3:0];   // Preamble
    wire signed [23:0] live_audio = s0_axis_tdata[27:4];//audio limpio
    reg signed [23:0] last_ram_audio; // "Sample & hold" (solo audio de la ram):
    always @(posedge clk or negedge resetn) begin
        if (!resetn)
            last_ram_audio <= 24'd0;
        else if (s1_axis_tvalid && s1_axis_tready)
            last_ram_audio <= s1_axis_tdata[27:4];
    end
    
    // ==========================================
    // 3. MEZCLA
    // ==========================================
    
    wire signed [23:0] ram_audio = s1_axis_tvalid ? s1_axis_tdata[27:4] : last_ram_audio;
    wire signed [24:0] sum = $signed(live_audio) + $signed(ram_audio);  // MEZCLA CON SATURACION
    reg signed [23:0] mixed_audio;
    always @(*) begin
        if (sum > 25'sh7FFFFF)
            mixed_audio = 24'h7FFFFF;
        else if (sum < -25'sh800000)
            mixed_audio = 24'h800000;
        else
            mixed_audio = sum[23:0];
    end
    // Reconstrucción de muestra audio procesado + metadata correcta del I2S RX
    // P (parity) se RECALCULA para cada frame: P = XOR de bits [30:0] (paridad par)
    wire [31:0] live_frame  = s0_axis_tdata; // Passthrough: frame original intacto
    wire [30:0] mix_bits   = {live_meta_hi[2:0], mixed_audio, live_preamble};
    wire [31:0] mixed_frame = {^mix_bits, mix_bits};

    // Ruteo de senales segun el modo operativo
    reg [31:0] i2s_out_data;
    reg [31:0] dma_out_data;

    always @(*) begin
        case(mode_sync_2)
            2'b00: i2s_out_data = live_frame;
            2'b01: i2s_out_data = live_frame;
            2'b10: i2s_out_data = mixed_frame;
            2'b11: i2s_out_data = mixed_frame;
        endcase
    end
    
    // DMA siempre recibe lo que suena en el parlante para grabacion SD
    always @(*) begin
        dma_out_data = i2s_out_data;
    end

    assign m_i2s_axis_tdata = i2s_out_data;
    assign m_dma_axis_tdata = dma_out_data;

    // ==========================================
    // 4. LOGICA DE CONTROL (HANDSHAKE AXI-STREAM)
    // ==========================================
    // Passthrough para todas los demás datos de control
    assign m_i2s_axis_tlast = s0_axis_tlast;
    assign m_i2s_axis_tid   = s0_axis_tid;
    assign m_i2s_axis_tkeep = s0_axis_tkeep;
    
    assign m_dma_axis_tlast = s0_axis_tlast;
    assign m_dma_axis_tid   = s0_axis_tid;
    assign m_dma_axis_tkeep = s0_axis_tkeep;

    // I2S TX y DMA S2MM siempre reciben datos, el software en C 
    // se encarga de ignorarlos o guardarlos segun sea necesario.
    assign m_i2s_axis_tvalid = s0_axis_tvalid;
    assign m_dma_axis_tvalid = s0_axis_tvalid;

    // usamos el TREADY del TX de adelante para atrás, para llamar a la siguiente muestra desde el RX
    assign s0_axis_tready = m_i2s_axis_tready;

    // Solo se llaman muestras desde la RAM en modo PLAY y OVERDUB
    assign ram_active = (mode_sync_2 == 2'b10 || mode_sync_2 == 2'b11);
    assign s1_axis_tready = ram_active && s0_axis_tvalid && s0_axis_tready;

endmodule
