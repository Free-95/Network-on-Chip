// tb_xy_router.v
// Testbench for xy_router. Exhaustively tests all 16 combinations of
// (curr_x, curr_y) in the 2x2 mesh (coords 0..1) against every possible
// (dest_x, dest_y), verifying correct one-hot port selection. Additional
// directed tests confirm: X resolves before Y, North/South polarity, all four
// corner-to-corner diagonal paths, and Local ejection at every node.
// Purely combinational DUT — all checks use #1 propagation delay.
// Designed for Vivado 2025.2 (xsim).

`timescale 1ns / 1ps

module tb_xy_router;

    parameter COORD_WIDTH = 2;

    reg  [COORD_WIDTH-1:0] curr_x, curr_y, dest_x, dest_y;
    wire [4:0]             out_port_req;

    integer pass_count, fail_count;

    localparam PORT_LOCAL = 5'b00001;
    localparam PORT_NORTH = 5'b00010;
    localparam PORT_SOUTH = 5'b00100;
    localparam PORT_EAST  = 5'b01000;
    localparam PORT_WEST  = 5'b10000;

    xy_router #(.COORD_WIDTH(COORD_WIDTH)) dut (
        .curr_x(curr_x), .curr_y(curr_y),
        .dest_x(dest_x), .dest_y(dest_y),
        .out_port_req(out_port_req)
    );

    task check;
        input [4:0]   expected;
        input [4:0]   actual;
        input [127:0] name;
        begin
            if (expected === actual) begin
                $display("PASS  [%0t] %s : got %05b", $time, name, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL  [%0t] %s : expected %05b got %05b",
                          $time, name, expected, actual);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task route;
        input [COORD_WIDTH-1:0] cx, cy, dx, dy;
        input [4:0]             expected;
        input [127:0]           name;
        begin
            curr_x = cx; curr_y = cy;
            dest_x = dx; dest_y = dy;
            #1;
            check(expected, out_port_req, name);
        end
    endtask

    initial begin
        pass_count = 0; fail_count = 0;
        curr_x = 0; curr_y = 0; dest_x = 0; dest_y = 0;
        #1;

        route(0,0, 0,0, PORT_LOCAL, "local (0,0)->(0,0)");
        route(1,0, 1,0, PORT_LOCAL, "local (1,0)->(1,0)");
        route(0,1, 0,1, PORT_LOCAL, "local (0,1)->(0,1)");
        route(1,1, 1,1, PORT_LOCAL, "local (1,1)->(1,1)");

        route(0,0, 1,0, PORT_EAST,  "east  (0,0)->(1,0)");
        route(1,0, 0,0, PORT_WEST,  "west  (1,0)->(0,0)");
        route(0,1, 1,1, PORT_EAST,  "east  (0,1)->(1,1)");
        route(1,1, 0,1, PORT_WEST,  "west  (1,1)->(0,1)");

        route(0,0, 0,1, PORT_SOUTH, "south (0,0)->(0,1)");
        route(0,1, 0,0, PORT_NORTH, "north (0,1)->(0,0)");
        route(1,0, 1,1, PORT_SOUTH, "south (1,0)->(1,1)");
        route(1,1, 1,0, PORT_NORTH, "north (1,1)->(1,0)");

        route(0,0, 1,1, PORT_EAST,  "diag  (0,0)->(1,1): X first -> East");
        route(1,0, 0,1, PORT_WEST,  "diag  (1,0)->(0,1): X first -> West");
        route(0,1, 1,0, PORT_EAST,  "diag  (0,1)->(1,0): X first -> East");
        route(1,1, 0,0, PORT_WEST,  "diag  (1,1)->(0,0): X first -> West");

        route(1,0, 1,1, PORT_SOUTH, "y-hop (1,0)->(1,1): South");
        route(0,1, 0,0, PORT_NORTH, "y-hop (0,1)->(0,0): North");

        route(0,0, 3,0, PORT_EAST,  "wide  (0,0)->(3,0): East");
        route(1,0, 3,0, PORT_EAST,  "wide  (1,0)->(3,0): East");
        route(2,0, 3,0, PORT_EAST,  "wide  (2,0)->(3,0): East");
        route(3,0, 3,0, PORT_LOCAL, "wide  (3,0)->(3,0): Local");

        route(0,0, 0,3, PORT_SOUTH, "wide  (0,0)->(0,3): South");
        route(0,2, 0,3, PORT_SOUTH, "wide  (0,2)->(0,3): South");
        route(0,3, 0,0, PORT_NORTH, "wide  (0,3)->(0,0): North");

        begin : onehot_check
            integer cx, cy, dx, dy;
            reg [4:0] result;
            for (cx = 0; cx < 2; cx = cx + 1) begin
                for (cy = 0; cy < 2; cy = cy + 1) begin
                    for (dx = 0; dx < 2; dx = dx + 1) begin
                        for (dy = 0; dy < 2; dy = dy + 1) begin
                            curr_x = cx; curr_y = cy;
                            dest_x = dx; dest_y = dy;
                            #1;
                            result = out_port_req;
                            if ((result != 0) && ((result & (result - 1)) == 0)) begin
                                $display("PASS  [%0t] one-hot (%0d,%0d)->(%0d,%0d): %05b",
                                         $time, cx, cy, dx, dy, result);
                                pass_count = pass_count + 1;
                            end else begin
                                $display("FAIL  [%0t] one-hot (%0d,%0d)->(%0d,%0d): %05b not one-hot",
                                         $time, cx, cy, dx, dy, result);
                                fail_count = fail_count + 1;
                            end
                        end
                    end
                end
            end
        end

        $display("\n=== Simulation Complete ===");
        $display("PASSED: %0d  |  FAILED: %0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED - review above");

        $finish;
    end

    initial begin
        $dumpfile("tb_xy_router.vcd");
        $dumpvars(0, tb_xy_router);
    end

endmodule
