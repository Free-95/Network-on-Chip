// uart_cmd_parser.sv
//   Parses incoming binary UART frames and translates them into NoC injection commands.

// Protocol (Binary Framing):
//   A complete command consists of 1 Header Byte followed by PAYLOAD_BYTES of data.
//
//   Byte 0: Header Byte
//           [7:4] = 4'hA  (Command Nibble indicating "SEND")
//           [3:2] = 2'b00 (Reserved/Unused)
//           [1:0] = Destination Node ID (0 to 3)
//           Example: 0xA3 means "Send to Node 3"
//
//   Bytes 1..PAYLOAD_BYTES: Raw payload data (received MSB first)

// Example Transmission (PAYLOAD_BYTES = 3):
//   To send the 24-bit hex payload 0x414243 to Node 3, the PC transmits 4 bytes:
//   0xA3  0x41  0x42  0x43

// Interface:
//   .rx_data         [7:0]                         Raw byte from uart_rx
//   .rx_valid                                      Pulses high for 1 cycle when rx_data is valid
//   .cmd_valid                                     Pulses 1 cycle when the entire frame is reassembled
//   .cmd_dest_node   [1:0]                         Extracted destination node index (0-3)
//   .cmd_payload     [PAYLOAD_BYTES*8-1:0]         Concatenated payload bytes (MSB first)
//   .cmd_payload_len [$clog2(PAYLOAD_BYTES+1)-1:0] Constant indicating payload size

`timescale 1ns / 1ps

module uart_cmd_parser #(
    parameter integer PAYLOAD_BYTES = 3
)(
    input  logic                      clk,
    input  logic                      rst_n,

    input  logic [7:0]                rx_data,
    input  logic                      rx_valid,

    output logic                      cmd_valid,
    output logic [1:0]                cmd_dest_node,
    output logic [PAYLOAD_BYTES*8-1:0] cmd_payload,
    output logic [$clog2(PAYLOAD_BYTES+1)-1:0] cmd_payload_len
);

    localparam integer CNT_W = $clog2(PAYLOAD_BYTES + 1);

    // -------------------------------------------------------------------------
    // Binary framing state machine:
    //   State 0: wait for command header byte (0xA0 to 0xA3)
    //   State 1..PAYLOAD_BYTES: collect incoming payload bytes into shift register
    // -------------------------------------------------------------------------
    logic [CNT_W-1:0]         byte_cnt;   // 0 = expecting cmd, 1..PB = payload
    logic [PAYLOAD_BYTES*8-1:0] payload_r;
    logic [1:0]               dest_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_cnt      <= '0;
            payload_r     <= '0;
            dest_r        <= 2'd0;
            cmd_valid     <= 1'b0;
            cmd_dest_node <= 2'd0;
            cmd_payload   <= '0;
            cmd_payload_len <= '0;
        end else begin
            cmd_valid <= 1'b0;   // default: pulse only

            if (rx_valid) begin
                if (byte_cnt == '0) begin
                    // Command byte: expect 0xA0 | dest[1:0]
                    if (rx_data[7:2] == 6'b101000) begin   // 0xA0..0xA3
                        dest_r   <= rx_data[1:0];
                        byte_cnt <= CNT_W'(1);
                    end
                    // else: garbage — stay in byte 0 wait
                end else begin
                    // Payload bytes: MSB first, shift left
                    payload_r <= {payload_r[PAYLOAD_BYTES*8-9:0], rx_data};

                    if (byte_cnt == CNT_W'(PAYLOAD_BYTES)) begin
                        // Last payload byte received
                        cmd_dest_node   <= dest_r;
                        cmd_payload     <= {payload_r[PAYLOAD_BYTES*8-9:0], rx_data};
                        cmd_payload_len <= CNT_W'(PAYLOAD_BYTES);
                        cmd_valid       <= 1'b1;
                        byte_cnt        <= '0;
                    end else begin
                        byte_cnt <= byte_cnt + 1'b1;
                    end
                end
            end
        end
    end

endmodule
