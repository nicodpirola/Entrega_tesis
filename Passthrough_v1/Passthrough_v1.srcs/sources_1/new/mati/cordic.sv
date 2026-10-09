/*
* Diseño de cordic mio
*/

module cordic(
    input logic           clk,
    input logic           rst_n,
    input logic           start, // arranca el calculo
    input logic signed [31:0] angle_q29,
    output logic          done,
    output logic signed [31:0] sin_q31,
    output logic signed [31:0] cos_q31
);

    // 1/k lo calculamos en python en q1_31
    localparam logic signed [31:0] KINV = 32'h4DBA76D4;

    localparam logic signed [31:0] ATAN[16]= '{
        32'h1921FB54, 32'h0ED63383, 32'h07D6DD7E, 32'h03FAB753,
        32'h01FF55BB, 32'h00FFEAAE, 32'h007FFD55, 32'h003FFFAB,
        32'h001FFFF5, 32'h000FFFFF, 32'h00080000, 32'h00040000,
        32'h00020000, 32'h00010000, 32'h00008000, 32'h00004000
    };

    // constantes de ángulo para la reduccion de cuadrante (q3_29)
    localparam logic signed [31:0] PI_Q29     = 32'h6487ED51;  // pi * 2^29
    localparam logic signed [31:0] HALFPI_Q29 = 32'h3243F6A9;  // pi/2  * 2^29

    logic signed [32:0] x_acc;  //le agregamos un bit porq con q1.31 no puedo mostrar exactamente el
    logic signed [32:0] y_acc;  // 1 y para angulos chicos (n mayor) puede complicarse
    logic signed [31:0] z;
    logic sign_x;
    logic [4:0] iter; // 16 iteraciones con esto

    function automatic logic signed [31:0] sat33_to_32(input logic signed [32:0] v);
        if (v > 33'sh0_7FFF_FFFF) sat33_to_32 = 32'sh7FFF_FFFF;
        else if (v < 33'sh1_8000_0000) sat33_to_32 = 32'sh8000_0000;
        else sat33_to_32 = v[31:0];
    endfunction


    typedef enum logic [1:0]{
        ST_IDLE = 2'd0,
        ST_ITER = 2'd1,
        ST_DONE = 2'd2
    } state_t;

    state_t state;


    always_ff @(posedge clk)begin
        if(!rst_n)begin
            sin_q31 <= '0;
            cos_q31 <= '0;
            done    <= '0;
            x_acc   <= '0;
            y_acc   <= '0;
            z       <= '0;
            sign_x  <= 1'b0;
            iter    <= 5'b0;
            state   <= ST_IDLE;
        end else begin
            case(state)
                ST_IDLE:begin
                    done <= '0;
                    if(start)begin
                        //reduccion de cuadrante
                        if(angle_q29 > HALFPI_Q29) begin
                            z <= PI_Q29 - angle_q29; //segundo cuadrante
                            sign_x <= 1'b1;
                        end else if(angle_q29 < -HALFPI_Q29) begin
                            z <=  -PI_Q29 - angle_q29; //tercer cuadrante
                            sign_x <= 1'b1;
                        end else begin
                            z <= angle_q29;
                            sign_x <= 1'b0;
                        end
                        x_acc <= KINV;
                        y_acc <= '0;
                        iter  <= '0;
                        state <= ST_ITER;
                    end
                end
                ST_ITER:begin
                    if(z >= 0)begin
                        x_acc <= x_acc - (y_acc >>> iter);
                        y_acc <= y_acc + (x_acc >>> iter);
                        z <= z - ATAN[iter];
                    end else begin
                        x_acc <= x_acc + (y_acc >>> iter);
                        y_acc <= y_acc - (x_acc >>> iter);
                        z <= z + ATAN[iter];
                    end
                    if(iter == 5'd15)begin
                        state <= ST_DONE;
                    end else
                        iter <= iter + 1'b1;
                end
                ST_DONE: begin
                    // coseno con signo de cuadrante, saturado a Q1.31
                    logic signed [32:0] cos_val;
                    cos_q31 <= sat33_to_32(sign_x? -x_acc : x_acc);
                    sin_q31 <= sat33_to_32 (y_acc);
                    done  <= 1'b1;
                    state <= ST_IDLE;
                end
                default: state <= ST_IDLE;
            endcase

        end
    end
endmodule
