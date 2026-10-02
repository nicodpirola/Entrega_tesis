//Hacemos interpolacion para devolver dato en muestras intermedias
// d_out = S0 + (S1 - S0)*mu.
// S1 es muestra anterior a S0.


module delay_frac_read #(
  parameter int ADDR_W = 15,
  parameter int DATA_W = 32,
  parameter int MAX_DELAY_SAMPLES = (1<<ADDR_W)-1
)(
  input logic                      clk,
  input logic                      rst_n,


  //control
  input logic                      start,
  input logic [31:0]               D_16_16,
  input logic [ADDR_W-1:0]         write_ptr,

  output logic                     rd_en,
  output logic [ADDR_W-1:0]        rd_addr,
  input logic [DATA_W-1:0]         rd_data,
  input logic                      rd_data_valid,

  //salida interpolada
  output logic signed [DATA_W-1:0] d_out,
  output logic                     d_valid,
  output logic                     ready
);

  import fx_dsp_pkg::*;

  typedef enum logic [2:0] {
    ST_IDLE   =   3'd0,
    ST_ISSUE0 = 3'd1,
    ST_WAIT0  = 3'd2,
    ST_ISSUE1 = 3'd3,
    ST_WAIT1  = 3'd4,
    ST_MUL    = 3'd5,
    ST_ADD    = 3'd6
  } state_t;

  state_t state;

  logic [15:0] mu_reg;         // este lo usamos para la interpolacion
  logic [ADDR_W-1:0] rptr0_reg;
  logic [ADDR_W-1:0] rptr1_reg;  
  logic signed [DATA_W-1:0] s0_reg;
  logic signed [DATA_W-1:0] delta_r; // s1-s0
  logic signed [DATA_W-1:0] term_r; // (delta * mu) >>> 16

  function automatic logic [ADDR_W-1:0] clamp_delay_int(input logic [15:0] d_int16);
    logic [15:0] tmp;
    begin
      tmp = (d_int16 > MAX_DELAY_SAMPLES[15:0]) ? MAX_DELAY_SAMPLES[15:0] : d_int16;
      if (tmp == 16'd0) tmp = 16'd1;
      clamp_delay_int = tmp[ADDR_W-1:0];
    end
  endfunction // clamp_delay_int

  assign ready = (state == ST_IDLE);

  

  always_ff @(posedge clk)begin
    if (!rst_n) begin
      state <= ST_IDLE;
      rd_en <= 1'b0;
      rd_addr <= '0;
      d_out <= '0;
      d_valid <= 1'b0;

      mu_reg <= '0;
      rptr0_reg <= '0;
      rptr1_reg <= '0;
      s0_reg <= '0;
      delta_r <= '0;
      term_r <= '0;
    end else begin // if (!rst_n)
      d_valid <= 1'b0;
      case (state) 
        ST_IDLE: begin
          rd_en <= 1'b0;
          if (start) begin
            logic [ADDR_W-1:0] D_int_clamped;
            logic [15:0] D_int16;

            D_int16 =  D_16_16[31:16];
            mu_reg  <= D_16_16[15:0];
            D_int_clamped = clamp_delay_int(D_int16);

            rptr0_reg <= write_ptr - D_int_clamped;
            rptr1_reg <= (write_ptr - D_int_clamped) - {{(ADDR_W-1){1'b0}},1'b1}; // 0000...1

            state <= ST_ISSUE0;
          end 
        end        
        ST_ISSUE0: begin
          rd_en <= 1'b1;
          rd_addr <= rptr0_reg;
          state <= ST_WAIT0;
        end
        ST_WAIT0: begin
          rd_en <= 1'b0;
          if (rd_data_valid) begin
            s0_reg <= $signed(rd_data);
            state <= ST_ISSUE1;
          end 
        end
        ST_ISSUE1: begin
          rd_en <= 1'b1;
          rd_addr <= rptr1_reg;
          state <= ST_WAIT1;
        end
        ST_WAIT1: begin
          rd_en <= 1'b0;
          if (rd_data_valid) begin
            delta_r <= $signed(rd_data) - s0_reg;
            state <= ST_MUL;
          end 
        end
        ST_MUL: begin
          logic signed [63:0] prod;
          prod = $signed(delta_r) * $signed({1'b0, mu_reg});
          term_r <= prod[DATA_W-1+16:16]; // >>> 16, mantenemos 32 bits
          state <= ST_ADD;
        end
        ST_ADD: begin
          d_out <= sat_add32(s0_reg, term_r);
          d_valid <= 1'b1;
          state <= ST_IDLE;          
        end
        default: state <= ST_IDLE;
      endcase // case (state)
    end // else: !if(!rst_n)
  end
  
endmodule // delay_frac_read
