`timescale 1ns / 1ps

module fx_axis_mono_adapter(
  input logic                clk,
  input logic                rst_n,

  // AXI-Stream IN (m_axis de I2S RX)
  input logic [31:0]         s_axis_tdata,
  input logic [2:0]          s_axis_tid,
  input logic                s_axis_tvalid,
  output logic               s_axis_tready,

  // AXI-Stream OUT (s_axis de I2S TX)
  output logic [31:0]        m_axis_tdata,
  output logic [2:0]         m_axis_tid,
  output logic               m_axis_tvalid,
  input logic                m_axis_tready,

  // Mono hacia cadena FX (1 muestra por frame)
  output logic               in_valid,
  output logic signed [31:0] in_data,
  input logic                in_ready,

  // Mono desde cadena FX
  input logic                out_valid,
  input logic signed [31:0]  out_data,
  output logic               out_ready,

  output logic               idle
);

  // ===========================================================================
  // FIFO SETTINGS
  // ===========================================================================

  localparam int FIFO_DEPTH = 4;
  localparam int PTR_W      = 2;
  localparam int COUNT_W    = 3;

  // ===========================================================================
  // INPUT FRAME STATE
  //
  // RX entrega:
  //   TID=0 -> Left
  //   TID=1 -> Right
  //
  // Seguimos usando Right como muestra mono, igual que antes.
  // ===========================================================================

  typedef enum logic {
    IN_WAIT_L,
    IN_WAIT_R
  } in_state_t;

  in_state_t in_state;

  // ===========================================================================
  // OUTPUT FRAME STATE
  //
  // Cada muestra mono procesada se duplica:
  //   mono -> Left
  //        -> Right
  // ===========================================================================

  typedef enum logic [1:0] {
    OUT_IDLE,
    OUT_SEND_L,
    OUT_SEND_R
  } out_state_t;

  out_state_t out_state;

  // ===========================================================================
  // INPUT FIFO
  // ===========================================================================

  logic signed [31:0] in_fifo [0:FIFO_DEPTH-1];

  logic [PTR_W-1:0]   in_wr_ptr;
  logic [PTR_W-1:0]   in_rd_ptr;
  logic [COUNT_W-1:0] in_count;

  logic in_fifo_empty;
  logic in_fifo_full;

  logic in_push;
  logic in_pop;

  // ===========================================================================
  // OUTPUT FIFO
  // ===========================================================================

  logic signed [31:0] out_fifo [0:FIFO_DEPTH-1];

  logic [PTR_W-1:0]   out_wr_ptr;
  logic [PTR_W-1:0]   out_rd_ptr;
  logic [COUNT_W-1:0] out_count;

  logic out_fifo_empty;
  logic out_fifo_full;

  logic out_push;
  logic out_pop;

  // ===========================================================================
  // DSP IN-FLIGHT COUNTER
  //
  // Cuenta muestras que ya salieron del input FIFO hacia DSP pero que todavia
  // no regresaron por out_valid/out_ready.
  //
  // Reemplaza al viejo flag booleano "inflight".
  // ===========================================================================

  logic [15:0] inflight_count;

  logic dsp_in_fire;
  logic dsp_out_fire;

  // ===========================================================================
  // TX SAMPLE REGISTER
  // ===========================================================================

  logic signed [31:0] tx_sample;

  logic signed [31:0] tx_shifted;
  logic signed [23:0] audio_out_24;

  logic fire_axis_in;
  logic fire_axis_out;

  // ===========================================================================
  // BASIC FLAGS
  // ===========================================================================

  assign in_fifo_empty = (in_count == 0);
  assign in_fifo_full  = (in_count == FIFO_DEPTH);

  assign out_fifo_empty = (out_count == 0);
  assign out_fifo_full  = (out_count == FIFO_DEPTH);

  assign fire_axis_in =
      s_axis_tvalid &&
      s_axis_tready;

  assign fire_axis_out =
      m_axis_tvalid &&
      m_axis_tready;

  // ===========================================================================
  // INPUT AXI READY
  //
  // Si el FIFO tiene lugar, podemos seguir recibiendo frames aunque haya
  // muestras anteriores circulando por el DSP.
  // ===========================================================================

  assign s_axis_tready =
      !in_fifo_full;

  // ===========================================================================
  // INPUT FIFO -> DSP
  // ===========================================================================

  assign in_valid =
      !in_fifo_empty;

  assign in_data =
      in_fifo_empty
          ? 32'sd0
          : in_fifo[in_rd_ptr];

  assign dsp_in_fire =
      in_valid &&
      in_ready;

  assign in_pop =
      dsp_in_fire;

  // ===========================================================================
  // DSP -> OUTPUT FIFO
  // ===========================================================================

  assign out_ready =
      !out_fifo_full;

  assign dsp_out_fire =
      out_valid &&
      out_ready;

  assign out_push =
      dsp_out_fire;

  // Cuando TX esta libre, toma inmediatamente la muestra mas vieja del FIFO.
  assign out_pop =
      (out_state == OUT_IDLE) &&
      !out_fifo_empty;

  // ===========================================================================
  // INPUT FRAME DECODER
  // ===========================================================================

  assign in_push =
      fire_axis_in &&
      (in_state == IN_WAIT_R) &&
      (s_axis_tid == 3'd1);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      in_state <= IN_WAIT_L;
    end else begin

      if (fire_axis_in) begin

        case (in_state)

          IN_WAIT_L: begin
            if (s_axis_tid == 3'd0)
              in_state <= IN_WAIT_R;
          end

          IN_WAIT_R: begin

            if (s_axis_tid == 3'd1)
              in_state <= IN_WAIT_L;

            // Si por algun motivo aparece otro LEFT antes del RIGHT,
            // lo tomamos como comienzo de un frame nuevo.
            else if (s_axis_tid == 3'd0)
              in_state <= IN_WAIT_R;

            else
              in_state <= IN_WAIT_L;
          end

          default: begin
            in_state <= IN_WAIT_L;
          end

        endcase
      end
    end
  end

  // ===========================================================================
  // INPUT FIFO
  //
  // Conversión:
  //
  // PCM24 signed
  //   [27:4]
  //
  // -> sign extend a 32 bits
  // -> << 6
  //
  // Resultado interno Q3.29.
  // ===========================================================================

  always_ff @(posedge clk) begin
    if (!rst_n) begin

      in_wr_ptr <= 0;
      in_rd_ptr <= 0;
      in_count  <= 0;

    end else begin

      if (in_push) begin

        in_fifo[in_wr_ptr] <=
            $signed({
              {8{s_axis_tdata[27]}},
              s_axis_tdata[27:4]
            }) <<< 6;

        in_wr_ptr <=
            in_wr_ptr + 1'b1;
      end

      if (in_pop) begin

        in_rd_ptr <=
            in_rd_ptr + 1'b1;
      end

      case ({
        in_push,
        in_pop
      })

        2'b10:
          in_count <=
              in_count + 1'b1;

        2'b01:
          in_count <=
              in_count - 1'b1;

        default:
          in_count <=
              in_count;

      endcase
    end
  end

  // ===========================================================================
  // OUTPUT FIFO
  // ===========================================================================

  always_ff @(posedge clk) begin
    if (!rst_n) begin

      out_wr_ptr <= 0;
      out_rd_ptr <= 0;
      out_count  <= 0;

    end else begin

      if (out_push) begin

        out_fifo[out_wr_ptr] <=
            out_data;

        out_wr_ptr <=
            out_wr_ptr + 1'b1;
      end

      if (out_pop) begin

        out_rd_ptr <=
            out_rd_ptr + 1'b1;
      end

      case ({
        out_push,
        out_pop
      })

        2'b10:
          out_count <=
              out_count + 1'b1;

        2'b01:
          out_count <=
              out_count - 1'b1;

        default:
          out_count <=
              out_count;

      endcase
    end
  end

  // ===========================================================================
  // DSP IN-FLIGHT COUNTER
  // ===========================================================================

  always_ff @(posedge clk) begin
    if (!rst_n) begin

      inflight_count <= 0;

    end else begin

      case ({
        dsp_in_fire,
        dsp_out_fire
      })

        2'b10:
          inflight_count <=
              inflight_count + 1'b1;

        2'b01: begin
          if (inflight_count != 0)
            inflight_count <=
                inflight_count - 1'b1;
        end

        default:
          inflight_count <=
              inflight_count;

      endcase
    end
  end

  // ===========================================================================
  // OUTPUT FIFO -> TX SAMPLE REGISTER
  //
  // Sacamos una muestra del FIFO solamente cuando el transmisor L/R esta libre.
  // ===========================================================================

  always_ff @(posedge clk) begin
    if (!rst_n) begin

      tx_sample <= 32'sd0;

    end else begin

      if (out_pop) begin

        tx_sample <=
            out_fifo[out_rd_ptr];
      end
    end
  end

  // ===========================================================================
  // OUTPUT STATE MACHINE
  // ===========================================================================

  always_ff @(posedge clk) begin
    if (!rst_n) begin

      out_state <= OUT_IDLE;

    end else begin

      case (out_state)

        OUT_IDLE: begin

          if (!out_fifo_empty)
            out_state <= OUT_SEND_L;
        end

        OUT_SEND_L: begin

          if (fire_axis_out)
            out_state <= OUT_SEND_R;
        end

        OUT_SEND_R: begin

          if (fire_axis_out)
            out_state <= OUT_IDLE;
        end

        default: begin

          out_state <= OUT_IDLE;
        end

      endcase
    end
  end

  // ===========================================================================
  // Q3.29 -> PCM24 SATURATION
  // ===========================================================================

  always_comb begin

    tx_shifted =
        tx_sample >>> 6;

    if (tx_shifted > 32'sd8388607)
      audio_out_24 =
          24'sh7FFFFF;

    else if (tx_shifted < -32'sd8388608)
      audio_out_24 =
          24'sh800000;

    else
      audio_out_24 =
          tx_shifted[23:0];
  end

  // ===========================================================================
  // AXI OUTPUT
  // ===========================================================================

  always_comb begin

    m_axis_tvalid = 1'b0;
    m_axis_tdata  = 32'd0;
    m_axis_tid    = 3'd0;

    case (out_state)

      OUT_SEND_L: begin

        m_axis_tvalid = 1'b1;

        m_axis_tdata = {
          4'b0000,
          audio_out_24,
          4'b0001
        };

        m_axis_tid = 3'd0;
      end

      OUT_SEND_R: begin

        m_axis_tvalid = 1'b1;

        m_axis_tdata = {
          4'b0000,
          audio_out_24,
          4'b0011
        };

        m_axis_tid = 3'd1;
      end

      default: begin

        m_axis_tvalid = 1'b0;
        m_axis_tdata  = 32'd0;
        m_axis_tid    = 3'd0;
      end

    endcase
  end

  // ===========================================================================
  // IDLE
  //
  // Ahora significa realmente que no queda ninguna muestra:
  //
  // - a medio recibir
  // - esperando entrar al DSP
  // - circulando dentro del DSP
  // - esperando salir
  // - siendo enviada al TX
  //
  // Esto sera util despues para CONFIG_COMMIT / drain.
  // ===========================================================================

  assign idle =
      (in_state == IN_WAIT_L) &&
      in_fifo_empty &&
      (inflight_count == 0) &&
      out_fifo_empty &&
      (out_state == OUT_IDLE);

  // ===========================================================================
  // SIMULATION CHECKS
  // ===========================================================================

`ifndef SYNTHESIS

  always_ff @(posedge clk) begin
    if (rst_n) begin

      if (in_push && in_fifo_full)
        $error(
          "fx_axis_mono_adapter: input FIFO overflow"
        );

      if (in_pop && in_fifo_empty)
        $error(
          "fx_axis_mono_adapter: input FIFO underflow"
        );

      if (out_push && out_fifo_full)
        $error(
          "fx_axis_mono_adapter: output FIFO overflow"
        );

      if (out_pop && out_fifo_empty)
        $error(
          "fx_axis_mono_adapter: output FIFO underflow"
        );

      if (
        dsp_out_fire &&
        (inflight_count == 0) &&
        !dsp_in_fire
      )
        $error(
          "fx_axis_mono_adapter: DSP output without inflight sample"
        );
    end
  end

`endif

endmodule