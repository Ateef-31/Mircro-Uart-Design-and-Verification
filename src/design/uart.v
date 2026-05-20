`timescale 1ns / 1ps
module uart #(
    parameter WORD_LEN = 8,
    parameter BAUD = 2400,
    parameter SYS_CLK  = 100000000
)(
    input clk,
    input rst,          
    input [WORD_LEN-1:0] xmit_dataH,
    input xmitH,
    input uart_REC_dataH, 
    // Transmitter outputs
    output uart_XMIT_dataH,  
    output xmit_doneH,    
    output xmit_active,     
    // Receiver outputs
    output [WORD_LEN-1:0] rec_dataH,      
    output rec_readyH,   
    output rec_busy  
);
    wire uart_clk;   
    baud #(.BAUD(BAUD),.SYS_CLK(SYS_CLK)) 
        baud_gen (
        .clk(clk),
        .rst(rst),
        .uart_clk(uart_clk)
    );
    u_xmit #(.WORD_LEN(WORD_LEN)) 
    transmitter (
        .uart_clk(uart_clk),
        .rst(rst),
        .xmit_dataH(xmit_dataH),
        .xmitH(xmitH),
        .uart_XMIT_dataH(uart_XMIT_dataH),
        .xmit_doneH(xmit_doneH),
        .xmit_active(xmit_active)
    );
    u_rec #(.WORD_LEN(WORD_LEN)) 
    receiver (
        .uart_clk(uart_clk),
        .rst(rst),
        .uart_REC_dataH(uart_REC_dataH),
        .rec_dataH(rec_dataH),
        .rec_readyH(rec_readyH),
        .rec_busy(rec_busy)
    );
endmodule
