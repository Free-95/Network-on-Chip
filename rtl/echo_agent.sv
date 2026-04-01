// echo_agent.sv
// ============================================================================
// Sits at Node(1,1)'s local port.
// When it receives a flit on its local-in port it immediately re-injects
// a reply flit addressed back to Node(0,0).
//
// Reply flit format (DATA_WIDTH=34):
//   [33]    dest_x = 0  (Node 0,0)
//   [32]    dest_y = 0
//   [31: 0] original payload  (echo)
// ============================================================================

`timescale 1ns / 1ps

module echo_agent #(
    parameter DATA_WIDTH  = 34,
    parameter COORD_WIDTH = 1
)(
    input  logic                  clk,
    input  logic                  rst_n,

    // Local-in: flit arriving at this node
    input  logic [DATA_WIDTH-1:0] local_rx_flit,
    input  logic                  local_rx_valid,
    output logic                  local_rx_ready,   // always ready to receive

    // Local-out: reply flit to inject back into NoC
    output logic [DATA_WIDTH-1:0] local_tx_flit,
    output logic                  local_tx_valid,
    input  logic                  local_tx_ready
);

    // We are always ready to receive (single-cycle latency echo)
    assign local_rx_ready = 1'b1;

    // Simple registered echo: capture on rx_valid, fire on next cycle
    logic [DATA_WIDTH-1:0] reply_r;
    logic                  reply_pending;

    // Destination is always Node(0,0)
    localparam [COORD_WIDTH-1:0] REPLY_X = 0;
    localparam [COORD_WIDTH-1:0] REPLY_Y = 0;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reply_r       <= '0;
            reply_pending <= 1'b0;
        end else begin
            if (local_rx_valid && !reply_pending) begin
                // Rebuild flit with destination (0,0) but same payload
                reply_r       <= {REPLY_X, REPLY_Y, local_rx_flit[31:0]};
                reply_pending <= 1'b1;
            end else if (reply_pending && local_tx_ready) begin
                reply_pending <= 1'b0;
            end
        end
    end

    assign local_tx_flit  = reply_r;
    assign local_tx_valid = reply_pending;

endmodule
