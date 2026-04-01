// uart_resp_formatter.sv
// ============================================================================
// Receives a bounced-back flit arriving at Node(0,0)'s local-in port,
// then streams a human-readable ASCII response over UART.
//
// Output format (sent byte-by-byte via UART Tx):
//   "[Node X] Received: <payload_chars> | Latency: <N> cycles\r\n"
//
// The latency counter is reset when a flit is injected (tx_timestamp) and
// captured when the echoed flit arrives (rx_timestamp). Difference in cycles
// is formatted as a decimal string (up to 5 digits, i.e. ≤ 99999 cycles).
// ============================================================================

`timescale 1ns / 1ps

module uart_resp_formatter #(
    parameter DATA_WIDTH  = 34,
    parameter COORD_WIDTH = 1,
    parameter MAX_DIGITS  = 5      // max latency digits printed
)(
    input  logic                  clk,
    input  logic                  rst_n,

    // Timestamp of original injection (latched by top when flit_valid fires)
    input  logic [31:0]           inject_timestamp,

    // Echoed flit arriving at Node(0,0) local port from Node(1,1)
    input  logic [DATA_WIDTH-1:0] echo_flit,
    input  logic                  echo_valid,

    // UART Tx interface
    output logic [7:0]            tx_byte,
    output logic                  tx_start,
    input  logic                  tx_busy
);

    // -----------------------------------------------------------------------
    // Latency capture
    // -----------------------------------------------------------------------
    logic [31:0] global_cycle;
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) global_cycle <= '0;
        else        global_cycle <= global_cycle + 1;

    logic [31:0] latency_r;
    logic [31:0] payload_r;
    logic [COORD_WIDTH-1:0] src_x_r, src_y_r;
    logic        capture_pending;

    // -----------------------------------------------------------------------
    // Response string assembly
    // We pre-build a byte array then stream it out through UART Tx.
    // Maximum string: "[Node 3] Received: XXXX | Latency: 99999 cycles\r\n"
    //                  ≈ 52 chars → use 80-byte buffer for safety
    // -----------------------------------------------------------------------
    localparam BUF_LEN = 80;
    logic [7:0]  buf_r    [0:BUF_LEN-1];
    logic [6:0]  buf_len;      // actual length of this response
    logic [6:0]  tx_idx;       // next byte to send
    logic        tx_active;

    // -----------------------------------------------------------------------
    // Decimal formatter task (combinational helper via function)
    // Fills buf at position pos with at most MAX_DIGITS ASCII digits (no padding).
    // Returns the number of digits written.
    // -----------------------------------------------------------------------
    function automatic [3:0] fmt_decimal(
        input  logic [31:0]   val,
        // We write into a localparam-sized temp; caller copies
        output logic [7:0]    obuf [0:MAX_DIGITS-1]
    );
        integer i;
        logic [31:0] tmp;
        logic [3:0]  ndig;
        logic [7:0]  tmp_buf [0:MAX_DIGITS-1];
        tmp  = val;
        ndig = 0;
        // Generate digits LSD first into tmp_buf
        for (i = 0; i < MAX_DIGITS; i++) begin
            tmp_buf[i] = 8'h30 + (tmp % 10);
            tmp        = tmp / 10;
            if (val > 0 || i == 0) ndig = i + 1; // always emit at least '0'
            if (tmp == 0) break;
        end
        // Reverse into obuf
        for (i = 0; i < ndig; i++)
            obuf[i] = tmp_buf[ndig - 1 - i];
        fmt_decimal = ndig;
    endfunction

    // -----------------------------------------------------------------------
    // Build string into buf_r when echo arrives
    // -----------------------------------------------------------------------
    // Helper: write a literal string byte-by-byte (macro-like)
    integer bi;  // byte index used in always block

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            capture_pending <= 0;
            tx_active       <= 0;
            tx_start        <= 0;
            tx_idx          <= 0;
            buf_len         <= 0;
            tx_byte         <= 0;
            latency_r       <= 0;
            payload_r       <= 0;
        end else begin
            tx_start <= 0; // default

            // ----------------------------------------------------------------
            // Capture echoed flit and build response string
            // ----------------------------------------------------------------
            if (echo_valid && !tx_active) begin
                // Latency = current cycle - inject timestamp
                latency_r <= global_cycle - inject_timestamp;
                payload_r <= echo_flit[31:0];
                src_x_r   <= echo_flit[DATA_WIDTH-1 : DATA_WIDTH-COORD_WIDTH];
                src_y_r   <= echo_flit[DATA_WIDTH-COORD_WIDTH-1 : DATA_WIDTH-2*COORD_WIDTH];
                capture_pending <= 1;
            end

            // ----------------------------------------------------------------
            // One-cycle after capture: assemble ASCII buffer
            // ----------------------------------------------------------------
            if (capture_pending) begin
                capture_pending <= 0;
                begin
                    // Local variables for string building
                    logic [6:0]   idx;
                    logic [7:0]   lat_buf [0:MAX_DIGITS-1];
                    logic [3:0]   lat_len;
                    logic [7:0]   pay_char;
                    integer       k;

                    idx = 0;

                    // "[Node "
                    buf_r[idx] <= "["; idx = idx + 1;
                    buf_r[idx] <= "N"; idx = idx + 1;
                    buf_r[idx] <= "o"; idx = idx + 1;
                    buf_r[idx] <= "d"; idx = idx + 1;
                    buf_r[idx] <= "e"; idx = idx + 1;
                    buf_r[idx] <= " "; idx = idx + 1;

                    // Source node number (0-3)
                    buf_r[idx] <= 8'h30 + {src_x_r, src_y_r}; idx = idx + 1;

                    // "] Received: "
                    buf_r[idx] <= "]"; idx = idx + 1;
                    buf_r[idx] <= " "; idx = idx + 1;
                    buf_r[idx] <= "R"; idx = idx + 1;
                    buf_r[idx] <= "e"; idx = idx + 1;
                    buf_r[idx] <= "c"; idx = idx + 1;
                    buf_r[idx] <= "e"; idx = idx + 1;
                    buf_r[idx] <= "i"; idx = idx + 1;
                    buf_r[idx] <= "v"; idx = idx + 1;
                    buf_r[idx] <= "e"; idx = idx + 1;
                    buf_r[idx] <= "d"; idx = idx + 1;
                    buf_r[idx] <= ":"; idx = idx + 1;
                    buf_r[idx] <= " "; idx = idx + 1;

                    // Payload bytes as ASCII (print up to 4 printable chars)
                    for (k = 3; k >= 0; k--) begin
                        pay_char = payload_r[k*8 +: 8];
                        if (pay_char >= 8'h20 && pay_char <= 8'h7E)
                            buf_r[idx] <= pay_char;
                        else
                            buf_r[idx] <= ".";
                        idx = idx + 1;
                    end

                    // " | Latency: "
                    buf_r[idx] <= " "; idx = idx + 1;
                    buf_r[idx] <= "|"; idx = idx + 1;
                    buf_r[idx] <= " "; idx = idx + 1;
                    buf_r[idx] <= "L"; idx = idx + 1;
                    buf_r[idx] <= "a"; idx = idx + 1;
                    buf_r[idx] <= "t"; idx = idx + 1;
                    buf_r[idx] <= "e"; idx = idx + 1;
                    buf_r[idx] <= "n"; idx = idx + 1;
                    buf_r[idx] <= "c"; idx = idx + 1;
                    buf_r[idx] <= "y"; idx = idx + 1;
                    buf_r[idx] <= ":"; idx = idx + 1;
                    buf_r[idx] <= " "; idx = idx + 1;

                    // Decimal latency
                    lat_len = fmt_decimal(latency_r, lat_buf);
                    for (k = 0; k < lat_len; k++) begin
                        buf_r[idx] <= lat_buf[k]; idx = idx + 1;
                    end

                    // " cycles\r\n"
                    buf_r[idx] <= " "; idx = idx + 1;
                    buf_r[idx] <= "c"; idx = idx + 1;
                    buf_r[idx] <= "y"; idx = idx + 1;
                    buf_r[idx] <= "c"; idx = idx + 1;
                    buf_r[idx] <= "l"; idx = idx + 1;
                    buf_r[idx] <= "e"; idx = idx + 1;
                    buf_r[idx] <= "s"; idx = idx + 1;
                    buf_r[idx] <= 8'h0D; idx = idx + 1;  // CR
                    buf_r[idx] <= 8'h0A; idx = idx + 1;  // LF

                    buf_len  <= idx;
                    tx_idx   <= 0;
                    tx_active<= 1;
                end
            end

            // ----------------------------------------------------------------
            // Stream buffer through UART Tx
            // ----------------------------------------------------------------
            if (tx_active && !tx_busy && !tx_start) begin
                if (tx_idx < buf_len) begin
                    tx_byte  <= buf_r[tx_idx];
                    tx_start <= 1;
                    tx_idx   <= tx_idx + 1;
                end else begin
                    tx_active <= 0;
                end
            end
        end
    end

endmodule
