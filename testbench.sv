
// Testbench : tb_uart_top
// Purpose   : Self-checking loopback test for uart_top (no FIFO).
//             TX output is wired directly to RX input.
//
// Tests performed:
//   Test 1 — 8N1  : all 256 byte values, no parity
//   Test 2 — 8E1  : all 256 byte values, even parity
//   Test 3 — 8O1  : all 256 byte values, odd parity
//   Test 4 — corners: 0x00, 0xFF, 0xAA, 0x55
//
// Expected output:
//   Each line either "PASS: 0xNN" or "FAIL: ..."
//   Final line: "=== Results: PASS=NNN  FAIL=0 ==="
//   gtkwave uart_tb.vcd      # waveform view


`timescale 1ns / 1ps
`include "top.v"
module tb_uart_top;

    // Parameters — change here to test other configurations

    parameter integer CLK_HZ = 50_000_000; // 50 MHz
    parameter integer BAUD   = 115_200;

    localparam integer CLK_PERIOD_NS = 1_000_000_000 / CLK_HZ; // 20 ns

    // Approximate frame time in clock cycles (10 bits × 16 ticks × DIVISOR+1)
    localparam integer DIVISOR      = CLK_HZ / (BAUD * 16) - 1;
    localparam integer FRAME_CYCLES = 10 * 16 * (DIVISOR + 1) + 200; // +margin

    
    // Clock generation
    
    reg clk = 1'b0;
    always #(CLK_PERIOD_NS / 2) clk = ~clk;

  
    // DUT connections
 
    reg        rst_n      = 1'b0;
    reg        tx_start   = 1'b0;
    reg  [7:0] tx_data    = 8'h00;
    reg        parity_en  = 1'b0;
    reg        parity_type= 1'b0;

    wire       tx_line; // serial wire — looped back to rx
    wire [7:0] rx_data;
    wire       rx_done;
    wire       tx_done;
    wire       tx_busy;
    wire       parity_err;
    wire       frame_err;

    uart_top #(
        .CLK_HZ (CLK_HZ),
        .BAUD   (BAUD)
    ) u_dut (
        .clk         (clk),
        .rst_n       (rst_n),
        // TX
        .tx_start    (tx_start),
        .tx_data     (tx_data),
        .parity_en   (parity_en),
        .parity_type (parity_type),
        .tx          (tx_line),
        .tx_busy     (tx_busy),
        .tx_done     (tx_done),
        // RX — loopback: connect TX output to RX input
        .rx          (tx_line),
        .rx_data     (rx_data),
        .rx_done     (rx_done),
        .parity_err  (parity_err),
        .frame_err   (frame_err)
    );
    
    // Result counters

    integer pass_cnt = 0;
    integer fail_cnt = 0;

    // Task: send one byte and verify the looped-back result
  
    task send_and_verify;
    input [7:0] data;
        integer timeout;
        begin
            // Wait until TX is free
            wait (!tx_busy);
            @(posedge clk); #1;

            // Kick the transmitter
            tx_data  <= data;
            tx_start <= 1'b1;
            @(posedge clk); #1;
            tx_start <= 1'b0;

            // Wait for rx_done with a generous timeout
            timeout = 0;
            while (!rx_done && timeout < FRAME_CYCLES * 2) begin
                @(posedge clk);
                timeout = timeout + 1;
            end

            @(posedge clk); // let signals settle

            if (timeout >= FRAME_CYCLES * 2) begin
                $display("TIMEOUT: sent=0x%02h", data);
                fail_cnt = fail_cnt + 1;
            end else if (rx_data !== data || parity_err || frame_err) begin
                $display("FAIL: sent=0x%02h  rcv=0x%02h  parity_err=%b  frame_err=%b",
                          data, rx_data, parity_err, frame_err);
                fail_cnt = fail_cnt + 1;
            end else begin
                $display("PASS: 0x%02h", data);
                pass_cnt = pass_cnt + 1;
            end
        end
    endtask
//stimulus
    integer i;
    initial begin
        // Set up VCD dump for waveform viewing
        $dumpfile("uart_tb.vcd");
        $dumpvars(0, tb_uart_top);

        // Release reset after 10 clock cycles
        repeat(10) @(posedge clk);
        rst_n = 1'b1;
        repeat(5)  @(posedge clk);

        //  Test 1: 8N1, no parity
        $display("");
        $display("=== Test 1: 8N1 — no parity ===");
        parity_en   = 1'b0;
        parity_type = 1'b0;
        for (i = 0; i < 256; i = i + 1)
            send_and_verify(i[7:0]);
        //  Test 2: 8E1, even parity
        $display("");
        $display("=== Test 2: 8E1 — even parity ===");
        parity_en   = 1'b1;
        parity_type = 1'b0;
        for (i = 0; i < 256; i = i + 1)
            send_and_verify(i[7:0]);
        // Test 3: 8O1, odd parity
        $display("");
        $display("=== Test 3: 8O1 — odd parity ===");
        parity_en   = 1'b1;
        parity_type = 1'b1;
        for (i = 0; i < 256; i = i + 1)
            send_and_verify(i[7:0]);
        // Test 4: corner values
        $display("");
        $display("=== Test 4: Corner values ===");
        parity_en = 1'b0;
        send_and_verify(8'h00); // all zeros
        send_and_verify(8'hFF); // all ones
        send_and_verify(8'hAA); // 1010_1010
        send_and_verify(8'h55); // 0101_0101

        // Summary
        $display("");
        $display("=== Results: PASS=%0d  FAIL=%0d ===", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("ALL TESTS PASSED");
        else
            $display("*** %0d TESTS FAILED ***", fail_cnt);

        $finish;
    end

   
    // Watchdog — abort if simulation hangs
    
    initial begin
        #500_000_000; // 500 ms simulation time limit
        $display("!!! WATCHDOG TIMEOUT — simulation did not complete !!!");
        $finish;
    end


    // Simulation-only: monitor tx_busy and tx_done edges

`ifdef SIM
    always @(posedge tx_done)
        $display("  [%0t ns] tx_done pulse", $time / 1000);
    always @(posedge rx_done)
        $display("  [%0t ns] rx_done pulse  rx_data=0x%02h", $time/1000, rx_data);
`endif

endmodule
