// switch_allocator.sv
// Resolves routing conflicts using 5 independent Round-Robin arbiters.
// Takes in 5 one-hot request vectors (from the 5 input ports' XY routers)
// and transposes them to generate 5 one-hot grant vectors (for the crossbar).

`timescale 1ns / 1ps

// ============================================================================
// Sub-Module: 5-Bit Round-Robin Arbiter
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

    // Mask off requests from ports that have recently been granted
    assign masked_req = req & mask_reg;

    // Simple Fixed-Priority Arbiters
    // (The equation "req & ~(req - 1)" keeps the lowest-order '1' bit active)
    assign masked_grant   = masked_req & ~(masked_req - 1);
    assign unmasked_grant = req & ~(req - 1);

    // Grant request based on masked_grant 
    // If the mask blocked everything (everyone currently requesting has already had a turn), it ignores the mask and wraps around, finding the lowest-order bit in the raw 'req' instead
    assign grant = (masked_req == 0) ? unmasked_grant : masked_grant;

    // Update the rotating priority mask
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mask_reg <= {PORTS{1'b1}}; // Reset: All ports have equal priority
        end else if (grant != 0) begin
            // If a port is granted, update the mask to block that port and other lower-indexed ports on the next cycle.
            mask_reg <= ~(grant | (grant - 1));
        end
    end

endmodule

// ============================================================================
// Top-Level Module: Switch Allocator Matrix
// ============================================================================
module switch_allocator (
    input  logic clk,
    input  logic rst_n,
    
    input  logic [4:0][4:0] req_in,
    
    output logic [4:0][4:0] grant_out
);

    genvar out_port, in_port;

    generate
        for (out_port = 0; out_port < 5; out_port = out_port + 1) begin : gen_arbiters
            
            logic [4:0] arb_req;
            logic [4:0] arb_grant;

            for (in_port = 0; in_port < 5; in_port = in_port + 1) begin : gen_transpose
                assign arb_req[in_port] = req_in[in_port][out_port];
            end

            round_robin_arbiter #(.PORTS(5)) arbiter_inst (
                .clk  (clk),
                .rst_n(rst_n),
                .req  (arb_req),
                .grant(arb_grant)
            );

            assign grant_out[out_port] = arb_grant;
            
        end
    endgenerate

endmodule