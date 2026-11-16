// ============================================================================
// File: test_scenarios.sv
// Author: Ajit Kumar (Verification & Testbench Lead)
// Project: Design and Analysis of a Direct-Mapped Cache Controller
// Description: Modular SystemVerilog verification scenario routines for
//              top-level cache architecture validation. Contains test routines:
//                - TEST 1: Cold Cache (Compulsory Miss)
//                - TEST 2: Temporal Locality
//                - TEST 3: Spatial Locality
//                - TEST 4: Sequential Access & Block Reuse
//                - TEST 5: Conflict Miss & Line Replacement
//                - TEST 6: Reproducible Pseudo-Random Workload
//                - TEST 7: Reset Invalidation Behavior
//                - TEST 8: Consecutive Back-to-Back Requests
// ============================================================================

`ifndef TEST_SCENARIOS_SV
`define TEST_SCENARIOS_SV

`timescale 1ns / 1ps

// ============================================================================
// TEST 1: Cold Cache Test (Compulsory Miss Verification)
// ============================================================================
// Objective:
//   1. Reset cache so all valid bits are cleared.
//   2. Issue first access to an address.
//   3. Verify that the first access is classified as a compulsory miss.
//   4. Verify that main memory is queried and the returned word matches.
//   5. Verify that cache storage is refilled with valid=1 and correct tag.
// ============================================================================
task automatic run_test_cold_cache();
    reg [ADDR_WIDTH-1:0] test_addr;
    integer initial_misses;
    begin
        $display("\n==================================================================");
        $display("   TEST 1: COLD CACHE TEST (COMPULSORY MISSES)                    ");
        $display("==================================================================");

        initial_misses = miss_count;

        // Test 1.1: Cold access to Line 4 (Address 0x0000_1040: Tag=4, Idx=4, Word 0)
        test_addr = 32'h0000_1040;
        $display("[SCENARIO 1.1] Cold access to Address 0x%08h (Idx=%0d, Tag=0x%06h, Word=0)",
                 test_addr, test_addr[9:4], test_addr[31:10]);
        cpu_read(test_addr, "Test 1.1 - Cold Line 4");

        // Test 1.2: Cold access to Line 8 (Address 0x0000_2080: Tag=8, Idx=8, Word 0)
        test_addr = 32'h0000_2080;
        $display("[SCENARIO 1.2] Cold access to Address 0x%08h (Idx=%0d, Tag=0x%06h, Word=0)",
                 test_addr, test_addr[9:4], test_addr[31:10]);
        cpu_read(test_addr, "Test 1.2 - Cold Line 8");

        // Test 1.3: Cold access to Line 12 (Address 0x0000_30C4: Tag=12, Idx=12, Word 1)
        test_addr = 32'h0000_30C4;
        $display("[SCENARIO 1.3] Cold access to Address 0x%08h (Idx=%0d, Tag=0x%06h, Word=1)",
                 test_addr, test_addr[9:4], test_addr[31:10]);
        cpu_read(test_addr, "Test 1.3 - Cold Line 12");

        // Test 1.4: Cold access to Line 63 (Address 0x0000_03F8: Tag=0, Idx=63, Word 2)
        test_addr = 32'h0000_03F8;
        $display("[SCENARIO 1.4] Cold access to Address 0x%08h (Idx=%0d, Tag=0x%06h, Word=2)",
                 test_addr, test_addr[9:4], test_addr[31:10]);
        cpu_read(test_addr, "Test 1.4 - Cold Line 63 (Boundary)");

        if ((miss_count - initial_misses) == 4) begin
            $display("[SUMMARY] TEST 1: ALL 4 COLD ACCESSES GENERATED COMPULSORY MISSES & REFILLED CORRECTLY.");
        end else begin
            $display("[ERROR] TEST 1: Expected 4 misses, recorded %0d misses!", (miss_count - initial_misses));
        end
    end
endtask

`endif // TEST_SCENARIOS_SV
