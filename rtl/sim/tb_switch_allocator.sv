// tb_switch_allocator.sv
// SystemVerilog Testbench for the 5-port Switch Allocator.
// Tests: 
// 1. Reset and zero-request behavior.
// 2. Single isolated requests.
// 3. Simultaneous non-conflicting requests (Bijection).
// 4. Heavy Contention: All 5 inputs fighting for Output 0 to verify 
//    perfect Round-Robin rotation and wrap-around over 6 clock cycles.
// 5. Independent Contention: Output 0 and Output 1 experiencing different
//    levels of contention to prove the 5 arbiters operate independently.

`timescale 1ns / 1ps

module tb_switch_allocator;

    logic clk;
    logic rst_n;
    logic [4:0][4:0] input_reqs;
    logic [4:0][4:0] output_grants;

    int pass_count;
    int fail_count;

    switch_allocator uut (
        .clk(clk),
        .rst_n(rst_n),
        .req_in(input_reqs),
        .grant_out(output_grants)
    );

    always #5 clk = ~clk;

    task check_port(input int port, input logic [4:0] expected, input string name);
        if (output_grants[port] === expected) begin
            $display("PASS  [%0t] %s : got %05b", $time, name, output_grants[port]);
            pass_count++;
        end else begin
            $display("FAIL  [%0t] %s : expected %05b, got %05b", $time, name, expected, output_grants[port]);
            fail_count++;
        end
    endtask

    task clear_reqs();
        input_reqs = 0;
    endtask

    initial begin
        clk = 0;
        rst_n = 0;
        clear_reqs();
        pass_count = 0;
        fail_count = 0;

        // ----------------------------------------------------------------
        // 1. Reset
        // ----------------------------------------------------------------
        @(negedge clk);
        rst_n = 0;
        @(negedge clk);
        rst_n = 1; 
        #1;
        check_port(0, 5'b00000, "Reset, No grants for Out 0");
        check_port(1, 5'b00000, "Reset, No grants for Out 1");

        // ----------------------------------------------------------------
        // 2. Single Isolated Request (Input 0 requests Output 2)
        // ----------------------------------------------------------------
        @(negedge clk);
        input_reqs[0] = 5'b00100; 
        #1;
        check_port(2, 5'b00001, "Isolated, In 0 wins Out 2");
        check_port(0, 5'b00000, "Isolated, Out 0 correctly empty");

        // ----------------------------------------------------------------
        // 3. Simultaneous Non-Conflicting (Bijection)
        // ----------------------------------------------------------------
        @(negedge clk);
        input_reqs[0] = 5'b00001;
        input_reqs[1] = 5'b00010;
        input_reqs[2] = 5'b00100;
        input_reqs[3] = 5'b01000;
        input_reqs[4] = 5'b10000;
        #1;
        check_port(0, 5'b00001, "Bijection, In 0 wins Out 0");
        check_port(1, 5'b00010, "Bijection, In 1 wins Out 1");
        check_port(2, 5'b00100, "Bijection, In 2 wins Out 2");
        check_port(3, 5'b01000, "Bijection, In 3 wins Out 3");
        check_port(4, 5'b10000, "Bijection, In 4 wins Out 4");

        // ----------------------------------------------------------------
        // 4. Heavy Contention: Perfect Round-Robin Rotation
        // ALL 5 inputs constantly request Output 0 (Bit 0).
        // We expect the grant to cycle 0 -> 1 -> 2 -> 3 -> 4 -> 0.
        // ----------------------------------------------------------------
        
        // Reset mask_reg
        @(negedge clk);
        clear_reqs();
        rst_n = 0; 
        @(negedge clk);
        rst_n = 1;

        for (int i = 0; i < 5; i++) begin
            input_reqs[i] = 5'b00001; 
        end
        
        // Cycle 1
        #1; check_port(0, 5'b00001, "RR Cycle 1, In 0 wins");
        
        // Cycle 2
        @(negedge clk); 
        #1; check_port(0, 5'b00010, "RR Cycle 2, In 1 wins");
        
        // Cycle 3
        @(negedge clk); 
        #1; check_port(0, 5'b00100, "RR Cycle 3, In 2 wins");
        
        // Cycle 4
        @(negedge clk); 
        #1; check_port(0, 5'b01000, "RR Cycle 4, In 3 wins");
        
        // Cycle 5
        @(negedge clk); 
        #1; check_port(0, 5'b10000, "RR Cycle 5, In 4 wins");
        
        // Cycle 6 
        @(negedge clk); 
        #1; check_port(0, 5'b00001, "RR Cycle 6, Wrap around to In 0");

        // ----------------------------------------------------------------
        // 5. Independent Contention
        // ----------------------------------------------------------------

        // Reset mask_reg
        @(negedge clk);
        rst_n = 0; 
        @(negedge clk);
        rst_n = 1;

        @(negedge clk);
        clear_reqs();
        // In 2 & 3 want Out 0 (Bit 0 high)
        input_reqs[2] = 5'b00001; 
        input_reqs[3] = 5'b00001; 
        
        // In 0 & 4 want Out 1 (Bit 1 high)
        input_reqs[0] = 5'b00010; 
        input_reqs[4] = 5'b00010; 

        // Cycle 1
        #1; 
        check_port(0, 5'b00100, "Indep C1, In 2 wins Out 0");
        check_port(1, 5'b00001, "Indep C1, In 0 wins Out 1");

        // Cycle 2
        @(negedge clk);
        #1; 
        check_port(0, 5'b01000, "Indep C2, In 3 wins Out 0");
        check_port(1, 5'b10000, "Indep C2, In 4 wins Out 1");
        
        // Cycle 3 (Wrap around)
        @(negedge clk);
        #1; 
        check_port(0, 5'b00100, "Indep C3, Wrap back to In 2 for Out 0");
        check_port(1, 5'b00001, "Indep C3, Wrap back to In 0 for Out 1");

        $display("\n=== Simulation Complete ===");
        $display("PASSED: %0d  |  FAILED: %0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED - review above");

        $finish;
    end

    // VCD Dumping
    initial begin
        $dumpfile("tb_switch_allocator.vcd");
        $dumpvars(0, tb_switch_allocator);
    end

endmodule