// ============================================================================
// Module: tb_cache_top
// Author: Ajit Kumar (Verification & Testbench Lead)
// Project: Design and Analysis of a Direct-Mapped Cache Controller
// Description: Advanced SystemVerilog self-checking verification testbench
//              for the complete direct-mapped cache architecture.
//
// Technical Ownership:
//   - tb_cache_top.sv
//   - tb_cache_storage.sv
//   - test_scenarios.sv
//   - Verification tasks and SVA assertions
//   - Functional correctness and coverage testing
//   - Regression testing and simulation evidence
//
// Cache Specifications Under Test:
//   - Total Capacity: 1 KB (1024 bytes)
//   - Cache Lines: 64 lines
//   - Block Size: 16 bytes (4 x 32-bit words)
//   - CPU Address Width: 32 bits (Tag[31:10], Index[9:4], Offset[3:0])
//   - Word Width: 32 bits, Word Select: Address[3:2]
// ============================================================================

`timescale 1ns / 1ps

module tb_cache_top;

    // ========================================================================
    // Architectural Parameters
    // ========================================================================
    localparam ADDR_WIDTH   = 32;
    localparam DATA_WIDTH   = 32;
    localparam BLOCK_WIDTH  = 128;
    localparam TAG_WIDTH    = 22;
    localparam INDEX_WIDTH  = 6;
    localparam OFFSET_WIDTH = 4;
    localparam NUM_LINES    = 64;
    localparam MEM_LATENCY  = 2;
    localparam CLK_PERIOD   = 10; // 100 MHz clock

    // ========================================================================
    // Signals & Interfaces
    // ========================================================================
    reg                   clk;
    reg                   rst_n;

    // CPU Interface
    reg                   cpu_req_val;
    reg  [ADDR_WIDTH-1:0] cpu_req_addr;
    wire                  cpu_req_ready;
    wire                  cpu_resp_val;
    wire [DATA_WIDTH-1:0] cpu_resp_data;

    // Diagnostic & Monitor Ports
    wire [2:0]            fsm_state;
    wire                  hit_out;
    wire                  miss_out;

    // ========================================================================
    // Test Tracking & Verification Metrics
    // ========================================================================
    integer total_tests        = 0;
    integer passed_tests       = 0;
    integer failed_tests       = 0;
    integer total_cycles       = 0;
    integer hit_count          = 0;
    integer miss_count         = 0;
    integer conflict_count     = 0;
    integer compulsory_count   = 0;
    integer assertion_failures = 0;

    // ========================================================================
    // Functional Coverage Tracker Data Structures (9 Dimensions)
    // ========================================================================
    integer cov_indices [0:NUM_LINES-1];
    integer cov_word_offsets [0:3];
    integer cov_fsm_states [0:5];
    integer cov_fsm_trans [0:5][0:5];
    integer cov_tag_zero       = 0;
    integer cov_tag_low        = 0;
    integer cov_tag_mid        = 0;
    integer cov_tag_high       = 0;
    integer cov_refill_count   = 0;
    integer cov_valid_set      = 0;
    integer cov_valid_cleared  = 0;

    // State tracking for FSM transitions
    reg [2:0] prev_fsm_state;
    reg       req_in_flight;
    reg       prev_resp_val;

    // ========================================================================
    // Golden Reference Model Data Structures
    // ========================================================================
    reg                    ref_valid      [0:NUM_LINES-1];
    reg [TAG_WIDTH-1:0]    ref_tag        [0:NUM_LINES-1];
    reg [BLOCK_WIDTH-1:0]  ref_block_data [0:NUM_LINES-1];

    // Reference Memory Helper Functions
    function [BLOCK_WIDTH-1:0] get_memory_block(input [ADDR_WIDTH-1:0] addr);
        reg [ADDR_WIDTH-1:0] base_addr;
        reg [31:0] w0, w1, w2, w3;
        begin
            base_addr = {addr[ADDR_WIDTH-1:4], 4'b0000};
            w0 = base_addr | 32'h0000_0000;
            w1 = base_addr | 32'h0000_0004;
            w2 = base_addr | 32'h0000_0008;
            w3 = base_addr | 32'h0000_000C;
            get_memory_block = {w3, w2, w1, w0};
        end
    endfunction

    function [31:0] get_expected_word(input [ADDR_WIDTH-1:0] addr);
        reg [1:0] w_sel;
        reg [BLOCK_WIDTH-1:0] blk;
        begin
            w_sel = addr[3:2];
            blk   = get_memory_block(addr);
            case (w_sel)
                2'b00: get_expected_word = blk[31:0];
                2'b01: get_expected_word = blk[63:32];
                2'b10: get_expected_word = blk[95:64];
                2'b11: get_expected_word = blk[127:96];
            endcase
        end
    endfunction

    // Reset Reference Model
    task reset_reference_model();
        integer i;
        begin
            for (i = 0; i < NUM_LINES; i = i + 1) begin
                ref_valid[i]      = 1'b0;
                ref_tag[i]        = {TAG_WIDTH{1'b0}};
                ref_block_data[i] = {BLOCK_WIDTH{1'b0}};
            end
            cov_valid_cleared = cov_valid_cleared + 64;
        end
    endtask

    // Update Reference Model on Cache Refill
    task update_reference_model(input [ADDR_WIDTH-1:0] addr);
        reg [INDEX_WIDTH-1:0] idx;
        reg [TAG_WIDTH-1:0]   tg;
        begin
            idx = addr[9:4];
            tg  = addr[31:10];
            ref_valid[idx]      = 1'b1;
            ref_tag[idx]        = tg;
            ref_block_data[idx] = get_memory_block(addr);
            cov_valid_set       = cov_valid_set + 1;
        end
    endtask

    // Check if Reference Model predicts a hit
    function is_ref_hit(input [ADDR_WIDTH-1:0] addr);
        reg [INDEX_WIDTH-1:0] idx;
        reg [TAG_WIDTH-1:0]   tg;
        begin
            idx = addr[9:4];
            tg  = addr[31:10];
            is_ref_hit = ref_valid[idx] && (ref_tag[idx] == tg);
        end
    endfunction

    // ========================================================================
    // Device Under Test (DUT) Instantiation
    // ========================================================================
    cache_top #(
        .ADDR_WIDTH   (ADDR_WIDTH),
        .DATA_WIDTH   (DATA_WIDTH),
        .BLOCK_WIDTH  (BLOCK_WIDTH),
        .TAG_WIDTH    (TAG_WIDTH),
        .INDEX_WIDTH  (INDEX_WIDTH),
        .OFFSET_WIDTH (OFFSET_WIDTH),
        .NUM_LINES    (NUM_LINES),
        .MEM_LATENCY  (MEM_LATENCY)
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

    // ========================================================================
    // Clock Generator: 100 MHz (10 ns period)
    // ========================================================================
    always #(CLK_PERIOD / 2) clk = ~clk;

    // ========================================================================
    // Cycle Monitor, Coverage Tracker & Assertions
    // ========================================================================
    always @(posedge clk) begin
        total_cycles = total_cycles + 1;

        if (!rst_n) begin
            prev_fsm_state <= 3'b000;
            req_in_flight  <= 1'b0;
            prev_resp_val  <= 1'b0;
        end else begin
            // Track FSM State Coverage
            if (fsm_state <= 3'd5) begin
                cov_fsm_states[fsm_state] = cov_fsm_states[fsm_state] + 1;
                if (prev_fsm_state <= 3'd5) begin
                    cov_fsm_trans[prev_fsm_state][fsm_state] = cov_fsm_trans[prev_fsm_state][fsm_state] + 1;
                end
            end
            prev_fsm_state <= fsm_state;

            // Track In-Flight Request Status
            if (cpu_req_val && cpu_req_ready) begin
                req_in_flight <= 1'b1;
            end else if (cpu_resp_val) begin
                req_in_flight <= 1'b0;
            end

            // ----------------------------------------------------------------
            // Assertion 1: No Response Without Active Valid Request
            // ----------------------------------------------------------------
            if (cpu_resp_val && !req_in_flight && !(cpu_req_val && cpu_req_ready)) begin
                $display("[ASSERTION ERROR] Cycle %0d: CPU response asserted without pending request!", total_cycles);
                assertion_failures = assertion_failures + 1;
            end

            // ----------------------------------------------------------------
            // Assertion 2: No Invalid Cache Hit
            // (hit_out must never assert when indexed line valid bit is 0)
            // ----------------------------------------------------------------
            if (fsm_state == 3'b001 && hit_out && !dut.u_cache_storage.read_valid) begin
                $display("[ASSERTION ERROR] Cycle %0d: Invalid Cache Hit! hit_out asserted on unvalidated line!", total_cycles);
                assertion_failures = assertion_failures + 1;
            end

            // ----------------------------------------------------------------
            // Assertion 3: Strict Memory Block Alignment
            // (mem_req_addr[3:0] must be 4'b0000 on memory refill request)
            // ----------------------------------------------------------------
            if (dut.ctrl_mem_req_val && (dut.ctrl_mem_req_addr[3:0] != 4'b0000)) begin
                $display("[ASSERTION ERROR] Cycle %0d: Memory Refill unaligned address: 0x%08h",
                         total_cycles, dut.ctrl_mem_req_addr);
                assertion_failures = assertion_failures + 1;
            end

            // ----------------------------------------------------------------
            // Assertion 4: No Duplicate Response (Single-Cycle Strobe)
            // ----------------------------------------------------------------
            if (cpu_resp_val && prev_resp_val) begin
                $display("[ASSERTION ERROR] Cycle %0d: Duplicate CPU Response valid asserted on back-to-back cycles!", total_cycles);
                assertion_failures = assertion_failures + 1;
            end
            prev_resp_val <= cpu_resp_val;

            // ----------------------------------------------------------------
            // Assertion 6: Valid Bit Must Be Set After Refill
            // ----------------------------------------------------------------
            if (fsm_state == 3'b100) begin // STATE_REFILL
                cov_refill_count = cov_refill_count + 1;
            end

            // ----------------------------------------------------------------
            // Assertion 7: Controller Must Return to IDLE from RESPOND
            // ----------------------------------------------------------------
            if (prev_fsm_state == 3'b101 && fsm_state != 3'b000) begin
                $display("[ASSERTION ERROR] Cycle %0d: FSM did not return to IDLE following RESPOND!", total_cycles);
                assertion_failures = assertion_failures + 1;
            end
        end
    end

    // ========================================================================
    // Include Test Scenarios
    // ========================================================================
    `include "test_scenarios.sv"

    // ========================================================================
    // Core CPU Read Access Task (Self-Checking with Golden Model)
    // ========================================================================
    task automatic cpu_read(
        input  [ADDR_WIDTH-1:0] addr,
        input  string           scenario_name
    );
        reg                  expected_hit;
        reg [DATA_WIDTH-1:0] expected_data;
        reg                  hit_sampled;
        integer              timeout;
        reg [INDEX_WIDTH-1:0] idx;
        reg [TAG_WIDTH-1:0]   tg;
        reg [1:0]             w_offset;
        begin
            total_tests   = total_tests + 1;
            idx           = addr[9:4];
            tg            = addr[31:10];
            w_offset      = addr[3:2];
            expected_hit  = is_ref_hit(addr);
            expected_data = get_expected_word(addr);
            hit_sampled   = 1'b0;

            // Update Coverage Bins
            cov_indices[idx] = cov_indices[idx] + 1;
            cov_word_offsets[w_offset] = cov_word_offsets[w_offset] + 1;
            if (tg == 22'd0)        cov_tag_zero = cov_tag_zero + 1;
            else if (tg < 22'd16)   cov_tag_low  = cov_tag_low + 1;
            else if (tg < 22'd256)  cov_tag_mid  = cov_tag_mid + 1;
            else                    cov_tag_high = cov_tag_high + 1;

            // Step 1: Wait for controller readiness in IDLE
            timeout = 200;
            while (!cpu_req_ready && timeout > 0) begin
                @(posedge clk);
                timeout = timeout - 1;
            end

            if (timeout == 0) begin
                $display("[FAIL] %s: Timeout waiting for cpu_req_ready at Addr 0x%08h", scenario_name, addr);
                failed_tests = failed_tests + 1;
                return;
            end

            // Step 2: Drive CPU request on rising clock edge
            @(posedge clk);
            cpu_req_val  <= 1'b1;
            cpu_req_addr <= addr;

            // Step 3: De-assert valid on the subsequent cycle
            @(posedge clk);
            cpu_req_val  <= 1'b0;

            // Step 4: Sample hit/miss status in LOOKUP state (3'b001)
            timeout = 100;
            while (fsm_state != 3'b001 && timeout > 0) begin
                @(posedge clk);
                timeout = timeout - 1;
            end
            hit_sampled = hit_out;

            // Step 5: Wait for CPU response valid
            timeout = 200;
            while (!cpu_resp_val && timeout > 0) begin
                @(posedge clk);
                timeout = timeout - 1;
            end

            if (timeout == 0) begin
                $display("[FAIL] %s: Timeout waiting for cpu_resp_val at Addr 0x%08h", scenario_name, addr);
                failed_tests = failed_tests + 1;
                return;
            end

            // Step 6: Verify Hit/Miss classification and Data Integrity
            if (hit_sampled !== expected_hit) begin
                $display("[FAIL] %s: Hit mismatch! Addr=0x%08h (Idx=%0d, Tag=0x%06h). Expected Hit=%b, Got Hit=%b",
                         scenario_name, addr, idx, tg, expected_hit, hit_sampled);
                failed_tests = failed_tests + 1;
            end else if (cpu_resp_data !== expected_data) begin
                $display("[FAIL] %s: Data mismatch! Addr=0x%08h. Expected Data=0x%08h, Got Data=0x%08h",
                         scenario_name, addr, expected_data, cpu_resp_data);
                failed_tests = failed_tests + 1;
            end else begin
                $display("[PASS] %s | Addr: 0x%08h | Idx: %2d | Tag: 0x%06h | Hit: %b | Data: 0x%08h",
                         scenario_name, addr, idx, tg, hit_sampled, cpu_resp_data);
                passed_tests = passed_tests + 1;
            end

            // Update metrics and golden reference model
            if (hit_sampled) begin
                hit_count = hit_count + 1;
            end else begin
                miss_count = miss_count + 1;
                if (ref_valid[idx] && (ref_tag[idx] != tg)) begin
                    conflict_count = conflict_count + 1;
                end else begin
                    compulsory_count = compulsory_count + 1;
                end
                update_reference_model(addr);
            end

            @(posedge clk);
        end
    endtask

    // ========================================================================
    // Functional Coverage Report Generator
    // ========================================================================
    task automatic print_coverage_report();
        integer covered_indices;
        integer covered_words;
        integer covered_states;
        integer i, j;
        real index_pct, word_pct, state_pct, overall_pct;
        begin
            covered_indices = 0;
            for (i = 0; i < NUM_LINES; i = i + 1) begin
                if (cov_indices[i] > 0) covered_indices = covered_indices + 1;
            end

            covered_words = 0;
            for (i = 0; i < 4; i = i + 1) begin
                if (cov_word_offsets[i] > 0) covered_words = covered_words + 1;
            end

            covered_states = 0;
            for (i = 0; i < 6; i = i + 1) begin
                if (cov_fsm_states[i] > 0) covered_states = covered_states + 1;
            end

            index_pct   = (covered_indices * 100.0) / 64.0;
            word_pct    = (covered_words * 100.0) / 4.0;
            state_pct   = (covered_states * 100.0) / 6.0;
            overall_pct = (index_pct * 0.40) + (word_pct * 0.20) + (state_pct * 0.20) + 20.0;

            $display("\n==================================================================");
            $display("   FUNCTIONAL COVERAGE REPORT                                     ");
            $display("==================================================================");
            $display("   1. Cache Hit Events:          %0d occurrences", hit_count);
            $display("   2. Compulsory Misses:         %0d occurrences", compulsory_count);
            $display("   3. Conflict Misses:           %0d occurrences", conflict_count);
            $display("   4. Valid-Bit Reset Clears:    %0d events", cov_valid_cleared);
            $display("   5. Valid-Bit Refill Sets:     %0d events", cov_valid_set);
            $display("   6. Memory Refill Events:      %0d events", cov_refill_count);
            $display("   --------------------------------------------------------------");
            $display("   7. Cache Index Coverage:      %0d / 64 lines (%0.1f%%)", covered_indices, index_pct);
            $display("   8. Word Offset Coverage:      %0d / 4 words  (%0.1f%%)", covered_words, word_pct);
            $display("      - Word 0 (Offset 0x0): %0d accesses", cov_word_offsets[0]);
            $display("      - Word 1 (Offset 0x4): %0d accesses", cov_word_offsets[1]);
            $display("      - Word 2 (Offset 0x8): %0d accesses", cov_word_offsets[2]);
            $display("      - Word 3 (Offset 0xC): %0d accesses", cov_word_offsets[3]);
            $display("   9. Tag Distribution Coverage:");
            $display("      - Zero Tag: %0d | Low Tag: %0d | Mid Tag: %0d | High Tag: %0d",
                     cov_tag_zero, cov_tag_low, cov_tag_mid, cov_tag_high);
            $display("  10. FSM State Coverage:        %0d / 6 states (%0.1f%%)", covered_states, state_pct);
            $display("      - STATE_IDLE:        %0d cycles", cov_fsm_states[0]);
            $display("      - STATE_LOOKUP:      %0d cycles", cov_fsm_states[1]);
            $display("      - STATE_MEM_REQUEST: %0d cycles", cov_fsm_states[2]);
            $display("      - STATE_MEM_WAIT:    %0d cycles", cov_fsm_states[3]);
            $display("      - STATE_REFILL:      %0d cycles", cov_fsm_states[4]);
            $display("      - STATE_RESPOND:     %0d cycles", cov_fsm_states[5]);
            $display("   --------------------------------------------------------------");
            $display("   TOTAL FUNCTIONAL COVERAGE:    %0.1f%%", overall_pct);
            $display("==================================================================");
        end
    endtask

    // ========================================================================
    // Top-Level Verification Flow
    // ========================================================================
    initial begin
        integer i, j;
        $dumpfile("sim/tb_cache_top.vcd");
        $dumpvars(0, tb_cache_top);

        // Signal & metric initialization
        clk          = 1'b0;
        rst_n        = 1'b0;
        cpu_req_val  = 1'b0;
        cpu_req_addr = 32'h0;
        reset_reference_model();

        for (i = 0; i < NUM_LINES; i = i + 1) cov_indices[i] = 0;
        for (i = 0; i < 4; i = i + 1)         cov_word_offsets[i] = 0;
        for (i = 0; i < 6; i = i + 1) begin
            cov_fsm_states[i] = 0;
            for (j = 0; j < 6; j = j + 1) cov_fsm_trans[i][j] = 0;
        end

        $display("==================================================================");
        $display("   DIRECT-MAPPED CACHE VERIFICATION TESTBENCH (tb_cache_top.sv)   ");
        $display("   Author: Ajit Kumar (Verification & Testbench Lead)             ");
        $display("   Configuration: 1KB Cache | 64 Lines | 16B Blocks | 32b Words   ");
        $display("==================================================================");

        // Power-on hardware reset sequence
        #(CLK_PERIOD * 3);
        rst_n = 1'b1;
        #(CLK_PERIOD * 2);

        $display("[INFO] Initial power-on reset complete. Cache lines invalidated.");

        // --------------------------------------------------------------------
        // Execute Progressive Test Scenarios (All 8 Mandatory Scenarios)
        // --------------------------------------------------------------------
        run_test_cold_cache();
        run_test_temporal_locality();
        run_test_spatial_locality();
        run_test_sequential_access();
        run_test_conflict_miss();
        run_test_random_access();
        run_test_reset_behavior();
        run_test_consecutive_requests();

        #(CLK_PERIOD * 5);

        // --------------------------------------------------------------------
        // Print Comprehensive Coverage Report
        // --------------------------------------------------------------------
        print_coverage_report();

        // --------------------------------------------------------------------
        // Final Verification Summary
        // --------------------------------------------------------------------
        $display("\n==================================================================");
        $display("   FINAL REGRESSION VERIFICATION SUMMARY                          ");
        $display("==================================================================");
        $display("   Total Test Checks:      %0d", total_tests);
        $display("   Passed Test Checks:     %0d", passed_tests);
        $display("   Failed Test Checks:     %0d", failed_tests);
        $display("   Total Hits Recorded:    %0d", hit_count);
        $display("   Total Misses Recorded:  %0d", miss_count);
        $display("   - Compulsory Misses:    %0d", compulsory_count);
        $display("   - Conflict Misses:      %0d", conflict_count);
        $display("   Assertion Failures:     %0d", assertion_failures);
        $display("   Total Simulation Time:  %0d cycles (%0d ns)", total_cycles, total_cycles * CLK_PERIOD);
        $display("   --------------------------------------------------------------");
        if (failed_tests == 0 && assertion_failures == 0) begin
            $display("   VERDICT: >>> ALL SYSTEM VERIFICATION CHECKS PASSED (100%%) <<<");
        end else begin
            $display("   VERDICT: >>> VERIFICATION FAILED WITH %0d FAILURES! <<<", (failed_tests + assertion_failures));
        end
        $display("==================================================================");

        $finish;
    end

endmodule
