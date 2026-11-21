module npu_fc #(
    parameter int IN_SIZE = 169,
    parameter int IN_ADDR_W =
        (IN_SIZE <= 1) ? 1 : $clog2(IN_SIZE),
    parameter int CLASSES = 10,
    localparam int CLASS_W = CLASSES <= 1 ? 1 : $clog2(CLASSES)
)(
    input logic clk,
    input logic rst_n,

    input logic start,
    input logic [CLASSES*32-1:0] bias_data,

    output logic rd_en,
    output logic [IN_ADDR_W-1:0] rd_addr,

    input logic signed [7:0] input_rd_data,
    input logic [CLASSES*8-1:0] weight_rd_data,

    output logic out_we,
    output logic [CLASS_W-1:0] out_addr,
    output logic signed [31:0] out_data,

    output logic busy,
    output logic done
);

    logic nr_start;

    logic [CLASSES-1:0] nr_rd_en;
    logic [IN_ADDR_W-1:0] nr_rd_addr [0:CLASSES-1];

    logic signed [7:0] nr_weight [0:CLASSES-1];
    logic signed [31:0] bias_q [0:CLASSES-1];

    logic signed [31:0] nr_result [0:CLASSES-1];
    logic [CLASSES-1:0] nr_busy;
    logic [CLASSES-1:0] nr_done;

    logic signed [31:0] score [0:CLASSES-1];
    logic [CLASS_W-1:0] output_index;

    generate
        for(genvar j=0; j<CLASSES; j=j+1)begin
                assign nr_weight[j] = weight_rd_data[j*8 +: 8];
                npu_neuron #(
                    .N       (IN_SIZE  ),
                    .ADDR_W  (IN_ADDR_W),
                    .RELU_EN (1'b0     )
                ) u_npu_neuron (
                    .clk     (clk           ),
                    .rst_n   (rst_n         ),
                    .start   (nr_start      ),
                    .bias    (bias_q[j]     ),

                    .rd_en   (nr_rd_en[j]   ),
                    .rd_addr (nr_rd_addr[j] ),
                    .a_data  (input_rd_data ),
                    .b_data  (nr_weight[j]  ),

                    .result  (nr_result[j]  ),
                    .busy    (nr_busy[j]    ),
                    .done    (nr_done[j]    )
                );
            end
    endgenerate

    assign rd_en = nr_rd_en[0];
    assign rd_addr = nr_rd_addr[0];

    typedef enum logic [2:0] {
        IDLE,
        NEURON_START,
        NEURON_WAIT,
        WRITE,
        ADVANCE,
        FINISH
    } state_t;

    state_t state;

    always@(posedge clk)begin
        if(!rst_n)begin
            state <= IDLE;
            nr_start <= 1'b0;
            out_we <= 1'b0;
            busy <= 1'b0;
            done <= 1'b0;
            output_index <= 4'd0;
            out_addr <= 4'd0;
            out_data <= 32'sd0;
            for(int j=0; j<CLASSES; j=j+1)begin
                bias_q[j] <= 32'sd0;
                score[j] <= 32'sd0;
            end
        end else begin
            nr_start <= 1'b0;
            out_we <= 1'b0;
            done <= 1'b0;
            case(state)
                IDLE:begin
                    if(start)begin
                        state <= NEURON_START;
                        busy <= 1'b1;
                        output_index <= 1'b0;
                        for(int j=0; j<CLASSES; j=j+1)begin
                            bias_q[j] <= bias_data[j*32 +: 32];
                        end
                    end
                end
                NEURON_START:begin
                    nr_start <= 1'b1;
                    state <= NEURON_WAIT;
                end
                NEURON_WAIT:begin
                    if(&nr_done)begin
                        for(int j=0; j<CLASSES; j=j+1) score[j] <= nr_result[j];
                        state <= WRITE;
                    end
                end
                WRITE:begin
                    out_we <= 1'b1;
                    out_addr <= output_index;
                    out_data <= score[output_index];
                    state <= ADVANCE;
                end
                ADVANCE:begin
                    if(output_index < CLASSES-1)begin
                        output_index <= output_index + 1'b1;
                        state <= WRITE;
                    end else begin
                        state <= FINISH;
                    end
                end
                FINISH:begin
                    done <= 1'b1;
                    busy <= 1'b0;
                    state <= IDLE;
                end
            endcase
        end
    end


endmodule
