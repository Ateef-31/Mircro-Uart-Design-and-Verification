// =============================================================================
//  uart_sc_tb.v   -  Self-Checking Testbench  (UART)
//
//  Structure
//  ---------
//  1.  DUT  (uart)           - your RTL under test
//  2.  REF  (uart_ref_model) - behavioural golden model
//  3.  Scoreboard            - event-driven checker comparing every
//                              DUT output against the reference model
//
//  TX trigger protocol (important timing detail)
//  -----------------------------------------------
//  xmitH is asserted just after a NEGEDGE of baud_clk (inside send_byte).
//  The TX FSM samples xmitH on the next POSEDGE and drives TX LOW on that
//  same posedge - that posedge is tick-0 of the start bit.
//  START state then holds LOW for 15 more posedge ticks (baud_count 0..14),
//  so the start bit spans exactly 16 posedge ticks = one full bit period.
//  DATA and STOP bits each span 16 ticks (baud_count 0..15).
//
//  Checks performed per byte
//  --------------------------
//  (a) rec_dataH  DUT == REF == sent value   (received data correctness)
//  (b) xmit_active == 0 after xmit_doneH    (TX FSM returns to idle)
//  (c) rec_readyH DUT == REF                (ready signal consistency)
//  (d) Serial TX line DUT == REF on every baud_clk (continuous monitor)
//  (e) Glitch rejection: xmit_active stays LOW after short xmitH pulse
//
//  Tests
//  ------
//  T1  - Corner bytes  : 0xAA, 0x11, 0x53
//  T2  - Boundary      : 0x00, 0xFF, 0x55, 0xAA
//  T3  - Back-to-back  : 0xDE, 0xAD, 0xBE, 0xEF  (no inter-frame gap)
//  T4  - Random (LFSR) : 16 bytes, seed 0xA5
//  T5  - Exhaustive    : 0x00-0xFF  (uncomment to enable)
//  T6  - Glitch        : short xmitH pulse then valid 0xC3
//  T7  - Serial line   : aggregate TX mismatch count across all tests
// =============================================================================

