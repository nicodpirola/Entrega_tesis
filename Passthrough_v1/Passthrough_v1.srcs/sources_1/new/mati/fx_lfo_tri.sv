// -----------------------------------------------------------------------------
// fx_lfo_tri.sv
// LFO triangular bipolar en Q1.31 usando phase accumulator 32-bit.
// - tick: avanza 1 paso por muestra (cuando tick=1)
// - phase_inc_u32: controla frecuencia (f = phase_inc * Fs / 2^32)
//
// Salida:
// - lfo_q1_31: signed Q1.31 en [-1, +1)
// -----------------------------------------------------------------------------
module fx_lfo_tri (
  input  logic         clk,
  input  logic         rst_n,

  input  logic         tick,            //avanzar 1 paso (por muestra aceptada)
  input  logic [31:0]  phase_inc_u32,   //incremento DDS
  input  logic         phase_clear,     //opcional

  output logic signed [31:0] lfo_q1_31
);

  logic [31:0] phase; //contador

  //triangular unipolar
  logic [30:0] tri_u31;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      phase <= 32'd0;
    end else begin
      if (phase_clear) begin
        phase <= 32'd0;
      end else if (tick) begin
        phase <= phase + phase_inc_u32;
      end
    end
  end

  //construcción triángulo
  //MSB de phase define subida/bajada, usamos 31 LSB.
  always_comb begin
    if (phase[31] == 1'b0) tri_u31 = phase[30:0];
    else                   tri_u31 = ~phase[30:0];
  end

  //unipolar -> bipolar: lfo = 2*(tri - 0.5)
  //tri en [0,1) -> tri - 0.5 en [-0.5, 0.5) -> x2 en [-1, 1). Sin desborde.
  always_comb begin
    logic signed [31:0] centrado;
    centrado  = $signed({1'b0, tri_u31}) - 32'sh4000_0000;//resta 0.5
    lfo_q1_31 = centrado <<< 1;//multiplica por 2
  end

endmodule
