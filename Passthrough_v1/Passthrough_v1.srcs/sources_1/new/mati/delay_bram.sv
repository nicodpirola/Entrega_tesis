// delay_bram.sv
// memoria del delay ram: Ram con dos puertos (lectura y escritura)
// vivado infiere como BRAM. Se usa en lugar del IP para elegir
// el tamano de cada efecto.
//
// Escritura: un ciclo. Lectura: el dato llega 2 ciclos despues de rd_en, igual que el IP.
//  ciclo 0: rd_en y rd_addr  -> lectura sincrona de la BRAM
//  ciclo 1: dato en ram_dout
//  ciclo 2: dato en rd_data con rd_data_valid

module delay_bram #(
    parameter int ADDR_W = 15,
    parameter int DATA_W = 32
)(
    input  logic              clk,
    input  logic              rst_n,

    input  logic              wr_en,
    input  logic [ADDR_W-1:0] wr_addr,
    input  logic [DATA_W-1:0] wr_data,

    input  logic              rd_en,
    input  logic [ADDR_W-1:0] rd_addr,
    output logic [DATA_W-1:0] rd_data,
    output logic              rd_data_valid
);

    (* ram_style = "block" *)
    logic [DATA_W-1:0] mem [0:(1<<ADDR_W)-1];

    logic [DATA_W-1:0] ram_dout;
    logic              rd_en_d1;
    logic              rd_en_d2;

    //salidas
    assign rd_data_valid = rd_en_d2;

    //puerto A: escritura
    always_ff @(posedge clk) begin
        if (wr_en) mem[wr_addr] <= wr_data;
    end

    //puerto B: lectura. Sin rd_en, ram_dout mantiene el ultimo valor leido
    always_ff @(posedge clk) begin
        if (rd_en) ram_dout <= mem[rd_addr];
    end

    //registro de salida y validez (2 ciclos, igual que el IP)
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            rd_data  <= '0;
            rd_en_d1 <= 1'b0;
            rd_en_d2 <= 1'b0;
        end
        else begin
            rd_data  <= ram_dout;
            rd_en_d1 <= rd_en;
            rd_en_d2 <= rd_en_d1;
        end
    end

endmodule
