module npu_conv_multi #(
    parameter int IMG_W = 28,
    parameter int IN_CH = 1,
    parameter int OUT_CH = 8,
    parameter int SHIFT = 8,
    parameter int IMG_ADDR_W = $clog2(IMG_W * IMG_W),
    parameter int OUT_ADDR_W = (IMG_W <= 3) ? 1 : $clog2((IMG_W - 2) * (IMG_W - 2)),
    parameter int K_ADDR_W = $clog2(IN_CH * 9),
    parameter int CH_W = IN_CH <= 1 ? 1 : $clog2(IN_CH)
)(
    input logic clk,
    input logic rst_n,

    input logic start,
    input logic [OUT_CH*32-1:0] bias_data,

    output logic rd_en,
    output logic [IMG_ADDR_W-1:0] img_rd_addr,
    output logic [CH_W-1:0] img_rd_channel,
    output logic [K_ADDR_W-1:0] weight_rd_addr,
    input logic signed [7:0] img_rd_data,
    input logic [OUT_CH*8-1:0] weight_rd_data,

    output logic out_we,
    output logic [OUT_ADDR_W-1:0] out_addr,
    output logic [OUT_CH*8-1:0] out_data,

    output logic busy,
    output logic done
);
    typedef enum logic [2:0]{
        IDLE,
        LAUNCH,
        WAIT_RESULT,
        ADVANCE,
        FINISH
    } state_t;
    state_t state;

    localparam int OUT_W = IMG_W - 2;
    localparam int XY_W = (OUT_W <= 1) ? 1 : $clog2(OUT_W);
    logic [XY_W-1:0] x;
    logic [XY_W-1:0] y;
    logic [OUT_CH*32-1:0] bias_q;
    logic [OUT_CH-1:0] nr_rd_en;
    logic [K_ADDR_W-1:0] nr_rd_addr[0:OUT_CH-1];
    logic signed [31:0] nr_result[0:OUT_CH-1];
    logic [OUT_CH-1:0] nr_done;
    logic [OUT_CH-1:0] q_valid;
    logic [OUT_CH*8-1:0] q_data;
    logic nr_start;
    logic [3:0] kernel_index;

    assign nr_start = state == LAUNCH;
    assign kernel_index = nr_rd_addr[0] % 9;

    assign rd_en = nr_rd_en[0];
    assign weight_rd_addr = nr_rd_addr[0];
    assign img_rd_channel = nr_rd_addr[0] / 9;
    assign img_rd_addr = (y + kernel_index / 3) * IMG_W + x + kernel_index % 3;
    assign out_addr = y * OUT_W + x;

    generate
        for(genvar c = 0; c < OUT_CH; c = c + 1)begin : lane
            npu_neuron
            #(
                .N       (IN_CH * 9),
                .ADDR_W  (K_ADDR_W ),
                .RELU_EN (1'b1     )
            )
            u_npu_neuron(
                .clk     (clk                   ),
                .rst_n   (rst_n                 ),
                .start   (nr_start              ),
                .bias    (bias_q[c*32+:32]      ),
                .rd_en   (nr_rd_en[c]           ),
                .rd_addr (nr_rd_addr[c]         ),
                .a_data  (img_rd_data           ),
                .b_data  (weight_rd_data[c*8+:8]),
                .result  (nr_result[c]          ),
                .busy    (                      ),
                .done    (nr_done[c]            )
            );
            npu_requantize
            #(
                .SHIFT (SHIFT)
            )
            u_npu_requantize(
                .clk       (clk           ),
                .rst_n     (rst_n         ),
                .in_valid  (nr_done[c]    ),
                .in_data   (nr_result[c]  ),
                .out_valid (q_valid[c]    ),
                .out_data  (q_data[c*8+:8])
            );
        end
    endgenerate

    always_ff@(posedge clk)begin
        if(!rst_n)begin
            state <= IDLE;
            x <= '0;
            y <= '0;
            bias_q <= '0;
            out_we <= 1'b0;
            out_data <= '0;
            busy <= 1'b0;
            done <= 1'b0;
        end else begin
            out_we <= 1'b0;
            done <= 1'b0;
            case(state)
                IDLE:begin
                    if(start)begin
                        x <= '0;
                        y <= '0;
                        bias_q <= bias_data;
                        busy <= 1'b1;
                        state <= LAUNCH;
                    end
                end
                LAUNCH:begin
                    state <= WAIT_RESULT;
                end
                WAIT_RESULT:begin
                    if(&q_valid)begin
                        out_we <= 1'b1;
                        out_data <= q_data;
                        state <= ADVANCE;
                    end
                end
                ADVANCE:begin
                    if(x == OUT_W - 1)begin
                        x <= '0;
                        if(y == OUT_W - 1)begin
                            state <= FINISH;
                        end else begin
                            y <= y + 1'b1;
                            state <= LAUNCH;
                        end
                    end else begin
                        x <= x + 1'b1;
                        state <= LAUNCH;
                    end
                end
                FINISH:begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule
