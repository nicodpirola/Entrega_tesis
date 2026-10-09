// =============================================================================
// fx_synth_frontend.sv
//
// audio post-DCB
//      -> envelope
//      -> env_vca
//      -> LPF pitch
//      -> detector de periodo:
//           PITCH_V2 = 1: YIN a 48 kHz (fx_pitch_yin48) + post-procesado (fx_pitch_post)
//           PITCH_V2 = 0: YIN a 12 kHz (fx_pitch_yin) o cruces por cero (fx_pitch_zcd)
//      -> periodo
//      -> phase_inc
//
// pitch_ctrl / pitch_cfg2 (REG_PITCH_CTRL / REG_PITCH_CFG2) solo se usan con PITCH_V2:
//   pitch_ctrl[0]     perfil del prefiltro de YIN (0 guitarra, 1 theremin)
//   pitch_ctrl[1]     memoria de nota: octava de arriba
//   pitch_ctrl[2]     memoria de nota: subarmonicos x2 x3 x4
//   pitch_ctrl[3]     re-ataque del VCA en cada pua
//   pitch_ctrl[7:4]   confianza (128avos, 0 = apagada)
//   pitch_ctrl[11:8]  confianza para el primer enganche (0 = apagada)
//   pitch_ctrl[15:12] detector de pua: env > ONK/8 * minimo de 20 ms
//   pitch_ctrl[20:16] espera despues de la pua (ms)
//   pitch_ctrl[26:21] K: estimaciones coincidentes para aceptar un salto
//   pitch_ctrl[31:27] K0: idem para el primer enganche
//   pitch_cfg2[7:0]   ms de nota estable para activar la memoria
// =============================================================================

module fx_synth_frontend #(
    parameter int ENV_VCA_SHIFT = 4,
    parameter bit PITCH_YIN     = 1'b1,   // (solo con PITCH_V2 = 0) 1: YIN 12 kHz   0: cruces por cero
    parameter bit PITCH_V2      = 1'b1,   // 1: YIN 48 kHz + post-procesado
    parameter int YIN_LANES     = 2       // carriles paralelos de fx_pitch_yin48 (1, 2 o 4)
)(
    input  logic               clk,
    input  logic               rst_n,

    input  logic               sample_valid,
    input  logic signed [31:0] sample_data_q3_29,

    input  logic signed [31:0] env_gain_q1_31,
    input  logic signed [31:0] env_attack_q1_31,
    input  logic signed [31:0] env_release_q1_31,
    input  logic signed [31:0] gate_on_thr_q3_29,
    input  logic signed [31:0] gate_off_thr_q3_29,
    input  logic signed [31:0] zc_hyst_q3_29,
    input  logic        [4:0]  glide_shift,
    input  logic        [31:0] pitch_ctrl,
    input  logic        [31:0] pitch_cfg2,

    output logic signed [31:0] env_q3_29,
    output logic signed [31:0] env_vca_q1_31,

    output logic               gate,
    output logic               pitch_locked,

    output logic [31:0]        period_16_16,
    output logic               period_valid,

    output logic [31:0]        base_phase_inc,
    output logic               inc_valid,

    output logic               pitch_ataque,     // pulso: pua detectada (estado/depuracion)
    output logic               pitch_overrun     // YIN no termino a tiempo (no deberia pasar)
);

import fx_dsp_pkg::*;

// =============================================================================
// ENVELOPE
// =============================================================================

logic env_update;

fx_envelope u_env(
    .clk                   (clk),
    .rst_n                 (rst_n),

    .sample_valid          (sample_valid),
    .sample_data           (sample_data_q3_29),

    .env_out               (env_q3_29),
    .gate                  (gate),
    .env_update            (env_update),

    .a_atk_q1_31           (env_attack_q1_31),
    .a_rel_q1_31           (env_release_q1_31),

    .gate_on_thr_q3_29     (gate_on_thr_q3_29),
    .gate_off_thr_q3_29    (gate_off_thr_q3_29)
);

// =============================================================================
// LPF PARA DETECCION DE PITCH
// =============================================================================

logic               pitch_lpf_ready;
logic               pitch_lpf_valid;
logic signed [31:0] pitch_lpf_data;

