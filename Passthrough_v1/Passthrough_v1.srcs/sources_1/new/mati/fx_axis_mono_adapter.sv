`timescale 1ns / 1ps

module fx_axis_mono_adapter(
  input logic                clk,
  input logic                rst_n,

  //AXI-Stream IN (m_axis de I2S RX)
  input logic [31:0]         s_axis_tdata,
  input logic [2:0]          s_axis_tid,
  input logic                s_axis_tvalid,
  output logic               s_axis_tready,

  //AXI-Stream OUT (s_axis de I2S TX)
  output logic [31:0]        m_axis_tdata,
  output logic [2:0]         m_axis_tid,
  output logic               m_axis_tvalid,
  input logic                m_axis_tready, 

  //Mono hacia cadena FX (1 muestra x frame)
  output logic               in_valid,
  output logic signed [31:0] in_data,
  input logic                in_ready,

  //Mono desde cadena FX
  input logic                out_valid,
  input logic signed [31:0]  out_data,
  output logic               out_ready,

  output logic               idle
);
  //Estados de FSM
  typedef enum logic [0:0] {IN_WAIT_L=1'b0, IN_WAIT_R=1'b1} in_state_t;
  typedef enum logic [1:0] {OUT_IDLE=2'd0, OUT_SEND_L=2'd1, OUT_SEND_R=2'd2} out_state_t;

  in_state_t in_state;
  out_state_t out_state;

  // buffers
  logic                       y_buf_valid;
  logic signed [31:0]         y_buf;
  logic                       inflight; 

  // handshake y logica combinacional
  logic                       fire_in;
  logic                       fire_out;
  logic                       can_accept;
  logic signed [23:0]         audio_out_24;
  
  assign fire_in  = s_axis_tvalid && s_axis_tready;
  assign fire_out = m_axis_tvalid && m_axis_tready;

  assign out_ready = inflight && (!y_buf_valid) && (out_state == OUT_IDLE);
  assign can_accept = (!inflight) && (!y_buf_valid) && in_ready && (out_state == OUT_IDLE);
  assign s_axis_tready = (in_state == IN_WAIT_L) ? 1'b1 : can_accept;
  assign idle = (in_state == IN_WAIT_L) && (!inflight) && (!y_buf_valid) && (out_state == OUT_IDLE);

  // Recorte y saturación de Q3.29 a 24 bits
  always_comb begin
    logic signed [31:0] unclipped_sh = y_buf >>> 6;
    if (unclipped_sh > 32'sd8388607)
      audio_out_24 = 24'sh7FFFFF;
    else if (unclipped_sh < -32'sd8388608)
      audio_out_24 = 24'sh800000;
    else
      audio_out_24 = unclipped_sh[23:0];
  end

  // Reconstrucción de la trama I2S
  always_comb begin
    m_axis_tvalid = (out_state != OUT_IDLE);
    case (out_state) 
      OUT_SEND_L: begin
        // Ensamblamos: [31:28] PCUV (0000) | [27:4] Audio procesado | [3:0] Preámbulo L
        m_axis_tdata = {4'b0000, audio_out_24, 4'b0001};
        m_axis_tid   = 3'd0;
      end
      OUT_SEND_R: begin
        // Ensamblamos: [31:28] PCUV (0000) | [27:4] Audio procesado | [3:0] Preámbulo R
        m_axis_tdata = {4'b0000, audio_out_24, 4'b0011};
        m_axis_tid   = 3'd1;
      end
      default: begin
        m_axis_tdata = 0;
        m_axis_tid   = 0;        
      end
    endcase
  end

  // Captura de datos (sólo Right Channel) y extracción de bits
  always_ff @(posedge clk)begin
    if(!rst_n)begin
      in_valid <= 1'b0;
      in_state <= IN_WAIT_L;
      in_data  <= 'b0;
      inflight <= 1'b0;
    end else begin
      in_valid <= 1'b0;
      if(fire_in)begin
        if(in_state == IN_WAIT_R)begin
          if (s_axis_tid == 3'd1) begin
            // Extraemos los 24 bits de audio y los llevamos a Q3.29
            in_data  <= $signed(s_axis_tdata[27:4]) <<< 6;
            in_valid <= 1'b1;
            inflight <= 1'b1;
          end
          in_state <= IN_WAIT_L;
        end else begin
          if (s_axis_tid == 3'd0) begin
            in_state <= IN_WAIT_R;
          end
        end
      end
      
      if(out_valid && out_ready)begin
        inflight <= 1'b0;
      end
    end
  end

  // Manejo del buffer de salida
  always_ff @(posedge clk)begin
    if (!rst_n) begin
      y_buf <= 'b0;
      y_buf_valid <= 1'b0;
    end else begin
      if(out_valid && out_ready)begin
        y_buf <= out_data;
        y_buf_valid <= 1'b1;
      end
      if((out_state == OUT_SEND_R) && fire_out)begin
        y_buf_valid <= 1'b0;
      end
    end
  end

  // FSM de salida
  always_ff @(posedge clk)begin
    if (!rst_n) begin
      out_state <= OUT_IDLE;
    end else begin
      case (out_state) 
        OUT_IDLE: if (y_buf_valid) out_state <= OUT_SEND_L;
        OUT_SEND_L: if(fire_out) out_state <= OUT_SEND_R;
        OUT_SEND_R: if(fire_out) out_state <= OUT_IDLE;
        default: out_state <= OUT_IDLE;
      endcase
    end
  end
endmodule
