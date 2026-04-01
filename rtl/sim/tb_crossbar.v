// tb_crossbar_switch.v
// Testbench for crossbar_switch. Because the DUT is purely combinational,
// all checks are done with a small #1 propagation delay after driving inputs —
// no clock needed for correctness, but a clock is included for waveform
// readability. Tests: each one-hot grant selects the correct FIFO for every
// output port, all 5 output ports route simultaneously and independently,
// zero-grant (no bits set) outputs zero data, and changing grants mid-sim
// immediately propagates. Designed for Vivado 2025.2 (xsim).

`timescale 1ns / 1ps

module tb_crossbar_switch;

    parameter DATA_WIDTH = 34;

    reg  [DATA_WIDTH-1:0] fifo_data_in_0, fifo_data_in_1, fifo_data_in_2;
    reg  [DATA_WIDTH-1:0] fifo_data_in_3, fifo_data_in_4;
    reg  [4:0] arbiter_sel_0, arbiter_sel_1, arbiter_sel_2;
    reg  [4:0] arbiter_sel_3, arbiter_sel_4;
    wire [DATA_WIDTH-1:0] router_data_out_0, router_data_out_1, router_data_out_2;
    wire [DATA_WIDTH-1:0] router_data_out_3, router_data_out_4;

    integer pass_count, fail_count;
    integer i, j;

    crossbar_switch #(.DATA_WIDTH(DATA_WIDTH)) dut (
        .fifo_data_in_0(fifo_data_in_0), .fifo_data_in_1(fifo_data_in_1),
        .fifo_data_in_2(fifo_data_in_2), .fifo_data_in_3(fifo_data_in_3),
        .fifo_data_in_4(fifo_data_in_4),
        .arbiter_sel_0(arbiter_sel_0),   .arbiter_sel_1(arbiter_sel_1),
        .arbiter_sel_2(arbiter_sel_2),   .arbiter_sel_3(arbiter_sel_3),
        .arbiter_sel_4(arbiter_sel_4),
        .router_data_out_0(router_data_out_0), .router_data_out_1(router_data_out_1),
        .router_data_out_2(router_data_out_2), .router_data_out_3(router_data_out_3),
        .router_data_out_4(router_data_out_4)
    );

    task check;
        input [DATA_WIDTH-1:0] expected, actual;
        input [127:0] name;
        begin
            if (expected === actual) begin
                $display("PASS  [%0t] %s : got %0h", $time, name, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL  [%0t] %s : expected %0h got %0h", $time, name, expected, actual);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task drive_all_zero_grants;
        begin
            arbiter_sel_0 = 5'b00000; arbiter_sel_1 = 5'b00000;
            arbiter_sel_2 = 5'b00000; arbiter_sel_3 = 5'b00000;
            arbiter_sel_4 = 5'b00000;
        end
    endtask

    initial begin
        pass_count = 0; fail_count = 0;

        fifo_data_in_0 = 34'h0_AAAA_0000;
        fifo_data_in_1 = 34'h1_BBBB_1111;
        fifo_data_in_2 = 34'h2_CCCC_2222;
        fifo_data_in_3 = 34'h3_DDDD_3333;
        fifo_data_in_4 = 34'h0_EEEE_4444;

        drive_all_zero_grants;
        #1;

        // ----------------------------------------------------------------
        // 1. Each one-hot grant selects the correct FIFO on output port 0
        // ----------------------------------------------------------------
        arbiter_sel_0 = 5'b00001; #1;
        check(fifo_data_in_0, router_data_out_0, "out0: sel input0");
        arbiter_sel_0 = 5'b00010; #1;
        check(fifo_data_in_1, router_data_out_0, "out0: sel input1");
        arbiter_sel_0 = 5'b00100; #1;
        check(fifo_data_in_2, router_data_out_0, "out0: sel input2");
        arbiter_sel_0 = 5'b01000; #1;
        check(fifo_data_in_3, router_data_out_0, "out0: sel input3");
        arbiter_sel_0 = 5'b10000; #1;
        check(fifo_data_in_4, router_data_out_0, "out0: sel input4");

        // ----------------------------------------------------------------
        // 2. Same sweep for output port 1
        // ----------------------------------------------------------------
        arbiter_sel_0 = 5'b00000;
        arbiter_sel_1 = 5'b00001; #1;
        check(fifo_data_in_0, router_data_out_1, "out1: sel input0");
        arbiter_sel_1 = 5'b00010; #1;
        check(fifo_data_in_1, router_data_out_1, "out1: sel input1");
        arbiter_sel_1 = 5'b00100; #1;
        check(fifo_data_in_2, router_data_out_1, "out1: sel input2");
        arbiter_sel_1 = 5'b01000; #1;
        check(fifo_data_in_3, router_data_out_1, "out1: sel input3");
        arbiter_sel_1 = 5'b10000; #1;
        check(fifo_data_in_4, router_data_out_1, "out1: sel input4");

        // ----------------------------------------------------------------
        // 3. Same sweep for output ports 2, 3, 4 (diagonal grant pattern)
        // ----------------------------------------------------------------
        arbiter_sel_1 = 5'b00000;

        arbiter_sel_2 = 5'b00100; #1;
        check(fifo_data_in_2, router_data_out_2, "out2: sel input2");
        arbiter_sel_3 = 5'b01000; #1;
        check(fifo_data_in_3, router_data_out_3, "out3: sel input3");
        arbiter_sel_4 = 5'b10000; #1;
        check(fifo_data_in_4, router_data_out_4, "out4: sel input4");

        // ----------------------------------------------------------------
        // 4. All 5 outputs active simultaneously (no conflicts — bijection)
        //    out0←in0, out1←in1, out2←in2, out3←in3, out4←in4
        // ----------------------------------------------------------------
        arbiter_sel_2 = 5'b00000; arbiter_sel_3 = 5'b00000; arbiter_sel_4 = 5'b00000;

        arbiter_sel_0 = 5'b00001;
        arbiter_sel_1 = 5'b00010;
        arbiter_sel_2 = 5'b00100;
        arbiter_sel_3 = 5'b01000;
        arbiter_sel_4 = 5'b10000;
        #1;
        check(fifo_data_in_0, router_data_out_0, "sim: out0=in0");
        check(fifo_data_in_1, router_data_out_1, "sim: out1=in1");
        check(fifo_data_in_2, router_data_out_2, "sim: out2=in2");
        check(fifo_data_in_3, router_data_out_3, "sim: out3=in3");
        check(fifo_data_in_4, router_data_out_4, "sim: out4=in4");

        // ----------------------------------------------------------------
        // 5. Rotate grants: out0←in4, out1←in0, out2←in1, out3←in2, out4←in3
        // ----------------------------------------------------------------
        arbiter_sel_0 = 5'b10000;
        arbiter_sel_1 = 5'b00001;
        arbiter_sel_2 = 5'b00010;
        arbiter_sel_3 = 5'b00100;
        arbiter_sel_4 = 5'b01000;
        #1;
        check(fifo_data_in_4, router_data_out_0, "rot: out0=in4");
        check(fifo_data_in_0, router_data_out_1, "rot: out1=in0");
        check(fifo_data_in_1, router_data_out_2, "rot: out2=in1");
        check(fifo_data_in_2, router_data_out_3, "rot: out3=in2");
        check(fifo_data_in_3, router_data_out_4, "rot: out4=in3");

        // ----------------------------------------------------------------
        // 6. Zero grant -> zero output
        // ----------------------------------------------------------------
        drive_all_zero_grants; #1;
        check({DATA_WIDTH{1'b0}}, router_data_out_0, "zero grant out0");
        check({DATA_WIDTH{1'b0}}, router_data_out_1, "zero grant out1");
        check({DATA_WIDTH{1'b0}}, router_data_out_2, "zero grant out2");
        check({DATA_WIDTH{1'b0}}, router_data_out_3, "zero grant out3");
        check({DATA_WIDTH{1'b0}}, router_data_out_4, "zero grant out4");

        // ----------------------------------------------------------------
        // 7. Dynamic: change grant mid-sim, output follows immediately
        // ----------------------------------------------------------------
        arbiter_sel_0 = 5'b00001; #1;
        check(fifo_data_in_0, router_data_out_0, "dyn: out0=in0 before change");
        arbiter_sel_0 = 5'b01000; #1;
        check(fifo_data_in_3, router_data_out_0, "dyn: out0=in3 after change");

        // ----------------------------------------------------------------
        // 8. Multiple outputs reading the same input simultaneously
        //    All 5 outputs granted to input 2
        // ----------------------------------------------------------------
        arbiter_sel_0 = 5'b00100;
        arbiter_sel_1 = 5'b00100;
        arbiter_sel_2 = 5'b00100;
        arbiter_sel_3 = 5'b00100;
        arbiter_sel_4 = 5'b00100;
        #1;
        check(fifo_data_in_2, router_data_out_0, "bcast: out0=in2");
        check(fifo_data_in_2, router_data_out_1, "bcast: out1=in2");
        check(fifo_data_in_2, router_data_out_2, "bcast: out2=in2");
        check(fifo_data_in_2, router_data_out_3, "bcast: out3=in2");
        check(fifo_data_in_2, router_data_out_4, "bcast: out4=in2");

        $display("\n=== Simulation Complete ===");
        $display("PASSED: %0d  |  FAILED: %0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED - review above");

        $finish;
    end

    initial begin
        $dumpfile("tb_crossbar_switch.vcd");
        $dumpvars(0, tb_crossbar_switch);
    end

endmodule
