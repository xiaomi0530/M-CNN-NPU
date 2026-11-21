module probe_uart_tx #(
    parameter int CLK_HZ = 100_000_000,
    parameter int BAUD = 115200
)(
    input logic clk,
    input logic rst_n,

    input logic valid,
    input logic [7:0] data,
    output logic ready,

    output logic tx
);
    localparam int DIV = (CLK_HZ + BAUD / 2) / BAUD;
    localparam int COUNT_W = (DIV <= 1) ? 1 : $clog2(DIV);

    logic active;
    logic [COUNT_W-1:0] count;
    logic [9:0] frame;
    logic [3:0] index;

    assign ready = !active;

    always_ff@(posedge clk)begin
        if(!rst_n)begin
            tx <= 1'b1;
            active <= 1'b0;
            count <= '0;
            frame <= '1;
            index <= '0;
        end else if(!active)begin
            tx <= 1'b1;
            if(valid)begin
                frame <= {1'b1, data, 1'b0};
                tx <= 1'b0;
                index <= '0;
                count <= '0;
                active <= 1'b1;
            end
        end else if(count == DIV - 1)begin
            count <= '0;
            if(index == 4'd9)begin
                tx <= 1'b1;
                active <= 1'b0;
            end else begin
                index <= index + 1'b1;
                tx <= frame[index+1'b1];
            end
        end else begin
            count <= count + 1'b1;
        end
    end
endmodule
