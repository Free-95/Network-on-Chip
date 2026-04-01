// uart_tx.v
// 8N1 UART Transmitter
// Accepts 1 byte + tx_start pulse. Holds tx_busy high during transmission.

`timescale 1ns / 1ps

module uart_tx #(
    parameter CLKS_PER_BIT = 868
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] tx_byte,
    input  wire       tx_start,
    output reg        tx_serial,
    output reg        tx_busy
);

    localparam S_IDLE  = 2'd0;
    localparam S_START = 2'd1;
    localparam S_DATA  = 2'd2;
    localparam S_STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shift_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            tx_serial <= 1;
            tx_busy   <= 0;
            clk_cnt   <= 0;
            bit_idx   <= 0;
            shift_reg <= 0;
        end else begin
            case (state)

                S_IDLE: begin
                    tx_serial <= 1;
                    tx_busy   <= 0;
                    if (tx_start) begin
                        shift_reg <= tx_byte;
                        tx_busy   <= 1;
                        clk_cnt   <= 0;
                        state     <= S_START;
                    end
                end

                S_START: begin
                    tx_serial <= 0;     // start bit
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 0;
                        bit_idx <= 0;
                        state   <= S_DATA;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                S_DATA: begin
                    tx_serial <= shift_reg[bit_idx];
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 0;
                        if (bit_idx == 7) begin
                            state   <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                S_STOP: begin
                    tx_serial <= 1;     // stop bit
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 0;
                        state   <= S_IDLE;
                        tx_busy <= 0;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

            endcase
        end
    end

endmodule
