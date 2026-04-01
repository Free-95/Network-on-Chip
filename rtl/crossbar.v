// crossbar_switch.v
// Purely combinational 5x5 multiplexer matrix. Routes flit data from any of
// the 5 input FIFOs (Local, North, South, East, West) to any of the 5 output
// ports. Each output port has a dedicated 5-to-1 mux whose select line is the
// one-hot grant vector produced by that port's Round-Robin Arbiter. Up to 5
// simultaneous non-conflicting transfers are supported per cycle. No registers;
// output is valid within one combinational delay of the arbiter grant settling.
// Synthesizable for Vivado 2025.2.

`timescale 1ns / 1ps

module crossbar_switch #(
    parameter DATA_WIDTH = 34
)(
    input  wire [DATA_WIDTH-1:0] fifo_data_in_0,
    input  wire [DATA_WIDTH-1:0] fifo_data_in_1,
    input  wire [DATA_WIDTH-1:0] fifo_data_in_2,
    input  wire [DATA_WIDTH-1:0] fifo_data_in_3,
    input  wire [DATA_WIDTH-1:0] fifo_data_in_4,

    input  wire [4:0] arbiter_sel_0,
    input  wire [4:0] arbiter_sel_1,
    input  wire [4:0] arbiter_sel_2,
    input  wire [4:0] arbiter_sel_3,
    input  wire [4:0] arbiter_sel_4,

    output reg  [DATA_WIDTH-1:0] router_data_out_0,
    output reg  [DATA_WIDTH-1:0] router_data_out_1,
    output reg  [DATA_WIDTH-1:0] router_data_out_2,
    output reg  [DATA_WIDTH-1:0] router_data_out_3,
    output reg  [DATA_WIDTH-1:0] router_data_out_4
);

    wire [DATA_WIDTH-1:0] inputs [0:4];

    assign inputs[0] = fifo_data_in_0;
    assign inputs[1] = fifo_data_in_1;
    assign inputs[2] = fifo_data_in_2;
    assign inputs[3] = fifo_data_in_3;
    assign inputs[4] = fifo_data_in_4;

    function [DATA_WIDTH-1:0] mux5;
        input [DATA_WIDTH-1:0] d0, d1, d2, d3, d4;
        input [4:0] sel;
        begin
            case (sel)
                5'b00001: mux5 = d0;
                5'b00010: mux5 = d1;
                5'b00100: mux5 = d2;
                5'b01000: mux5 = d3;
                5'b10000: mux5 = d4;
                default:  mux5 = {DATA_WIDTH{1'b0}};
            endcase
        end
    endfunction

    always @(*) begin
        router_data_out_0 = mux5(fifo_data_in_0, fifo_data_in_1, fifo_data_in_2,
                                  fifo_data_in_3, fifo_data_in_4, arbiter_sel_0);
        router_data_out_1 = mux5(fifo_data_in_0, fifo_data_in_1, fifo_data_in_2,
                                  fifo_data_in_3, fifo_data_in_4, arbiter_sel_1);
        router_data_out_2 = mux5(fifo_data_in_0, fifo_data_in_1, fifo_data_in_2,
                                  fifo_data_in_3, fifo_data_in_4, arbiter_sel_2);
        router_data_out_3 = mux5(fifo_data_in_0, fifo_data_in_1, fifo_data_in_2,
                                  fifo_data_in_3, fifo_data_in_4, arbiter_sel_3);
        router_data_out_4 = mux5(fifo_data_in_0, fifo_data_in_1, fifo_data_in_2,
                                  fifo_data_in_3, fifo_data_in_4, arbiter_sel_4);
    end

endmodule
