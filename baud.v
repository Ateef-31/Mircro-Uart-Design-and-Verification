`timescale 1ns / 1ps
module baud #(
    parameter BAUD = 2400,
    parameter SYS_CLK = 100000000
)(
    input clk,
    input rst,          
    output reg uart_clk
);
    localparam CLK_DIV = SYS_CLK / (BAUD * 16 * 2);
    reg [$clog2(CLK_DIV)-1:0] count;
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            count <= 0;
            uart_clk <= 1'b0;
        end
        else begin
            if (count == CLK_DIV - 1) begin
                count <= 0;
                uart_clk <= ~uart_clk;
            end
            else
                count <= count + 1;
        end
    end
endmodule
