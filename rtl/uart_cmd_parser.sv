// uart_cmd_parser.sv
// ============================================================================
// Parses the ASCII command stream from UART and drives a NoC flit injection.
//
// Protocol (ASCII, terminated by CR or LF):
//   SEND <node> <payload_string>
//
// <node>  is a single decimal digit 0-3 mapping to 2x2 grid coordinates:
//   0 → (x=0,y=0)   1 → (x=1,y=0)
//   2 → (x=0,y=1)   3 → (x=1,y=1)
//
// Flit format  (DATA_WIDTH=34):
//   [33]    dest_x   (1 bit)
//   [32]    dest_y   (1 bit)
//   [31: 0] payload  (first 4 payload bytes, zero-padded)
//
// After parsing:
//   flit_out   – assembled 34-bit flit
//   flit_valid – 1-cycle pulse; user should hold until rx_ready
// ============================================================================

`timescale 1ns / 1ps

module uart_cmd_parser #(
    parameter DATA_WIDTH  = 34,
    parameter COORD_WIDTH = 1
)(
    input  logic        clk,
    input  logic        rst_n,

    // From UART Rx
    input  logic [7:0]  rx_byte,
    input  logic        rx_valid,

    // To NoC local-port injection
    output logic [DATA_WIDTH-1:0] flit_out,
    output logic                  flit_valid,

    // Error indicator (bad command syntax)
    output logic                  parse_error
);

    // -----------------------------------------------------------------------
    // States
    // -----------------------------------------------------------------------
    typedef enum logic [3:0] {
        ST_IDLE,        // waiting for 'S'
        ST_S,           // got 'S', waiting 'E'
        ST_SE,
        ST_SEN,
        ST_SEND,        // got 'SEND', waiting space
        ST_NODE,        // waiting node digit
        ST_SPACE2,      // waiting space after node
        ST_PAYLOAD,     // collecting payload bytes
        ST_EMIT         // emit flit for one cycle
    } state_t;

    state_t state;

    // -----------------------------------------------------------------------
    // Internal registers
    // -----------------------------------------------------------------------
    logic [COORD_WIDTH-1:0] dest_x_r, dest_y_r;
    logic [31:0]            payload_r;
    logic [1:0]             pay_idx;    // byte index 0-3 within 32-bit payload

    // -----------------------------------------------------------------------
    // Convenience: map node digit → coordinates
    // -----------------------------------------------------------------------
    function automatic void node_to_coord(
        input  logic [3:0] node,
        output logic [COORD_WIDTH-1:0] dx,
        output logic [COORD_WIDTH-1:0] dy
    );
        case (node)
            4'd0: begin dx = 1'b0; dy = 1'b0; end
            4'd1: begin dx = 1'b1; dy = 1'b0; end
            4'd2: begin dx = 1'b0; dy = 1'b1; end
            4'd3: begin dx = 1'b1; dy = 1'b1; end
            default: begin dx = 1'b0; dy = 1'b0; end
        endcase
    endfunction

    // -----------------------------------------------------------------------
    // FSM
    // -----------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= ST_IDLE;
            dest_x_r    <= '0;
            dest_y_r    <= '0;
            payload_r   <= '0;
            pay_idx     <= '0;
            flit_out    <= '0;
            flit_valid  <= 1'b0;
            parse_error <= 1'b0;
        end else begin
            flit_valid  <= 1'b0;
            parse_error <= 1'b0;

            case (state)

                ST_IDLE: begin
                    if (rx_valid && (rx_byte == "S"))
                        state <= ST_S;
                end

                ST_S: begin
                    if (rx_valid) begin
                        if (rx_byte == "E") state <= ST_SE;
                        else begin parse_error <= 1; state <= ST_IDLE; end
                    end
                end

                ST_SE: begin
                    if (rx_valid) begin
                        if (rx_byte == "N") state <= ST_SEN;
                        else begin parse_error <= 1; state <= ST_IDLE; end
                    end
                end

                ST_SEN: begin
                    if (rx_valid) begin
                        if (rx_byte == "D") state <= ST_SEND;
                        else begin parse_error <= 1; state <= ST_IDLE; end
                    end
                end

                ST_SEND: begin
                    if (rx_valid) begin
                        if (rx_byte == " ") state <= ST_NODE;
                        else begin parse_error <= 1; state <= ST_IDLE; end
                    end
                end

                ST_NODE: begin
                    if (rx_valid) begin
                        if (rx_byte >= "0" && rx_byte <= "3") begin
                            logic [COORD_WIDTH-1:0] dx, dy;
                            node_to_coord(rx_byte - "0", dx, dy);
                            dest_x_r <= dx;
                            dest_y_r <= dy;
                            state    <= ST_SPACE2;
                        end else begin
                            parse_error <= 1;
                            state       <= ST_IDLE;
                        end
                    end
                end

                ST_SPACE2: begin
                    if (rx_valid) begin
                        if (rx_byte == " ") begin
                            payload_r <= '0;
                            pay_idx   <= 2'd0;
                            state     <= ST_PAYLOAD;
                        end else begin
                            parse_error <= 1;
                            state       <= ST_IDLE;
                        end
                    end
                end

                ST_PAYLOAD: begin
                    if (rx_valid) begin
                        // CR, LF, or null terminates the command
                        if (rx_byte == 8'h0D || rx_byte == 8'h0A || rx_byte == 8'h00) begin
                            state <= ST_EMIT;
                        end else begin
                            // Pack up to 4 bytes MSB-first into payload_r
                            if (pay_idx < 4) begin
                                payload_r <= (payload_r << 8) | {24'b0, rx_byte};
                                pay_idx   <= pay_idx + 1;
                            end
                            // Extra bytes silently discarded (4-byte payload max)
                        end
                    end
                end

                ST_EMIT: begin
                    flit_out   <= {dest_x_r, dest_y_r, payload_r};
                    flit_valid <= 1'b1;
                    state      <= ST_IDLE;
                end

            endcase
        end
    end

endmodule
