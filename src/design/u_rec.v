`timescale 1ns / 1ps
module u_rec #(
    parameter WORD_LEN = 8
)(
    input uart_clk,
    input rst,
    input uart_REC_dataH, 
    output reg [WORD_LEN-1:0] rec_dataH,
    output rec_readyH,    
    output reg rec_busy        
);
    assign rec_readyH = ~rec_busy;  
     parameter INIT  = 3'b000, 
        IDLE  = 3'b001,
        START = 3'b010,
        DATA  = 3'b011,
        STOP  = 3'b100;
    reg [2:0] nt_st;
    reg sync_ff1, sync_ff2;
    always @(posedge uart_clk or negedge rst) begin
        if (!rst) begin
            sync_ff1 <= 1'b1;
            sync_ff2 <= 1'b1;
        end
        else begin
            sync_ff1 <= uart_REC_dataH;
            sync_ff2 <= sync_ff1;
        end
    end
    reg [WORD_LEN-1:0] shift_reg;
    reg [$clog2(WORD_LEN)-1:0] bit_count;
    reg [3:0] baud_count;   // 0..15 within each bit
    reg [5:0] init_count;   
    always @(posedge uart_clk or negedge rst) begin
        if (!rst) begin
            nt_st <= INIT;
            rec_dataH <= {WORD_LEN{1'b0}};
            rec_busy <= 1'b0;
            shift_reg <= {WORD_LEN{1'b0}};
            bit_count <= 0;
            baud_count <= 0;
            init_count <= 0;
        end
        else begin
            case (nt_st)
                INIT: begin
                    rec_busy <= 1'b0;
                    if (sync_ff2 == 1'b0) begin
                        init_count <= 0;
                    end
                    else begin
                        if (init_count == 6'd31) begin
                            init_count <= 0;
                            nt_st <= IDLE;
                        end
                        else begin
                            init_count <= init_count + 1;
                        end
                    end
                end
                IDLE: begin
                    rec_busy <= 1'b0;
                    bit_count <= 0;
                    baud_count <= 0;
                    if (sync_ff2 == 1'b0) begin
                        rec_busy <= 1'b1;  
                        baud_count <= 0;
                        nt_st <= START;
                    end
                end
                START: begin
                    baud_count <= baud_count + 1;
                    if (baud_count == 4'd7) begin
                        if (sync_ff2 == 1'b1) begin
                            rec_busy <= 1'b0;
                            baud_count <= 0;
                            nt_st <= IDLE;
                        end
                    end
                    if (baud_count == 4'd15) begin
                        baud_count <= 0;
                        bit_count <= 0;
                        nt_st <= DATA;
                    end
                end
                DATA: begin
                    baud_count <= baud_count + 1;
                    if (baud_count == 4'd8)
                        shift_reg[bit_count] <= sync_ff2;
                    if (baud_count == 4'd15) begin
                        baud_count <= 0;
                        if (bit_count < WORD_LEN - 1)
                            bit_count <= bit_count + 1;
                        else begin
                            bit_count <= 0;
                            nt_st <= STOP;
                        end
                    end
                end
                STOP: begin
                    baud_count <= baud_count + 1;
                    if (baud_count == 4'd8) begin
                        if (sync_ff2 == 1'b1)
                            rec_dataH <= shift_reg;
                    end
                    if (baud_count == 4'd15) begin
                        baud_count <= 0;
                        rec_busy <= 1'b0;   
                        nt_st <= IDLE;
                    end
                end
                default: begin
                    rec_busy <= 1'b0;
                    nt_st <= IDLE;
                end
            endcase
        end
    end
endmodule
