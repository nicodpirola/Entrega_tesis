`timescale 1ns/1ps
//! @title Recorte de diodos del overdrive
//! @file fx_od_diode.sv
//! @brief Tabla positiva con intervalos variables e interpolacion lineal.
//! Entrada u Q12.20; salida v/V_FS Q3.29 para sumar a la rama directa.
//! La tabla y los coeficientes de la rama deben corresponder al mismo Drive.

module fx_od_diode #(
    parameter string TABLE_FILE = ""
)(
    input  logic               clk,
    input  logic               rst_n,
    input  logic               in_valid,
    output logic               in_ready,
    input  logic signed [31:0] in_data,
    output logic               out_valid,
    input  logic               out_ready,
    output logic signed [31:0] out_data,
    input  logic               active_bank,
    input  logic               wt_wr_en,
    output logic               wt_wr_ready,
    input  logic               wt_wr_bank,
    input  logic        [11:0] wt_wr_addr,
    input  logic        [31:0] wt_wr_data
);

    import fx_dsp_pkg::*;
    localparam logic [11:0] LAST_ADDRESS = 12'd2560;

    typedef enum logic [3:0] {
        ST_IDLE, ST_ABS, ST_EXPONENT, ST_INDEX, ST_READ0, ST_READ1,
        ST_CAPTURE1, ST_SUB_VALUES, ST_LOAD_MUL, ST_MUL, ST_ROUND, ST_SAVE_TERM,
        ST_ADD, ST_SAVE_MAGNITUDE, ST_SAVE_OUTPUT
    } state_t;
    state_t state;

    (* ram_style = "block" *) logic signed [31:0] table_mem_0 [0:2560];
    (* ram_style = "block" *) logic signed [31:0] table_mem_1 [0:2560];

    logic signed [31:0] sample_reg, t0_reg, t1_reg, term_reg, magnitude_out_reg;
    logic               sign_reg, sample_bank_reg, linear_reg, endpoint_reg;
    logic        [31:0] magnitude_reg;
    logic        [4:0]  exponent_reg, interval_shift_reg;
    logic        [11:0] index_reg;
    logic        [11:0] read_addr_reg;
    logic signed [31:0] read_data_0, read_data_1;
    logic        [15:0] fraction_reg;
    logic signed [32:0] delta_reg, sum_reg;
    logic signed [31:0] mul_a_reg, mul_b_reg;
    logic signed [63:0] mul_product_reg, rounded_reg;

    logic        [4:0]  exponent_value;
    logic        [31:0] mantissa_value, fraction_value;
    logic        [11:0] index_value;
    logic               out_buf_valid;
    logic signed [31:0] out_buf;
    wire in_fire, out_fire, write_fire, read_enable;

    function automatic logic [4:0] leading_one(input logic [31:0] value);
        logic [31:0] part;
        logic [4:0] position;
        begin
            part = value; position = 0;
            if (|part[31:16]) begin position[4] = 1; part = part >> 16; end
            if (|part[15:8])  begin position[3] = 1; part = part >> 8; end
            if (|part[7:4])   begin position[2] = 1; part = part >> 4; end
            if (|part[3:2])   begin position[1] = 1; part = part >> 2; end
            if (part[1]) position[0] = 1;
            leading_one = position;
        end
    endfunction

    function automatic logic signed [31:0] sat_sum32(input logic signed [32:0] value);
        begin
            if (value[32] == value[31]) sat_sum32 = value[31:0];
            else if (value[32]) sat_sum32 = 32'sh8000_0000;
            else sat_sum32 = 32'sh7FFF_FFFF;
        end
    endfunction

    // Opcional: tabla fija de arranque. Sin archivo, cargar desde PS antes de usar.
    initial begin
        if (TABLE_FILE != "") begin
            $readmemh(TABLE_FILE, table_mem_0);
            $readmemh(TABLE_FILE, table_mem_1);
        end
    end

    // Se escribe solo el banco inactivo, sin alterar una muestra ya aceptada.
    assign wt_wr_ready = rst_n && (wt_wr_addr <= LAST_ADDRESS) && !wt_wr_data[31] &&
                         (wt_wr_bank != active_bank) && ((state == ST_IDLE) || (wt_wr_bank != sample_bank_reg));
    assign write_fire = wt_wr_en && wt_wr_ready;
    // Un puerto de escritura y uno de lectura sincronica por banco.
    // El dato de BRAM no lleva reset; la FSM descarta cualquier lectura vieja.
    assign read_enable = rst_n && ((state == ST_READ0) || (state == ST_READ1));
    always_ff @(posedge clk) begin
        if (write_fire && !wt_wr_bank) table_mem_0[wt_wr_addr] <= wt_wr_data;
        if (read_enable && !sample_bank_reg) read_data_0 <= table_mem_0[read_addr_reg];
    end
    always_ff @(posedge clk) begin
        if (write_fire && wt_wr_bank) table_mem_1[wt_wr_addr] <= wt_wr_data;
        if (read_enable && sample_bank_reg) read_data_1 <= table_mem_1[read_addr_reg];
    end

    assign in_ready  = rst_n && (state == ST_IDLE) && !out_buf_valid;
    assign in_fire   = in_valid && in_ready;
    assign out_fire  = out_valid && out_ready;
    assign out_valid = out_buf_valid;
    assign out_data  = out_buf;

    always_comb begin
        exponent_value = leading_one(magnitude_reg);
        mantissa_value = magnitude_reg >> interval_shift_reg;
        index_value = {exponent_reg - 5'd11, 7'd0} | {5'd0, mantissa_value[6:0]};
        if (linear_reg) index_value = {5'd0, magnitude_reg[11:5]};
        if (endpoint_reg) index_value = LAST_ADDRESS;
        if (interval_shift_reg < 16) fraction_value = magnitude_reg << (16-interval_shift_reg);
        else fraction_value = magnitude_reg >> (interval_shift_reg-16);
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            sample_reg <= '0; sign_reg <= 0; sample_bank_reg <= 0;
            magnitude_reg <= '0; exponent_reg <= '0; interval_shift_reg <= '0;
            linear_reg <= 0; endpoint_reg <= 0; index_reg <= '0; fraction_reg <= '0; read_addr_reg <= '0;
            t0_reg <= '0; t1_reg <= '0; delta_reg <= '0; term_reg <= '0; sum_reg <= '0;
            mul_a_reg <= '0; mul_b_reg <= '0; mul_product_reg <= '0; rounded_reg <= '0;
            magnitude_out_reg <= '0; out_buf <= '0; out_buf_valid <= 0;
        end else begin
            if (out_fire) out_buf_valid <= 0;

            case (state)
                ST_IDLE: begin
                    if (in_fire) begin
                        sample_reg <= in_data;
                        sign_reg <= in_data[31]; sample_bank_reg <= active_bank;
                        state <= ST_ABS;
                    end
                end
                ST_ABS: begin
                    // Magnitud unsigned: tambien admite el minimo signed32 (-2048).
                    magnitude_reg <= sign_reg ? (~sample_reg + 32'd1) : sample_reg;
                    state <= ST_EXPONENT;
                end
                ST_EXPONENT: begin
                    exponent_reg <= exponent_value;
                    linear_reg <= magnitude_reg < 32'd4096;
                    endpoint_reg <= magnitude_reg == 32'h8000_0000;
                    interval_shift_reg <= (magnitude_reg < 32'd4096) ? 5'd5 : (exponent_value - 5'd7);
                    state <= ST_INDEX;
                end
                ST_INDEX: begin
                    index_reg <= index_value;
                    read_addr_reg <= index_value;
                    fraction_reg <= endpoint_reg ? 16'd0 : fraction_value[15:0];
                    state <= ST_READ0;
                end
                ST_READ0: begin
                    read_addr_reg <= (index_reg == LAST_ADDRESS) ? index_reg : (index_reg + 12'd1);
                    state <= ST_READ1;
                end
                ST_READ1: begin
                    t0_reg <= sample_bank_reg ? read_data_1 : read_data_0;
                    state <= ST_CAPTURE1;
                end
                ST_CAPTURE1: begin
                    t1_reg <= sample_bank_reg ? read_data_1 : read_data_0;
                    state <= ST_SUB_VALUES;
                end
                ST_SUB_VALUES: begin
                    delta_reg <= $signed({t1_reg[31], t1_reg}) - $signed({t0_reg[31], t0_reg});
                    state <= ST_LOAD_MUL;
                end
                ST_LOAD_MUL: begin
                    mul_a_reg <= sat_sum32(delta_reg);
                    mul_b_reg <= $signed({16'd0, fraction_reg});
                    state <= ST_MUL;
                end
                ST_MUL: begin
                    mul_product_reg <= $signed(mul_a_reg) * $signed(mul_b_reg);
                    state <= ST_ROUND;
                end
                ST_ROUND: begin
                    rounded_reg <= mul_product_reg + (mul_product_reg[63] ? 64'sd32767 : 64'sd32768);
                    state <= ST_SAVE_TERM;
                end
                ST_SAVE_TERM: begin
                    term_reg <= sat32(rounded_reg >>> 16);
                    state <= ST_ADD;
                end
                ST_ADD: begin
                    sum_reg <= $signed({t0_reg[31], t0_reg}) + $signed({term_reg[31], term_reg});
                    state <= ST_SAVE_MAGNITUDE;
                end
                ST_SAVE_MAGNITUDE: begin
                    magnitude_out_reg <= sat_sum32(sum_reg);
                    state <= ST_SAVE_OUTPUT;
                end
                ST_SAVE_OUTPUT: begin
                    out_buf <= sign_reg ? -magnitude_out_reg : magnitude_out_reg;
                    out_buf_valid <= 1;
                    state <= ST_IDLE;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
