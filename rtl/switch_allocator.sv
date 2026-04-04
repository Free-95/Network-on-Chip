// switch_allocator.sv
// Vivado 2025 compatible.
//
// VIVADO COMPATIBILITY CHANGES:
//   • i++ / out_port++ replaced with i = i + 1 / out_port = out_port + 1
//     (Vivado 2025 synthesis accepts ++ but some linters/tools warn; explicit is safer)
//   • All generate blocks have matching named begin..end labels
//   • logic [4:0][4:0] packed 2D array ports — fully supported in Vivado SV synthesis
//   • No typedef enum, no automatic tasks, no dynamic constructs — fully synthesisable

`timescale 1ns / 1ps

// ============================================================================
// Sub-Module: 5-bit Round-Robin Arbiter
// ============================================================================
module round_robin_arbiter #(
    parameter PORTS = 5
)(
    input  logic             clk,
    input  logic             rst_n,
    input  logic [PORTS-1:0] req,
    output logic [PORTS-1:0] grant
);
    logic [PORTS-1:0] mask_reg;
    logic [PORTS-1:0] masked_req;
    logic [PORTS-1:0] masked_grant;
    logic [PORTS-1:0] unmasked_grant;

    // Mask off ports that recently received a grant
    assign masked_req     = req & mask_reg;
    // Lowest-active-bit fixed-priority from masked set
    assign masked_grant   = masked_req   & (~masked_req   + {{(PORTS-1){1'b0}}, 1'b1});
    // Lowest-active-bit fixed-priority from full request (wrap-around fallback)
    assign unmasked_grant = req          & (~req           + {{(PORTS-1){1'b0}}, 1'b1});

    // Use masked grant unless the mask has blocked everything
    assign grant = (masked_req == {PORTS{1'b0}}) ? unmasked_grant : masked_grant;

    // Advance priority mask: block current winner and all lower-indexed ports
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mask_reg <= {PORTS{1'b1}};      // reset: all ports equal priority
        end else if (grant != {PORTS{1'b0}}) begin
            // Mask = bits above the winner (i.e. ~(grant | (grant-1)))
            // Vivado-safe: written as two separate operations
            mask_reg <= ~(grant | (grant - {{(PORTS-1){1'b0}}, 1'b1}));
        end
        // No grant this cycle: mask unchanged
    end

endmodule


// ============================================================================
// Top-Level: Switch Allocator (5 independent output-port arbiters)
// ============================================================================
module switch_allocator (
    input  logic clk,
    input  logic rst_n,

    // req_in[input_port][output_port] — one-hot per input port
    input  logic [4:0][4:0] req_in,

    // grant_out[output_port][input_port] — one-hot per output port
    output logic [4:0][4:0] grant_out
);

    genvar out_port;
    genvar in_port;

    generate
        for (out_port = 0; out_port < 5; out_port = out_port + 1) begin : gen_arbiters

            // Transpose: collect bit [out_port] from each input's request vector
            logic [4:0] arb_req;
            logic [4:0] arb_grant;

            for (in_port = 0; in_port < 5; in_port = in_port + 1) begin : gen_transpose
                assign arb_req[in_port] = req_in[in_port][out_port];
            end : gen_transpose

            round_robin_arbiter #(
                .PORTS (5)
            ) arbiter_inst (
                .clk   (clk),
                .rst_n (rst_n),
                .req   (arb_req),
                .grant (arb_grant)
            );

            assign grant_out[out_port] = arb_grant;

        end : gen_arbiters
    endgenerate

endmodule
