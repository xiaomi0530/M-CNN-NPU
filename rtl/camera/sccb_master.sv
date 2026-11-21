module sccb_master (
    input logic clk,
    input logic rst_n,
    input logic start,
    input logic r_en,
    input logic [7:0] reg_addr,
    input logic [7:0] w_data,

    output logic [7:0] r_data,
    output logic busy,
    output logic done,
    output logic scl,
    inout wire sda
);
    logic sda_drive_low;
    assign sda = sda_drive_low? 1'b0 : 1'bz;

    logic r_en_q;
    logic [7:0] reg_addr_q;
    logic [7:0] w_data_q;

    typedef enum logic [4:0]{ 
        IDLE,
        START_A,
        START_B,
        BIT_SETUP,
        BIT_HIGH,
        BIT_HOLD,
        BIT_LOW,
        DC_SETUP,
        DC_HIGH,
        DC_HOLD,
        DC_LOW,
        STOP_A,
        STOP_B,
        STOP_C,
        STOP_WAIT,
        RX_SETUP,
        RX_HIGH,
        RX_SAMPLE,
        RX_LOW,
        NA_SETUP,
        NA_HIGH,
        NA_HOLD,
        NA_LOW
    } state_t;
    state_t state;

    logic [7:0] tick_count;
    logic tick;
    assign tick = tick_count == 8'd249;
    always_ff @(posedge clk) begin
        if(!rst_n)begin
            tick_count <= 1'b0;
        end else begin
            if(tick_count == 8'd249)begin
                tick_count <= 1'b0;
            end else begin
                tick_count <= tick_count + 1'b1;
            end
        end
    end

    logic [7:0] tx_byte;
    logic [2:0] bit_index;
    logic [1:0] byte_index;

    logic read_phase;
    logic [7:0] rx_byte;

    always_ff @(posedge clk)begin
        if(!rst_n)begin
            r_data <= 8'b0;
            busy   <= 1'b0;
            done   <= 1'b0;
            scl    <= 1'b1;
            sda_drive_low <= 1'b0;
            state <= IDLE;
            r_en_q     <= 1'b0;
            reg_addr_q <= 8'd0;
            w_data_q   <= 8'd0;
            tx_byte <= 1'b0;
            bit_index <= 1'b0;
            byte_index <= 1'b0;
            read_phase <= 1'b0;
            rx_byte <= 1'b0;
        end else begin
            done <= 1'b0;
            if(state == IDLE && start)begin
                state <= START_A;
                busy <= 1'b1;
                reg_addr_q <= reg_addr;
                w_data_q <= w_data;
                r_en_q <= r_en;
                tx_byte <= 8'h60;
                bit_index <= 3'd7;
                byte_index <= 1'b0;
                read_phase <= 1'b0;
                rx_byte <= 1'b0;
            end
            else if(tick)begin
                case (state)
                    START_A:begin
                        sda_drive_low <= 1'b1;
                        state <= START_B;
                    end
                    START_B:begin
                        scl <= 1'b0;
                        state <= BIT_SETUP;
                    end 
                    BIT_SETUP:begin
                        sda_drive_low <= !tx_byte[bit_index];
                        state <= BIT_HIGH;
                    end
                    BIT_HIGH:begin
                        scl <= 1'b1;
                        state <= BIT_HOLD;
                    end
                    BIT_HOLD:begin
                        state <= BIT_LOW;
                    end
                    BIT_LOW:begin
                        scl <= 1'b0;
                        if(bit_index == 1'b0)begin
                            state <= DC_SETUP;
                        end else begin
                            bit_index <= bit_index - 1'b1;
                            state <= BIT_SETUP;
                        end
                    end
                    DC_SETUP:begin
                        sda_drive_low <= 1'b0;
                        state <= DC_HIGH;
                    end
                    DC_HIGH:begin
                        scl <= 1'b1;
                        state <= DC_HOLD;
                    end
                    DC_HOLD:begin
                        state <= DC_LOW;
                    end
                    DC_LOW:begin
                        scl <= 1'b0;
                        if(read_phase == 1'b1)begin
                            bit_index <= 3'd7;
                            state <= RX_SETUP;
                        end else if(byte_index == 1'd1)begin
                            if(r_en_q)begin
                                state <= STOP_A;
                            end else begin
                                byte_index <= 2'd2;
                                tx_byte <= w_data_q;
                                bit_index <= 3'd7;
                                state <= BIT_SETUP;
                            end
                        end else if(byte_index == 2'd2)begin
                            state <= STOP_A;
                        end else if(byte_index == 1'b0)begin
                            byte_index <= 1'b1;
                            tx_byte <= reg_addr_q;
                            bit_index <= 3'd7;
                            state <= BIT_SETUP;
                        end
                    end
                    STOP_A:begin
                        sda_drive_low <= 1'b1;
                        state <= STOP_B;
                    end
                    STOP_B:begin
                        scl <= 1'b1;
                        state <= STOP_C;
                    end
                    STOP_C:begin
                        sda_drive_low <= 1'b0;
                        state <= STOP_WAIT;
                    end
                    STOP_WAIT:begin
                        if(read_phase == 1'b0 && r_en_q)begin
                            read_phase <= 1'b1;
                            tx_byte <= 8'h61;
                            byte_index <= 1'b0;
                            bit_index <= 3'd7;
                            state <= START_A;
                        end else begin
                            busy <= 1'b0;
                            done <= 1'b1;
                            state <= IDLE;
                            r_data <= rx_byte;
                        end
                    end

                    RX_SETUP:begin
                        scl <= 1'b0;
                        sda_drive_low <= 1'b0;
                        state <= RX_HIGH;
                    end 
                    RX_HIGH:begin
                        scl <= 1'b1;
                        state <= RX_SAMPLE;
                    end
                    RX_SAMPLE:begin
                        rx_byte[bit_index] <= sda;
                        state <= RX_LOW;
                    end
                    RX_LOW:begin
                        scl <= 1'b0;
                        if(bit_index == 1'b0)begin
                            state <= NA_SETUP;
                        end else begin
                            bit_index <= bit_index - 1'b1;
                            state <= RX_SETUP;
                        end
                    end
                    NA_SETUP:begin
                        sda_drive_low <= 1'b0;
                        state <= NA_HIGH;
                    end
                    NA_HIGH:begin
                        scl <= 1'b1;
                        state <= NA_HOLD;
                    end
                    NA_HOLD:begin
                        state <= NA_LOW;
                    end
                    NA_LOW:begin
                        scl <= 1'b0;
                        state <= STOP_A;
                    end

                    default: begin
                        state <= IDLE;
                        busy <= 1'b0;
                    end
                endcase
            end  
        end
    end
endmodule