fx_biquad u_pitch_lpf(
    .clk        (clk),
    .rst_n      (rst_n),

    .state_clear(!gate),
    .enable     (1'b1),

    .in_valid   (sample_valid),
    .in_ready   (pitch_lpf_ready),
    .in_data    (sample_data_q3_29),

    .out_valid  (pitch_lpf_valid),
    .out_ready  (1'b1),
    .out_data   (pitch_lpf_data),

    .b0_q2_30   (32'sh063F_9666),
    .b1_q2_30   (32'sh0C7F_2CCD),
    .b2_q2_30   (32'sh063F_9666),

    .a1_q2_30   (32'shC3A9_0444),
    .a2_q2_30   (32'sh1555_5555)
);

// =============================================================================
// ZERO CROSSING / PERIODO
// =============================================================================

logic pitch_retrig;

generate
if (PITCH_V2) begin : g_pitch_v2

    logic [31:0] yin_period;
    logic        yin_valid;
    logic [33:0] yin_cl;
    logic [51:0] yin_cr;
    logic        yin_busy;

    fx_pitch_yin48 #(
        .N         (YIN_LANES),
        .THETA_NUM (19),       // umbral 19/128 = 0,148
        .TAU_MIN   (6),        // 8 kHz
        .TAU_MAX   (800),      // 60 Hz
        .HOP       (16)        // una estimacion cada 16 muestras (3 kHz)
    ) u_yin(
        .clk          (clk),
        .rst_n        (rst_n),
        .perfil       (pitch_ctrl[0]),
        .sample_valid (pitch_lpf_valid),
        .sample_data  (pitch_lpf_data),
        .period_16_16 (yin_period),
        .period_valid (yin_valid),
        .conf_cl      (yin_cl),
        .conf_cr      (yin_cr),
        .busy         (yin_busy),
        .overrun      (pitch_overrun)
    );

    fx_pitch_post u_post(
        .clk               (clk),
        .rst_n             (rst_n),
        .en_oct            (pitch_ctrl[1]),
        .en_sub            (pitch_ctrl[2]),
        .mem_ms            (pitch_cfg2[7:0]),
        .conf_num          (pitch_ctrl[7:4]),
        .conf0_num         (pitch_ctrl[11:8]),
        .en_retrig         (pitch_ctrl[3]),
        .espera_ms         (pitch_ctrl[20:16]),
        .k_salto           (pitch_ctrl[26:21]),
        .k0_salto          ({1'b0, pitch_ctrl[31:27]}),
        .onk               (pitch_ctrl[15:12]),
        .sample_valid      (env_update),
        .env_q3_29         (env_q3_29),
        .gate              (gate),
        .gate_on_thr_q3_29 (gate_on_thr_q3_29),
        .in_valid          (yin_valid),
        .in_period_16_16   (yin_period),
        .in_cl             (yin_cl),
        .in_cr             (yin_cr),
        .out_valid         (period_valid),
        .out_period_16_16  (period_16_16),
        .ataque            (pitch_ataque),
        .retrig            (pitch_retrig)
    );

end else begin : g_pitch_v1

    assign pitch_retrig  = 1'b0;
    assign pitch_ataque  = 1'b0;
    assign pitch_overrun = 1'b0;

    if (PITCH_YIN) begin : g_pitch_yin

        fx_pitch_yin #(
            .THETA_NUM (19),       // umbral 19/128 = 0,148
            .TAU_MIN   (5),        // 2400 Hz
            .TAU_MAX   (200),      // 60 Hz
            .REF_PMAX  (128)       // refinamiento a 48 kHz por encima de 375 Hz
        ) u_pitch(
            .clk            (clk),
            .rst_n          (rst_n),

            .sample_valid   (pitch_lpf_valid),
            .sample_data    (pitch_lpf_data),

            .gate           (gate),
            .zc_hyst_q3_29  (zc_hyst_q3_29),

            .period_16_16   (period_16_16),
            .period_valid   (period_valid)
        );

    end else begin : g_pitch_zcd

        fx_pitch_zcd #(
            .PERIOD_MIN_Q16(32'd8    << 16),
            .PERIOD_MAX_Q16(32'd1200 << 16)
        ) u_pitch(
            .clk            (clk),
            .rst_n          (rst_n),

            .sample_valid   (pitch_lpf_valid),
            .sample_data    (pitch_lpf_data),

            .gate           (gate),
            .zc_hyst_q3_29  (zc_hyst_q3_29),

            .period_16_16   (period_16_16),
            .period_valid   (period_valid)
        );

    end

end
endgenerate

// =============================================================================
// PERIODO -> PHASE INC
// =============================================================================

fx_period_to_inc u_p2i(
    .clk          (clk),
    .rst_n        (rst_n),

    .period_16_16 (period_16_16),
    .period_valid (period_valid),

    .gate         (gate && !pitch_retrig),     // un ciclo en 0 en el re-ataque: vuelve a enganchar
    .sample_tick  (sample_valid),
    .glide_shift  (glide_shift),

    .phase_inc    (base_phase_inc),
    .inc_valid    (inc_valid)
);

// =============================================================================
// PITCH LOCK
// =============================================================================

always_ff @(posedge clk) begin
    if (!rst_n)
        pitch_locked <= 1'b0;
    else if (!gate)
        pitch_locked <= 1'b0;
    else if (pitch_retrig)                 // pua nueva: el VCA baja hasta enganchar la nota nueva
        pitch_locked <= 1'b0;
    else if (inc_valid)
        pitch_locked <= 1'b1;
end

// =============================================================================
// ENVELOPE VCA
//
// env_q3_29      : Q3.29
// env_gain_q1_31 : Q1.31
//
// Q3.29 * Q1.31 -> producto con 60 bits fraccionales.
// >>> 31 vuelve a Q3.29.
// ENV_VCA_SHIFT agrega ganancia gruesa.
// La salida se limita a Q1.31 positivo [0, 1).
// =============================================================================

logic signed [63:0] env_gain_prod_r;
logic               env_gain_prod_valid;

logic signed [63:0] env_prod_rounded;
logic signed [63:0] env_scaled_wide;
logic signed [31:0] env_scaled_q3_29;
logic        [63:0] env_shifted;

always_comb begin
    env_prod_rounded =
        env_gain_prod_r +
        (64'sd1 <<< 30);

    env_scaled_wide =
        env_prod_rounded >>> 31;

    env_scaled_q3_29 =
        sat32(env_scaled_wide);

    env_shifted =
        {32'd0, $unsigned(env_scaled_q3_29)}
        << ENV_VCA_SHIFT;
end

always_ff @(posedge clk) begin
    if (!rst_n) begin
        env_gain_prod_r     <= 64'sd0;
        env_gain_prod_valid <= 1'b0;
        env_vca_q1_31       <= 32'sd0;
    end else begin
        env_gain_prod_valid <= 1'b0;

        // El VCA depende solamente del envelope/gate.
        // Pitch y volumen quedan desacoplados.
        if (!gate) begin
            env_gain_prod_r     <= 64'sd0;
            env_gain_prod_valid <= 1'b0;
            env_vca_q1_31       <= 32'sd0;
        end else begin
            if (env_update) begin
                if (env_q3_29 > 0) begin
                    env_gain_prod_r <=
                        $signed(env_q3_29) *
                        $signed(env_gain_q1_31);
                end else begin
                    env_gain_prod_r <= 64'sd0;
                end

                env_gain_prod_valid <= 1'b1;
            end

            if (env_gain_prod_valid) begin
                if (env_scaled_q3_29 <= 0) begin
                    env_vca_q1_31 <= 32'sd0;
                end else if (
                    env_shifted >=
                    64'h0000_0000_7FFF_FFFF
                ) begin
                    env_vca_q1_31 <= 32'sh7FFF_FFFF;
                end else begin
                    env_vca_q1_31 <=
                        $signed(env_shifted[31:0]);
                end
            end
        end
    end
end

// =============================================================================
// DEBUG
// =============================================================================

`ifndef SYNTHESIS

always_ff @(posedge clk) begin
    if (
        rst_n &&
        sample_valid &&
        !pitch_lpf_ready
    ) begin
        $error(
            "fx_synth_frontend: overrun en LPF de pitch"
        );
    end
end

`endif

endmodule
