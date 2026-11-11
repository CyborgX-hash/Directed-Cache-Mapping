// ============================================================================
// Testbench: cache_top_tb
// Author: Ajit & Saksham
// Project: Design and Analysis of a Direct-Mapped Cache Controller
// Description: Comprehensive verification testbench validating all 7 key
//              architectural scenarios:
//              1. Compulsory miss on cold access
//              2. Hit on identical address access
//              3. Spatial locality hit on different word within the same block
//              4. Conflict miss causing cache line replacement
//              5. Correct data integrity after line replacement
//              6. Reset invalidates all cache lines
//              7. Backpressure handling and consecutive request pipelining
// ============================================================================

`timescale 1ns / 1ps

module cache_top_tb;

    // Parameters
    localparam ADDR_WIDTH   = 32;
    localparam DATA_WIDTH   = 32;
    localparam BLOCK_WIDTH  = 128;
    localparam TAG_WIDTH    = 22;
    localparam INDEX_WIDTH  = 6;
    localparam OFFSET_WIDTH = 4;
    localparam CLK_PERIOD   = 10; // 100 MHz clock

    // Testbench Signals
    reg                   clk;
    reg                   rst_n;
    reg                   cpu_req_val;
    reg  [ADDR_WIDTH-1:0] cpu_req_addr;
    wire                  cpu_req_ready;
    wire                  cpu_resp_val;
    wire [DATA_WIDTH-1:0] cpu_resp_data;
    wire [2:0]            fsm_state;
    wire                  hit_out;
    wire                  miss_out;

    // Test Tracking
    integer total_tests  = 0;
    integer passed_tests = 0;
    integer failed_tests = 0;

    // Instantiate Device Under Test (DUT)
    cache_top #(
        .ADDR_WIDTH   (ADDR_WIDTH),
        .DATA_WIDTH   (DATA_WIDTH),
        .BLOCK_WIDTH  (BLOCK_WIDTH),
        .TAG_WIDTH    (TAG_WIDTH),
        .INDEX_WIDTH  (INDEX_WIDTH),
        .OFFSET_WIDTH (OFFSET_WIDTH),
        .NUM_LINES    (64),
        .MEM_LATENCY  (2)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .cpu_req_val   (cpu_req_val),
        .cpu_req_addr  (cpu_req_addr),
        .cpu_req_ready (cpu_req_ready),
        .cpu_resp_val  (cpu_resp_val),
        .cpu_resp_data (cpu_resp_data),
        .fsm_state     (fsm_state),
        .hit_out       (hit_out),
        .miss_out      (miss_out)
    );

    // Clock Generator: 100 MHz
    always #(CLK_PERIOD / 2) clk = ~clk;

    // ========================================================================
    // Task: Perform CPU Read Access
    // ========================================================================
    task cpu_read(
        input  [31:0] addr,
        input         expect_hit,
        input  [31:0] expected_data,
        input  [383:0] test_name
    );
        reg hit_observed;
        integer timeout;
        begin
            total_tests = total_tests + 1;
            hit_observed = 1'b0;

            // Wait until cache controller is ready
            timeout = 100;
            while (!cpu_req_ready && timeout > 0) begin
                @(posedge clk);
                timeout = timeout - 1;
            end

            if (timeout == 0) begin
                $display("[ERROR] Timeout waiting for cpu_req_ready before request: %0s", test_name);
                failed_tests = failed_tests + 1;
                disable cpu_read;
            end

            // Issue request
            @(posedge clk);
            cpu_req_val  <= 1'b1;
            cpu_req_addr <= addr;

            @(posedge clk);
            cpu_req_val  <= 1'b0;

            // Sample hit/miss status during LOOKUP state
            timeout = 100;
            while (fsm_state != 3'b001 && timeout > 0) begin
                @(posedge clk);
                timeout = timeout - 1;
            end
            hit_observed = hit_out;

            // Wait for response valid
            timeout = 100;
            while (!cpu_resp_val && timeout > 0) begin
                @(posedge clk);
                timeout = timeout - 1;
            end

            if (timeout == 0) begin
                $display("[FAIL] %0s: Timeout waiting for cpu_resp_val!", test_name);
                failed_tests = failed_tests + 1;
            end else begin
                // Check Hit/Miss expectation
                if (hit_observed !== expect_hit) begin
                    $display("[FAIL] %0s: Hit expectation mismatch! Expected Hit=%b, Got Hit=%b",
                             test_name, expect_hit, hit_observed);
                    failed_tests = failed_tests + 1;
                end else if (cpu_resp_data !== expected_data) begin
                    $display("[FAIL] %0s: Data mismatch! Addr=0x%08h, Expected=0x%08h, Got=0x%08h",
                             test_name, addr, expected_data, cpu_resp_data);
                    failed_tests = failed_tests + 1;
                end else begin
                    $display("[PASS] %0s: Addr=0x%08h | Hit=%b | Data=0x%08h",
                             test_name, addr, hit_observed, cpu_resp_data);
                    passed_tests = passed_tests + 1;
                end
            end

            @(posedge clk);
        end
    endtask

    // ========================================================================
    // Main Verification Sequence
    // ========================================================================
    initial begin
        $dumpfile("sim/cache_top_tb.vcd");
        $dumpvars(0, cache_top_tb);

        // Signal initialization
        clk          = 1'b0;
        rst_n        = 1'b0;
        cpu_req_val  = 1'b0;
        cpu_req_addr = 32'h0;

        $display("==================================================================");
        $display("   DIRECT-MAPPED CACHE CONTROLLER SYSTEM VERIFICATION SUITE       ");
        $display("   Authors: Saksham, Mihika, Harsh, Priyanshu, Ajit               ");
        $display("==================================================================");

        // Power-on reset sequence
        #(CLK_PERIOD * 3);
        rst_n = 1'b1;
        #(CLK_PERIOD * 2);

        // --------------------------------------------------------------------
        // Test 1: First access to an address produces a compulsory miss
        // --------------------------------------------------------------------
        $display("\n--- Test 1: Compulsory Miss (Cold Access) ---");
        // Address 0x0000_1040: Tag=4, Index=4, Offset=0 (Word 0)
        // Memory returns word0=0x0000_1040, word1=0x0000_1044, word2=0x0000_1048, word3=0x0000_104C
        cpu_read(32'h0000_1040, 1'b0, 32'h0000_1040, "Test 1 - Cold Access Miss");

        // --------------------------------------------------------------------
        // Test 2: Second access to the same address produces a hit
        // --------------------------------------------------------------------
        $display("\n--- Test 2: Cache Hit (Same Address) ---");
        cpu_read(32'h0000_1040, 1'b1, 32'h0000_1040, "Test 2 - Re-access Hit");

        // --------------------------------------------------------------------
        // Test 3: Access to another word in the same block produces a hit
        // --------------------------------------------------------------------
        $display("\n--- Test 3: Spatial Locality Hit (Different Word, Same Block) ---");
        // Address 0x0000_1048: Tag=4, Index=4, Offset=8 (Word 2)
        cpu_read(32'h0000_1048, 1'b1, 32'h0000_1048, "Test 3 - Word 2 Hit");
        // Address 0x0000_104C: Tag=4, Index=4, Offset=12 (Word 3)
        cpu_read(32'h0000_104C, 1'b1, 32'h0000_104C, "Test 3 - Word 3 Hit");

        // --------------------------------------------------------------------
        // Test 4: Conflict Miss & Cache Line Replacement
        // --------------------------------------------------------------------
        $display("\n--- Test 4: Conflict Miss (Same Index, Different Tag) ---");
        // Address 0x0000_2040: Index=4 (same!), Tag=8 (different!)
        cpu_read(32'h0000_2040, 1'b0, 32'h0000_2040, "Test 4 - Conflict Miss Replacement");

        // --------------------------------------------------------------------
        // Test 5: Access after replacement produces correct result
        // --------------------------------------------------------------------
        $display("\n--- Test 5: Verify Replaced Block Data & Re-fetch Old Block ---");
        // Replaced block (0x0000_2040) is now in line 4 -> access Word 1 (0x0000_2044) should HIT
        cpu_read(32'h0000_2044, 1'b1, 32'h0000_2044, "Test 5 - New Block Hit");
        // Access old block (0x0000_1040) -> must MISS and reload correctly
        cpu_read(32'h0000_1040, 1'b0, 32'h0000_1040, "Test 5 - Evicted Block Re-fetch Miss");

        // --------------------------------------------------------------------
        // Test 6: Reset invalidates all cache entries
        // --------------------------------------------------------------------
        $display("\n--- Test 6: Cache Invalidation via Reset ---");
        $display("Applying active-low reset pulse...");
        rst_n = 1'b0;
        #(CLK_PERIOD * 2);
        rst_n = 1'b1;
        #(CLK_PERIOD * 2);

        // Address 0x0000_1040 was in cache before reset; after reset, it MUST miss
        cpu_read(32'h0000_1040, 1'b0, 32'h0000_1040, "Test 6 - Post-Reset Compulsory Miss");

        // --------------------------------------------------------------------
        // Test 7: Busy backpressure and consecutive request handling
        // --------------------------------------------------------------------
        $display("\n--- Test 7: Backpressure & Consecutive Seamless Requests ---");
        // Test 4 consecutive requests with zero wait cycles
        cpu_read(32'h0000_3000, 1'b0, 32'h0000_3000, "Test 7 - Request A (Miss)");
        cpu_read(32'h0000_3004, 1'b1, 32'h0000_3004, "Test 7 - Request B (Immediate Hit)");
        cpu_read(32'h0000_4000, 1'b0, 32'h0000_4000, "Test 7 - Request C (Miss)");
        cpu_read(32'h0000_400C, 1'b1, 32'h0000_400C, "Test 7 - Request D (Immediate Hit)");

        // --------------------------------------------------------------------
        // Verification Summary
        // --------------------------------------------------------------------
        $display("\n==================================================================");
        $display("   VERIFICATION SUMMARY RESULTS                                   ");
        $display("   Total Checks:  %0d", total_tests);
        $display("   Passed Checks: %0d", passed_tests);
        $display("   Failed Checks: %0d", failed_tests);
        if (failed_tests == 0) begin
            $display("   STATUS: >>> ALL INTEGRATION TESTS PASSED SUCCESSFULLY! <<<");
        end else begin
            $display("   STATUS: >>> SOME TESTS FAILED! PLEASE REVIEW SIGNALS. <<<");
        end
        $display("==================================================================");

        #(CLK_PERIOD * 5);
        $finish;
    end

endmodule
