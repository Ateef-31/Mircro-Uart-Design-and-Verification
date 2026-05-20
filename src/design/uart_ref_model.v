// =============================================================================
//  uart_ref_model.v
//  Behavioural Golden / Reference Model for the uart DUT
//
//  Mirrors the EXACT protocol of the RTL:
//    - Baud clock    : uart_clk toggles every CLK_DIV sys_clk cycles
//                      CLK_DIV = SYS_CLK / (BAUD * 16 * 2)
//                      => 16 uart_clk posedges per UART bit (x16 oversampling)
//
//  TX trigger & start-bit timing (key detail):
//    - Testbench asserts xmitH just after a NEGEDGE of baud_clk
//    - FSM samples xmitH on the next POSEDGE \u2192 drives TX LOW on that posedge
//      (this is posedge tick 0 of the start bit)
//    - FSM moves to START state; START counts baud_count 0..14 (15 more ticks)
//    - Total start bit width = 1 (IDLE\u2192START transition tick) + 15 (START ticks)
//                            = 16 posedge ticks  \u2190 full bit period
//    - Each subsequent DATA bit: 16 ticks (baud_count 0..15)
//    - STOP bit             : 16 ticks (baud_count 0..15), done pulse at end
//
//    - Frame format  : 1 start + 8 data (LSB-first) + 1 stop  (no parity)
//    - RX sampling   : START false-start check at tick 7, data sampled at tick 8
//    - rec_readyH    : = ~rec_busy (combinational)
//    - rec_dataH     : latched in STOP state at baud_count==8 if stop bit HIGH
//
//  Outputs (all driven as reg so scoreboard can read them):
//    ref_uart_XMIT_dataH  - serial TX line
//    ref_xmit_doneH       - one uart_clk pulse when frame done
//    ref_xmit_active      - HIGH while TX frame in progress
//    ref_rec_dataH        - received parallel byte
//    ref_rec_readyH       - = ~ref_rec_busy
//    ref_rec_busy         - HIGH while receiving frame
// =============================================================================

