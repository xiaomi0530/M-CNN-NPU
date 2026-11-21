module npu_top #(
    parameter int C0 = 12,
    parameter int C1 = 24,
    parameter int C2 = 40,
    parameter int C3 = 48,
    parameter int SHIFT0 = 6,
    parameter int SHIFT1 = 7,
    parameter int SHIFT2 = 9,
    parameter int SHIFT3 = 8
)(
    input logic clk,
    input logic rst_n,

    input logic start,
    output logic img_rd_en,
    output logic [11:0] img_rd_addr,
    input logic [15:0] img_rd_data,

    output logic [3:0] class_id,
    output logic signed [31:0] max_score,

    output logic busy,
    output logic done,

    output logic score_we,
    output logic [3:0] score_index,
    output logic signed [31:0] score_value
);
    localparam int WIDTH[0:4] = '{3, C0, C1, C2, C3};
    localparam int SIDE[0:4] = '{56, 27, 12, 5, 3};
    localparam int SHIFT[0:3] = '{SHIFT0, SHIFT1, SHIFT2, SHIFT3};
    localparam int CLASSES = 15;
    localparam int FEATURES = C3 * 9;
    localparam int FC_CH_W = (C3 <= 1) ? 1 : $clog2(C3);
    localparam string WEIGHTS[0:3] = '{
        "conv0_weights.mem", "conv1_weights.mem", "conv2_weights.mem", "conv3_weights.mem"
    };
    localparam string BIAS[0:3] = '{
        "conv0_bias.mem", "conv1_bias.mem", "conv2_bias.mem", "conv3_bias.mem"
    };

    logic [3:0] stage_done;
    logic fc_re;
    logic [$clog2(FEATURES)-1:0] fc_addr;

    logic [CLASSES*8-1:0] weights[0:FEATURES-1];
    logic [CLASSES*32-1:0] biases[0:0];

    logic [FC_CH_W-1:0] channel_q;
    logic [CLASSES*8-1:0] weight_q;

    logic valid;

    for(genvar i = 0; i < 4; i++)begin : stage
        localparam int IN_CH = WIDTH[i];
        localparam int OUT_CH = WIDTH[i+1];
        localparam int W = SIDE[i];
        localparam int NEXT_W = SIDE[i+1];
        localparam int CH_W = (IN_CH <= 1) ? 1 : $clog2(IN_CH);

        logic re;
        logic [$clog2(W*W)-1:0] addr;
        logic [CH_W-1:0] channel;
        logic [CH_W-1:0] channel_q;
        logic [8*OUT_CH-1:0] packed_pixel;
        logic signed [7:0] pixel;
        logic launch;
        logic dst_re;
        logic [$clog2(NEXT_W*NEXT_W)-1:0] dst_addr;

        always_ff@(posedge clk)begin
            if(re)begin
                channel_q <= channel;
            end
        end
        if(i == 0)begin
            assign launch = start && !busy;
            assign img_rd_en = re;
            assign img_rd_addr = addr;
            always_comb begin
                case(channel_q)
                    0:begin
                        pixel = {1'b0, img_rd_data[15:11], img_rd_data[15:14]};
                    end
                    1:begin
                        pixel = {1'b0, img_rd_data[10:5], img_rd_data[10]};
                    end
                    default:begin
                        pixel = {1'b0, img_rd_data[4:0], img_rd_data[4:3]};
                    end
                endcase
            end
        end else begin
            assign launch = stage_done[i-1];
            assign pixel = stage[i-1].packed_pixel[8*channel_q+:8];
        end
        if(i == 3)begin
            assign dst_re = fc_re;
            assign dst_addr = fc_addr % 9;
        end else begin
            assign dst_re = stage[i+1].re;
            assign dst_addr = stage[i+1].addr;
        end
        npu_conv_multi_maxpool2d
        #(
            .IMG_W  (W         ),
            .IN_CH  (IN_CH     ),
            .OUT_CH (OUT_CH    ),
            .SHIFT  (SHIFT[i]  ),
            .POOL   (i < 3     ),
            .WFILE  (WEIGHTS[i]),
            .BFILE  (BIAS[i]   )
        )
        u_npu_conv_multi_maxpool2d(
            .clk         (clk          ),
            .rst_n       (rst_n        ),
            .start       (launch       ),
            .src_re      (re           ),
            .src_addr    (addr         ),
            .src_channel (channel      ),
            .src_data    (pixel        ),
            .dst_re      (dst_re       ),
            .dst_addr    (dst_addr     ),
            .dst_data    (packed_pixel ),
            .done        (stage_done[i])
        );
    end

    initial begin
        $readmemh("fc_weights.mem", weights);
        $readmemh("fc_bias.mem", biases);
    end
    always_ff@(posedge clk)begin
        if(fc_re)begin
            channel_q <= fc_addr / 9;
            weight_q <= weights[fc_addr];
        end
    end
    npu_fc
    #(
        .IN_SIZE (FEATURES),
        .CLASSES (CLASSES )
    )
    u_npu_fc(
        .clk            (clk                                  ),
        .rst_n          (rst_n                                ),
        .start          (stage_done[3]                        ),
        .bias_data      (biases[0]                            ),
        .rd_en          (fc_re                                ),
        .rd_addr        (fc_addr                              ),
        .input_rd_data  (stage[3].packed_pixel[8*channel_q+:8]),
        .weight_rd_data (weight_q                             ),
        .out_we         (score_we                             ),
        .out_addr       (score_index                          ),
        .out_data       (score_value                          ),
        .busy           (                                     ),
        .done           (                                     )
    );
    npu_argmax
    #(
        .CLASSES (CLASSES)
    )
    u_npu_argmax(
        .clk          (clk        ),
        .rst_n        (rst_n      ),
        .in_valid     (score_we   ),
        .in_index     (score_index),
        .in_score     (score_value),
        .class_id     (class_id   ),
        .max_score    (max_score  ),
        .result_valid (valid      )
    );
    always_ff@(posedge clk)begin
        if(!rst_n)begin
            busy <= 1'b0;
            done <= 1'b0;
        end else begin
            done <= valid;
            if(valid)begin
                busy <= 1'b0;
            end else if(start)begin
                busy <= 1'b1;
            end
        end
    end
endmodule
