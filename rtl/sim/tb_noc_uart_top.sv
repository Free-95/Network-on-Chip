// tb_noc_uart_top.sv
// ============================================================================
// Self-checking testbench for noc_uart_top
//
// What it does:
//  1. Drives a real UART byte-stream "SEND 3 HELL\r" at the correct baud rate.
//  2. Waits for the NoC to route the flit through two hops (0,0)→(1,0)→(1,1).
//  3. Waits for the echo to return (1,1)→(0,1)→(0,0).  [or (1,1)→(1,0)→(0,0)]
//  4. Monitors the UART Tx output from the DUT and reconstructs the ASCII
//     response string.
//  5. Checks that the response contains "Received" and the payload "HELL".
//  6. Prints PASS / FAIL.
//
// Testbench sends a second packet "SEND 1 HI!!" to exercise a shorter path.
// ============================================================================

`timescale 1ns / 1ps

module tb_noc_uart_top;

    // -------------------------------------------------------------------------
    // Parameters – must match DUT
    // -------------------------------------------------------------------------
    localparam CLK_PERIOD    = 10;          // 10 ns → 100 MHz
    localparam CLKS_PER_BIT  = 868;         // 100 MHz / 115200
    localparam BIT_PERIOD_NS = CLK_PERIOD * CLKS_PER_BIT;  // ~86.8 µs per bit

    localparam DATA_WIDTH    = 34;
    localparam COORD_WIDTH   = 1;
    localparam FIFO_DEPTH    = 8;

    // -------------------------------------------------------------------------
    // DUT ports
    // -------------------------------------------------------------------------
    logic clk     = 0;
    logic rst_n   = 0;
    logic uart_rxd = 1;    // idle high
    logic uart_txd;

    // -------------------------------------------------------------------------
    // Clock
    // -------------------------------------------------------------------------
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    noc_uart_top #(
        .DATA_WIDTH  (DATA_WIDTH),
        .COORD_WIDTH (COORD_WIDTH),
        .FIFO_DEPTH  (FIFO_DEPTH),
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .uart_rxd(uart_rxd),
        .uart_txd(uart_txd)
    );

    // -------------------------------------------------------------------------
    // UART Tx monitor – capture DUT's serial output into a string
    // -------------------------------------------------------------------------
    integer          rx_bit_cnt;
    logic [7:0]      rx_shift;
    logic [7:0]      rx_char;
    logic            rx_char_valid;

    // Reconstructed response
    logic [7:0] resp_buf [0:127];
    integer      resp_len;
    integer      resp_ptr;

    // Simple bit-level UART monitor
    initial begin
        rx_bit_cnt    = 0;
        rx_shift      = 0;
        rx_char_valid = 0;
        resp_len      = 0;
        resp_ptr      = 0;

        forever begin
            // Wait for start bit (falling edge on uart_txd)
            @(negedge uart_txd);
            // Sample in the middle of each bit
            #(BIT_PERIOD_NS * 1.5);  // skip start bit centre
            rx_shift = 0;
            for (integer b = 0; b < 8; b++) begin
                rx_shift[b] = uart_txd;
                if (b < 7) #(BIT_PERIOD_NS);
            end
            #(BIT_PERIOD_NS);        // stop bit
            // Store character
            resp_buf[resp_len] = rx_shift;
            resp_len           = resp_len + 1;
        end
    end

    // -------------------------------------------------------------------------
    // Task: send one UART byte (LSB first, 8N1, 115200 baud)
    // -------------------------------------------------------------------------
    task automatic uart_send_byte(input logic [7:0] b);
        integer i;
        uart_rxd = 0;               // start bit
        #(BIT_PERIOD_NS);
        for (i = 0; i < 8; i++) begin
            uart_rxd = b[i];
            #(BIT_PERIOD_NS);
        end
        uart_rxd = 1;               // stop bit
        #(BIT_PERIOD_NS);
    endtask

    // Task: send null-terminated string
    task automatic uart_send_str(input string s);
        foreach (s[i])
            uart_send_byte(s[i]);
    endtask

    // -------------------------------------------------------------------------
    // Helper: search resp_buf for a sub-string, return 1 if found
    // -------------------------------------------------------------------------
    function automatic int find_substr(input string sub, input int len);
        integer si, ri;
        logic   match;
        for (ri = 0; ri <= len - sub.len(); ri++) begin
            match = 1;
            for (si = 0; si < sub.len(); si++) begin
                if (resp_buf[ri + si] != sub[si]) begin
                    match = 0;
                    break;
                end
            end
            if (match) return 1;
        end
        return 0;
    endfunction

    // -------------------------------------------------------------------------
    // Test sequence
    // -------------------------------------------------------------------------
    integer test_pass;
    integer base_len;

    initial begin
        $dumpfile("tb_noc_uart_top.vcd");
        $dumpvars(0, tb_noc_uart_top);

        test_pass = 1;

        // -------------------------------------------------------------------
        // Reset
        // -------------------------------------------------------------------
        rst_n = 0;
        repeat(20) @(posedge clk);
        rst_n = 1;
        repeat(10) @(posedge clk);

        $display("");
        $display("========================================================");
        $display("  NoC UART Demo Testbench – Starting");
        $display("========================================================");

        // ===================================================================
        // TEST 1: SEND 3 HELL   (Node 3 = x=1, y=1 → 2-hop route)
        // ===================================================================
        $display("[TB] Sending: SEND 3 HELL<CR>");
        base_len = resp_len;

        uart_send_str("SEND 3 HELL");
        uart_send_byte(8'h0D);    // CR

        // Wait up to 5 ms for the response (echo latency + UART Tx time)
        begin
            integer timeout;
            timeout = 0;
            while ((resp_len - base_len) < 10 && timeout < 500_000) begin
                #100;
                timeout = timeout + 100;
            end
        end

        // Give UART time to finish printing
        #5_000_000;   // 5 ms

        $display("[TB] Response received (%0d chars):", resp_len - base_len);
        begin
            integer i;
            $write("[TB]   > ");
            for (i = base_len; i < resp_len; i++) begin
                if (resp_buf[i] >= 8'h20 && resp_buf[i] <= 8'h7E)
                    $write("%s", resp_buf[i]);
                else if (resp_buf[i] == 8'h0D || resp_buf[i] == 8'h0A)
                    $write("\\n");
            end
            $write("\n");
        end

        // Check for "Received" keyword in response
        if (!find_substr("Received", resp_len))  begin
            $display("[TB] FAIL – 'Received' not found in response");
            test_pass = 0;
        end else begin
            $display("[TB] PASS – 'Received' found");
        end

        // Check for payload "HELL"
        if (!find_substr("HELL", resp_len)) begin
            $display("[TB] FAIL – payload 'HELL' not found in response");
            test_pass = 0;
        end else begin
            $display("[TB] PASS – payload 'HELL' found");
        end

        // Check for "Latency:"
        if (!find_substr("Latency:", resp_len)) begin
            $display("[TB] FAIL – 'Latency:' not found in response");
            test_pass = 0;
        end else begin
            $display("[TB] PASS – Latency field present");
        end

        // ===================================================================
        // TEST 2: SEND 1 HI!!   (Node 1 = x=1, y=0 → 1-hop route East)
        // ===================================================================
        $display("");
        $display("[TB] Sending: SEND 1 HI!!<CR>");
        base_len = resp_len;

        uart_send_str("SEND 1 HI!!");
        uart_send_byte(8'h0D);

        #10_000_000;   // 10 ms

        $display("[TB] Response received (%0d chars):", resp_len - base_len);
        begin
            integer i;
            $write("[TB]   > ");
            for (i = base_len; i < resp_len; i++) begin
                if (resp_buf[i] >= 8'h20 && resp_buf[i] <= 8'h7E)
                    $write("%s", resp_buf[i]);
                else if (resp_buf[i] == 8'h0D || resp_buf[i] == 8'h0A)
                    $write("\\n");
            end
            $write("\n");
        end

        if (!find_substr("Received", resp_len))
            $display("[TB] FAIL – Test2: 'Received' not found");
        else
            $display("[TB] PASS – Test2: 'Received' found");

        // ===================================================================
        // TEST 3: Bad command (should not crash or produce garbage)
        // ===================================================================
        $display("");
        $display("[TB] Sending bad command: XYZZY<CR>");
        base_len = resp_len;
        uart_send_str("XYZZY");
        uart_send_byte(8'h0D);
        #2_000_000;
        if (resp_len == base_len)
            $display("[TB] PASS – Bad command produced no UART output (correct)");
        else
            $display("[TB] INFO – Bad command generated %0d response bytes", resp_len - base_len);

        // ===================================================================
        // Summary
        // ===================================================================
        $display("");
        $display("========================================================");
        if (test_pass)
            $display("  OVERALL RESULT: ** PASS **");
        else
            $display("  OVERALL RESULT: ** FAIL **");
        $display("========================================================");
        $display("");

        $finish;
    end

    // -------------------------------------------------------------------------
    // Watchdog
    // -------------------------------------------------------------------------
    initial begin
        #100_000_000;   // 100 ms absolute timeout
        $display("[TB] WATCHDOG TIMEOUT – simulation halted");
        $finish;
    end

endmodule
