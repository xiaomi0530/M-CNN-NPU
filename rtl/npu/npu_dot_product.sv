module npu_dot_product #(
    parameter integer N = 9,
    parameter integer ADDR_W = (N <= 1) ? 1 : $clog2(N)
)(
    input logic clk,
    input logic rst_n,
    input logic start,

    output logic rd_en,
    output logic [ADDR_W-1:0] rd_addr,

    input logic signed [7:0] a_data,
    input logic signed [7:0] b_data,

    output logic signed [31:0] result,
    output logic busy,
    output logic done
);

    typedef enum logic [2:0] {
        IDLE,
        CLEAR,
        READ,
        WAIT_DATA,
        FEED,
        WAIT_RESULT
    } state_t;

    state_t state;

    logic mac_clear;
    logic mac_in_valid;
    logic mac_in_last;
    logic signed [7:0] mac_a;
    logic signed [7:0] mac_b;
    logic signed [31:0] mac_result;
    logic mac_result_valid;
    npu_mac u_npu_mac(
        .clk          (clk              ),
        .rst_n        (rst_n            ),
        .clear        (mac_clear        ),
        .in_valid     (mac_in_valid     ),
        .in_last      (mac_in_last      ),
        .a            (mac_a            ),
        .b            (mac_b            ),
        .result       (mac_result       ),
        .result_valid (mac_result_valid )
    );
    
    always_ff @(posedge clk) begin
        if(!rst_n)begin
            state <= IDLE;
            rd_en = 1'b0;
            rd_addr <= 1'b0;
            result <= 1'b0;
            busy <= 1'b0;
            done <= 1'b0;
            rd_addr <= 1'b0;
            mac_in_valid <= 1'b0;
            mac_in_last <= 1'b0;
        end else begin
            done <= 1'b0;
            rd_en <= 1'b0;
            mac_clear <= 1'b0;
            case(state)
                IDLE:begin
                    mac_in_valid <= 1'b0;
                    mac_in_last <= 1'b0;
                    if(start)begin
                        state <= CLEAR;
                        busy <= 1'b1;
                        rd_addr <= 1'b0;
                    end
                end
                CLEAR:begin
                    mac_clear <= 1'b1;
                    state <= READ;
                end
                READ:begin
                    rd_en <= 1'b1;
                    mac_in_valid <= 1'b0;
                    mac_in_last <= 1'b0;
                    state <= WAIT_DATA;
                end
                WAIT_DATA:begin
                    state <= FEED;
                end
                FEED:begin
                    mac_a <= a_data;
                    mac_b <= b_data;
                    if(rd_addr < N)begin
                        mac_in_valid <= 1'b1;
                        rd_addr <= rd_addr + 1'b1;
                        if(rd_addr == N-1)begin
                            mac_in_last <= 1'b1;
                            state <= WAIT_RESULT;
                        end else begin
                            state <= READ;
                        end
                    end
                end
                WAIT_RESULT:begin
                    mac_in_valid <= 1'b0;
                    mac_in_last <= 1'b0;
                    if(mac_result_valid)begin
                        result <= mac_result;
                        state <= IDLE;
                        done <= 1'b1;
                        busy <= 1'b0;
                    end
                end
            endcase
        end  
    end

endmodule