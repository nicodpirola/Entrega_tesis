// =============================================================================
// fx_synth_frontend.sv  (v2 - env_gain configurable desde el PS)
//   audio post-DCB -> envelope -> env_vca (Q1.31, calibrado)
//                  -> LPF pitch -> ZCD -> periodo -> phase_inc
//
// El VCA scaling ahora es: env_vca = clamp( (env_q3_29 * env_gain) << SHIFT , 1 )
//   env_gain (Q1.31, del PS) = ajuste fino lineal
//   ENV_VCA_SHIFT (param)    = ganancia gruesa (potencias de 2) para señal debil
// =============================================================================
module fx_synth_frontend #(
  parameter int GLIDE = 8,
  parameter int ENV_VCA_SHIFT = 4    // ganancia gruesa base (señal debil del theremin)
)(
  input  logic               clk,
  input  logic               rst_n,
  input  logic               sample_valid,
  input  logic signed [31:0] sample_data_q3_29,

  input  logic signed [31:0] env_gain_q1_31,   // ajuste fino del PS

  output logic signed [31:0] env_q3_29,
  output logic signed [31:0] env_vca_q1_31,
  output logic               gate,
  output logic               pitch_locked,
  output logic [31:0]        period_16_16,
  output logic               period_valid,
  output logic [31:0]        base_phase_inc,
  output logic               inc_valid
);
  import fx_dsp_pkg::*;

  logic env_update;
  fx_envelope u_env (
    .clk(clk), .rst_n(rst_n),
    .sample_valid(sample_valid), .sample_data(sample_data_q3_29),
    .env_out(env_q3_29), .gate(gate), .env_update(env_update),
    .a_atk_q1_31(32'sh7F77_C02F), .a_rel_q1_31(32'sh7FFB_72FF),
    .gate_on_thr_q3_29(32'sh0051_EB85), .gate_off_thr_q3_29(32'sh0028_F5C3)
  );

  logic pitch_lpf_ready, pitch_lpf_valid;
  logic signed [31:0] pitch_lpf_data;
  fx_biquad u_pitch_lpf (
    .clk(clk), .rst_n(rst_n), .state_clear(!gate), .enable(1'b1),
    .in_valid(sample_valid), .in_ready(pitch_lpf_ready), .in_data(sample_data_q3_29),
    .out_valid(pitch_lpf_valid), .out_ready(1'b1), .out_data(pitch_lpf_data),
    .b0_q2_30(32'sh00EB_F405), .b1_q2_30(32'sh01D7_E80A), .b2_q2_30(32'sh00EB_F405),
    .a1_q2_30(32'sh977D_0A40), .a2_q2_30(32'sh2C32_C5D3)
  );

  fx_pitch_zcd #(.PERIOD_MIN_Q16(32'd8<<16), .PERIOD_MAX_Q16(32'd1200<<16)) u_pitch (
    .clk(clk), .rst_n(rst_n),
    .sample_valid(pitch_lpf_valid), .sample_data(pitch_lpf_data),
    .gate(gate), .zc_hyst_q3_29(32'sh0028_F5C3),
    .period_16_16(period_16_16), .period_valid(period_valid)
  );

  fx_period_to_inc #(.GLIDE(GLIDE)) u_p2i (
    .clk(clk), .rst_n(rst_n),
    .period_16_16(period_16_16), .period_valid(period_valid),
    .gate(gate), .sample_tick(sample_valid),
    .phase_inc(base_phase_inc), .inc_valid(inc_valid)
  );

  always_ff @(posedge clk) begin
    if (!rst_n)         pitch_locked <= 1'b0;
    else if (!gate)     pitch_locked <= 1'b0;
    else if (inc_valid) pitch_locked <= 1'b1;
  end

  logic signed [31:0] env_vca_next;
  // env Q3.29 -> * env_gain (fino) -> << SHIFT (grueso) -> clamp -> Q1.31
  always_comb begin
    logic signed [31:0] scaled_q329;
    logic [63:0]        shifted;
    env_vca_next = 32'sd0;
    if (gate && pitch_locked && (env_q3_29 > 0)) begin
      scaled_q329 = mul_aud_q31(env_q3_29, env_gain_q1_31);   // Q3.29 fino
      shifted     = $unsigned(scaled_q329) << ENV_VCA_SHIFT;   // grueso + a Q1.31
      if (shifted >= 64'h0000_0000_7FFF_FFFF)
        env_vca_next = 32'sh7FFF_FFFF;
      else
        env_vca_next = $signed(shifted[31:0]);
    end
  end

  // Pipeline (Rompe el TNS separando el calculo del multiplicador posterior)
  always_ff @(posedge clk) begin
    if (!rst_n) env_vca_q1_31 <= 32'sd0;
    else        env_vca_q1_31 <= env_vca_next;
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk)
    if (rst_n && sample_valid && !pitch_lpf_ready)
      $error("fx_synth_frontend: overrun en LPF de pitch");
`endif
endmodule