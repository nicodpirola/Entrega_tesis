// delay_frac_read.sv
// Lectura fraccional de la linea de retardo con interpolacion lineal.
//
// D = D_int + mu        (D en formato 16.16)
// s0 = x[n - D_int],  s1 = x[n - D_int - 1]
// d_out = s0 + (s1 - s0) * mu
//
// Dos lecturas sucesivas de la BRAM y un producto de 32x17 bits (mu sin signo).
// El producto se redondea sumando medio LSB antes de descartar los 16 bits de mu.

module delay_frac_read #(
    parameter int ADDR_W = 15,
    parameter int DATA_W = 32,
    parameter int MAX_DELAY_SAMPLES = (1<<ADDR_W)-1
)(
    input  logic                     clk,
    input  logic                     rst_n,

    input  logic                     start,
    input  logic [31:0]              D_16_16,
    input  logic [ADDR_W-1:0]        write_ptr,

    output logic                     rd_en,
    output logic [ADDR_W-1:0]        rd_addr,
    input  logic [DATA_W-1:0]        rd_data,
    input  logic                     rd_data_valid,

    output logic signed [DATA_W-1:0] d_out,
    output logic                     d_valid,
    output logic                     ready
);

    import fx_dsp_pkg::*;

    //estados
    typedef enum logic [2:0]{
        ST_IDLE,
        ST_READ_S0, //pide s0 a la bram
        ST_WAIT_S0, //espera s0 3 ciclos
        ST_READ_S1, //idem
        ST_WAIT_S1, //idem
        ST_MUL,
        ST_ADD
    } state_t;

    state_t state; //maquina de estados

    logic        [15:0]        mu_reg;
    logic        [ADDR_W-1:0]  rptr0_reg;
    logic        [ADDR_W-1:0]  rptr1_reg;
    logic signed [DATA_W-1:0]  s0_reg;
    logic signed [DATA_W-1:0]  delta_reg;
    logic signed [DATA_W-1:0]  term_reg;

    logic        [ADDR_W-1:0]  d_int_eff;
    logic signed [63:0]        interp_product;

    //salidas
    assign ready = (state == ST_IDLE);

    //logica combinacional
    always_comb begin
        //retardo entero entre 1 y MAX_DELAY_SAMPLES
        if (D_16_16[31:16] > MAX_DELAY_SAMPLES[15:0]) d_int_eff = MAX_DELAY_SAMPLES[ADDR_W-1:0];
        else if (D_16_16[31:16] == 16'd0)             d_int_eff = 1;
        else                                          d_int_eff = D_16_16[ADDR_W+15:16];

        interp_product = $signed(delta_reg) * $signed({1'b0, mu_reg}); //(s1 - s0) * mu
    end

    //logica secuencial y FSM
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state     <= ST_IDLE;
            rd_en     <= 1'b0;
            rd_addr   <= '0;
            d_out     <= '0;
            d_valid   <= 1'b0;

            mu_reg    <= '0;
            rptr0_reg <= '0;
            rptr1_reg <= '0;
            s0_reg    <= '0;
            delta_reg <= '0;
            term_reg  <= '0;
        end
        else begin
            d_valid <= 1'b0;

            case (state)
                ST_IDLE: begin
                    rd_en <= 1'b0;
                    if (start) begin
                        mu_reg    <= D_16_16[15:0];
                        rptr0_reg <= write_ptr - d_int_eff;        //s0
                        rptr1_reg <= write_ptr - d_int_eff - 1'b1; //s1, una muestra mas vieja
                        state     <= ST_READ_S0;
                    end
                end

                ST_READ_S0: begin
                    rd_en   <= 1'b1;
                    rd_addr <= rptr0_reg;
                    state   <= ST_WAIT_S0;
                end

                ST_WAIT_S0: begin
                    rd_en <= 1'b0;
                    if (rd_data_valid) begin
                        s0_reg <= $signed(rd_data);
                        state  <= ST_READ_S1;
                    end
                end

                ST_READ_S1: begin
                    rd_en   <= 1'b1;
                    rd_addr <= rptr1_reg;
                    state   <= ST_WAIT_S1;
                end

                ST_WAIT_S1: begin
                    rd_en <= 1'b0;
                    if (rd_data_valid) begin
                        delta_reg <= $signed(rd_data) - s0_reg;
                        state     <= ST_MUL;
                    end
                end

                ST_MUL: begin
                    term_reg <= DATA_W'((interp_product + (64'sd1 <<< 15)) >>> 16); //redondeo
                    state    <= ST_ADD;
                end

                ST_ADD: begin
                    d_out   <= sat_add32(s0_reg, term_reg);
                    d_valid <= 1'b1;
                    state   <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
