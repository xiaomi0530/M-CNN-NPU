module ov2640_config #(
    parameter integer CLK_HZ = 100_000_000
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    output logic        busy,
    output logic        config_done,
    output logic [9:0]  cfg_index,
    input  logic [15:0] cfg_word,
    input  logic        cfg_last,
    input  logic [7:0]  cfg_delay_ms,
    output logic        sccb_start,
    output wire         sccb_r_en,
    output logic [7:0]  sccb_reg_addr,
    output logic [7:0]  sccb_w_data,
    input  logic        sccb_busy,
    input  logic        sccb_done
);
    localparam integer MS_CYCLES = CLK_HZ / 1000;
    localparam integer COUNT_WIDTH = (MS_CYCLES > 1) ? $clog2(MS_CYCLES) : 1;
    typedef enum logic [2:0] {
        IDLE, LOAD, SEND, WAIT_DONE, DELAY, NEXT, FINISH
    } state_t;
    state_t state;
    logic last_q;
    logic [7:0] delay_ms_q, ms_remaining;
    logic [COUNT_WIDTH-1:0] ms_count;

    assign sccb_r_en = 1'b0;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state          <= IDLE;
            busy           <= 1'b0;
            config_done    <= 1'b0;
            cfg_index      <= '0;
            sccb_start     <= 1'b0;
            sccb_reg_addr  <= '0;
            sccb_w_data    <= '0;
            last_q         <= 1'b0;
            delay_ms_q     <= '0;
            ms_remaining   <= '0;
            ms_count       <= '0;
        end else begin
            sccb_start <= 1'b0;
            case (state)
                IDLE: begin
                    if (start) begin
                        busy        <= 1'b1;
                        config_done <= 1'b0;
                        cfg_index   <= '0;
                        state       <= LOAD;
                    end
                end
                LOAD: begin
                    sccb_reg_addr <= cfg_word[15:8];
                    sccb_w_data   <= cfg_word[7:0];
                    last_q        <= cfg_last;
                    delay_ms_q    <= cfg_delay_ms;
                    state         <= SEND;
                end
                SEND: begin
                    if (!sccb_busy) begin
                        sccb_start <= 1'b1;
                        state      <= WAIT_DONE;
                    end
                end
                WAIT_DONE: begin
                    if (sccb_done) begin
                        if (delay_ms_q == 0) begin
                            state <= NEXT;
                        end else begin
                            ms_count     <= '0;
                            ms_remaining <= delay_ms_q;
                            state        <= DELAY;
                        end
                    end
                end
                DELAY: begin
                    if (ms_count == MS_CYCLES - 1) begin
                        ms_count <= '0;
                        if (ms_remaining == 1) begin
                            ms_remaining <= '0;
                            state        <= NEXT;
                        end else begin
                            ms_remaining <= ms_remaining - 1'b1;
                        end
                    end else begin
                        ms_count <= ms_count + 1'b1;
                    end
                end
                NEXT: begin
                    if (last_q) state <= FINISH;
                    else begin
                        cfg_index <= cfg_index + 1'b1;
                        state     <= LOAD;
                    end
                end
                FINISH: begin
                    busy        <= 1'b0;
                    config_done <= 1'b1;
                    state       <= IDLE;
                end
                default: begin
                    state       <= IDLE;
                    busy        <= 1'b0;
                    config_done <= 1'b0;
                end
            endcase
        end
    end
endmodule