`timescale 1ns / 1ps

module uart_ref_model #(
    parameter WORD_LEN = 8,
    parameter BAUD = 2400,
  parameter SYS_CLK = 100_000_000 //(100MHZ)
)(
    input clk,
    input rst,
    input [WORD_LEN-1:0] xmit_dataH,
    input xmitH,
    // Reference outputs
    output reg ref_uart_XMIT_dataH,
    output reg ref_xmit_doneH,
    output reg ref_xmit_active,
    output reg [WORD_LEN-1:0] ref_rec_dataH,
    output ref_rec_readyH,
    output reg ref_rec_busy
);

  localparam CLK_DIV = SYS_CLK / (BAUD * 16 * 2); // Baud Clk generation from sys_clk for communication between the transmitter and receiver

    reg [$clog2(CLK_DIV)-1:0] baud_cnt;
    reg uart_clk;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            baud_cnt <= 0;
            uart_clk <= 1'b0;
        end else begin
            if (baud_cnt == CLK_DIV - 1) begin
                baud_cnt <= 0;
                uart_clk <= ~uart_clk;
            end else
                baud_cnt <= baud_cnt + 1;
        end
    end
  // Transmitter States
    localparam TX_IDLE  = 2'b00,
               TX_START = 2'b01,
               TX_DATA  = 2'b10,
               TX_STOP  = 2'b11;

    reg [1:0] tx_state;
    reg [WORD_LEN-1:0] tx_shift;
    reg [$clog2(WORD_LEN):0] tx_bit_cnt;
    reg [3:0] tx_baud_cnt;

    always @(posedge uart_clk or negedge rst) begin
        if (!rst) begin
            tx_state <= TX_IDLE;
            ref_uart_XMIT_dataH <= 1'b1;
            ref_xmit_doneH <= 1'b0;
            ref_xmit_active <= 1'b0;
            tx_shift <= 0;
            tx_bit_cnt <= 0;
            tx_baud_cnt <= 0;
        end else begin
            ref_xmit_doneH <= 1'b0;   // default de-assert

            case (tx_state)
                // ---------------------------------------------------------
                TX_IDLE: begin
                    ref_uart_XMIT_dataH <= 1'b1;
                    ref_xmit_active <= 1'b0;
                    tx_baud_cnt <= 0;
                    tx_bit_cnt <= 0;
                    ref_xmit_doneH <= 1'b1;   // idle = done asserted

                    if (xmitH) begin
                        tx_shift <= xmit_dataH;
                        ref_xmit_active <= 1'b1;
                        ref_uart_XMIT_dataH <= 1'b0;   // start bit
                        ref_xmit_doneH <= 1'b0;
                        tx_baud_cnt <= 0;
                        tx_state <= TX_START;
                    end
                end

                // ---------------------------------------------------------
                // START: TX LOW was already driven in IDLE on the trigger posedge
                //        (tick 0). Here we hold LOW for 15 more posedge ticks
                //        (baud_count 0..14), giving 16 total ticks = 1 full bit.
                // ---------------------------------------------------------
                TX_START: begin
                    if (tx_baud_cnt < 14)
                        tx_baud_cnt <= tx_baud_cnt + 1;
                    else begin
                        tx_baud_cnt <= 0;
                        tx_state <= TX_DATA;
                    end
                end

                // ---------------------------------------------------------
                // DATA: 16 ticks per bit, LSB first
                // ---------------------------------------------------------
                TX_DATA: begin
                    ref_uart_XMIT_dataH <= tx_shift[0];
                    if (tx_baud_cnt < 15)
                        tx_baud_cnt <= tx_baud_cnt + 1;
                    else begin
                        tx_baud_cnt <= 0;
                        tx_shift <= tx_shift >> 1;
                        if (tx_bit_cnt < WORD_LEN - 1)
                            tx_bit_cnt <= tx_bit_cnt + 1;
                        else begin
                            tx_bit_cnt <= 0;
                            tx_state <= TX_STOP;
                        end
                    end
                end

                // STOP: high for 16 ticks, pulse done, back to IDLE
                TX_STOP: begin
                    ref_uart_XMIT_dataH <= 1'b1;
                    if (tx_baud_cnt < 15)
                        tx_baud_cnt <= tx_baud_cnt + 1;
                    else begin
                        tx_baud_cnt <= 0;
                        ref_xmit_doneH <= 1'b1;
                        ref_xmit_active <= 1'b0;
                        tx_state <= TX_IDLE;
                    end
                end

                default: tx_state <= TX_IDLE;
            endcase
        end
    end

    // Receiver States
    localparam RX_INIT  = 3'b000,
               RX_IDLE  = 3'b001,
               RX_START = 3'b010,
               RX_DATA  = 3'b011,
               RX_STOP  = 3'b100;

    // Two-FF synchroniser on RX serial input
    reg rx_ff1, rx_ff2;
    always @(posedge uart_clk or negedge rst) begin
        if (!rst) begin
            rx_ff1 <= 1'b1;
            rx_ff2 <= 1'b1;
        end else begin
            rx_ff1 <= ref_uart_XMIT_dataH;   // loopback
            rx_ff2 <= rx_ff1;
        end
    end

    assign ref_rec_readyH = ~ref_rec_busy;

    reg [2:0] rx_state;
    reg [WORD_LEN-1:0] rx_shift;
    reg [$clog2(WORD_LEN):0] rx_bit_cnt;
    reg [3:0] rx_baud_cnt;
    reg [5:0] rx_init_cnt;

    always @(posedge uart_clk or negedge rst) begin
        if (!rst) begin
            rx_state <= RX_INIT;
            ref_rec_dataH <= {WORD_LEN{1'b0}};
            ref_rec_busy <= 1'b0;
            rx_shift <= 0;
            rx_bit_cnt <= 0;
            rx_baud_cnt <= 0;
            rx_init_cnt <= 0;
        end else begin
            case (rx_state)
                // INIT: wait for 32 consecutive HIGH cycles before going IDLE for false reset check
                RX_INIT: begin
                    ref_rec_busy <= 1'b0;
                    if (rx_ff2 == 1'b0)
                        rx_init_cnt <= 0;
                    else begin
                        if (rx_init_cnt == 6'd31) begin
                            rx_init_cnt <= 0;
                            rx_state <= RX_IDLE;
                        end else
                            rx_init_cnt <= rx_init_cnt + 1;
                    end
                end

                // ---------------------------------------------------------
                RX_IDLE: begin
                    ref_rec_busy <= 1'b0;
                    rx_bit_cnt <= 0;
                    rx_baud_cnt <= 0;
                    if (rx_ff2 == 1'b0) begin
                        ref_rec_busy <= 1'b1;
                        rx_baud_cnt <= 0;
                        rx_state <= RX_START;
                    end
                end

                // START: validate at mid-bit (tick 7), full bit at tick 15
                RX_START: begin
                    rx_baud_cnt <= rx_baud_cnt + 1;
                    if (rx_baud_cnt == 4'd7) begin
                        if (rx_ff2 == 1'b1) begin   // false start
                            ref_rec_busy <= 1'b0;
                            rx_baud_cnt <= 0;
                            rx_state <= RX_IDLE;
                        end
                    end
                    if (rx_baud_cnt == 4'd15) begin
                        rx_baud_cnt <= 0;
                        rx_bit_cnt <= 0;
                        rx_state <= RX_DATA;
                    end
                end
                // DATA: sample at tick 8 (mid), 8 bits LSB-first
                RX_DATA: begin
                    rx_baud_cnt <= rx_baud_cnt + 1;
                    if (rx_baud_cnt == 4'd8)
                        rx_shift[rx_bit_cnt] <= rx_ff2;
                    if (rx_baud_cnt == 4'd15) begin
                        rx_baud_cnt <= 0;
                        if (rx_bit_cnt < WORD_LEN - 1)
                            rx_bit_cnt <= rx_bit_cnt + 1;
                        else begin
                            rx_bit_cnt <= 0;
                            rx_state <= RX_STOP;
                        end
                    end
                end

                // STOP: latch data at tick 8 if stop bit HIGH
                RX_STOP: begin
                    rx_baud_cnt <= rx_baud_cnt + 1;
                    if (rx_baud_cnt == 4'd8) begin
                        if (rx_ff2 == 1'b1)
                            ref_rec_dataH <= rx_shift;
                    end
                    if (rx_baud_cnt == 4'd15) begin
                        rx_baud_cnt <= 0;
                        ref_rec_busy <= 1'b0;
                        rx_state <= RX_IDLE;
                    end
                end

                default: begin
                    ref_rec_busy <= 1'b0;
                    rx_state <= RX_IDLE;
                end
            endcase
        end
    end

endmodule
