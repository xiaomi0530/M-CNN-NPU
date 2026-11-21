module ov2640_capture (
    input logic cam_pclk,
    input logic rst_n,

    input logic capture_enable,
    input logic cam_vsync,
    input logic cam_href,
    input logic [7:0] cam_data,

    output logic pixel_valid,
    output logic [15:0] pixel_data,
    output logic [8:0] pixel_x,
    output logic [7:0] pixel_y,

    output logic frame_start
);
    typedef enum logic [1:0] { 
        WAIT_FRAME,
        WAIT_LOW,
        WAIT_HIGH
    } state_t;
    state_t state;
    
    logic [7:0] low_byte;
    logic cam_href_q;
    logic cam_vsync_q;

    logic [8:0] x_count;
    logic [8:0] y_count;

    always_ff @(posedge cam_pclk) begin
        if(!rst_n)begin
            pixel_valid <= 1'b0;
            pixel_data <= 1'b0;
            pixel_x <= 1'b0;
            pixel_y <= 1'b0;
            frame_start <= 1'b0;
            state <= WAIT_FRAME;
            cam_href_q <= 1'b0;
            cam_vsync_q <= 1'b0;
            x_count <= 1'b0;
            y_count <= 1'b0;
        end else begin
            if(capture_enable)begin
                cam_href_q <= cam_href;
                cam_vsync_q <= cam_vsync;
                frame_start <= 1'b0;
                pixel_valid <= 1'b0;
                case(state)
                    WAIT_FRAME:begin
                        if(cam_vsync && !cam_vsync_q)begin
                            state <= WAIT_LOW;
                            pixel_x <= 1'b0;
                            pixel_y <= 1'b0;
                            x_count <= 1'b0;
                            y_count <= 1'b0;
                            frame_start <= 1'b1;
                        end else begin
                            state <= WAIT_FRAME;
                        end
                    end
                    WAIT_LOW:begin
                        if(cam_vsync && !cam_vsync_q)begin
                            pixel_x <= 1'b0;
                            pixel_y <= 1'b0;
                            x_count <= 1'b0;
                            y_count <= 1'b0;
                            pixel_data <= 1'b0;
                            pixel_valid <= 1'b0;
                            frame_start <= 1'b1;
                        end else if(!cam_vsync && cam_href)begin
                            low_byte <= cam_data;
                            state <= WAIT_HIGH;
                        end else if(!cam_href && cam_href_q && !cam_vsync_q)begin
                            x_count <= 1'b0;
                            if(y_count < 9'd240)begin
                                y_count <= y_count + 1'b1;
                                state <= WAIT_LOW;
                            end else begin
                                state <= WAIT_FRAME;
                            end
                        end
                    end
                    WAIT_HIGH:begin
                        if(cam_vsync && !cam_vsync_q)begin
                            state <= WAIT_LOW;
                            pixel_x <= 1'b0;
                            pixel_y <= 1'b0;
                            x_count <= 1'b0;
                            y_count <= 1'b0;
                            pixel_data <= 1'b0;
                            pixel_valid <= 1'b0;
                            frame_start <= 1'b1;
                        end else if(!cam_vsync && cam_href)begin
                            pixel_data <= {cam_data,low_byte};
                            pixel_valid <= ((y_count < 9'd240)&&(x_count<9'd320))? 1'b1 : 1'b0;
                            pixel_x <= x_count;
                            pixel_y <= y_count;
                            if(x_count < 9'd320)begin
                                x_count <= x_count + 1'b1;
                            end
                            state <= WAIT_LOW;
                        end else if(cam_href_q && !cam_href && !cam_vsync_q)begin
                            x_count <= 1'b0;
                            if(y_count < 9'd240)begin
                                y_count <= y_count + 1'b1;
                                state <= WAIT_LOW;
                            end else begin
                                state <= WAIT_FRAME;
                            end
                        end
                    end
                endcase
            end else begin
                state <= WAIT_FRAME;
                pixel_x <= 1'b0;
                pixel_y <= 1'b0;
                x_count <= 1'b0;
                y_count <= 1'b0;
                pixel_data <= 1'b0;
                pixel_valid <= 1'b0;
                frame_start <= 1'b0;
                cam_href_q <= 1'b0;
                cam_vsync_q <= 1'b0;
            end
        end
    end
        
endmodule