// top_noc_fabric.sv
// Vivado 2025 compatible 2×2 Mesh NoC fabric.
//
// VIVADO COMPATIBILITY CHANGES:
//   • Removed unpacked arrays as port connections (rx_flit[4] → router port).
//     Vivado rejects unpacked→packed array port bindings.
//     Fix: declare inter-router wires as flat named signals per-port.
//   • Removed localparam inside generate blocks (Vivado 2025 may warn/error).
//   • All internal signals use logic type (in .sv file — fully supported).
//   • Dependent parameter expressions (PAYLOAD_W, CORE_DATA_W) kept in
//     parameter list — Vivado supports dependent parameters in #() lists.
//   • generate-for with named begin blocks — supported.
//   • NI and router instantiations use explicit named port connections.
//
// Node mapping (2×2 mesh):
//   Node 0 = (x=0, y=0) — top-left
//   Node 1 = (x=1, y=0) — top-right
//   Node 2 = (x=0, y=1) — bottom-left
//   Node 3 = (x=1, y=1) — bottom-right
//
// Port indices per router: 0=Local  1=North  2=South  3=East  4=West

`timescale 1ns / 1ps

module mesh_fabric_noc #(
    parameter DATA_WIDTH  = 34,
    parameter COORD_WIDTH = 1,
    parameter FIFO_DEPTH  = 8,
    parameter TS_WIDTH    = 16,
    // Derived — kept in parameter list so top-level can override if needed
    parameter PAYLOAD_W   = DATA_WIDTH - (2*COORD_WIDTH) - 2,
    parameter CORE_DATA_W = PAYLOAD_W * 2
)(
    input  logic clk,
    input  logic rst_n,

    // Core interfaces — node indexed [3:0] using packed arrays (Vivado-safe)
    input  logic [3:0][CORE_DATA_W-1:0]  core_tx_data,
    input  logic [3:0][COORD_WIDTH-1:0]  core_tx_dest_x,
    input  logic [3:0][COORD_WIDTH-1:0]  core_tx_dest_y,
    input  logic [3:0]                   core_tx_valid,
    output logic [3:0]                   core_tx_ready,

    output logic [3:0][CORE_DATA_W-1:0]  core_rx_data,
    output logic [3:0]                   core_rx_valid,
    input  logic [3:0]                   core_rx_ready,

    output logic [3:0][TS_WIDTH-1:0]     latency_cycles_out,
    output logic [3:0]                   latency_valid
);

    // =========================================================================
    // NI ↔ Router local-port wires (Port 0) — flat scalars, Vivado-safe
    // ni_tx = NI transmit → router rx
    // ni_rx = NI receive  ← router tx
    // =========================================================================
    logic [DATA_WIDTH-1:0] ni_tx_flit  [0:3];
    logic                  ni_tx_valid [0:3];
    logic                  ni_tx_ready [0:3];

    logic [DATA_WIDTH-1:0] ni_rx_flit  [0:3];
    logic                  ni_rx_valid [0:3];
    logic                  ni_rx_ready [0:3];

    // =========================================================================
    // Router inter-port wires — all flat, named per link
    // Naming: r<A>_to_r<B>_flit/valid/ready
    // =========================================================================

    // Link: r0(East/3) ↔ r1(West/4)
    logic [DATA_WIDTH-1:0] r0_r1_flit;  logic r0_r1_valid; logic r0_r1_ready;
    logic [DATA_WIDTH-1:0] r1_r0_flit;  logic r1_r0_valid; logic r1_r0_ready;

    // Link: r0(South/2) ↔ r2(North/1)
    logic [DATA_WIDTH-1:0] r0_r2_flit;  logic r0_r2_valid; logic r0_r2_ready;
    logic [DATA_WIDTH-1:0] r2_r0_flit;  logic r2_r0_valid; logic r2_r0_ready;

    // Link: r1(South/2) ↔ r3(North/1)
    logic [DATA_WIDTH-1:0] r1_r3_flit;  logic r1_r3_valid; logic r1_r3_ready;
    logic [DATA_WIDTH-1:0] r3_r1_flit;  logic r3_r1_valid; logic r3_r1_ready;

    // Link: r2(East/3) ↔ r3(West/4)
    logic [DATA_WIDTH-1:0] r2_r3_flit;  logic r2_r3_valid; logic r2_r3_ready;
    logic [DATA_WIDTH-1:0] r3_r2_flit;  logic r3_r2_valid; logic r3_r2_ready;

    // =========================================================================
    // Router input/output port buses — assembled from flat signals above.
    // Each router has 5 ports. Declare as packed [4:0][DATA_WIDTH-1:0]
    // so they match the router_5port port type exactly (no unpacked mismatch).
    // =========================================================================
    logic [4:0][DATA_WIDTH-1:0] r0_rx_flit,  r1_rx_flit,  r2_rx_flit,  r3_rx_flit;
    logic [4:0]                 r0_rx_valid, r1_rx_valid, r2_rx_valid, r3_rx_valid;
    logic [4:0]                 r0_rx_ready, r1_rx_ready, r2_rx_ready, r3_rx_ready;

    logic [4:0][DATA_WIDTH-1:0] r0_tx_flit,  r1_tx_flit,  r2_tx_flit,  r3_tx_flit;
    logic [4:0]                 r0_tx_valid, r1_tx_valid, r2_tx_valid, r3_tx_valid;
    logic [4:0]                 r0_tx_ready, r1_tx_ready, r2_tx_ready, r3_tx_ready;

    // =========================================================================
    // Port-bus assembly: slot the flat wires into packed [4:0] buses
    // Port 0=Local  1=North  2=South  3=East  4=West
    // =========================================================================

    // ----- Router 0 (0,0) -----------------------------------------------
    // Port 0 Local
    assign r0_rx_flit[0]  = ni_tx_flit[0];   assign r0_rx_valid[0] = ni_tx_valid[0];
    assign ni_tx_ready[0] = r0_rx_ready[0];
    assign ni_rx_flit[0]  = r0_tx_flit[0];   assign ni_rx_valid[0] = r0_tx_valid[0];
    assign r0_tx_ready[0] = ni_rx_ready[0];
    // Port 1 North — border tie-off
    assign r0_rx_flit[1]  = '0;              assign r0_rx_valid[1] = 1'b0;
    assign r0_tx_ready[1] = 1'b1;
    // Port 2 South → r2 North
    assign r0_rx_flit[2]  = r2_r0_flit;     assign r0_rx_valid[2] = r2_r0_valid;
    assign r2_r0_ready    = r0_rx_ready[2];
    assign r0_r2_flit     = r0_tx_flit[2];   assign r0_r2_valid    = r0_tx_valid[2];
    assign r0_tx_ready[2] = r0_r2_ready;
    // Port 3 East → r1 West
    assign r0_rx_flit[3]  = r1_r0_flit;     assign r0_rx_valid[3] = r1_r0_valid;
    assign r1_r0_ready    = r0_rx_ready[3];
    assign r0_r1_flit     = r0_tx_flit[3];   assign r0_r1_valid    = r0_tx_valid[3];
    assign r0_tx_ready[3] = r0_r1_ready;
    // Port 4 West — border tie-off
    assign r0_rx_flit[4]  = '0;              assign r0_rx_valid[4] = 1'b0;
    assign r0_tx_ready[4] = 1'b1;

    // ----- Router 1 (1,0) -----------------------------------------------
    assign r1_rx_flit[0]  = ni_tx_flit[1];   assign r1_rx_valid[0] = ni_tx_valid[1];
    assign ni_tx_ready[1] = r1_rx_ready[0];
    assign ni_rx_flit[1]  = r1_tx_flit[0];   assign ni_rx_valid[1] = r1_tx_valid[0];
    assign r1_tx_ready[0] = ni_rx_ready[1];
    // Port 1 North — border tie-off
    assign r1_rx_flit[1]  = '0;              assign r1_rx_valid[1] = 1'b0;
    assign r1_tx_ready[1] = 1'b1;
    // Port 2 South → r3 North
    assign r1_rx_flit[2]  = r3_r1_flit;     assign r1_rx_valid[2] = r3_r1_valid;
    assign r3_r1_ready    = r1_rx_ready[2];
    assign r1_r3_flit     = r1_tx_flit[2];   assign r1_r3_valid    = r1_tx_valid[2];
    assign r1_tx_ready[2] = r1_r3_ready;
    // Port 3 East — border tie-off
    assign r1_rx_flit[3]  = '0;              assign r1_rx_valid[3] = 1'b0;
    assign r1_tx_ready[3] = 1'b1;
    // Port 4 West ← r0 East
    assign r1_rx_flit[4]  = r0_r1_flit;     assign r1_rx_valid[4] = r0_r1_valid;
    assign r0_r1_ready    = r1_rx_ready[4];
    assign r1_r0_flit     = r1_tx_flit[4];   assign r1_r0_valid    = r1_tx_valid[4];
    assign r1_tx_ready[4] = r1_r0_ready;

    // ----- Router 2 (0,1) -----------------------------------------------
    assign r2_rx_flit[0]  = ni_tx_flit[2];   assign r2_rx_valid[0] = ni_tx_valid[2];
    assign ni_tx_ready[2] = r2_rx_ready[0];
    assign ni_rx_flit[2]  = r2_tx_flit[0];   assign ni_rx_valid[2] = r2_tx_valid[0];
    assign r2_tx_ready[0] = ni_rx_ready[2];
    // Port 1 North ← r0 South
    assign r2_rx_flit[1]  = r0_r2_flit;     assign r2_rx_valid[1] = r0_r2_valid;
    assign r0_r2_ready    = r2_rx_ready[1];
    assign r2_r0_flit     = r2_tx_flit[1];   assign r2_r0_valid    = r2_tx_valid[1];
    assign r2_tx_ready[1] = r2_r0_ready;
    // Port 2 South — border tie-off
    assign r2_rx_flit[2]  = '0;              assign r2_rx_valid[2] = 1'b0;
    assign r2_tx_ready[2] = 1'b1;
    // Port 3 East → r3 West
    assign r2_rx_flit[3]  = r3_r2_flit;     assign r2_rx_valid[3] = r3_r2_valid;
    assign r3_r2_ready    = r2_rx_ready[3];
    assign r2_r3_flit     = r2_tx_flit[3];   assign r2_r3_valid    = r2_tx_valid[3];
    assign r2_tx_ready[3] = r2_r3_ready;
    // Port 4 West — border tie-off
    assign r2_rx_flit[4]  = '0;              assign r2_rx_valid[4] = 1'b0;
    assign r2_tx_ready[4] = 1'b1;

    // ----- Router 3 (1,1) -----------------------------------------------
    assign r3_rx_flit[0]  = ni_tx_flit[3];   assign r3_rx_valid[0] = ni_tx_valid[3];
    assign ni_tx_ready[3] = r3_rx_ready[0];
    assign ni_rx_flit[3]  = r3_tx_flit[0];   assign ni_rx_valid[3] = r3_tx_valid[0];
    assign r3_tx_ready[0] = ni_rx_ready[3];
    // Port 1 North ← r1 South
    assign r3_rx_flit[1]  = r1_r3_flit;     assign r3_rx_valid[1] = r1_r3_valid;
    assign r1_r3_ready    = r3_rx_ready[1];
    assign r3_r1_flit     = r3_tx_flit[1];   assign r3_r1_valid    = r3_tx_valid[1];
    assign r3_tx_ready[1] = r3_r1_ready;
    // Port 2 South — border tie-off
    assign r3_rx_flit[2]  = '0;              assign r3_rx_valid[2] = 1'b0;
    assign r3_tx_ready[2] = 1'b1;
    // Port 3 East — border tie-off
    assign r3_rx_flit[3]  = '0;              assign r3_rx_valid[3] = 1'b0;
    assign r3_tx_ready[3] = 1'b1;
    // Port 4 West ← r2 East
    assign r3_rx_flit[4]  = r2_r3_flit;     assign r3_rx_valid[4] = r2_r3_valid;
    assign r2_r3_ready    = r3_rx_ready[4];
    assign r3_r2_flit     = r3_tx_flit[4];   assign r3_r2_valid    = r3_tx_valid[4];
    assign r3_tx_ready[4] = r3_r2_ready;

    // =========================================================================
    // Network Interface instantiation (4×)
    // =========================================================================
    genvar n;
    generate
        for (n = 0; n < 4; n = n + 1) begin : gen_ni
            network_interface #(
                .DATA_WIDTH  (DATA_WIDTH),
                .COORD_WIDTH (COORD_WIDTH),
                .TS_WIDTH    (TS_WIDTH)
            ) ni_inst (
                .clk               (clk),
                .rst_n             (rst_n),
                .core_tx_data      (core_tx_data[n]),
                .core_tx_dest_x    (core_tx_dest_x[n]),
                .core_tx_dest_y    (core_tx_dest_y[n]),
                .core_tx_valid     (core_tx_valid[n]),
                .core_tx_ready     (core_tx_ready[n]),
                .core_rx_data      (core_rx_data[n]),
                .core_rx_valid     (core_rx_valid[n]),
                .core_rx_ready     (core_rx_ready[n]),
                .router_tx_flit    (ni_tx_flit[n]),
                .router_tx_valid   (ni_tx_valid[n]),
                .router_tx_ready   (ni_tx_ready[n]),
                .router_rx_flit    (ni_rx_flit[n]),
                .router_rx_valid   (ni_rx_valid[n]),
                .router_rx_ready   (ni_rx_ready[n]),
                .latency_cycles_out(latency_cycles_out[n]),
                .latency_valid     (latency_valid[n])
            );
        end
    endgenerate

    // =========================================================================
    // Router instantiation (4×) — explicit instances, no generate needed
    // =========================================================================
    router_5port #(
        .DATA_WIDTH  (DATA_WIDTH),
        .COORD_WIDTH (COORD_WIDTH),
        .FIFO_DEPTH  (FIFO_DEPTH)
    ) r0_inst (
        .clk          (clk),          .rst_n        (rst_n),
        .router_x     (1'b0),         .router_y     (1'b0),
        .rx_flit_arr  (r0_rx_flit),   .rx_valid_arr (r0_rx_valid),  .rx_ready_arr (r0_rx_ready),
        .tx_flit_arr  (r0_tx_flit),   .tx_valid_arr (r0_tx_valid),  .tx_ready_arr (r0_tx_ready)
    );

    router_5port #(
        .DATA_WIDTH  (DATA_WIDTH),
        .COORD_WIDTH (COORD_WIDTH),
        .FIFO_DEPTH  (FIFO_DEPTH)
    ) r1_inst (
        .clk          (clk),          .rst_n        (rst_n),
        .router_x     (1'b1),         .router_y     (1'b0),
        .rx_flit_arr  (r1_rx_flit),   .rx_valid_arr (r1_rx_valid),  .rx_ready_arr (r1_rx_ready),
        .tx_flit_arr  (r1_tx_flit),   .tx_valid_arr (r1_tx_valid),  .tx_ready_arr (r1_tx_ready)
    );

    router_5port #(
        .DATA_WIDTH  (DATA_WIDTH),
        .COORD_WIDTH (COORD_WIDTH),
        .FIFO_DEPTH  (FIFO_DEPTH)
    ) r2_inst (
        .clk          (clk),          .rst_n        (rst_n),
        .router_x     (1'b0),         .router_y     (1'b1),
        .rx_flit_arr  (r2_rx_flit),   .rx_valid_arr (r2_rx_valid),  .rx_ready_arr (r2_rx_ready),
        .tx_flit_arr  (r2_tx_flit),   .tx_valid_arr (r2_tx_valid),  .tx_ready_arr (r2_tx_ready)
    );

    router_5port #(
        .DATA_WIDTH  (DATA_WIDTH),
        .COORD_WIDTH (COORD_WIDTH),
        .FIFO_DEPTH  (FIFO_DEPTH)
    ) r3_inst (
        .clk          (clk),          .rst_n        (rst_n),
        .router_x     (1'b1),         .router_y     (1'b1),
        .rx_flit_arr  (r3_rx_flit),   .rx_valid_arr (r3_rx_valid),  .rx_ready_arr (r3_rx_ready),
        .tx_flit_arr  (r3_tx_flit),   .tx_valid_arr (r3_tx_valid),  .tx_ready_arr (r3_tx_ready)
    );

endmodule
