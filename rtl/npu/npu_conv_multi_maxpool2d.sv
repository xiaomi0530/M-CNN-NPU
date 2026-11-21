module npu_conv_multi_maxpool2d #(
    parameter int IMG_W = 56,
    parameter int IN_CH = 3,
    parameter int OUT_CH = 8,
    parameter int SHIFT = 7,
    parameter bit POOL = 1'b1,
    parameter WFILE = "conv0_weights.mem",
    parameter BFILE = "conv0_bias.mem",
    localparam int CONV_W = IMG_W - 2,
    localparam int OUT_W = POOL ? CONV_W / 2 : CONV_W,
    localparam int SRC_AW = $clog2(IMG_W * IMG_W),
    localparam int CONV_AW = (CONV_W <= 1) ? 1 : $clog2(CONV_W * CONV_W),
    localparam int OUT_AW = (OUT_W <= 1) ? 1 : $clog2(OUT_W * OUT_W),
    localparam int CH_W = (IN_CH <= 1) ? 1 : $clog2(IN_CH)
)(
    input logic clk,
    input logic rst_n,

    input logic start,
    output logic src_re,
    output logic [SRC_AW-1:0] src_addr,
    output logic [CH_W-1:0] src_channel,
    input logic signed [7:0] src_data,

    input logic dst_re,
    input logic [OUT_AW-1:0] dst_addr,
    output logic [8*OUT_CH-1:0] dst_data,
    output logic done
);
    logic [OUT_CH*8-1:0] weights[0:IN_CH*9-1];
    logic [OUT_CH*32-1:0] biases[0:0];
    logic [$clog2(IN_CH*9)-1:0] weight_addr;
    logic [8*OUT_CH-1:0] weight_q;

    logic conv_we, conv_done;
    logic [CONV_AW-1:0] conv_addr;
    logic [8*OUT_CH-1:0] conv_data;

    logic feature_we;
    logic [OUT_AW-1:0] feature_addr;
    logic [8*OUT_CH-1:0] feature_data;

    logic [8*OUT_CH-1:0] feature_ram[0:OUT_W*OUT_W-1];

    initial begin
        $readmemh(WFILE, weights);
        $readmemh(BFILE, biases);
    end
    always_ff@(posedge clk)begin
        if(src_re)begin
            weight_q <= weights[weight_addr];
        end
    end
    npu_conv_multi
    #(
        .IMG_W  (IMG_W ),
        .IN_CH  (IN_CH ),
        .OUT_CH (OUT_CH),
        .SHIFT  (SHIFT )
    )
    u_npu_conv_multi(
        .clk            (clk        ),
        .rst_n          (rst_n      ),
        .start          (start      ),
        .bias_data      (biases[0]  ),
        .rd_en          (src_re     ),
        .img_rd_addr    (src_addr   ),
        .img_rd_channel (src_channel),
        .img_rd_data    (src_data   ),
        .weight_rd_addr (weight_addr),
        .weight_rd_data (weight_q   ),
        .out_we         (conv_we    ),
        .out_addr       (conv_addr  ),
        .out_data       (conv_data  ),
        .busy           (           ),
        .done           (conv_done  )
    );
    if(POOL)begin : pooled
        (* ram_style = "block" *) logic [8*OUT_CH-1:0] conv_ram[0:CONV_W*CONV_W-1];
        logic [OUT_CH-1:0] re, we, finished;
        logic [CONV_AW-1:0] raddr[0:OUT_CH-1];
        logic [OUT_AW-1:0] waddr[0:OUT_CH-1];
        logic [8*OUT_CH-1:0] q;
        always_ff@(posedge clk)begin
            if(conv_we)begin
                conv_ram[conv_addr] <= conv_data;
            end
            if(re[0])begin
                q <= conv_ram[raddr[0]];
            end
        end
        for(genvar c = 0; c < OUT_CH; c++)begin : lanes
            npu_maxpool2d
            #(
                .IMG_W (CONV_W),
                .IMG_H (CONV_W)
            )
            u_npu_maxpool2d(
                .clk         (clk                 ),
                .rst_n       (rst_n               ),
                .start       (conv_done           ),
                .rd_en       (re[c]               ),
                .img_rd_addr (raddr[c]            ),
                .img_rd_data (q[c*8+:8]           ),
                .out_we      (we[c]               ),
                .out_addr    (waddr[c]            ),
                .out_data    (feature_data[c*8+:8]),
                .busy        (                    ),
                .done        (finished[c]         )
            );
        end
        assign feature_we = we[0];
        assign feature_addr = waddr[0];
        assign done = &finished;
    end else begin : direct
        assign feature_we = conv_we;
        assign feature_addr = conv_addr;
        assign feature_data = conv_data;
        assign done = conv_done;
    end
    always_ff@(posedge clk)begin
        if(feature_we)begin
            feature_ram[feature_addr] <= feature_data;
        end
        if(dst_re)begin
            dst_data <= feature_ram[dst_addr];
        end
    end
endmodule
