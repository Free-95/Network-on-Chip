// network_interface.sv
// Vivado 2025 compatible — renamed from .v to .sv (file used logic/always_ff/SV literals).
//
// CHANGES FOR VIVADO COMPATIBILITY:
//   • File extension: .v → .sv  (Vivado treats .v as Verilog-2005; SV keywords require .sv)
//   • All 'logic' declarations preserved (already correct SV)
//   • always_ff preserved (already correct SV)
//   • '0 reset literal kept — supported in SV
//   • No packed-array ports (NI uses scalar ports only — no Vivado array issues)
//   • localparam expressions in module body — fully supported
//
// FIX APPLIED (from prior analysis):
//   TX state machine drives each flit immediately on state entry, eliminating
//   the stale-HEAD flit bug present in the original network_interface.v.

`timescale 1ns / 1ps

module network_interface #(
    parameter DATA_WIDTH  = 34,
    parameter COORD_WIDTH = 1,
    parameter TS_WIDTH    = 16
)(
    input  logic clk,
    input  logic rst_n,

    // Core side
    input  logic [(DATA_WIDTH-(2*COORD_WIDTH)-2)*2-1 : 0] core_tx_data,
    input  logic [COORD_WIDTH-1:0]  core_tx_dest_x,
    input  logic [COORD_WIDTH-1:0]  core_tx_dest_y,
    input  logic                    core_tx_valid,
    output logic                    core_tx_ready,

    output logic [(DATA_WIDTH-(2*COORD_WIDTH)-2)*2-1 : 0] core_rx_data,
    output logic                    core_rx_valid,
    input  logic                    core_rx_ready,

    // Router side
    output logic [DATA_WIDTH-1:0]   router_tx_flit,
    output logic                    router_tx_valid,
    input  logic                    router_tx_ready,

    input  logic [DATA_WIDTH-1:0]   router_rx_flit,
    input  logic                    router_rx_valid,
    output logic                    router_rx_ready,

    // Latency measurement
    output logic [TS_WIDTH-1:0]     latency_cycles_out,
    output logic                    latency_valid
);

    localparam FLIT_TYPE_W = 2;
    localparam PAYLOAD_W   = DATA_WIDTH - (2*COORD_WIDTH) - FLIT_TYPE_W;
    localparam CORE_DATA_W = PAYLOAD_W * 2;

    localparam logic [FLIT_TYPE_W-1:0] TYPE_HEAD = 2'b01;
    localparam logic [FLIT_TYPE_W-1:0] TYPE_BODY = 2'b10;
    localparam logic [FLIT_TYPE_W-1:0] TYPE_TAIL = 2'b11;

    // ── timestamp counter ────────────────────────────────────────────────────
    logic [TS_WIDTH-1:0] ts_counter;
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) ts_counter <= '0;
        else        ts_counter <= ts_counter + 1'b1;

    // =========================================================================
    // TX PATH  (fixed: flit driven on state entry, held until accepted)
    // =========================================================================
    typedef enum logic [1:0] {
        TX_IDLE = 2'd0,
        TX_HEAD = 2'd1,
        TX_BODY = 2'd2,
        TX_TAIL = 2'd3
    } tx_state_t;

    tx_state_t             tx_state;
    logic [CORE_DATA_W-1:0] tx_data_reg;
    logic [COORD_WIDTH-1:0] tx_dest_x_r, tx_dest_y_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state        <= TX_IDLE;
            router_tx_valid <= 1'b0;
            core_tx_ready   <= 1'b1;
            router_tx_flit  <= '0;
            tx_data_reg     <= '0;
            tx_dest_x_r     <= '0;
            tx_dest_y_r     <= '0;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    core_tx_ready <= 1'b1;
                    if (core_tx_valid) begin
                        tx_data_reg   <= core_tx_data;
                        tx_dest_x_r   <= core_tx_dest_x;
                        tx_dest_y_r   <= core_tx_dest_y;
                        // Drive HEAD immediately — held until router accepts
                        router_tx_flit  <= {core_tx_dest_x, core_tx_dest_y,
                                            TYPE_HEAD,
                                            {{(PAYLOAD_W-TS_WIDTH){1'b0}}, ts_counter}};
                        router_tx_valid <= 1'b1;
                        core_tx_ready   <= 1'b0;
                        tx_state        <= TX_HEAD;
                    end
                end

                TX_HEAD: begin
                    if (router_tx_ready) begin
                        // HEAD accepted — immediately present BODY
                        router_tx_flit <= {tx_dest_x_r, tx_dest_y_r,
                                           TYPE_BODY,
                                           tx_data_reg[CORE_DATA_W-1 -: PAYLOAD_W]};
                        tx_state <= TX_BODY;
                    end
                end

                TX_BODY: begin
                    if (router_tx_ready) begin
                        // BODY accepted — immediately present TAIL
                        router_tx_flit <= {tx_dest_x_r, tx_dest_y_r,
                                           TYPE_TAIL,
                                           tx_data_reg[PAYLOAD_W-1 : 0]};
                        tx_state <= TX_TAIL;
                    end
                end

                TX_TAIL: begin
                    if (router_tx_ready) begin
                        router_tx_valid <= 1'b0;
                        core_tx_ready   <= 1'b1;
                        tx_state        <= TX_IDLE;
                    end
                end

                default: tx_state <= TX_IDLE;
            endcase
        end
    end

    // =========================================================================
    // RX PATH
    // =========================================================================
    typedef enum logic [1:0] {
        RX_HEAD = 2'd0,
        RX_BODY = 2'd1,
        RX_TAIL = 2'd2,
        RX_PUSH = 2'd3
    } rx_state_t;

    rx_state_t              rx_state;
    logic [CORE_DATA_W-1:0] rx_data_reg;

    wire [FLIT_TYPE_W-1:0] rx_flit_type = router_rx_flit[DATA_WIDTH-(2*COORD_WIDTH)-1 -: FLIT_TYPE_W];
    wire [PAYLOAD_W-1:0]   rx_payload   = router_rx_flit[PAYLOAD_W-1:0];

    assign core_rx_data = rx_data_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state           <= RX_HEAD;
            router_rx_ready    <= 1'b1;
            core_rx_valid      <= 1'b0;
            latency_valid      <= 1'b0;
            latency_cycles_out <= '0;
            rx_data_reg        <= '0;
        end else begin
            latency_valid <= 1'b0;  // default: pulse for one cycle only

            case (rx_state)
                RX_HEAD: begin
                    router_rx_ready <= 1'b1;
                    if (router_rx_valid && router_rx_ready &&
                            rx_flit_type == TYPE_HEAD) begin
                        latency_cycles_out <= ts_counter - rx_payload[TS_WIDTH-1:0];
                        latency_valid      <= 1'b1;
                        rx_state           <= RX_BODY;
                    end
                end

                RX_BODY: begin
                    if (router_rx_valid && router_rx_ready &&
                            rx_flit_type == TYPE_BODY) begin
                        rx_data_reg[CORE_DATA_W-1 -: PAYLOAD_W] <= rx_payload;
                        rx_state <= RX_TAIL;
                    end
                end

                RX_TAIL: begin
                    if (router_rx_valid && router_rx_ready &&
                            rx_flit_type == TYPE_TAIL) begin
                        rx_data_reg[PAYLOAD_W-1:0] <= rx_payload;
                        router_rx_ready            <= 1'b0;
                        core_rx_valid              <= 1'b1;
                        rx_state                   <= RX_PUSH;
                    end
                end

                RX_PUSH: begin
                    if (core_rx_valid && core_rx_ready) begin
                        core_rx_valid   <= 1'b0;
                        router_rx_ready <= 1'b1;
                        rx_state        <= RX_HEAD;
                    end
                end

                default: rx_state <= RX_HEAD;
            endcase
        end
    end

endmodule
