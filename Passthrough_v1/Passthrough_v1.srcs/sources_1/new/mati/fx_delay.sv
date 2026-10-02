
// fx_delay_block.sv (enable + DC blocker + LPF + softclip )

module fx_delay #(
  parameter int ADDR_W = 15
)(
  input  logic               clk,
  input  logic               rst_n,
  input  logic               enable,

  input  logic               in_valid,
  output logic               in_ready,
  input  logic signed [31:0] in_data,

  output logic               out_valid,
  input  logic               out_ready,
  output logic signed [31:0] out_data,

  input  logic [31:0]        D_16_16,
  input  logic signed [31:0] fb_q1_31,
  input  logic signed [31:0] wet_q1_31,
  input  logic signed [31:0] lpf_G_q1_31

`ifdef SIM
  ,
  output logic               dbg_clear_busy,
  output logic               dbg_clear_done
`endif
);

  import fx_dsp_pkg::*;

  // Output buffer
  logic               out_buf_valid;
  logic signed [31:0] out_buf;
  assign out_valid = out_buf_valid;
  assign out_data  = out_buf;
  wire out_fire = out_valid && out_ready;

  // delay_line_core
  logic               req_valid, req_ready;
  logic signed [31:0] d_raw;
  logic               d_valid, d_ready;
  logic               w_valid, w_ready;
  logic signed [31:0] w_in;
  logic               clear_req, clear_busy, clear_done;

