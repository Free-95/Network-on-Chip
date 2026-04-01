// uart_rx.v
// 8N1 UART Receiver
// Samples at 16x oversampling. Outputs 1 byte per valid pulse.
// Baud = clk_freq / CLKS_PER_BIT

`timescale 1ns / 1ps

module uart_rx #(
    parameter CLKS_PER_BIT = 868  // 100 MHz / 115200
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx_serial,
    output reg  [7:0] rx_byte,
    output reg        rx_valid    // 1-cycle pulse when byte ready
);

    // States
    localparam S_IDLE    = 3'd0;
    localparam S_START   = 3'd1;
    localparam S_DATA    = 3'd2;
    localparam S_STOP    = 3'd3;

    reg [2:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shift_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            clk_cnt  <= 0;
            bit_idx  <= 0;
            shift_reg<= 0;
            rx_byte  <= 0;
            rx_valid <= 0;
        end else begin
            rx_valid <= 0;  // default
            case (state)

                S_IDLE: begin
                    if (rx_serial == 0) begin       // start bit detected
                        clk_cnt <= 0;
                        state   <= S_START;
                    end
                end

                S_START: begin
                    // wait to middle of start bit
                    if (clk_cnt == (CLKS_PER_BIT/2 - 1)) begin
                        if (rx_serial == 0) begin   // still low → valid start
                            clk_cnt <= 0;
                            bit_idx <= 0;
                            state   <= S_DATA;
                        end else begin
                            state   <= S_IDLE;      // glitch, abort
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                S_DATA: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt             <= 0;
                        shift_reg[bit_idx]  <= rx_serial;
                        if (bit_idx == 7) begin
                            bit_idx <= 0;
                            state   <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                S_STOP: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        rx_valid <= 1;
                        rx_byte  <= shift_reg;
                        clk_cnt  <= 0;
                        state    <= S_IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
