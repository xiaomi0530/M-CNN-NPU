module npu_requantize #(
    parameter int SHIFT = 0
)(
    input logic clk,
    input logic rst_n,

    input logic in_valid,
    input logic signed [31:0] in_data,

    output logic out_valid,
    output logic signed [7:0] out_data
);

    logic signed [31:0] shifted_data;
    assign shifted_data = in_data>>>SHIFT;
    
    always_ff@(posedge clk)begin
        if(!rst_n)begin
            out_valid <= 1'b0;
            out_data <= 1'b0;
        end else begin
            if(in_valid)begin
                out_valid <= in_valid;
                out_data <= (shifted_data>32'sd127) ? 8'sd127:((shifted_data<-32'sd128)?8'sh80:shifted_data[7:0]);
            end else begin
                out_valid <= 1'b0;
                out_data <= out_data;
            end
        end
    end

endmodule