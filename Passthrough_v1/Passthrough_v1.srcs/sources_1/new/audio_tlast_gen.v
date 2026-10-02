`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10.03.2026 18:24:47
// Design Name: 
// Module Name: audio_tlast_gen
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
module axis_tlast_gen_transparent (
    input  wire        clk,
    input  wire        resetn,
    
    // Entrada de Audio (viene del adder)
    input  wire [31:0] s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    
    // Salida hacia el FIFO de entrada
    output wire [31:0] m_axis_tdata,
    output wire        m_axis_tvalid,
    output wire        m_axis_tlast,
    input  wire        m_axis_tready
);

    // Parámetros del paquete (ej. 1024 muestras = 4KB en 32-bit)
    parameter integer PKT_SIZE = 1024;
    reg [15:0] count_reg;

    // PASSTHROUGH (CERO ciclos de delay)
    assign m_axis_tdata  = s_axis_tdata;
    assign m_axis_tvalid = s_axis_tvalid;
    assign s_axis_tready = m_axis_tready;

    // Generación de TLAST basada en el conteo
    assign m_axis_tlast = (count_reg == (PKT_SIZE - 1));

    always @(posedge clk) begin
        if (!resetn) begin
            count_reg <= 0;
        end else begin
            // Solo contamos cuando ocurre un apretón de manos (handshake) exitoso
            if (s_axis_tvalid && m_axis_tready) begin
                if (m_axis_tlast)
                    count_reg <= 0;
                else
                    count_reg <= count_reg + 1;
            end
        end
    end
endmodule