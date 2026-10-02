// Distorsion AUSTERA: waveshaper (wavetable) + level. SIN oversampling.
// Para diagnostico y como escalon 1 de la escalera de complejidad.
module fx_shaper_lite (
  input  logic               clk,
  input  logic               rst_n,
  input  logic               enable,
  input  logic               in_valid,
  output logic               in_ready,
  input  logic signed [31:0] in_data,
  output logic               out_valid,
  input  logic               out_ready,
  output logic signed [31:0] out_data,
  input  logic [31:0]        drive_16_16,
  input  logic signed [31:0] level_q1_31,
  input  logic               wt_wr_en,
  input  logic [7:0]         wt_wr_addr,
  input  logic [31:0]        wt_wr_data
);
  import fx_dsp_pkg::*;

  logic s_iv, s_ir, s_ov, s_or;
  logic signed [31:0] s_od;

  fx_waveshaper u_sh (
    .clk(clk), .rst_n(rst_n),
    .in_valid(s_iv), .in_ready(s_ir), .in_data(in_data),
    .out_valid(s_ov), .out_ready(s_or), .out_data(s_od),
    .drive_16_16(drive_16_16),
    .wt_wr_en(wt_wr_en), .wt_wr_addr(wt_wr_addr), .wt_wr_data(wt_wr_data)
  );

  // FSM chica: shaper -> level (1 mul registrado) -> out
  typedef enum logic [1:0] {ST_IDLE=2'd0, ST_WAIT=2'd1, ST_LVL=2'd2} st_t;
  st_t st;
  logic signed [31:0] y_r;
  logic               out_buf_valid;
  logic signed [31:0] out_buf;

  wire bypass = !enable;
  assign out_valid = out_buf_valid;
  assign out_data  = out_buf;
  wire out_fire = out_valid && out_ready;
  wire in_fire  = in_valid && in_ready;
  assign in_ready = (st == ST_IDLE) && !out_buf_valid && (bypass || s_ir);
  assign s_iv = (!bypass) && (st == ST_IDLE) && in_fire;
  assign s_or = (st == ST_WAIT);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      st <= ST_IDLE; y_r <= '0; out_buf_valid <= 1'b0; out_buf <= '0;
    end else begin
      if (out_fire) out_buf_valid <= 1'b0;
      if (bypass) begin
        st <= ST_IDLE;
        if (in_fire) begin out_buf <= in_data; out_buf_valid <= 1'b1; end
      end else begin
        case (st)
          ST_IDLE: if (in_fire) st <= ST_WAIT;
          ST_WAIT: if (s_ov && s_or) begin y_r <= s_od; st <= ST_LVL; end
          ST_LVL: begin
            out_buf       <= mul_aud_q31(y_r, level_q1_31);
            out_buf_valid <= 1'b1;
            st            <= ST_IDLE;
          end
          default: st <= ST_IDLE;
        endcase
      end
    end
  end
endmodule