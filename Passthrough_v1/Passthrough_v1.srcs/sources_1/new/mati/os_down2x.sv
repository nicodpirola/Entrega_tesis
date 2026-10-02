// =============================================================================
// os_down2x.sv - Baja la tasa x2: por cada DOS muestras que entran, sale UNA.
//
// Anti-aliasing + descarte: las dos muestras entran al FIR interno (las dos
// actualizan la linea de retardo), pero solo la salida de la primera de cada
// par se entrega aguas abajo; la otra se consume y se descarta.
// =============================================================================
module os_down2x #(
  parameter int N = 32,
  parameter logic [32*N-1:0] COEFS = '0
)(
  input  logic               clk,
  input  logic               rst_n,
  input  logic               state_clear,

  input  logic               in_valid,
  output logic               in_ready,
  input  logic signed [31:0] in_data,

  output logic               out_valid,
  input  logic               out_ready,
  output logic signed [31:0] out_data
);

  logic               f_in_valid, f_in_ready;
  logic signed [31:0] f_in_data;
  logic               f_out_valid, f_out_ready;
  logic signed [31:0] f_out_data;

  fir_serial #(.N(N), .COEFS(COEFS)) u_fir (
    .clk(clk), .rst_n(rst_n), .state_clear(state_clear),
    .in_valid(f_in_valid), .in_ready(f_in_ready), .in_data(f_in_data),
    .out_valid(f_out_valid), .out_ready(f_out_ready), .out_data(f_out_data)
  );

  // fase 0: esta muestra PRODUCE salida (se entrega)
  // fase 1: esta muestra solo actualiza el filtro (su salida se descarta)
  logic fase;

  typedef enum logic [1:0] {
    ST_IDLE = 2'd0,
    ST_PUSH = 2'd1,
    ST_OUT  = 2'd2
  } state_t;
  state_t st;

  logic signed [31:0] x_reg;
  logic               fase_reg;   // fase de la muestra en proceso

  wire in_fire = in_valid && in_ready;
  assign in_ready = (st == ST_IDLE);

  assign f_in_valid = (st == ST_PUSH);
  assign f_in_data  = x_reg;

  // En fase 0 la salida va aguas abajo; en fase 1 se consume y descarta.
  assign out_valid   = (st == ST_OUT) && f_out_valid && (fase_reg == 1'b0);
  assign out_data    = f_out_data;
  assign f_out_ready = (st == ST_OUT) && ((fase_reg == 1'b0) ? out_ready : 1'b1);

  wire f_in_fire  = f_in_valid && f_in_ready;
  wire f_out_fire = f_out_valid && f_out_ready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st <= ST_IDLE; x_reg <= '0; fase <= 1'b0; fase_reg <= 1'b0;
    end else begin
      if (state_clear) fase <= 1'b0;
      case (st)
        ST_IDLE: if (in_fire) begin
          x_reg    <= in_data;
          fase_reg <= fase;
          fase     <= ~fase;
          st       <= ST_PUSH;
        end
        ST_PUSH: if (f_in_fire)  st <= ST_OUT;
        ST_OUT:  if (f_out_fire) st <= ST_IDLE;
        default: st <= ST_IDLE;
      endcase
    end
  end
endmodule
