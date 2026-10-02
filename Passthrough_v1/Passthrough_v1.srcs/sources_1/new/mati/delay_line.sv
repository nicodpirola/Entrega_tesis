//delay_line generico
//protocolo 1-sample-in-flight:
// 1) req_valid/req_ready: latch de D y wptr, dispara lectura fraccional
// 2) d_valid/d_ready: entrega d_out
// 3) w_valid/w_ready: recibe w_in para escribir

//Clear de BRAM
// - arranca cuando clear_req se activa.
// - durante clear_busy el core no acepta req ni produce d_valid.

module delay_line #(
  parameter int ADDR_W = 15,
  parameter int DATA_W = 32
)(
  input logic clk,
  input logic rst_n,

  //iniciar una muestra
  input logic req_valid,
  output logic req_ready,
  input logic [31:0] D_16_16,

  //sample de salida delay
  output logic signed [DATA_W-1:0] d_out,
  output logic                     d_valid,
  input logic                      d_ready,

  //escribir sample de entrada
  input logic w_valid,
  output logic w_ready,
  input logic signed [DATA_W-1:0] w_in,

  //limpiar bram
  input logic clear_req,
  output logic clear_busy,
  output logic clear_done,

  //debug
  output logic [ADDR_W-1:0] write_ptr_dbg
);

  
  typedef enum logic [2:0]{
    ST_IDLE = 3'd0,
    ST_WAIT_D = 3'd1,
    ST_WAIT_W = 3'd2,
    ST_CLEAR = 3'd3
  } state_t;

  state_t state;


  logic                  bram_wr_en;
  logic [ADDR_W-1:0]     bram_wr_addr;
  logic [DATA_W-1:0]     bram_wr_data;

  logic                  bram_rd_en;
  logic [ADDR_W-1:0]     bram_rd_addr;
  logic [DATA_W-1:0]     bram_rd_data;
  logic                  bram_rd_valid;

  // frac_read signals
  logic                  frac_start;
  logic signed [DATA_W-1:0] frac_d_out;
  logic                  frac_d_valid;
  logic                  frac_ready;

  // Registros latch por request
  logic [31:0]           D_reg;
  logic [ADDR_W-1:0]     wptr_reg;
  logic [ADDR_W-1:0]     wptr_latched;

  assign write_ptr_dbg = wptr_reg;

  // Registro de salida d_out/d_valid (buffer)
  logic signed [DATA_W-1:0] d_reg;
  logic                     d_reg_valid;

  assign d_out   = d_reg;
  assign d_valid = d_reg_valid;


  // Clear engine
  logic [ADDR_W-1:0] clear_addr;
  assign clear_busy = (state == ST_CLEAR);

  delay_bram #(
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W)
  )bram_u (
    .clk          (clk),
    .rst_n        (rst_n),

    .wr_en        (bram_wr_en),
    .wr_addr      (bram_wr_addr),
    .wr_data      (bram_wr_data),

    .rd_en        (bram_rd_en),
    .rd_addr      (bram_rd_addr),
    .rd_data      (bram_rd_data),
    .rd_data_valid(bram_rd_valid)
  );
  delay_frac_read #(
   .ADDR_W(ADDR_W),
    .DATA_W(DATA_W)
  ) frac_u (
    .clk          (clk),
    .rst_n        (rst_n),

    .start        (frac_start),
    .D_16_16      (D_reg),
    .write_ptr    (wptr_latched),

    .rd_en        (bram_rd_en),
    .rd_addr      (bram_rd_addr),
    .rd_data      (bram_rd_data),
    .rd_data_valid(bram_rd_valid),

    .d_out        (frac_d_out),
    .d_valid      (frac_d_valid),
    .ready        (frac_ready)
  );

  //handshakes

  wire req_fire = req_valid && req_ready;
  wire d_fire   = d_valid && d_ready;
  wire w_fire   = w_valid && w_ready;

  assign req_ready = (state == ST_IDLE) && frac_ready && !clear_req;
  assign w_ready   = (state == ST_WAIT_W);

  always_ff @(posedge clk)begin
    if (!rst_n) begin
      state <= ST_IDLE;

      wptr_reg <= '0;
      wptr_latched <= '0;
      D_reg <= '0;

      frac_start <= 1'b0;

      bram_wr_en <= 1'b0;
      bram_wr_addr <= '0;
      bram_wr_data <= '0;

      d_reg  <= '0;
      d_reg_valid <= 1'b0;

      clear_addr <= '0;
      clear_done <= 1'b0;
    end else begin
      frac_start <= 1'b0;
      bram_wr_en <= 1'b0;
      clear_done <= 1'b0;

      if((state == ST_IDLE) && clear_req)begin
        state <= ST_CLEAR;
        clear_addr <= '0;
        d_reg_valid <= 1'b0; // no entregamos datos durante clear
      end else begin
        case (state) 
          ST_IDLE: begin
            d_reg_valid <= 1'b0;
            if(req_fire)begin
              D_reg     <= D_16_16;
              wptr_latched <= wptr_reg;

              frac_start <= 1'b1;
              state <= ST_WAIT_D;
            end
          end
          ST_WAIT_D: begin
            //esperamos resultado de frac_read
            if(frac_d_valid)begin
              d_reg <= frac_d_out;
              d_reg_valid <= 1'b1;
            end
            //cuando el wrapper consume d_out
            if (d_fire)begin
              d_reg_valid <= 1'b0;
              state <= ST_WAIT_W;
            end
          end
          ST_WAIT_W: begin
            if(w_fire)begin
              bram_wr_en <= 1'b1;
              bram_wr_addr <= wptr_latched;
              bram_wr_data <= w_in;

              wptr_reg <= wptr_reg + {{(ADDR_W-1){1'b0}},1'b1};

              state <= ST_IDLE;
            end
          end
          ST_CLEAR: begin
            bram_wr_en <= 1'b1;
            bram_wr_addr <= clear_addr;
            bram_wr_data <= '0;

            //avanzar
            if (clear_addr == {ADDR_W{1'b1}})begin
              //terminar barrido
              state <= ST_IDLE;
              clear_done <= 1'b1;

              wptr_reg <= '0;
            end else begin
              clear_addr <= clear_addr + {{(ADDR_W-1){1'b0}}, 1'b1};
            end
          end
          default: state <= ST_IDLE;

        endcase // case (state)
      end
    end
  end

endmodule // delay_line

  
