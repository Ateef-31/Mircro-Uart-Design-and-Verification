`timescale 1ns / 1ps
module u_xmit #(
    parameter WORD_LEN = 8
)(
    input uart_clk,
    input rst,
    input [WORD_LEN-1:0] xmit_dataH,
    input xmitH,
    output reg uart_XMIT_dataH,
    output reg xmit_doneH,
    output reg xmit_active
);    
    parameter IDLE  = 2'b00,
        START = 2'b01,
        DATA  = 2'b10,
        STOP  = 2'b11;
    reg [1:0] nt_st;
    reg xmit_s1, xmit_s2;
    reg xmit_prev;
    always @(posedge uart_clk or negedge rst) begin
        if (!rst) begin
            xmit_s1 <= 1'b0;
            xmit_s2 <= 1'b0;
            xmit_prev <= 1'b0;
        end
        else begin
            xmit_s1 <= xmitH;
            xmit_s2 <= xmit_s1;
            xmit_prev <= xmit_s2;
        end
    end
    wire xmit_fall;
    assign xmit_fall = xmit_prev & ~xmit_s2;
    reg [WORD_LEN-1:0] shift_reg;
    reg [$clog2(WORD_LEN)-1:0] bit_count;
    reg [3:0] baud_count;
    always @(posedge uart_clk or negedge rst) begin
        if (!rst) begin
            nt_st <= IDLE;
            uart_XMIT_dataH <= 1'b1;
            xmit_doneH <= 1'b0;
            xmit_active <= 1'b0;
            shift_reg <= 0;
            bit_count <= 0;
            baud_count <= 0;
        end
        else begin
            xmit_doneH <= 1'b0;
            case (nt_st)
                IDLE: begin
                    uart_XMIT_dataH <= 1'b1;
                    xmit_active <= 1'b0;
                    baud_count <= 0;
                    bit_count <= 0;
                    xmit_doneH <= 1'b1;
                    if (xmitH) begin
                        shift_reg <= xmit_dataH;
                        xmit_active <= 1'b1;
                        uart_XMIT_dataH <= 1'b0;
                        xmit_doneH <= 0;
                        baud_count <= 0;
                        nt_st <= START;
                    end
                end
                START: begin
                   // uart_XMIT_dataH <= 1'b0;
                    if (baud_count < 14)
                        baud_count <= baud_count + 1;
                    else begin
                        baud_count <= 0;
                        nt_st <= DATA;
                    end
                end
                DATA: begin
                    uart_XMIT_dataH <= shift_reg[0];
                    if (baud_count < 15)
                        baud_count <= baud_count + 1;
                    else begin
                        baud_count <= 0;
                        shift_reg <= shift_reg >> 1;
                        if (bit_count < WORD_LEN-1)
                            bit_count <= bit_count + 1;
                        else begin
                            bit_count <= 0;
                            nt_st <= STOP;
                        end
                    end
                end
                STOP: begin
                    uart_XMIT_dataH <= 1'b1;
                    if (baud_count < 15)
                        baud_count <= baud_count + 1;
                    else begin
                        baud_count <= 0;
                        xmit_doneH <= 1'b1;
                        xmit_active <= 1'b0;
                        nt_st <= IDLE;
                    end
                end
                default: nt_st <= IDLE;
            endcase
        end
    end
endmodule
