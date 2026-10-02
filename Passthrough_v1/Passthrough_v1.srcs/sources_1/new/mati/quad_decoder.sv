module quad_decoder #(
  parameter int CNT_W = 16,
  parameter int DB_N  = 8
)(
  input  logic                    clk,
  input  logic                    rst_n,
  input  logic                    tick,
  input  logic                    a_raw,
  input  logic                    b_raw,
  output logic signed [CNT_W-1:0] count,
  output logic                    step
);
  // Etapa 0: sincronizadores (sin reset, a proposito)
  logic [1:0] a_sync, b_sync;
  always_ff @(posedge clk) begin
    a_sync <= {a_sync[0], a_raw};
    b_sync <= {b_sync[0], b_raw};
  end
  wire a_s = a_sync[1];
  wire b_s = b_sync[1];

  // Etapa 1: debounce por linea
  localparam int CW = (DB_N <= 1) ? 1 : $clog2(DB_N);
  logic          clean_a, clean_b;
  logic [CW-1:0] cnt_a, cnt_b;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      clean_a <= 1'b1; clean_b <= 1'b1;   // reposo = 11
      cnt_a   <= '0;   cnt_b   <= '0;
    end else if (tick) begin
      if (a_s == clean_a)        cnt_a <= '0;
      else if (cnt_a == DB_N-1)  begin clean_a <= a_s; cnt_a <= '0; end
      else                       cnt_a <= cnt_a + 1'b1;
      if (b_s == clean_b)        cnt_b <= '0;
      else if (cnt_b == DB_N-1)  begin clean_b <= b_s; cnt_b <= '0; end
      else                       cnt_b <= cnt_b + 1'b1;
    end
  end

  // Etapas 2-4: decodificar entrada al reposo (11) y acumular
  logic [1:0] state, state_d;
  assign state = {clean_a, clean_b};
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state_d <= 2'b11; count <= '0; step <= 1'b0;
    end else begin
      step    <= 1'b0;
      state_d <= state;
      if (state == 2'b11 && state_d != 2'b11) begin
        if      (state_d == 2'b01) begin count <= count + 1'b1; step <= 1'b1; end // forward
        else if (state_d == 2'b10) begin count <= count - 1'b1; step <= 1'b1; end // reverse
        // state_d == 2'b00 => salto de detent, no contamos
      end
    end
  end
endmodule