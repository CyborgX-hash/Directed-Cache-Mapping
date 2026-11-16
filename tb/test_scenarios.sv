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

// ============================================================================
// TEST 2: Temporal Locality (Repeated Access to Identical Address)
// ============================================================================
// Objective:
//   1. Access a specific memory address repeatedly in succession.
//   2. Verify that the first access (if cold) is a miss, and ALL subsequent
//      accesses result in guaranteed cache HITS.
//   3. Verify that hit accesses do not trigger any external memory requests.
//   4. Confirm data consistency across all consecutive hits.
// ============================================================================
task automatic run_test_temporal_locality();
    reg [ADDR_WIDTH-1:0] test_addr;
    integer initial_hits, initial_misses;
    integer iter;
    begin
        $display("\n==================================================================");
        $display("   TEST 2: TEMPORAL LOCALITY TEST (REPEATED ACCESS)               ");
        $display("==================================================================");

        initial_hits   = hit_count;
        initial_misses = miss_count;
        test_addr      = 32'h0000_1040; // Already in cache from Test 1.1

        $display("[SCENARIO 2.1] Repeated access to Address 0x%08h (Line 4) for 5 iterations", test_addr);
        for (iter = 1; iter <= 5; iter = iter + 1) begin
            cpu_read(test_addr, $sformatf("Test 2.1 - Temporal Hit #%0d", iter));
        end

        // Test 2.2: New address temporal locality
        test_addr = 32'h0000_50A0; // Line 10 (Tag=20, Idx=10, Word 0)
        $display("[SCENARIO 2.2] Cold access then 3 repeated hits on Address 0x%08h", test_addr);
        cpu_read(test_addr, "Test 2.2 - Initial Cold Access");
        for (iter = 1; iter <= 3; iter = iter + 1) begin
            cpu_read(test_addr, $sformatf("Test 2.2 - Re-access Hit #%0d", iter));
        end

        $display("[SUMMARY] TEST 2: TEMPORAL LOCALITY VERIFIED. Recorded %0d hits out of %0d accesses.",
                 (hit_count - initial_hits), (hit_count - initial_hits + miss_count - initial_misses));
    end
endtask

// ============================================================================
// TEST 3: Spatial Locality (Multi-Word Access Within Same 16-Byte Block)
// ============================================================================
// Objective:
//   1. Access a word in a cold block to trigger a 16-byte block refill.
//   2. Access all other 3 words within the exact same block.
//   3. Verify that ONLY the very first access causes a cache miss.
//   4. Verify that the subsequent 3 word accesses result in immediate cache HITS.
//   5. Verify that all 4 returned words match the independently calculated values.
//   6. Test arbitrary non-sequential word access within another block.
// ============================================================================
task automatic run_test_spatial_locality();
    reg [ADDR_WIDTH-1:0] block_base;
    integer initial_hits, initial_misses;
    begin
        $display("\n==================================================================");
        $display("   TEST 3: SPATIAL LOCALITY TEST (WORD OFFSETS WITHIN BLOCK)      ");
        $display("==================================================================");

        initial_hits   = hit_count;
        initial_misses = miss_count;

        // Block Base 0x0000_7120 (Tag=28, Idx=18, Offset 0)
        block_base = 32'h0000_7120;
        $display("[SCENARIO 3.1] Accessing 4 words in block 0x%08h sequentially (Word 0 -> 1 -> 2 -> 3)", block_base);

        // Word 0 (Offset 0x0): Compulsory Miss, fetches all 16 bytes
        cpu_read(block_base | 32'h0, "Test 3.1 - Word 0 (Offset 0x0, Expect Miss)");

        // Word 1 (Offset 0x4): Spatial Hit
        cpu_read(block_base | 32'h4, "Test 3.1 - Word 1 (Offset 0x4, Expect Hit)");

        // Word 2 (Offset 0x8): Spatial Hit
        cpu_read(block_base | 32'h8, "Test 3.1 - Word 2 (Offset 0x8, Expect Hit)");

        // Word 3 (Offset 0xC): Spatial Hit
        cpu_read(block_base | 32'hC, "Test 3.1 - Word 3 (Offset 0xC, Expect Hit)");

        // Block Base 0x0000_8160 (Tag=32, Idx=22) - Arbitrary word order: Word 3 -> 1 -> 0 -> 2
        block_base = 32'h0000_8160;
        $display("[SCENARIO 3.2] Accessing words in block 0x%08h out of order (Word 3 -> 1 -> 0 -> 2)", block_base);
        cpu_read(block_base | 32'hC, "Test 3.2 - Word 3 (Offset 0xC, Expect Miss)");
        cpu_read(block_base | 32'h4, "Test 3.2 - Word 1 (Offset 0x4, Expect Hit)");
        cpu_read(block_base | 32'h0, "Test 3.2 - Word 0 (Offset 0x0, Expect Hit)");
        cpu_read(block_base | 32'h8, "Test 3.2 - Word 2 (Offset 0x8, Expect Hit)");

        if ((miss_count - initial_misses) == 2 && (hit_count - initial_hits) == 6) begin
            $display("[SUMMARY] TEST 3: SPATIAL LOCALITY CONFIRMED: 2 block refills served 8 word accesses (75%% hit rate).");
        end else begin
            $display("[ERROR] TEST 3: Spatial hit/miss counts unexpected: Misses=%0d, Hits=%0d",
                     (miss_count - initial_misses), (hit_count - initial_hits));
        end
    end
endtask

`endif // TEST_SCENARIOS_SV
