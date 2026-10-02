// =============================================================================
// fx_synth_insert.sv  (v3 - parametrizable desde el PS + enable seguro)
//
// Inserto AXI-stream de la voz sintetizada. Todos los parametros vienen del
// regmap (ya no hardcodeados). Mezcla dry/synth con niveles del PS.
//   enable=0: bypass bit-perfect.
//   enable=1: out = dry*dry_level + synth*synth_level  (con saturacion)
//   synth_only fuerza dry_level=0 efectivo (solo synth).
//
// Transicion de enable segura: el enable global ya se congela en fx_core
// (fx_en_active en adapter_idle), asi que aca solo respetamos el handshake.
// =============================================================================
module fx_synth_insert (
  input  logic               clk,
  input  logic               rst_n,
  input  logic               enable,
  input  logic               synth_only,

  input  logic               in_valid,
  output logic               in_ready,
  input  logic signed [31:0] in_data,

  output logic               out_valid,
  input  logic               out_ready,
  output logic signed [31:0] out_data,

  // pitch/envelope del frontend
  input  logic [31:0]        base_phase_inc,
  input  logic               inc_valid,
  input  logic signed [31:0] env_vca_q1_31,

  // --- parametros del PS (regmap) ---
  input  logic [31:0]        p_waves,       // [2:0]w1 [5:3]w2 [8:6]w3
  input  logic [31:0]        p_ranges,      // [3:0]r1 [7:4]r2 [11:8]r3 signed
  input  logic signed [31:0] p_osc2_tune,   // Q2.30
  input  logic signed [31:0] p_osc3_tune,
  input  logic signed [31:0] p_osc1_level,  // Q1.31
  input  logic signed [31:0] p_osc2_level,
  input  logic signed [31:0] p_osc3_level,
  input  logic signed [31:0] p_noise_level,
  input  logic signed [31:0] p_synth_level, // Q1.31 nivel salida synth
  input  logic signed [31:0] p_dry_level,   // Q1.31 nivel dry en mezcla
  input  logic signed [31:0] p_f_b0, p_f_b1, p_f_b2, p_f_a1, p_f_a2,
  input  logic               p_filter_on
);
  import fx_dsp_pkg::*;

  typedef enum logic [1:0] { ST_IDLE, ST_WAIT, ST_MIX, ST_OUT } state_t;
  state_t st;

  logic signed [31:0] dry_r;
  logic               synth_tick;
  logic signed [31:0] synth_sample;
  logic               synth_sample_valid;
  logic signed [31:0] out_buf;
  logic               out_buf_valid;

  assign in_ready  = enable ? ((st == ST_IDLE) && !out_buf_valid) : out_ready;
  assign out_valid = enable ? out_buf_valid : in_valid;
  assign out_data  = enable ? out_buf       : in_data;

  wire in_fire  = enable && in_valid && in_ready;
  wire out_fire = out_valid && out_ready;

  // desempaquetar waves y ranges
  wire [2:0] w1 = p_waves[2:0];
  wire [2:0] w2 = p_waves[5:3];
  wire [2:0] w3 = p_waves[8:6];
  wire signed [3:0] r1 = p_ranges[3:0];
  wire signed [3:0] r2 = p_ranges[7:4];
  wire signed [3:0] r3 = p_ranges[11:8];

  fx_synth u_synth (
    .clk(clk), .rst_n(rst_n),
    .sample_tick(synth_tick), .base_phase_inc(base_phase_inc),
    .inc_valid(inc_valid), .env_vca_q1_31(env_vca_q1_31),
    .synth_out(synth_sample), .synth_valid(synth_sample_valid),
    .osc1_wave(w1), .osc2_wave(w2), .osc3_wave(w3),
    .osc1_range(r1), .osc2_range(r2), .osc3_range(r3),
    .osc2_tune_q2_30(p_osc2_tune), .osc3_tune_q2_30(p_osc3_tune),
    .osc1_level(p_osc1_level), .osc2_level(p_osc2_level), .osc3_level(p_osc3_level),
    .noise_level(p_noise_level),
    .f_b0(p_f_b0), .f_b1(p_f_b1), .f_b2(p_f_b2), .f_a1(p_f_a1), .f_a2(p_f_a2),
    .filter_on(p_filter_on)
  );

  // niveles efectivos de mezcla (synth_only anula el dry)
  wire signed [31:0] dry_lvl_eff = synth_only ? 32'sd0 : p_dry_level;

  logic signed [31:0] mix_dry, mix_syn;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      st<=ST_IDLE; dry_r<='0; synth_tick<=1'b0;
      out_buf<='0; out_buf_valid<=1'b0; mix_dry<='0; mix_syn<='0;
    end else begin
      synth_tick <= 1'b0;
      if (!enable) begin
        st<=ST_IDLE; out_buf_valid<=1'b0;
      end else begin
        if (out_fire) out_buf_valid <= 1'b0;
        case (st)
          ST_IDLE: if (in_fire) begin
            dry_r      <= in_data;
            synth_tick <= 1'b1;
            st         <= ST_WAIT;
          end
          ST_WAIT: if (synth_sample_valid) begin
            // dos productos: dry*dry_level y synth*synth_level
            mix_dry <= mul_aud_q31(dry_r, dry_lvl_eff);
            mix_syn <= mul_aud_q31(synth_sample, p_synth_level);
            st      <= ST_MIX;
          end
          ST_MIX: begin
            out_buf       <= sat_add32(mix_dry, mix_syn);
            out_buf_valid <= 1'b1;
            st            <= ST_OUT;
          end
          ST_OUT: if (out_fire) st <= ST_IDLE;
          default: st <= ST_IDLE;
        endcase
      end
    end
  end
endmodule