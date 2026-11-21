module npu_mac (
    input logic clk,
    input logic rst_n,

    input logic clear,
    input logic in_valid,
    input logic in_last,

    input logic signed [7:0] a,
    input logic signed [7:0] b,

    output logic signed [31:0] result,
    output logic result_valid
);

    logic signed [15:0] mul_result;
    logic signed [31:0] mac_result;
    logic signed [31:0] mac_next;

    assign mul_result = a * b;
    assign mac_next =  mac_result + {{16{mul_result[15]}},mul_result};

    always_ff @(posedge clk)begin
        if(!rst_n || clear)begin
            result <= 1'b0;
            result_valid <= 1'b0;
            mac_result <= 1'b0;
        end else begin
            result_valid <= 1'b0;
            if(in_valid)begin
                mac_result <= mac_next;
                if(in_last)begin
                    result <= mac_next;
                    result_valid <= 1'b1;
                end
            end
        end
    end

endmodule