`ifdef SIM
  assign dbg_clear_busy = clear_busy;
  assign dbg_clear_done = clear_done;
`endif

  delay_line #(.ADDR_W(ADDR_W)) u_delay_line (
    .clk(clk), .rst_n(rst_n),
    .req_valid(req_valid), .req_ready(req_ready), .D_16_16(D_16_16),
    .d_out(d_raw), .d_valid(d_valid), .d_ready(d_ready),
    .w_valid(w_valid), .w_ready(w_ready), .w_in(w_in),
    .clear_req(clear_req), .clear_busy(clear_busy), .clear_done(clear_done),
    .write_ptr_dbg()
  );

  // DC blocker
  logic               dc_in_valid, dc_in_ready;
  logic signed [31:0] dc_in_data;
  logic               dc_out_valid, dc_out_ready;
  logic signed [31:0] dc_out_data;
  logic               dc_state_clear;

  localparam logic signed [31:0] DC_R_Q31 = 32'sh7FD5_2286;

  fx_dc_blocker_1pole u_dc (
    .clk(clk), .rst_n(rst_n),
    .in_valid(dc_in_valid), .in_ready(dc_in_ready), .in_data(dc_in_data),
    .out_valid(dc_out_valid), .out_ready(dc_out_ready), .out_data(dc_out_data),
    .R_q1_31(DC_R_Q31), .state_clear(dc_state_clear)
  );

  // LPF TPT
  logic               lpf_in_valid, lpf_in_ready;
  logic signed [31:0] lpf_in_data;
  logic               lpf_out_valid;
  logic signed [31:0] lpf_out_data;
  logic               lpf_state_clear;

  fx_lpf_1p_tpt u_lpf (
    .clk(clk), .rst_n(rst_n),
    .in_valid(lpf_in_valid), .in_ready(lpf_in_ready), .in_data(lpf_in_data),
    .out_valid(lpf_out_valid), .out_ready(1'b1), .out_data(lpf_out_data),
    .G_q1_31(lpf_G_q1_31), .state_clear(lpf_state_clear)
  );

  // DC a LPF chain
  assign lpf_in_valid = dc_out_valid;
  assign lpf_in_data  = dc_out_data;
  assign dc_out_ready = lpf_in_ready;

  // Enable rise
  logic enable_d;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) enable_d <= 1'b0;
    else        enable_d <= enable;
  end
  wire enable_rise = enable && !enable_d;


  // FSM 10 estados (4 bits)
  typedef enum logic [3:0] {
    ST_IDLE      = 4'd0,
    ST_WAIT_D    = 4'd1,
    ST_WAIT_DC   = 4'd2,
    ST_WAIT_LPF  = 4'd3,
    ST_MUL       = 4'd4,
    ST_MIX       = 4'd5,
    ST_CLIP_PRE  = 4'd6,
    ST_CLIP_MUL  = 4'd7,
    ST_CLIP_ADD  = 4'd8,
    ST_WAIT_W    = 4'd9
  } state_t;

  state_t state;
  logic signed [31:0] x_reg;

  // Pipeline registers
  logic signed [31:0] lpf_data_r;
  logic signed [31:0] wet_term_r;
  logic signed [31:0] fb_term_r;
  logic signed [31:0] w_pre_r;

  // Softclip pipeline registers
  logic               sc_neg_r;
  logic signed [31:0] sc_delta_r;
  logic signed [31:0] sc_base_r;
  logic signed [31:0] sc_k_r;
  logic signed [31:0] sc_mul_r;

  wire in_fire = in_valid && in_ready;
  wire w_fire  = w_valid && w_ready;

  // Bypass
  wire bypass_mode = (!enable) || clear_busy;
  wire can_accept_bypass = (state == ST_IDLE) && (!out_buf_valid);
  wire can_accept_active = (state == ST_IDLE) && (!out_buf_valid) && req_ready && enable && !clear_busy;
  assign in_ready = bypass_mode ? can_accept_bypass : can_accept_active;

  // Clear control
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      clear_req <= 1'b0; dc_state_clear <= 1'b0; lpf_state_clear <= 1'b0;
    end else begin
      clear_req <= 1'b0; dc_state_clear <= 1'b0; lpf_state_clear <= 1'b0;
      if (enable_rise && (state == ST_IDLE) && !out_buf_valid && !clear_busy) begin
        clear_req <= 1'b1; dc_state_clear <= 1'b1; lpf_state_clear <= 1'b1;
      end
    end
  end

  // Handshake signals
  assign req_valid  = (!bypass_mode) && (state == ST_IDLE) && in_fire;
  assign d_ready    = (state == ST_WAIT_D) && dc_in_ready;
  assign dc_in_valid= (state == ST_WAIT_D) && d_valid && dc_in_ready;
  assign dc_in_data = d_raw;
  assign w_valid    = (state == ST_WAIT_W);

  // Softclip constants
  localparam logic signed [31:0] SC_T1_Q29 = 32'sh1666_6666;
  localparam logic signed [31:0] SC_T2_Q29 = 32'sh1E66_6666;
  localparam logic signed [31:0] SC_K1_Q31 = 32'sh7333_3333;
  localparam logic signed [31:0] SC_K2_Q31 = 32'sh5999_999A;
  localparam logic signed [31:0] SC_Y2_Q29 = 32'sh1D99_9999; // T1 + (T2-T1)*k1

  // Secuencial principal
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state <= ST_IDLE; x_reg <= '0; out_buf_valid <= 1'b0; out_buf <= '0;
      w_in <= '0; lpf_data_r <= '0; wet_term_r <= '0; fb_term_r <= '0;
      w_pre_r <= '0; sc_neg_r <= 1'b0; sc_delta_r <= '0;
      sc_base_r <= '0; sc_k_r <= '0; sc_mul_r <= '0;
    end else begin
      if (out_fire) out_buf_valid <= 1'b0;

      if (bypass_mode) begin
        state <= ST_IDLE;
        if (in_fire) begin out_buf <= in_data; out_buf_valid <= 1'b1; end
      end else begin
        unique case (state)

          ST_IDLE: if (in_fire) begin x_reg <= in_data; state <= ST_WAIT_D; end

          ST_WAIT_D: if (d_valid && d_ready) state <= ST_WAIT_DC;

          ST_WAIT_DC: if (dc_out_valid && dc_out_ready) state <= ST_WAIT_LPF;

          ST_WAIT_LPF: if (lpf_out_valid) begin
            lpf_data_r <= lpf_out_data;
            state      <= ST_MUL;
          end

          ST_MUL: begin
            wet_term_r <= mul_aud_q31(lpf_data_r, wet_q1_31);
            fb_term_r  <= mul_aud_q31(lpf_data_r, fb_q1_31);
            state      <= ST_MIX;
          end

          ST_MIX: begin
            out_buf       <= sat_add32(x_reg, wet_term_r);
            out_buf_valid <= 1'b1;
            w_pre_r       <= sat_add32(x_reg, fb_term_r);
            state         <= ST_CLIP_PRE;
          end

          ST_CLIP_PRE: begin
            logic signed [31:0] a_l;
            a_l = $signed(abs32(w_pre_r));
            sc_neg_r <= w_pre_r[31];

            if (a_l <= $signed(SC_T1_Q29)) begin
              w_in  <= w_pre_r;
              state <= ST_WAIT_W;
            end else if (a_l <= $signed(SC_T2_Q29)) begin
              sc_delta_r <= sat_sub32(a_l, SC_T1_Q29);
              sc_base_r  <= SC_T1_Q29;
              sc_k_r     <= SC_K1_Q31;
              state      <= ST_CLIP_MUL;
            end else begin
              sc_delta_r <= sat_sub32(a_l, SC_T2_Q29);
              sc_base_r  <= SC_Y2_Q29;
              sc_k_r     <= SC_K2_Q31;
              state      <= ST_CLIP_MUL;
            end
          end

          ST_CLIP_MUL: begin
            sc_mul_r <= mul_aud_q31(sc_delta_r, sc_k_r);
            state    <= ST_CLIP_ADD;
          end

          ST_CLIP_ADD: begin
            logic signed [31:0] y_mag;
            y_mag = sat_add32(sc_base_r, sc_mul_r);
            w_in  <= sc_neg_r ? -y_mag : y_mag;
            state <= ST_WAIT_W;
          end

          ST_WAIT_W: if (w_fire) state <= ST_IDLE;
          default: state <= ST_IDLE;
        endcase
      end
    end
  end

`ifdef SIM
  always_ff @(posedge clk) if (rst_n) begin
    if (in_fire) assert(!out_buf_valid)
      else $error("fx_delay_block: out_buf_valid=1 on in_fire");
  end
`endif
endmodule
