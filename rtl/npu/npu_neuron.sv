module npu_neuron #(
    parameter int N = 9,
    parameter int ADDR_W = (N <= 1) ? 1 : $clog2(N),
    parameter bit RELU_EN = 1'b1
)(
    input logic clk,
    input logic rst_n,

    input logic start,
    input logic signed [31:0] bias,

    output logic rd_en,
    output logic [ADDR_W-1:0] rd_addr,
    input logic signed [7:0] a_data,
    input logic signed [7:0] b_data,

    output logic signed [31:0] result,
    output logic busy,
    output logic done
);

    typedef enum logic [2:0]{
        IDLE,
        DOT_START,
        DOT_WAIT,
        ACTIVATE
    } state_t;

    state_t state;

    logic signed [31:0] bias_q;
    logic signed [31:0] biased_result;

    logic dp_start;
    logic [31:0] dp_result;
    logic dp_busy;
    logic dp_done;
    npu_dot_product 
    #(
        .N      (N      ),
        .ADDR_W (ADDR_W )
    )
    u_npu_dot_product(
        .clk     (clk     ),
        .rst_n   (rst_n   ),
        .start   (dp_start   ),
        .rd_en   (rd_en   ),
        .rd_addr (rd_addr ),
        .a_data  (a_data  ),
        .b_data  (b_data  ),
        .result  (dp_result  ),
        .busy    (dp_busy    ),
        .done    (dp_done    )
    );
    
    always_ff@(posedge clk)begin
        if(!rst_n)begin
            result <= 1'b0;
            dp_start <= 1'b0;
            busy <= 1'b0;
            done <= 1'b0;
            state <= IDLE;
            bias_q <=1'b0;
            biased_result <= 1'b0;
        end else begin
            dp_start <= 1'b0;
            done <= 1'b0;
            case(state)
                IDLE:begin
                    if(start)begin
                        busy <= 1'b1;
                        bias_q <= bias;
                        state <= DOT_START;
                    end
                end
                DOT_START:begin
                    dp_start <= 1'b1;
                    state <= DOT_WAIT;
                end
                DOT_WAIT:begin
                    if(dp_done)begin
                        biased_result <= bias_q + dp_result;
                        state <= ACTIVATE;
                    end
                end
                ACTIVATE:begin
                    done <= 1'b1;
                    busy <= 1'b0;
                    if(RELU_EN)begin
                        result <= !biased_result[31]? biased_result : 32'sd0;
                    end else begin
                        result <= biased_result;
                    end
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule