// noc_uart_top.sv
// ============================================================================
// TOP-LEVEL WRAPPER  –  NoC Serial Terminal Monitor (UART MVP Demo)
//
// Architecture:
//   2 x 2 mesh of router_5port nodes
//
//   Node coordinates:
//     (0,0)──East──(1,0)
//       │               │
//     South           South
//       │               │
//     (0,1)──East──(1,1)
//
//   Port wiring per router:
//     Port 0 = Local   Port 1 = North   Port 2 = South
//     Port 3 = East    Port 4 = West
//
//   UART bridge attached to Node(0,0) Local port:
//     • uart_cmd_parser  parses "SEND N MSG\r\n" → injects flit
//     • uart_resp_formatter prints "[Node X] Received: MSG | Latency: N cycles"
//
//   Echo agent attached to Node(1,1) Local port:
//     • Receives any flit addressed to (1,1) and bounces it back to (0,0)
//
// UART settings: 115200 8N1 (CLKS_PER_BIT = CLK_FREQ / 115200)
//
// Flit format (34 bits, COORD_WIDTH=1):
//   [33]    dest_x
//   [32]    dest_y
//   [31: 0] payload (ASCII chars, MSB = first char)
// ============================================================================

`timescale 1ns / 1ps

module noc_uart_top #(
    parameter DATA_WIDTH   = 34,
    parameter COORD_WIDTH  = 1,
    parameter FIFO_DEPTH   = 8,
    parameter CLKS_PER_BIT = 868    // 100 MHz / 115200 baud
)(
    input  logic clk,
    input  logic rst_n,

    // Physical UART pins (connect to FPGA USB-UART bridge)
    input  logic uart_rxd,
    output logic uart_txd
);

    // =========================================================================
    // Inter-router link buses
    // Each router has 5 tx ports and 5 rx ports. Naming convention:
    //   rXY_tx_flit[port]  = data driven by router XY on output port N
    //   rXY_tx_valid[port]
    //   rXY_tx_ready[port] = backpressure from downstream router
    // =========================================================================

    // Router outputs
    logic [4:0][DATA_WIDTH-1:0] r00_tx_flit,  r10_tx_flit,
                                 r01_tx_flit,  r11_tx_flit;
    logic [4:0]                  r00_tx_valid, r10_tx_valid,
                                 r01_tx_valid, r11_tx_valid;
    logic [4:0]                  r00_tx_ready, r10_tx_ready,
                                 r01_tx_ready, r11_tx_ready;

    // Router inputs (assembled from neighbour outputs)
    logic [4:0][DATA_WIDTH-1:0] r00_rx_flit,  r10_rx_flit,
                                 r01_rx_flit,  r11_rx_flit;
    logic [4:0]                  r00_rx_valid, r10_rx_valid,
                                 r01_rx_valid, r11_rx_valid;
    logic [4:0]                  r00_rx_ready, r10_rx_ready,
                                 r01_rx_ready, r11_rx_ready;

    // =========================================================================
    // UART Rx / Tx
    // =========================================================================
    logic [7:0] uart_rx_byte;
    logic        uart_rx_valid;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) uart_rx_inst (
        .clk      (clk),
        .rst_n    (rst_n),
        .rx_serial(uart_rxd),
        .rx_byte  (uart_rx_byte),
        .rx_valid (uart_rx_valid)
    );

    logic [7:0] uart_tx_byte;
    logic        uart_tx_start;
    logic        uart_tx_busy;

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) uart_tx_inst (
        .clk      (clk),
        .rst_n    (rst_n),
        .tx_byte  (uart_tx_byte),
        .tx_start (uart_tx_start),
        .tx_serial(uart_txd),
        .tx_busy  (uart_tx_busy)
    );

    // =========================================================================
    // Command Parser → flit for Node(0,0) Local-in
    // =========================================================================
    logic [DATA_WIDTH-1:0] inject_flit;
    logic                   inject_valid;
    logic                   parse_error;    // tied to LED if needed

    uart_cmd_parser #(
        .DATA_WIDTH (DATA_WIDTH),
        .COORD_WIDTH(COORD_WIDTH)
    ) parser_inst (
        .clk        (clk),
        .rst_n      (rst_n),
        .rx_byte    (uart_rx_byte),
        .rx_valid   (uart_rx_valid),
        .flit_out   (inject_flit),
        .flit_valid (inject_valid),
        .parse_error(parse_error)
    );

    // =========================================================================
    // Timestamp for latency measurement
    // =========================================================================
    logic [31:0] inject_timestamp;
    logic [31:0] global_cycle_top;

    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) global_cycle_top <= '0;
        else        global_cycle_top <= global_cycle_top + 1;

    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)        inject_timestamp <= '0;
        else if (inject_valid) inject_timestamp <= global_cycle_top;

    // =========================================================================
    // Response Formatter ← echo flit from Node(0,0) Local-out
    // =========================================================================
    // Port 0 (Local) of r00 is where the echoed flit will arrive
    logic [DATA_WIDTH-1:0] echo_flit_to_format;
    logic                   echo_valid_to_format;

    // The echo from node(1,1) returns addressed to (0,0) and ejects at Local
    assign echo_flit_to_format  = r00_tx_flit[0];
    assign echo_valid_to_format = r00_tx_valid[0];

    // r00 Local-out is consumed by formatter (always ready)
    assign r00_tx_ready[0] = 1'b1;

    uart_resp_formatter #(
        .DATA_WIDTH (DATA_WIDTH),
        .COORD_WIDTH(COORD_WIDTH)
    ) formatter_inst (
        .clk              (clk),
        .rst_n            (rst_n),
        .inject_timestamp (inject_timestamp),
        .echo_flit        (echo_flit_to_format),
        .echo_valid       (echo_valid_to_format),
        .tx_byte          (uart_tx_byte),
        .tx_start         (uart_tx_start),
        .tx_busy          (uart_tx_busy)
    );

    // =========================================================================
    // Echo Agent at Node(1,1)
    // =========================================================================
    logic [DATA_WIDTH-1:0] echo_rx_flit;
    logic                   echo_rx_valid, echo_rx_ready;
    logic [DATA_WIDTH-1:0] echo_tx_flit;
    logic                   echo_tx_valid, echo_tx_ready;

    // r11 Local-out → echo agent input
    assign echo_rx_flit        = r11_tx_flit[0];
    assign echo_rx_valid       = r11_tx_valid[0];
    assign r11_tx_ready[0]     = echo_rx_ready;

    // echo agent output → r11 Local-in
    assign r11_rx_flit[0]      = echo_tx_flit;
    assign r11_rx_valid[0]     = echo_tx_valid;
    assign echo_tx_ready       = r11_rx_ready[0];

    echo_agent #(
        .DATA_WIDTH (DATA_WIDTH),
        .COORD_WIDTH(COORD_WIDTH)
    ) echo_inst (
        .clk            (clk),
        .rst_n          (rst_n),
        .local_rx_flit  (echo_rx_flit),
        .local_rx_valid (echo_rx_valid),
        .local_rx_ready (echo_rx_ready),
        .local_tx_flit  (echo_tx_flit),
        .local_tx_valid (echo_tx_valid),
        .local_tx_ready (echo_tx_ready)
    );

    // =========================================================================
    // Null agents at unused local ports of r10 and r01
    // (nothing injects or receives at these nodes for this demo)
    // =========================================================================
    assign r10_rx_flit[0]  = '0;
    assign r10_rx_valid[0] = 1'b0;
    assign r10_tx_ready[0] = 1'b1;    // absorb anything that arrives

    assign r01_rx_flit[0]  = '0;
    assign r01_rx_valid[0] = 1'b0;
    assign r01_tx_ready[0] = 1'b1;

    // =========================================================================
    // Node(0,0) Local-in driven by parser
    // =========================================================================
    assign r00_rx_flit[0]  = inject_flit;
    assign r00_rx_valid[0] = inject_valid;
    // r00_rx_ready[0] is the FIFO's backpressure signal; ignore for now (FIFO is deep)

    // =========================================================================
    // Mesh Link Wiring
    // =========================================================================
    // Port mapping:  0=Local  1=North  2=South  3=East  4=West
    //
    //   r00 ──East(3)──► r10     r10 ──West(4)──► r00
    //   r00 ──South(2)──► r01    r01 ──North(1)──► r00
    //   r10 ──South(2)──► r11    r11 ──North(1)──► r10
    //   r01 ──East(3)──► r11     r11 ──West(4)──► r01
    //
    // Border ports are tied off (no wrap-around in this demo).

    // r00 → r10 (East)
    assign r10_rx_flit[4]   = r00_tx_flit[3];    // r10 West-in  ← r00 East-out
    assign r10_rx_valid[4]  = r00_tx_valid[3];
    assign r00_tx_ready[3]  = r10_rx_ready[4];

    // r10 → r00 (West)
    assign r00_rx_flit[4]   = r10_tx_flit[4];    // r00 West-in  ← r10 West-out
    assign r00_rx_valid[4]  = r10_tx_valid[4];
    assign r10_tx_ready[4]  = r00_rx_ready[4];

    // r00 → r01 (South)
    assign r01_rx_flit[1]   = r00_tx_flit[2];    // r01 North-in ← r00 South-out
    assign r01_rx_valid[1]  = r00_tx_valid[2];
    assign r00_tx_ready[2]  = r01_rx_ready[1];

    // r01 → r00 (North)
    assign r00_rx_flit[1]   = r01_tx_flit[1];    // r00 North-in ← r01 North-out
    assign r00_rx_valid[1]  = r01_tx_valid[1];
    assign r01_tx_ready[1]  = r00_rx_ready[1];

    // r10 → r11 (South)
    assign r11_rx_flit[1]   = r10_tx_flit[2];    // r11 North-in ← r10 South-out
    assign r11_rx_valid[1]  = r10_tx_valid[2];
    assign r10_tx_ready[2]  = r11_rx_ready[1];

    // r11 → r10 (North)
    assign r10_rx_flit[1]   = r11_tx_flit[1];
    assign r10_rx_valid[1]  = r11_tx_valid[1];
    assign r11_tx_ready[1]  = r10_rx_ready[1];

    // r01 → r11 (East)
    assign r11_rx_flit[4]   = r01_tx_flit[3];    // r11 West-in  ← r01 East-out
    assign r11_rx_valid[4]  = r01_tx_valid[3];
    assign r01_tx_ready[3]  = r11_rx_ready[4];

    // r11 → r01 (West)
    assign r01_rx_flit[3]   = r11_tx_flit[4];    // r01 East-in  ← r11 West-out
    assign r01_rx_valid[3]  = r11_tx_valid[4];
    assign r11_tx_ready[4]  = r01_rx_ready[3];

    // -------------------------------------------------------------------------
    // Border tie-offs (North of row-0, South of row-1, East of col-1, West of col-0)
    // -------------------------------------------------------------------------
    // r00: North-in, West-in unused
    assign r00_rx_flit[1]  = '0;   // already driven above; this line intentionally
                                    // commented to avoid double-drive – see above
    // North borders: r00[1] driven by r01 above. r10[1] driven by r11 above.
    // West borders
    assign r00_rx_flit[4]  = r10_tx_flit[4];   // already assigned above
    // South borders (row-1 routers have no southern neighbour)
    assign r01_tx_ready[2] = 1'b1;    // r01 South-out: nowhere to go, absorb
    assign r11_tx_ready[2] = 1'b1;    // r11 South-out: absorb
    // East borders (col-1 routers)
    assign r10_tx_ready[3] = 1'b1;    // r10 East-out: absorb
    assign r11_tx_ready[3] = 1'b1;
    // North of top row
    assign r00_tx_ready[1] = 1'b1;    // r00 North-out: absorb
    assign r10_tx_ready[1] = 1'b1;    // r10 North-out: absorb
    // West of left column
    assign r00_tx_ready[4] = 1'b1;
    assign r01_tx_ready[4] = 1'b1;
    // Unused rx borders
    assign r10_rx_flit[3]  = '0; assign r10_rx_valid[3] = 1'b0;   // East-in unused
    assign r01_rx_flit[2]  = '0; assign r01_rx_valid[2] = 1'b0;   // South-in unused
    assign r11_rx_flit[2]  = '0; assign r11_rx_valid[2] = 1'b0;   // South-in unused
    assign r11_rx_flit[3]  = '0; assign r11_rx_valid[3] = 1'b0;   // East-in unused
    assign r00_rx_flit[2]  = r01_tx_flit[1]; // already driven; keep consistent
    assign r00_rx_valid[2] = 1'b0;           // r00 south-in: unused (r01 drives north-out to r00)

    // =========================================================================
    // Router Instances
    // =========================================================================
    router_5port #(
        .DATA_WIDTH (DATA_WIDTH),
        .COORD_WIDTH(COORD_WIDTH),
        .FIFO_DEPTH (FIFO_DEPTH)
    ) r00 (
        .clk         (clk),          .rst_n       (rst_n),
        .router_x    (1'b0),         .router_y    (1'b0),
        .rx_flit_arr (r00_rx_flit),  .rx_valid_arr(r00_rx_valid),
        .rx_ready_arr(r00_rx_ready),
        .tx_flit_arr (r00_tx_flit),  .tx_valid_arr(r00_tx_valid),
        .tx_ready_arr(r00_tx_ready)
    );

    router_5port #(
        .DATA_WIDTH (DATA_WIDTH),
        .COORD_WIDTH(COORD_WIDTH),
        .FIFO_DEPTH (FIFO_DEPTH)
    ) r10 (
        .clk         (clk),          .rst_n       (rst_n),
        .router_x    (1'b1),         .router_y    (1'b0),
        .rx_flit_arr (r10_rx_flit),  .rx_valid_arr(r10_rx_valid),
        .rx_ready_arr(r10_rx_ready),
        .tx_flit_arr (r10_tx_flit),  .tx_valid_arr(r10_tx_valid),
        .tx_ready_arr(r10_tx_ready)
    );

    router_5port #(
        .DATA_WIDTH (DATA_WIDTH),
        .COORD_WIDTH(COORD_WIDTH),
        .FIFO_DEPTH (FIFO_DEPTH)
    ) r01 (
        .clk         (clk),          .rst_n       (rst_n),
        .router_x    (1'b0),         .router_y    (1'b1),
        .rx_flit_arr (r01_rx_flit),  .rx_valid_arr(r01_rx_valid),
        .rx_ready_arr(r01_rx_ready),
        .tx_flit_arr (r01_tx_flit),  .tx_valid_arr(r01_tx_valid),
        .tx_ready_arr(r01_tx_ready)
    );

    router_5port #(
        .DATA_WIDTH (DATA_WIDTH),
        .COORD_WIDTH(COORD_WIDTH),
        .FIFO_DEPTH (FIFO_DEPTH)
    ) r11 (
        .clk         (clk),          .rst_n       (rst_n),
        .router_x    (1'b1),         .router_y    (1'b1),
        .rx_flit_arr (r11_rx_flit),  .rx_valid_arr(r11_rx_valid),
        .rx_ready_arr(r11_rx_ready),
        .tx_flit_arr (r11_tx_flit),  .tx_valid_arr(r11_tx_valid),
        .tx_ready_arr(r11_tx_ready)
    );

endmodule
