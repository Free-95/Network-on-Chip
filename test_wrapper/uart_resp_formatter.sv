// uart_resp_formatter.sv
//   Serializes a received NoC payload and latency metadata into a binary UART byte stream.
//   This is the module that sends the "Visual Ping" back to your PC.

// Protocol (Binary Response Framing):
//   A complete response consists of 1 Header Byte, PAYLOAD_BYTES of data, 
//   and 2 bytes of Latency information.
//
//   Byte 0: Header Byte
//           [7:4] = 4'hB  (Response Nibble indicating NoC output)
//           [3:2] = 2'b00 (Reserved/Unused)
//           [1:0] = Source Node ID (0 to 3)
//           Example: 0xB3 means "Response bounced from Node 3"
//
//   Bytes 1..PAYLOAD_BYTES: Raw payload data (transmitted MSB first)
//
//   Byte N+1: Latency High Byte
//   Byte N+2: Latency Low Byte

// Example Transmission (PAYLOAD_BYTES = 3):
//   If Node 3 returns payload 0x48454C with a latency of 30 cycles (0x001E):
//   0xB3  0x48  0x45  0x4C  0x00  0x1E

// Interface:
//   .fmt_valid        Pulse high to lock in data and begin UART transmission
//   .fmt_src_node     [1:0] Node that bounced the packet back
//   .fmt_payload      [PAYLOAD_BYTES*8-1:0] Payload to transmit
//   .fmt_latency      [TS_WIDTH-1:0] Clock cycles taken for round-trip
//   .tx_data          [7:0] Pushed to uart_tx module
//   .fmt_busy         Held high while serializing. Gates new inputs.

`timescale 1ns / 1ps

module uart_resp_formatter #(
    parameter integer PAYLOAD_BYTES = 3,
    parameter integer TS_WIDTH      = 16
)(
    input  logic                       clk,
    input  logic                       rst_n,

    input  logic                       fmt_valid,
    input  logic [1:0]                 fmt_src_node,
    input  logic [PAYLOAD_BYTES*8-1:0] fmt_payload,
    input  logic [$clog2(PAYLOAD_BYTES+1)-1:0] fmt_payload_len,
    input  logic [TS_WIDTH-1:0]        fmt_latency,

    output logic [7:0]                 tx_data,
    output logic                       tx_valid,
    input  logic                       tx_ready,

    output logic                       fmt_busy
);

    // Total bytes to send: 1 header + PAYLOAD_BYTES + 2 latency = PAYLOAD_BYTES+3
    localparam integer TOTAL_BYTES = PAYLOAD_BYTES + 3;
    localparam integer IDX_W       = $clog2(TOTAL_BYTES + 1);

    // Build a flat byte array at capture time: [hdr, p2, p1, p0, lat_hi, lat_lo]
    // Byte index 0 = first to send
    localparam integer FRAME_BYTES = 1 + PAYLOAD_BYTES + 2;  // = TOTAL_BYTES

    logic [7:0]       frame [0:FRAME_BYTES-1];
    logic [IDX_W-1:0] byte_idx;
    logic             sending;

    // fmt_busy: high from capture until last byte is accepted
    assign fmt_busy = sending;

    // tx_valid: high whenever we have a byte to send
    assign tx_valid = sending;
    assign tx_data  = frame[byte_idx];

    integer k;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sending  <= 1'b0;
            byte_idx <= '0;
            for (k = 0; k < FRAME_BYTES; k = k + 1)
                frame[k] <= 8'd0;
        end else begin
            if (!sending && fmt_valid) begin
                // Byte 0: Capture response header (0xB0 | src_node)
                frame[0] <= {6'b101100, fmt_src_node};  // 0xB0 | src_node

                // Bytes 1..PAYLOAD: Extract payload bytes (MSB-first)
                for (k = 0; k < PAYLOAD_BYTES; k = k + 1)
                    frame[1 + k] <= fmt_payload[(PAYLOAD_BYTES - 1 - k)*8 +: 8];

                // Bytes N+1, N+2: Latency high byte then low byte
                frame[1 + PAYLOAD_BYTES]     <= fmt_latency[TS_WIDTH-1 -: 8];
                frame[1 + PAYLOAD_BYTES + 1] <= fmt_latency[7:0];

                byte_idx <= '0;
                sending  <= 1'b1;
            end else if (sending && tx_ready) begin
                // uart_tx accepted current byte, move to next
                if (byte_idx == IDX_W'(FRAME_BYTES - 1)) begin
                    sending <= 1'b0;
                end else begin
                    byte_idx <= byte_idx + 1'b1;
                end
            end
        end
    end

endmodule
