module cordic_phase (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               start,

    // Una vuelta completa = 2^32
    // 0x00000000 = 0
    // 0x40000000 = pi/2
    // 0x80000000 = pi
    // 0xC0000000 = 3pi/2
    input  logic [31:0]        phase_u32,

    output logic               done,
    output logic signed [31:0] sin_q31,
    output logic signed [31:0] cos_q31
);

    // 1 / CORDIC gain, Q1.31
    localparam logic signed [31:0] KINV = 32'h4DBA76D4;

    // atan(2^-i) expresado en phase units:
    //
    // atan_phase = atan(2^-i)/(2*pi) * 2^32
    //
    localparam logic signed [31:0] ATAN_PHASE [0:15] = '{
        32'h20000000, 32'h12E4051E, 32'h09FB385B, 32'h051111D4,
        32'h028B0D43, 32'h0145D7E1, 32'h00A2F61E, 32'h00517C55,
        32'h0028BE53, 32'h00145F2F, 32'h000A2F98, 32'h000517CC,
        32'h00028BE6, 32'h000145F3, 32'h0000A2FA, 32'h0000517D
    };

    logic signed [32:0] x_acc;
    logic signed [32:0] y_acc;
    logic signed [31:0] z; // z ahora es angulo signed en unidad de phase: 
    // 0x40000000 = +pi/2 //  0x00000000 = 0 //  0xC0000000 = -pi/2
 
    logic        sign_x;
    logic [4:0]  iter;

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_ITER,
        ST_DONE
    } state_t;
    state_t state;
    
    function automatic logic signed [31:0] sat33_to_32(input logic signed [32:0] v);
        if (v > 33'sh0_7FFF_FFFF) sat33_to_32 = 32'sh7FFF_FFFF;
        else if (v < 33'sh1_8000_0000) sat33_to_32 = 32'sh80000000;
        else sat33_to_32 = v[31:0];
    endfunction

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            sin_q31 <= '0;
            cos_q31 <= '0;
            done    <= 1'b0;
            x_acc   <= '0;
            y_acc   <= '0;
            z       <= '0;
            sign_x  <= 1'b0;
            iter    <= '0;
            state   <= ST_IDLE;
        end else begin
            case (state)
                ST_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        /*
                         * Quadrant reduction
                         *
                         * Q0: 0 a pi/2
                         * Q1: pi/2 a pi
                         * Q2: pi a 3pi/2
                         * Q3: 3pi/2 a 2pi
                         * CORDIC recibe: -pi/2 <= z <= +pi/2
                         */
                        case (phase_u32[31:30])
                            2'b00: begin
                                // 0 a +pi/2
                                z      <= $signed(phase_u32);
                                sign_x <= 1'b0;
                            end
                            2'b01: begin
                                // +pi/2 ... pi
                                // z = pi - phase
                                z <= $signed(32'h80000000 - phase_u32);
                                sign_x <= 1'b1;
                            end
                            2'b10: begin
                                // pi a 3pi/2
                                // La resta modular produce un valor negativo:
                                // z = pi - phase
                                z <= $signed(32'h80000000- phase_u32);
                                sign_x <= 1'b1;
                            end
                            2'b11: begin
                                // 3pi/2 ... 2pi
                                // Interpretado signed: -pi/2 ... 0
                                z      <= $signed(phase_u32);
                                sign_x <= 1'b0;
                            end
                        endcase
                        x_acc <= {{1{KINV[31]}}, KINV};
                        y_acc <= '0;
                        iter  <= '0;
                        state <= ST_ITER;

                    end
                end
                ST_ITER: begin
                    if (z >= 0) begin
                        x_acc <= x_acc - (y_acc >>> iter);
                        y_acc <= y_acc + (x_acc >>> iter);
                        z     <= z - ATAN_PHASE[iter];
                    end else begin
                        x_acc <= x_acc + (y_acc >>> iter);
                        y_acc <= y_acc - (x_acc >>> iter);
                        z     <= z + ATAN_PHASE[iter];
                    end
                    if (iter == 5'd15) begin
                        state <= ST_DONE;
                    end else begin
                        iter <= iter + 1'b1;
                    end
                end
                ST_DONE: begin
                    cos_q31 <= sat33_to_32(sign_x ? -x_acc : x_acc);
                    sin_q31 <= sat33_to_32(y_acc);
                    done  <= 1'b1;
                    state <= ST_IDLE;
                end
                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end
endmodule
