// mul32_seq.sv
// Producto de 32x32 bits con signo usando un solo DSP48.
//
// a = a1 * 2^17 + a0      (a0: 17 bits sin signo, a1: 15 bits con signo)
// b = b1 * 2^17 + b0      (b0: 17 bits sin signo, b1: 15 bits con signo)
// p = a0*b0 + 2^17 * (a1*b0 + a0*b1) + 2^34 * a1*b1
//
// Un multiplicador de 18x18 bits (1 DSP48) usado en 4 pasadas. Entre pasadas el
// acumulador se desplaza 17 bits y se guardan los bits ya resueltos.
// El resultado esta disponible 6 ciclos despues de start.

module mul32_seq(
    input  logic               clk,
    input  logic               rst_n,

    input  logic               start,
    input  logic signed [31:0] a,
    input  logic signed [31:0] b,

    output logic               busy,
    output logic               valid,
    output logic signed [63:0] p
);

    //estados
    typedef enum logic [2:0]{
        ST_IDLE,
        ST_MUL_1,
        ST_MUL_2,
        ST_MUL_3,
        ST_MUL_4,
        ST_MUL_5
    } state_t;

    state_t state; //maquina de estados

    logic signed [31:0] a_reg;
    logic signed [31:0] b_reg;

    logic signed [17:0] mul_a_reg;
    logic signed [17:0] mul_b_reg;
    logic signed [35:0] mul_product_reg;
    logic signed [47:0] acc_reg;
    logic        [33:0] p_low_reg;

    logic signed [17:0] a_lo;
    logic signed [17:0] a_hi;
    logic signed [17:0] b_lo;
    logic signed [17:0] b_hi;
    logic signed [47:0] acc_in;

    //salidas
    assign busy = (state != ST_IDLE);
    assign p    = {acc_reg[29:0], p_low_reg};

    //logica combinacional
    always_comb begin
        //parte baja sin signo (se agrega un 0), parte alta con signo
        a_lo = $signed({1'b0, a_reg[16:0]});
        a_hi = {{3{a_reg[31]}}, a_reg[31:17]};
        b_lo = $signed({1'b0, b_reg[16:0]});
        b_hi = {{3{b_reg[31]}}, b_reg[31:17]};

        //lo que se suma al producto (como el mux Z del DSP48)
        case (state)
            ST_MUL_2: acc_in = '0;              //a0*b0
            ST_MUL_4: acc_in = acc_reg;         //a0*b1, mismo peso que a1*b0
            default:  acc_in = acc_reg >>> 17;  //a1*b0 y a1*b1
        endcase
    end

    //logica secuencial y FSM
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state           <= ST_IDLE;
            valid           <= 1'b0;

            a_reg           <= '0;
            b_reg           <= '0;

            mul_a_reg       <= '0;
            mul_b_reg       <= '0;
            mul_product_reg <= '0;
            acc_reg         <= '0;
            p_low_reg       <= '0;
        end
        else begin
            valid <= 1'b0;

            //el producto entra al acumulador un ciclo despues
            mul_product_reg <= mul_a_reg * mul_b_reg;

            //una sola suma para todas las pasadas
            if ((state != ST_IDLE) && (state != ST_MUL_1)) begin
                acc_reg <= acc_in + 48'(mul_product_reg);
            end

            case (state)
                ST_IDLE: begin
                    if (start) begin
                        a_reg     <= a;
                        b_reg     <= b;
                        mul_a_reg <= $signed({1'b0, a[16:0]}); //a0
                        mul_b_reg <= $signed({1'b0, b[16:0]}); //b0
                        state     <= ST_MUL_1;
                    end
                end

                ST_MUL_1: begin //multiplica a0*b0
                    mul_a_reg <= a_hi;
                    mul_b_reg <= b_lo;
                    state     <= ST_MUL_2;
                end

                ST_MUL_2: begin //multiplica a1*b0, acumula a0*b0
                    mul_a_reg <= a_lo;
                    mul_b_reg <= b_hi;
                    state     <= ST_MUL_3;
                end

                ST_MUL_3: begin //multiplica a0*b1, acumula a1*b0, bits 16:0 resueltos
                    p_low_reg[16:0] <= acc_reg[16:0];
                    mul_a_reg <= a_hi;
                    mul_b_reg <= b_hi;
                    state     <= ST_MUL_4;
                end

                ST_MUL_4: begin //multiplica a1*b1, acumula a0*b1
                    state     <= ST_MUL_5;
                end

                ST_MUL_5: begin //acumula a1*b1, bits 33:17 resueltos
                    p_low_reg[33:17] <= acc_reg[16:0];
                    valid     <= 1'b1;
                    state     <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule