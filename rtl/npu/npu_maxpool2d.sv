module npu_maxpool2d #(
    parameter int IMG_W = 26,
    parameter int IMG_H = 26,

    parameter int IMG_ADDR_W =
        (IMG_W * IMG_H <= 1) ? 1 : $clog2(IMG_W * IMG_H),

    parameter int OUT_ADDR_W =
        ((IMG_W / 2) * (IMG_H / 2) <= 1) ?
        1 : $clog2((IMG_W / 2) * (IMG_H / 2))
)(
    input logic clk,
    input logic rst_n,

    input logic start,

    output logic rd_en,
    output logic [IMG_ADDR_W-1:0] img_rd_addr,
    input logic signed [7:0] img_rd_data,

    output logic out_we,
    output logic [OUT_ADDR_W-1:0] out_addr,
    output logic signed [7:0] out_data,

    output logic busy,
    output logic done
);

    typedef enum logic [2:0]{
        IDLE,
        READ,
        WAIT_DATA,
        COMPARE,
        WRITE,
        ADVANCE,
        FINISH
    }state_t;
    state_t state;

    logic [$clog2(IMG_W)-1:0] out_x;
    logic [$clog2(IMG_H)-1:0] out_y;
    logic [2:0] k;
    logic [2:0] kx;
    logic [2:0] ky;

    assign kx = k%2;
    assign ky = k/2;

    logic  signed [7:0] max_value;

    assign out_addr = out_x/2 + (out_y/2)*(IMG_W/2);
    assign img_rd_addr = (out_x+kx) + (out_y+ky)*IMG_W;

    always_ff@(posedge clk)begin
        if(!rst_n)begin
            rd_en <= 1'b0;
            out_we <= 1'b0;
            done <= 1'b0;
            busy <= 1'b0;
            out_data <= 1'b0;
            state <= IDLE;
            max_value <= 1'b0;
        end else begin
            rd_en <= 1'b0;
            out_we <= 1'b0;
            done <= 1'b0;
            case(state)
                IDLE:begin
                    if(start)begin
                        state <= READ;
                        busy <= 1'b1;
                        k <= 1'b0;
                        out_x <= 1'b0;
                        out_y <= 1'b0;
                        max_value <= 1'b0;
                    end
                end
                READ:begin
                    rd_en <= 1'b1;
                    state <= WAIT_DATA;
                end
                WAIT_DATA:begin
                    state <= COMPARE;
                end
                COMPARE:begin
                    max_value <= ((max_value<img_rd_data) || (k == 1'b0))? img_rd_data : max_value;
                    if(k < 3)begin
                        k <= k + 1'b1;
                        state <= READ;
                    end else begin
                        state <= WRITE;
                    end
                end
                WRITE:begin
                    out_we <= 1'b1;
                    out_data <= max_value;
                    state <= ADVANCE;
                end
                ADVANCE:begin
                    if(out_y < 2*(IMG_H/2)-2)begin
                        k <= 1'b0;
                        state <= READ;
                        if(out_x < 2*(IMG_W/2)-2)begin
                            out_x <= out_x + 2'd2;
                        end else begin
                            out_x <= 1'b0;
                            out_y <= out_y + 2'd2;
                        end
                    end else begin
                        if(out_x < 2*(IMG_W/2)-2)begin
                            out_x <= out_x + 2'd2;
                            k <= 1'b0;
                            state <= READ;
                        end else begin
                            state <= FINISH;
                        end
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
