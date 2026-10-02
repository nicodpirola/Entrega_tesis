// =============================================================================
// fx_synth.sv - Voz monofonica inspirada en Minimoog
//
//   OSC1 + OSC2 + OSC3 + ruido -> mixer -> biquad provisional -> VCA
//
// Formatos:
//   audio                  : Q3.29 signed
//   niveles / VCA          : Q1.31 signed, 0..1
//   tune ratio OSC2/OSC3   : UQ2.30 unsigned, 1.0 = 0x40000000
//   coeficientes biquad    : Q2.30 signed
//
// RANGE usa -2,-1,0,+1,+2 para 32',16',8',4',2'. El modo LO del
// Minimoog no se implementa aqui; debe ser un LFO/frecuencia independiente.
//
// Los incrementos se precalculan al cambiar pitch/range/tune. Hay un unico
// multiplicador unsigned para TUNE y un unico multiplicador signed compartido
// para niveles/VCA. La salida se calcula en pocos clocks por sample_tick.
// =============================================================================
module fx_synth (
  input  logic               clk,
  input  logic               rst_n,

  input  logic               sample_tick,
  input  logic [31:0]        base_phase_inc,
  input  logic               inc_valid,
  input  logic signed [31:0] env_vca_q1_31,

  output logic signed [31:0] synth_out,
  output logic               synth_valid,

  input  logic [2:0]         osc1_wave,
  input  logic [2:0]         osc2_wave,
  input  logic [2:0]         osc3_wave,
  input  logic signed [3:0]  osc1_range,
  input  logic signed [3:0]  osc2_range,
  input  logic signed [3:0]  osc3_range,
  input  logic [31:0]        osc2_tune_q2_30,
  input  logic [31:0]        osc3_tune_q2_30,
  input  logic signed [31:0] osc1_level,
  input  logic signed [31:0] osc2_level,
  input  logic signed [31:0] osc3_level,
  input  logic signed [31:0] noise_level,

  input  logic signed [31:0] f_b0,
  input  logic signed [31:0] f_b1,
  input  logic signed [31:0] f_b2,
  input  logic signed [31:0] f_a1,
  input  logic signed [31:0] f_a2,
  input  logic               filter_on
);
  import fx_dsp_pkg::*;

  localparam logic signed [31:0] ONE_Q3_29 = 32'sh2000_0000;
  localparam logic        [31:0] NYQUIST_INC_MAX = 32'h7FFF_FFFF;

  // ---------------------------------------------------------------------------
  // RANGE y TUNE con limite final de Nyquist
  // ---------------------------------------------------------------------------
  // La afinacion de OSC2/OSC3 se calcula primero en 34 bits y RANGE se aplica
  // despues. De esta forma no se satura prematuramente un valor que luego
  // podria bajar de octava.
  function automatic logic [31:0] range_and_limit(
    input logic [33:0]       inc_wide,
    input logic signed [3:0] range_sel
  );
    logic [35:0] shifted;
    begin
      case (range_sel)
        -2:      shifted = {2'b0, inc_wide} >> 2; // 32'
        -1:      shifted = {2'b0, inc_wide} >> 1; // 16'
         0:      shifted = {2'b0, inc_wide};      // 8'
         1:      shifted = {2'b0, inc_wide} << 1; // 4'
         2:      shifted = {2'b0, inc_wide} << 2; // 2'
        default: shifted = {2'b0, inc_wide};      // valor invalido: usar 8'
      endcase

      if (shifted >= 36'd2147483648)
        range_and_limit = NYQUIST_INC_MAX;
      else
        range_and_limit = shifted[31:0];
    end
  endfunction

  // ---------------------------------------------------------------------------
  // Precalculo de incrementos
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] {
    P_IDLE = 2'd0,
    P_T2   = 2'd1,
    P_T3   = 2'd2
  } pstate_t;

  pstate_t pst;

  logic [31:0] inc1_reg;
  logic [31:0] inc2_reg;
  logic [31:0] inc3_reg;

  logic [31:0]       base_snapshot;
  logic [31:0]       tune2_snapshot;
  logic [31:0]       tune3_snapshot;
  logic signed [3:0] range2_snapshot;
  logic signed [3:0] range3_snapshot;

  // Copias de la configuracion que produjo los incrementos vigentes.
  logic [31:0]       cfg_base_d;
  logic [31:0]       cfg_tune2_d;
  logic [31:0]       cfg_tune3_d;
  logic signed [3:0] cfg_range1_d;
  logic signed [3:0] cfg_range2_d;
  logic signed [3:0] cfg_range3_d;
  logic              recalc_pending;

  wire cfg_changed =
      (base_phase_inc   != cfg_base_d)   ||
      (osc2_tune_q2_30 != cfg_tune2_d)  ||
      (osc3_tune_q2_30 != cfg_tune3_d)  ||
      (osc1_range      != cfg_range1_d) ||
      (osc2_range      != cfg_range2_d) ||
      (osc3_range      != cfg_range3_d);

  // Un unico multiplicador unsigned para afinar OSC2/OSC3.
  logic [31:0] tune_mul_a;
  logic [31:0] tune_mul_b;
  wire  [63:0] tune_mul_product = tune_mul_a * tune_mul_b;
  wire  [33:0] tuned_inc_wide   = tune_mul_product[63:30];

  always_comb begin
    case (pst)
      P_T2: begin
        tune_mul_a = base_snapshot;
        tune_mul_b = tune2_snapshot;
      end
      P_T3: begin
        tune_mul_a = base_snapshot;
        tune_mul_b = tune3_snapshot;
      end
      default: begin
        tune_mul_a = 32'd0;
        tune_mul_b = 32'd0;
      end
    endcase
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      pst              <= P_IDLE;
      inc1_reg         <= '0;
      inc2_reg         <= '0;
      inc3_reg         <= '0;
      base_snapshot    <= '0;
      tune2_snapshot   <= 32'h4000_0000;
      tune3_snapshot   <= 32'h4000_0000;
      range2_snapshot  <= '0;
      range3_snapshot  <= '0;
      cfg_base_d       <= '0;
      cfg_tune2_d      <= '0;
      cfg_tune3_d      <= '0;
      cfg_range1_d     <= '0;
      cfg_range2_d     <= '0;
      cfg_range3_d     <= '0;
      recalc_pending   <= 1'b0;
    end else begin
      // Si cambia algo mientras la FSM esta ocupada, se repite el precalculo
      // al terminar usando la configuracion mas reciente.
      if (inc_valid || cfg_changed)
        recalc_pending <= 1'b1;

      case (pst)
        P_IDLE: begin
          if (recalc_pending || inc_valid || cfg_changed) begin
            inc1_reg       <= range_and_limit({2'b0, base_phase_inc}, osc1_range);
            base_snapshot  <= base_phase_inc;
            tune2_snapshot <= osc2_tune_q2_30;
            tune3_snapshot <= osc3_tune_q2_30;
            range2_snapshot <= osc2_range;
            range3_snapshot <= osc3_range;

            cfg_base_d     <= base_phase_inc;
            cfg_tune2_d    <= osc2_tune_q2_30;
            cfg_tune3_d    <= osc3_tune_q2_30;
            cfg_range1_d   <= osc1_range;
            cfg_range2_d   <= osc2_range;
            cfg_range3_d   <= osc3_range;

            recalc_pending <= 1'b0;
            pst            <= P_T2;
          end
        end

        P_T2: begin
          inc2_reg <= range_and_limit(tuned_inc_wide, range2_snapshot);
          pst      <= P_T3;
        end

        P_T3: begin
          inc3_reg <= range_and_limit(tuned_inc_wide, range3_snapshot);
          pst      <= P_IDLE;
        end

        default: pst <= P_IDLE;
      endcase
    end
  end

  // ---------------------------------------------------------------------------
  // Osciladores y ruido
  // ---------------------------------------------------------------------------
  logic [31:0] ph1;
  logic [31:0] ph2;
  logic [31:0] ph3;

  logic [31:0] lfsr;
  wire [31:0] lfsr_next =
      {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
  wire signed [31:0] noise_sample = $signed(lfsr) >>> 2;

  // division por 3 via reciproco (0x55555556 ~ 1/3 en Q0.32): mas rapido que /3
  function automatic logic [31:0] div3(input logic [31:0] x);
    logic [63:0] p;
    begin
      p    = $unsigned(x) * 64'h5555_5556;
      div3 = p[63:32];
    end
  endfunction

  function automatic logic signed [31:0] gen_wave(
    input logic [31:0] phase,
    input logic [2:0]  wave_sel,
    input logic        is_osc3
  );
    logic signed [31:0] triangle;
    logic signed [31:0] triangle_saw;
    logic signed [31:0] saw;
    logic signed [31:0] wave_position_1;
    begin
      if (phase < 32'h8000_0000)
        triangle = -ONE_Q3_29 + $signed({1'b0, phase >> 1});
      else
        triangle =  ONE_Q3_29
                  - $signed({1'b0, (phase - 32'h8000_0000) >> 1});

      saw = $signed(phase - 32'h8000_0000) >>> 2;

      if (phase < 32'hC000_0000)
        triangle_saw = -ONE_Q3_29 + $signed({1'b0, div3(phase)});
      else
        triangle_saw =  ONE_Q3_29
                     - $signed(phase - 32'hC000_0000);

      wave_position_1 = is_osc3 ? -saw : triangle_saw;

      case (wave_sel)
        3'd0:    gen_wave = triangle;
        3'd1:    gen_wave = wave_position_1;
        3'd2:    gen_wave = saw;
        3'd3:    gen_wave = (phase < 32'h8000_0000)
                               ? ONE_Q3_29 : -ONE_Q3_29;
        3'd4:    gen_wave = (phase < 32'h4A00_0000)
                               ? ONE_Q3_29 : -ONE_Q3_29;
        default: gen_wave = (phase < 32'h1A00_0000)
                               ? ONE_Q3_29 : -ONE_Q3_29;
      endcase
    end
  endfunction

  // ---------------------------------------------------------------------------
  // Multiplicador signed compartido para mixer y VCA
  // ---------------------------------------------------------------------------
  typedef enum logic [3:0] {
    S_IDLE    = 4'd0,
    S_O1_GEN  = 4'd1,   // registra forma OSC1 (gen_wave con div3)
    S_O1_MUL  = 4'd2,   // multiplica y acumula OSC1
    S_O2_GEN  = 4'd3,
    S_O2_MUL  = 4'd4,
    S_O3_GEN  = 4'd5,
    S_O3_MUL  = 4'd6,
    S_NZ      = 4'd7,
    S_ACC     = 4'd8,
    S_FILT    = 4'd9,
    S_VCA     = 4'd10
  } state_t;

  state_t st;

  logic signed [31:0] mul_a;
  logic signed [31:0] mul_b;
  wire  signed [63:0] mul_product = $signed(mul_a) * $signed(mul_b);
  wire  signed [31:0] mul_q3_29 =
      sat32((mul_product + (64'sd1 <<< 30)) >>> 31);

  // La forma de onda se genera y registra en estados _GEN; aca solo se multiplica
  // el valor YA registrado (wave_r). Asi gen_wave (con div3) y el multiplicador
  // 32x32 nunca comparten el mismo camino combinacional -> cierra timing a 50MHz.
  always_comb begin
    case (st)
      S_O1_MUL: begin mul_a = wave_r;       mul_b = osc1_level; end
      S_O2_MUL: begin mul_a = wave_r;       mul_b = osc2_level; end
      S_O3_MUL: begin mul_a = wave_r;       mul_b = osc3_level; end
      S_NZ:     begin mul_a = noise_sample; mul_b = noise_level; end
      S_VCA:    begin mul_a = bq_out;       mul_b = env_vca_q1_31; end
      default:  begin mul_a = 32'sd0;       mul_b = 32'sd0; end
    endcase
  end

  // ---------------------------------------------------------------------------
  // Mixer, filtro provisional y VCA
  // ---------------------------------------------------------------------------
  logic signed [31:0] wave_r;       // forma de onda registrada (rompe camino critico)
  logic signed [63:0] mix_acc;
  logic signed [31:0] mix_sat;
  logic signed [31:0] synth_reg;
  logic               synth_valid_reg;

  assign synth_out   = synth_reg;
  assign synth_valid = synth_valid_reg;

  logic               bq_in_valid;
  logic               bq_out_valid;
  logic signed [31:0] bq_out;

  fx_biquad u_filter (
    .clk       (clk),
    .rst_n     (rst_n),
    .state_clear(1'b0),
    .enable    (filter_on),
    .in_valid  (bq_in_valid),
    .in_ready  (),
    .in_data   (mix_sat),
    .out_valid (bq_out_valid),
    .out_ready (1'b1),
    .out_data  (bq_out),
    .b0_q2_30  (f_b0),
    .b1_q2_30  (f_b1),
    .b2_q2_30  (f_b2),
    .a1_q2_30  (f_a1),
    .a2_q2_30  (f_a2)
  );

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      st              <= S_IDLE;
      ph1             <= '0;
      ph2             <= '0;
      ph3             <= '0;
      lfsr            <= 32'hACE1_ACE1;
      wave_r          <= '0;
      mix_acc         <= '0;
      mix_sat         <= '0;
      synth_reg       <= '0;
      synth_valid_reg <= 1'b0;
      bq_in_valid     <= 1'b0;
    end else begin
      synth_valid_reg <= 1'b0;
      bq_in_valid     <= 1'b0;

      case (st)
        S_IDLE: begin
          if (sample_tick) begin
            ph1     <= ph1 + inc1_reg;
            ph2     <= ph2 + inc2_reg;
            ph3     <= ph3 + inc3_reg;
            lfsr    <= lfsr_next;
            mix_acc <= '0;
            st      <= S_O1_GEN;
          end
        end

        // Cada oscilador: GEN registra la forma, MUL multiplica y acumula.
        S_O1_GEN: begin wave_r <= gen_wave(ph1, osc1_wave, 1'b0); st <= S_O1_MUL; end
        S_O1_MUL: begin mix_acc <= mix_acc + mul_q3_29;           st <= S_O2_GEN; end
        S_O2_GEN: begin wave_r <= gen_wave(ph2, osc2_wave, 1'b0); st <= S_O2_MUL; end
        S_O2_MUL: begin mix_acc <= mix_acc + mul_q3_29;           st <= S_O3_GEN; end
        S_O3_GEN: begin wave_r <= gen_wave(ph3, osc3_wave, 1'b1); st <= S_O3_MUL; end
        S_O3_MUL: begin mix_acc <= mix_acc + mul_q3_29;           st <= S_NZ; end

        S_NZ: begin
          mix_acc <= mix_acc + mul_q3_29;
          st      <= S_ACC;
        end

        S_ACC: begin
          mix_sat     <= sat32(mix_acc);
          bq_in_valid <= 1'b1;
          st          <= S_FILT;
        end

        S_FILT: begin
          if (bq_out_valid)
            st <= S_VCA;
        end

        S_VCA: begin
          synth_reg       <= mul_q3_29;
          synth_valid_reg <= 1'b1;
          st              <= S_IDLE;
        end

        default: st <= S_IDLE;
      endcase
    end
  end

`ifndef SYNTHESIS
  // La arquitectura supone que termina antes del siguiente sample_tick.
  always_ff @(posedge clk) begin
    if (rst_n && sample_tick && (st != S_IDLE))
      $error("fx_synth overrun: sample_tick con FSM ocupada (st=%0d)", st);
  end
`endif

endmodule