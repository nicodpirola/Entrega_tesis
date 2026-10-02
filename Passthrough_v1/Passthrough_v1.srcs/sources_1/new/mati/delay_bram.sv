
// Single Dual Port RAM. Imitamos el comportamiento del IP para tener tama�os espec�ficos a cada efecto.

// el IP real en lectura tarda dos ciclos desde rd_en/rd_addr hasta un rd_data v�lido.
//  Ciclo 0: rd_en + rd_addr muestreados -> lectura s�ncrona de BRAM
//  Ciclo 1: bram_doutb disponible -> guardado en rd_data
//  Ciclo 2: rd_data y rd_data_valid estables

//Sintesis
// usamos el atributo (* ram_style = "block" *) para inferir bram (template).

module delay_bram #(
  parameter int ADDR_W = 15,
  parameter int DATA_W = 32
)(
  input logic               clk,
  input logic               rst_n,

  //Write port (A)
  input logic               wr_en,
  input logic [ADDR_W-1:0]  wr_addr,
  input logic [DATA_W-1:0]  wr_data,

  //Read port (B)
  input logic               rd_en,
  input logic [ADDR_W-1:0]  rd_addr,
  output logic [DATA_W-1:0] rd_data,
  output logic              rd_data_valid
);

  //inferimos BRAM
  (* ram_style = "block" *)
  
  //<element_type> [<MSB_index>:<LSB_index>] array_name [<array_start_index>:<array_end_index>];
  //p.26 Quick Start Guide to Verilog
  
  logic [DATA_W-1:0] mem [0:(1<<ADDR_W)-1];
  logic [DATA_W-1:0] bram_doutb;

  //Port A: Escritura sincrona 
  always_ff @(posedge clk)begin
    if (wr_en) begin            
      mem[wr_addr] <= wr_data;
    end
  end

  //Port B: Lectura s�ncrona (1 ciclo)
  //leemos cuando rd_en =1, igual que la IP.
  //cuando rd_en=0, bram_doutb mantiene el ultimo valor leido.

  always_ff@(posedge clk)begin
    if (rd_en) begin
      bram_doutb <= mem[rd_addr];
    end 
  end

  logic vld_d1, vld_d2;

  //matcheo con la IP original
  // vld_d1: hubo rd_en hace 1 ciclo (dato en bram_doutb)
  // vld_d2: hubo rd_en hace 2 ciclos (dato en rd_data)
  always_ff @(posedge clk or negedge rst_n)begin
    if (!rst_n) begin
      vld_d1 <= 1'b0;
      vld_d2 <= 1'b0;
    end else begin
      vld_d1 <= rd_en;
      vld_d2 <= vld_d1;
    end
  end

  //registro de salida (latencia 1 ciclo)
  always_ff @(posedge clk)begin
    if (!rst_n) begin
      rd_data <= '0;      
    end
    else rd_data <= bram_doutb;
  end

  assign rd_data_valid = vld_d2;
  
  
endmodule // delay_bram
