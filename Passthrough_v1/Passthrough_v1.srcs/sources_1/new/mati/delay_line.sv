// delay_line.sv
// Linea de retardo generica: buffer circular en BRAM con lectura fraccional.
// Se usa en los efectos de delay, chorus y flanger.
//
// d[n] = w[n - D]       (D en formato 16.16, interpolado en delay_frac_read)
//
// Una muestra por vez, en tres pasos:
//  1) req_valid/req_ready: se guardan D y el puntero de escritura y arranca la lectura.
//  2) d_valid/d_ready:     se entrega la muestra retardada d_out.
//  3) w_valid/w_ready:     se recibe w_in y se escribe en la posicion del puntero.
// La lectura va antes que la escritura, asi que D = 1 devuelve la muestra anterior.
//
// clear_req borra toda la BRAM (una posicion por ciclo). Mientras clear_busy esta
// activo no se aceptan pedidos ni se entregan muestras.

module delay_line #(
    parameter int ADDR_W = 15,
    parameter int DATA_W = 32
)(
    input  logic                     clk,
    input  logic                     rst_n,

    input  logic                     req_valid,
    output logic                     req_ready,
    input  logic [31:0]              D_16_16,

    output logic signed [DATA_W-1:0] d_out,
    output logic                     d_valid,
    input  logic                     d_ready,

    input  logic                     w_valid,
    output logic                     w_ready,
    input  logic signed [DATA_W-1:0] w_in,

    input  logic                     clear_req,
    output logic                     clear_busy,
    output logic                     clear_done,

    output logic [ADDR_W-1:0]        write_ptr_dbg
);

    //estados
    typedef enum logic [2:0]{
        ST_IDLE,
        ST_WAIT_D,
        ST_WAIT_W,
        ST_CLEAR
    } state_t;

    state_t state; //maquina de estados

    logic                     bram_wr_en;
    logic [ADDR_W-1:0]        bram_wr_addr;
    logic [DATA_W-1:0]        bram_wr_data;

    logic                     bram_rd_en;
    logic [ADDR_W-1:0]        bram_rd_addr;
    logic [DATA_W-1:0]        bram_rd_data;
    logic                     bram_rd_valid;

    logic                     frac_start;
    logic signed [DATA_W-1:0] frac_d_out;
    logic                     frac_d_valid;
    logic                     frac_ready;

    logic [31:0]              D_reg;
    logic [ADDR_W-1:0]        wptr_reg;
    logic [ADDR_W-1:0]        wptr_latched;
    logic [ADDR_W-1:0]        clear_addr;

    logic signed [DATA_W-1:0] d_reg;
    logic                     d_reg_valid;

    wire req_fire = req_valid && req_ready;
    wire d_fire   = d_valid && d_ready;
    wire w_fire   = w_valid && w_ready;

    //instancias
    delay_bram #(
        .ADDR_W (ADDR_W),
        .DATA_W (DATA_W)
    ) bram_u (
        .clk           (clk          ),
        .rst_n         (rst_n        ),
        .wr_en         (bram_wr_en   ),
        .wr_addr       (bram_wr_addr ),
        .wr_data       (bram_wr_data ),
        .rd_en         (bram_rd_en   ),
        .rd_addr       (bram_rd_addr ),
        .rd_data       (bram_rd_data ),
        .rd_data_valid (bram_rd_valid)
    );

    delay_frac_read #(
        .ADDR_W (ADDR_W),
        .DATA_W (DATA_W)
    ) frac_u (
        .clk           (clk          ),
        .rst_n         (rst_n        ),
        .start         (frac_start   ),
        .D_16_16       (D_reg        ),
        .write_ptr     (wptr_latched ),
        .rd_en         (bram_rd_en   ),
        .rd_addr       (bram_rd_addr ),
        .rd_data       (bram_rd_data ),
        .rd_data_valid (bram_rd_valid),
        .d_out         (frac_d_out   ),
        .d_valid       (frac_d_valid ),
        .ready         (frac_ready   )
    );

    //salidas
    assign d_out         = d_reg;
    assign d_valid       = d_reg_valid;
    assign req_ready     = (state == ST_IDLE) && frac_ready && !clear_req;
    assign w_ready       = (state == ST_WAIT_W);
    assign clear_busy    = (state == ST_CLEAR);
    assign write_ptr_dbg = wptr_reg;

    //logica secuencial y FSM
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state        <= ST_IDLE;

            wptr_reg     <= '0;
            wptr_latched <= '0;
            D_reg        <= '0;
            frac_start   <= 1'b0;

            bram_wr_en   <= 1'b0;
            bram_wr_addr <= '0;
            bram_wr_data <= '0;

            d_reg        <= '0;
            d_reg_valid  <= 1'b0;

            clear_addr   <= '0;
            clear_done   <= 1'b0;
        end
        else begin
            frac_start <= 1'b0; //pulsos de un ciclo
            bram_wr_en <= 1'b0;
            clear_done <= 1'b0;

            if ((state == ST_IDLE) && clear_req) begin
                state       <= ST_CLEAR;
                clear_addr  <= '0;
                d_reg_valid <= 1'b0;
            end
            else begin
                case (state)
                    ST_IDLE: begin
                        d_reg_valid <= 1'b0;
                        if (req_fire) begin
                            D_reg        <= D_16_16;
                            wptr_latched <= wptr_reg;
                            frac_start   <= 1'b1;
                            state        <= ST_WAIT_D;
                        end
                    end

                    ST_WAIT_D: begin
                        if (frac_d_valid) begin //llega la muestra interpolada
                            d_reg       <= frac_d_out;
                            d_reg_valid <= 1'b1;
                        end
                        if (d_fire) begin //el efecto la consumio
                            d_reg_valid <= 1'b0;
                            state       <= ST_WAIT_W;
                        end
                    end

                    ST_WAIT_W: begin
                        if (w_fire) begin
                            bram_wr_en   <= 1'b1;
                            bram_wr_addr <= wptr_latched;
                            bram_wr_data <= w_in;
                            wptr_reg     <= wptr_reg + 1'b1;
                            state        <= ST_IDLE;
                        end
                    end

                    ST_CLEAR: begin
                        bram_wr_en   <= 1'b1;
                        bram_wr_addr <= clear_addr;
                        bram_wr_data <= '0;

                        if (clear_addr == {ADDR_W{1'b1}}) begin //ultima posicion
                            state      <= ST_IDLE;
                            clear_done <= 1'b1;
                            wptr_reg   <= '0;
                        end
                        else begin
                            clear_addr <= clear_addr + 1'b1;
                        end
                    end

                    default: begin
                        state <= ST_IDLE;
                    end
                endcase
            end
        end
    end

endmodule
