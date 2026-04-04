// crossbar_switch.sv
// Vivado 2025 compatible.
//
// VIVADO COMPATIBILITY CHANGES:
//   • i++ replaced with i = i + 1 in genvar for loop
//   • Named generate block label retained (switch_muxes)
//   • OR-reduction using {DATA_WIDTH{bit}} mask — fully synthesisable in Vivado
//   • No dynamic constructs; purely combinational assign statements

`timescale 1ns / 1ps

module crossbar_switch #(
    parameter DATA_WIDTH = 34
)(
    input  logic [4:0][DATA_WIDTH-1:0] fifo_data_in,
    input  logic [4:0][4:0]            arbiter_sel,
    output logic [4:0][DATA_WIDTH-1:0] router_data_out
);

    genvar i;
    generate
        for (i = 0; i < 5; i = i + 1) begin : switch_muxes
            // One-hot OR-mask: route selected FIFO data to this output port
            assign router_data_out[i] =
                ({DATA_WIDTH{arbiter_sel[i][0]}} & fifo_data_in[0]) |
                ({DATA_WIDTH{arbiter_sel[i][1]}} & fifo_data_in[1]) |
                ({DATA_WIDTH{arbiter_sel[i][2]}} & fifo_data_in[2]) |
                ({DATA_WIDTH{arbiter_sel[i][3]}} & fifo_data_in[3]) |
                ({DATA_WIDTH{arbiter_sel[i][4]}} & fifo_data_in[4]);
        end : switch_muxes
    endgenerate

endmodule
