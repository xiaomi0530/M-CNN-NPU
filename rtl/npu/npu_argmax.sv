module npu_argmax #(
    parameter int CLASSES = 10,
    localparam int CLASS_W = CLASSES <= 1 ? 1 : $clog2(CLASSES)
)(
    input logic clk, rst_n, in_valid,
    input logic [CLASS_W-1:0] in_index,
    input logic signed [31:0] in_score,
    output logic [CLASS_W-1:0] class_id,
    output logic signed [31:0] max_score,
    output logic result_valid
);
    logic signed [31:0] best;
    logic [CLASS_W-1:0] best_id;
    wire wins = in_index == 0 || in_score > best;
    wire signed [31:0] next_best = wins ? in_score : best;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            best <= '0;
            best_id <= '0;
            class_id <= '0;
            max_score <= '0;
            result_valid <= 0;
        end else begin
            result_valid <= 0;
            if (in_valid) begin
                if (wins) begin
                    best <= in_score;
                    best_id <= in_index;
                end
                if (in_index == CLASSES-1) begin
                    class_id <= wins ? in_index : best_id;
                    max_score <= next_best;
                    result_valid <= 1;
                end
            end
        end
    end
endmodule