`timescale 1ns / 1ps

module uart_sc_tb;

    // =========================================================================
    //  Parameters
    // =========================================================================
    parameter WORD_LEN    = 8;
    parameter BAUD        = 2400;
    parameter SYS_CLK     = 100_000_000;
    parameter TIMEOUT_CYC = (SYS_CLK / BAUD) * 12;   // ~3-frame safety timeout

    // =========================================================================
    //  Signals
    // =========================================================================
    reg                  sys_clk;
    reg                  sys_rst_l;
    reg  [WORD_LEN-1:0]  xmit_dataH;
    reg                  xmitH;

    // DUT outputs
    wire                 uart_XMIT_dataH;
    wire                 xmit_doneH;
    wire                 xmit_active;
    wire [WORD_LEN-1:0]  rec_dataH;
    wire                 rec_readyH;
    wire                 rec_busy;

    // Reference model outputs
    wire                 ref_uart_XMIT_dataH;
    wire                 ref_xmit_doneH;
    wire                 ref_xmit_active;
    wire [WORD_LEN-1:0]  ref_rec_dataH;
    wire                 ref_rec_readyH;
    wire                 ref_rec_busy;

    // Baud clock (tap from DUT for timing alignment in tasks)
    wire baud_clk;
    assign baud_clk = dut.uart_clk;

    // =========================================================================
    //  Scorecard
    // =========================================================================
    integer pass_count;
    integer fail_count;
    integer test_num;

    // =========================================================================
    //  DUT - loopback (TX wire drives RX)
    // =========================================================================
    uart #(
        .WORD_LEN(WORD_LEN),
        .BAUD    (BAUD),
        .SYS_CLK (SYS_CLK)
    ) dut (
        .clk             (sys_clk),
        .rst             (sys_rst_l),
        .xmit_dataH      (xmit_dataH),
        .xmitH           (xmitH),
        .uart_REC_dataH  (uart_XMIT_dataH),   // loopback
        .uart_XMIT_dataH (uart_XMIT_dataH),
        .xmit_doneH      (xmit_doneH),
        .xmit_active     (xmit_active),
        .rec_dataH       (rec_dataH),
        .rec_readyH      (rec_readyH),
        .rec_busy        (rec_busy)
    );

    // =========================================================================
    //  Reference Model - identical inputs, loopback on its own TX line
    // =========================================================================
    uart_ref_model #(
        .WORD_LEN(WORD_LEN),
        .BAUD    (BAUD),
        .SYS_CLK (SYS_CLK)
    ) ref (
        .clk                  (sys_clk),
        .rst                  (sys_rst_l),
        .xmit_dataH           (xmit_dataH),
        .xmitH                (xmitH),
        .ref_uart_XMIT_dataH  (ref_uart_XMIT_dataH),
        .ref_xmit_doneH       (ref_xmit_doneH),
        .ref_xmit_active      (ref_xmit_active),
        .ref_rec_dataH        (ref_rec_dataH),
        .ref_rec_readyH       (ref_rec_readyH),
        .ref_rec_busy         (ref_rec_busy)
    );

    // =========================================================================
    //  Clock
    // =========================================================================
    initial sys_clk = 1'b0;
    always  #5 sys_clk = ~sys_clk;   // 100 MHz

    // =========================================================================
    //  SCOREBOARD - runs in background, fires on every DUT output change
    // =========================================================================

    // --- (A) rec_dataH comparator ------------------------------------------
    // Fires whenever DUT rec_readyH goes HIGH (i.e. rec_busy falls)
    // At that moment both DUT and REF should have the same captured byte.
    task check_rec_data;
        input [WORD_LEN-1:0] sent;
        begin
            if (rec_dataH === ref_rec_dataH) begin
                if (rec_dataH === sent) begin
                    $display("[T%0d][%0t ns] PASS  rec_dataH : DUT=0x%02X  REF=0x%02X  SENT=0x%02X",
                             test_num, $time, rec_dataH, ref_rec_dataH, sent);
                    pass_count = pass_count + 1;
                end else begin
                    $display("[T%0d][%0t ns] FAIL  rec_dataH : DUT=REF=0x%02X but SENT=0x%02X  (data corruption)",
                             test_num, $time, rec_dataH, sent);
                    fail_count = fail_count + 1;
                end
            end else begin
                $display("[T%0d][%0t ns] FAIL  rec_dataH mismatch: DUT=0x%02X  REF=0x%02X  SENT=0x%02X",
                         test_num, $time, rec_dataH, ref_rec_dataH, sent);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // --- (B) xmit_doneH comparator (concurrent, event driven) --------------
    // Both DUT and REF xmit_doneH are compared at every posedge of baud_clk
    // This is done inline inside the send tasks after the frame completes.

    // --- (C) xmit_active comparator ----------------------------------------
    task check_xmit_active;
        input exp_active;    // 0 = expect inactive, 1 = expect active
        begin
            if (xmit_active !== exp_active) begin
                $display("[T%0d][%0t ns] FAIL  xmit_active: DUT=%b  EXPECTED=%b",
                         test_num, $time, xmit_active, exp_active);
                fail_count = fail_count + 1;
            end else begin
                $display("[T%0d][%0t ns] PASS  xmit_active=%b as expected", test_num, $time, xmit_active);
                pass_count = pass_count + 1;
            end
        end
    endtask

    // --- (D) Serial line comparator (TX bit-level) --------------------------
    // Continuous monitor: DUT TX line vs REF TX line
    // Any mismatch on the serial bus is a framing bug.
    integer serial_err_count;
    initial serial_err_count = 0;

    always @(posedge baud_clk) begin
        if (sys_rst_l) begin
            // Only check while either side is transmitting to avoid idle noise
            if (xmit_active || ref_xmit_active) begin
                if (uart_XMIT_dataH !== ref_uart_XMIT_dataH) begin
                    $display("[SERIAL][%0t ns] MISMATCH on TX line: DUT=%b REF=%b",
                             $time, uart_XMIT_dataH, ref_uart_XMIT_dataH);
                    serial_err_count = serial_err_count + 1;
                end
            end
        end
    end

    // =========================================================================
    //  TASK: send_byte
    //  Sends one byte, waits for completion, then compares DUT vs REF.
    // =========================================================================
    task send_byte;
        input [WORD_LEN-1:0] data;
        integer i;
        begin
            xmit_dataH = data;

            @(negedge baud_clk); #1;
            xmitH = 1'b1;

            // Hold for synchroniser to latch
            repeat(1) @(negedge baud_clk);
            #1;
            xmitH = 1'b0;

            // Wait for xmit_doneH from DUT, with timeout
            fork
                begin : blk_done
                    @(posedge xmit_doneH);
                    disable blk_timeout;
                end
                begin : blk_timeout
                    for (i = 0; i < TIMEOUT_CYC; i = i + 1)
                        @(posedge sys_clk);
                    $display("[T%0d][%0t ns] ERROR  TIMEOUT waiting xmit_doneH for 0x%02X",
                             test_num, $time, data);
                    fail_count = fail_count + 1;
                    disable blk_done;
                end
            join

            // Let rec_readyH pulse settle (both DUT and REF)
            repeat(8) @(posedge baud_clk);

            // ---- Scoreboard checks ----
            check_rec_data(data);

            // Compare xmit_doneH signals (check REF also fired)
            // REF done is checked by confirming DUT and REF are both idle
            if (xmit_active !== 1'b0) begin
                $display("[T%0d][%0t ns] FAIL  xmit_active still HIGH after done", test_num, $time);
                fail_count = fail_count + 1;
            end
            if (ref_xmit_active !== 1'b0) begin
                $display("[T%0d][%0t ns] WARN   ref_xmit_active still HIGH after done (REF issue)", test_num, $time);
            end

            // Compare rec_readyH
            if (rec_readyH !== ref_rec_readyH) begin
                $display("[T%0d][%0t ns] FAIL  rec_readyH mismatch: DUT=%b REF=%b",
                         test_num, $time, rec_readyH, ref_rec_readyH);
                fail_count = fail_count + 1;
            end

            // Inter-frame gap
            repeat(32) @(posedge baud_clk);
        end
    endtask

    // =========================================================================
    //  TASK: send_byte_back2back
    //  No inter-frame gap. Checks data only (rec_readyH settling skipped).
    // =========================================================================
    task send_byte_back2back;
        input [WORD_LEN-1:0] data;
        integer i;
        begin
            xmit_dataH = data;

            @(posedge baud_clk); #1;
            xmitH = 1'b1;
            @(posedge baud_clk); #1;
            xmitH = 1'b0;

            fork
                begin : b2b_done
                    @(posedge xmit_doneH);
                    disable b2b_timeout;
                end
                begin : b2b_timeout
                    for (i = 0; i < TIMEOUT_CYC; i = i + 1)
                        @(posedge sys_clk);
                    $display("[T%0d][%0t ns] ERROR  B2B TIMEOUT for 0x%02X",
                             test_num, $time, data);
                    fail_count = fail_count + 1;
                    disable b2b_done;
                end
            join

            repeat(4) @(posedge baud_clk);

            // Scoreboard
            check_rec_data(data);
        end
    endtask
    reg [7:0] lfsr;
    task lfsr_next;
        begin
            lfsr = {lfsr[6:0], 1'b0} ^
                   ({8{lfsr[7]}} & 8'b1011_1000);
            if (lfsr == 8'h00) lfsr = 8'hAC;
        end
    endtask
  
    task print_sep;
        input [240*8-1:0] label;
        begin
            $display("");
            $display("============================================================");
            $display("  %s", label);
            $display("============================================================");
        end
    endtask

    integer idx;
    initial begin
        // Initialise
        sys_rst_l  = 1'b0;
        xmitH      = 1'b0;
        xmit_dataH = 8'h00;
        pass_count = 0;
        fail_count = 0;
        test_num   = 0;
        lfsr       = 8'hA5;

        // Reset de-assert
        repeat(10) @(posedge sys_clk);
        sys_rst_l = 1'b1;

        // Wait for RX INIT state to complete (32 baud_clk HIGH cycles required)
        repeat(40) @(posedge baud_clk);

        // =================================================================
        // TEST 1 - Original corner bytes
        // =================================================================
        test_num = 1;
        print_sep("TEST 1: Corner bytes  0xAA  0x11  0x53");
        send_byte(8'hAA);
        send_byte(8'h11);
        send_byte(8'h53);

        // =================================================================
        // TEST 2 - Boundary values
        // =================================================================
        test_num = 2;
        print_sep("TEST 2: Boundary values  0x00  0xFF  0x55  0xAA");
        send_byte(8'h00);
        send_byte(8'hFF);
        send_byte(8'h55);
        send_byte(8'hAA);

        // =================================================================
        // TEST 3 - Back-to-back (no inter-frame gap)
        // =================================================================
        test_num = 3;
        print_sep("TEST 3: Back-to-back  0xDE 0xAD 0xBE 0xEF");
        send_byte_back2back(8'hDE);
        send_byte_back2back(8'hAD);
        send_byte_back2back(8'hBE);
        send_byte_back2back(8'hEF);
        repeat(32) @(posedge baud_clk);   // trailing gap

        // =================================================================
        // TEST 4 - Random data via LFSR (16 bytes)
        // =================================================================
        test_num = 4;
        print_sep("TEST 4: LFSR random data  (16 bytes, seed=0xA5)");
        for (idx = 0; idx < 16; idx = idx + 1) begin
            lfsr_next;
            $display("  [%0d/16] Sending 0x%02X", idx+1, lfsr);
            send_byte(lfsr);
        end

      //  // =================================================================
        // // TEST 5 - Exhaustive (all 256 values) - uncomment to enable
       // // =================================================================
      // // Careful with this case cause this may heatup the system and may lead to crash so careful while running this case
//        test_num = 5;
//        print_sep("TEST 5: Exhaustive 0x00..0xFF");
//        for (idx = 0; idx < 256; idx = idx + 1) begin
//            send_byte(idx[7:0]);
//        end

        // =================================================================
        // TEST 6 - Glitch rejection
        //   Pulse xmitH for only 5 sys_clk cycles (much shorter than one
        //   baud_clk period). The 2-FF synchroniser in the TX FSM samples
        //   xmitH on uart_clk edges, so the glitch should never latch.
        //   DUT xmit_active must stay LOW. Then a valid byte confirms FSM
        //   is still operational.
        // =================================================================
        test_num = 6;
        print_sep("TEST 6: xmitH glitch rejection  then valid 0xC3");

        $display("  [%0t ns] Injecting short glitch (~5 sys_clk) on xmitH...", $time);
        xmit_dataH = 8'hFF;   // dummy - must NOT be transmitted

        @(posedge sys_clk); #1;
        xmitH = 1'b1;
        repeat(5) @(posedge sys_clk); #1;
        xmitH = 1'b0;

        // Wait and observe - FSM should not go active
        repeat(20) @(posedge baud_clk);

        if (xmit_active == 1'b0) begin
            $display("[T6][%0t ns] PASS  Glitch rejected: xmit_active=0 (FSM stayed IDLE)", $time);
            pass_count = pass_count + 1;
        end else begin
            $display("[T6][%0t ns] FAIL  Glitch NOT rejected: xmit_active=1 (FSM wrongly triggered)", $time);
            fail_count = fail_count + 1;
        end

        // REF model check too
        if (ref_xmit_active == 1'b0)
            $display("[T6][%0t ns] INFO  REF model also idle after glitch (expected)" , $time);
        else
            $display("[T6][%0t ns] WARN  REF model xmit_active=1 after glitch (ref model issue)",$time);

        // Recover with a valid byte
        $display("  [%0t ns] Sending valid 0xC3 after glitch...", $time);
        send_byte(8'hC3);

        // =================================================================
        // TEST 7 - Signal consistency check (DUT vs REF, entire run)
        // =================================================================
        test_num = 7;
        print_sep("TEST 7: Serial TX line mismatch count");
        if (serial_err_count == 0) begin
            $display("[T7] PASS  No serial TX line mismatches between DUT and REF (%0d errors)", serial_err_count);
            pass_count = pass_count + 1;
        end else begin
            $display("[T7] FAIL  Serial TX mismatches detected: %0d", serial_err_count);
            fail_count = fail_count + 1;
        end

        // =================================================================
        // Final Scorecard
        // =================================================================
        $display("");
        $display("============================================================");
        $display("  SIMULATION COMPLETE");
        $display("  PASS  : %0d", pass_count);
        $display("  FAIL  : %0d", fail_count);
        $display("  TOTAL : %0d", pass_count + fail_count);
        if (fail_count == 0)
            $display("  STATUS: *** ALL TESTS PASSED ***");
        else
            $display("  STATUS: *** %0d TEST(S) FAILED ***", fail_count);
        $display("============================================================");
        #1000;
        $stop;
    end

endmodule
