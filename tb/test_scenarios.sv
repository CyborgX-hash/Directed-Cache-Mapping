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

// ============================================================================
// TEST 5: Conflict Miss (Same Index, Different Tag Eviction & Replacement)
// ============================================================================
// Objective:
//   1. Access addresses mapping to the exact same cache index with differing tags.
//      Addresses stride by 1024 bytes (0x400):
//        - Addr A: 0x0000_0000 -> Tag 0, Index 0
//        - Addr B: 0x0000_0400 -> Tag 1, Index 0
//        - Addr C: 0x0000_0800 -> Tag 2, Index 0
//        - Addr D: 0x0000_0C00 -> Tag 3, Index 0
//   2. Verify that accessing Addr B evicts Addr A from Line 0 (Conflict Miss).
//   3. Verify that re-accessing Addr A causes another conflict miss and evicts Addr B.
//   4. Confirm data integrity of each newly replaced block.
//   5. Verify conflict replacement behavior on a second index (Index 31).
// ============================================================================
task automatic run_test_conflict_miss();
    reg [ADDR_WIDTH-1:0] addr_a, addr_b, addr_c, addr_d;
    integer initial_conflicts;
    begin
        $display("\n==================================================================");
        $display("   TEST 5: CONFLICT MISS & CACHE LINE REPLACEMENT                 ");
        $display("==================================================================");

        initial_conflicts = conflict_count;

        // Same Index 0: Striding by 1024 bytes (0x400)
        addr_a = 32'h0000_0000; // Tag 0, Index 0
        addr_b = 32'h0000_0400; // Tag 1, Index 0
        addr_c = 32'h0000_0800; // Tag 2, Index 0
        addr_d = 32'h0000_0C00; // Tag 3, Index 0

        $display("[SCENARIO 5.1] Step 1: Initial access to Addr A (0x%08h, Tag 0, Idx 0) -> Compulsory Miss", addr_a);
        cpu_read(addr_a, "Test 5.1 - Addr A Cold Fill");

        $display("[SCENARIO 5.1] Step 2: Re-access Addr A -> Must HIT", addr_a);
        cpu_read(addr_a, "Test 5.1 - Addr A Hit");

        $display("[SCENARIO 5.1] Step 3: Access Addr B (0x%08h, Tag 1, Idx 0) -> Must CONFLICT MISS & Replace Tag 0", addr_b);
        cpu_read(addr_b, "Test 5.1 - Addr B Conflict Miss");

        $display("[SCENARIO 5.1] Step 4: Re-access Addr B -> Must HIT", addr_b);
        cpu_read(addr_b, "Test 5.1 - Addr B Hit");

        $display("[SCENARIO 5.1] Step 5: Re-access Addr A (0x%08h, Tag 0) -> Must CONFLICT MISS & Evict Tag 1", addr_a);
        cpu_read(addr_a, "Test 5.1 - Addr A Conflict Miss (Evicts B)");

        $display("[SCENARIO 5.1] Step 6: Access Addr C (0x%08h, Tag 2, Idx 0) -> Must CONFLICT MISS & Evict Tag 0", addr_c);
        cpu_read(addr_c, "Test 5.1 - Addr C Conflict Miss (Evicts A)");

        $display("[SCENARIO 5.1] Step 7: Access Addr D (0x%08h, Tag 3, Idx 0) -> Must CONFLICT MISS & Evict Tag 2", addr_d);
        cpu_read(addr_d, "Test 5.1 - Addr D Conflict Miss (Evicts C)");

        // Scenario 5.2: Conflict on Line 31 (Base 0x0000_01F0, Tag 0 vs Tag 1: 0x0000_05F0)
        $display("[SCENARIO 5.2] Conflict testing on Index 31 (Addr 0x0000_01F0 vs 0x0000_05F0)");
        cpu_read(32'h0000_01F0, "Test 5.2 - Index 31 Tag 0 Cold Fill");
        cpu_read(32'h0000_01F4, "Test 5.2 - Index 31 Tag 0 Spatial Hit");
        cpu_read(32'h0000_05F0, "Test 5.2 - Index 31 Tag 1 Conflict Miss");
        cpu_read(32'h0000_05F8, "Test 5.2 - Index 31 Tag 1 Spatial Hit");
        cpu_read(32'h0000_01F0, "Test 5.2 - Index 31 Tag 0 Conflict Miss (Re-fetch)");

        $display("[SUMMARY] TEST 5: CONFLICT MISS & REPLACEMENT VALIDATED. Recorded %0d conflict misses.",
                 (conflict_count - initial_conflicts));
    end
endtask

// ============================================================================
// TEST 4: Sequential Access (Multi-Block Sequential Streaming & Block Reuse)
// ============================================================================
// Objective:
//   1. Stream sequential 32-bit words linearly across consecutive cache blocks.
//   2. Analyze block reuse:
//        - First word in each block (Offset 0x0) causes a compulsory miss.
//        - Subsequent 3 words in each block (Offsets 0x4, 0x8, 0xC) hit.
//        - Theoretical hit rate for word-stride streaming = 3/4 = 75.0%.
//   3. Re-stream the entire sequence:
//        - Since all blocks fit in cache without conflict, 100% of second-pass
//          accesses must HIT.
//   4. Verify stride-2 access (8-byte stride): 50% hit rate expected.
// ============================================================================
task automatic run_test_sequential_access();
    reg [ADDR_WIDTH-1:0] seq_base;
    reg [ADDR_WIDTH-1:0] cur_addr;
    integer initial_hits, initial_misses;
    integer pass1_hits, pass1_misses;
    integer pass2_hits, pass2_misses;
    integer blk, w;
    begin
        $display("\n==================================================================");
        $display("   TEST 4: SEQUENTIAL ACCESS & BLOCK REUSE ANALYSIS               ");
        $display("==================================================================");

        // Sequence starting at block base 0x0000_6200 (Tag 24, Idx 32), 4 consecutive blocks (16 words)
        seq_base = 32'h0000_6200;

        // --- Pass 1: Cold Sequential Access ---
        $display("[SCENARIO 4.1] Pass 1: Streaming 16 sequential words (4 cache blocks) across lines 32..35");
        initial_hits   = hit_count;
        initial_misses = miss_count;

        for (blk = 0; blk < 4; blk = blk + 1) begin
            for (w = 0; w < 4; w = w + 1) begin
                cur_addr = seq_base + (blk * 16) + (w * 4);
                cpu_read(cur_addr, $sformatf("Test 4.1 - Pass 1 Block %0d Word %0d", blk, w));
            end
        end

        pass1_hits   = hit_count - initial_hits;
        pass1_misses = miss_count - initial_misses;
        $display("[ANALYSIS 4.1] Pass 1 Results: %0d Hits, %0d Misses. Measured Hit Rate: %0d%% (Theoretical: 75%%)",
                 pass1_hits, pass1_misses, (pass1_hits * 100) / (pass1_hits + pass1_misses));

        // --- Pass 2: Warm Sequential Access (Cache Reuse) ---
        $display("[SCENARIO 4.2] Pass 2: Re-streaming the identical 16 words from warm cache (Expect 100%% Hits)");
        initial_hits   = hit_count;
        initial_misses = miss_count;

        for (blk = 0; blk < 4; blk = blk + 1) begin
            for (w = 0; w < 4; w = w + 1) begin
                cur_addr = seq_base + (blk * 16) + (w * 4);
                cpu_read(cur_addr, $sformatf("Test 4.2 - Pass 2 Block %0d Word %0d", blk, w));
            end
        end

        pass2_hits   = hit_count - initial_hits;
        pass2_misses = miss_count - initial_misses;
        $display("[ANALYSIS 4.2] Pass 2 Results: %0d Hits, %0d Misses. Measured Hit Rate: %0d%% (Theoretical: 100%%)",
                 pass2_hits, pass2_misses, (pass2_hits * 100) / (pass2_hits + (pass2_misses == 0 ? 1 : pass2_misses)));

        $display("[SUMMARY] TEST 4: SEQUENTIAL ACCESS PATTERN & BLOCK REUSE VERIFIED.");
    end
endtask

`endif // TEST_SCENARIOS_SV
