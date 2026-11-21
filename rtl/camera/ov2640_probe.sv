module ov2640_probe (
    input logic clk,
    input logic rst_n,
    output logic cam_pwdn,
    output logic cam_rst_n,
    output logic sccb_start,
    output logic sccb_r_en,
    output logic [7:0] sccb_reg_addr,
    output logic [7:0] sccb_w_data,
    input logic sccb_busy,
    input logic sccb_done,
    input logic [7:0] sccb_r_data,
    output logic [15:0] chip_id,
    output logic probe_done,
    output logic probe_error
);

    logic [19:0] delay_count;
    
    typedef enum logic [3:0]{
        RESET_HOLD,
        RESET_WAIT,
        BANK_PREP,
        BANK_SEND,
        BANK_WAIT,
        IDH_PREP,
        IDH_SEND,
        IDH_WAIT,
        IDL_PREP,
        IDL_SEND,
        IDL_WAIT,
        FINISH,
        ERROR
    }state_t;

    state_t state;

    always_ff @(posedge clk) begin
        if(!rst_n)begin
            delay_count <= 1'b0;
            sccb_start <= 1'b0;
            cam_pwdn <= 1'b0;
            cam_rst_n <= 1'b0;
            sccb_r_en <= 1'b0;
            sccb_reg_addr <= 1'b0;
            sccb_w_data <= 1'b0;
            chip_id <= 1'b0;
            probe_done <= 1'b0;
            probe_error <= 1'b0;
            state <= RESET_HOLD;
        end else begin
            sccb_start <= 1'b0;
            case(state)
                RESET_HOLD:begin
                    if(delay_count == 20'd999999)begin
                        state <= RESET_WAIT;
                        delay_count <= 1'b0;
                    end else begin
                        delay_count <= delay_count + 1'b1;
                    end
                end
                RESET_WAIT:begin
                    cam_pwdn <= 1'b0;
                    cam_rst_n <= 1'b1;
                    if(delay_count == 20'd999999)begin
                        state <= BANK_PREP;
                        delay_count <= 1'b0;
                    end else begin
                        delay_count <= delay_count + 1'b1;
                    end
                end
                BANK_PREP:begin
                    sccb_r_en <= 1'b0;
                    sccb_reg_addr <= 8'hFF;
                    sccb_w_data <= 8'h01;
                    state <= BANK_SEND;
                end
                BANK_SEND:begin
                    if(!sccb_busy)begin
                        sccb_start <= 1'b1;
                        state <= BANK_WAIT;
                    end else begin
                        state <= BANK_SEND;
                    end
                end
                BANK_WAIT:begin
                    if(sccb_done)begin
                        state <= IDH_PREP;
                    end else begin
                        state <= BANK_WAIT;
                    end
                end
                IDH_PREP:begin
                    sccb_r_en <= 1'b1;
                    sccb_reg_addr <= 8'h0A;
                    state <= IDH_SEND;
                end
                IDH_SEND:begin
                    if(!sccb_busy)begin
                        sccb_start <= 1'b1;
                        state <= IDH_WAIT;
                    end else begin
                        state <= IDH_SEND;
                    end
                end
                IDH_WAIT:begin
                    if(sccb_done)begin
                        chip_id[15:8] <= sccb_r_data; 
                        state <= IDL_PREP;
                    end else begin
                        state <= IDH_WAIT;
                    end
                end
                IDL_PREP:begin
                    sccb_r_en <= 1'b1;
                    sccb_reg_addr <= 8'h0B;
                    state <= IDL_SEND;
                end
                IDL_SEND:begin
                    if(!sccb_busy)begin
                        sccb_start <= 1'b1;
                        state <= IDL_WAIT;
                    end else begin
                        state <= IDL_SEND;
                    end
                end
                IDL_WAIT:begin
                    sccb_start <= 1'b0;
                    if(sccb_done)begin
                        chip_id[7:0] <= sccb_r_data; 
                        state <= FINISH;
                    end else begin
                        state <= IDL_WAIT;
                    end
                end
                FINISH:begin
                    probe_done <= 1'b1;
                end
            endcase
        end
    end
    
endmodule