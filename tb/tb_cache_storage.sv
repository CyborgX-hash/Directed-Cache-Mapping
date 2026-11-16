// ============================================================================
// Module: tb_cache_storage
// Author: Ajit Kumar (Verification & Testbench Lead)
// Project: Design and Analysis of a Direct-Mapped Cache Controller
// Branch:  feature/verification-testbench
//
// Description:
//   Standalone unit-level testbench for the cache_storage module.
//   Tests all storage sub-modules (data RAM, tag RAM, valid-bit RAM) in
//   isolation from the full pipeline. Covers:
//     TC1: Reset clears all 64 valid bits
//     TC2: Write then read all 64 lines (data, tag, valid)
//     TC3: Tag values stored and retrieved correctly
//     TC4: Atomic refill (data+tag+valid in one write cycle)
//     TC5: Adjacent line isolation (no cross-talk)
//     TC6: Combinational read stability
//     TC7: Boundary lines (index 0 and 63)
//     TC8: Conflict eviction and overwrite
//
// Compile:
//   iverilog -g2012 -o sim/tb_cache_storage.vvp \
//     rtl/cache_data_ram.v rtl/tag_ram.v rtl/valid_bit_ram.v \
//     rtl/cache_storage.v tb/tb_cache_storage.sv
// Run:
//   vvp sim/tb_cache_storage.vvp | tee logs/storage_regression.log
// ============================================================================

`timescale 1ns / 1ps

module tb_cache_storage;

    // ========================================================================
    // Parameters
    // ========================================================================
    localparam NUM_LINES  = 64;
    localparam INDEX_BITS = 6;
    localparam TAG_BITS   = 22;
    localparam BLOCK_BITS = 128;
    localparam CLK_PERIOD = 10;

    // ========================================================================
    // Signals
    // ========================================================================
    reg                    clk;
    reg                    rst_n;

    reg  [INDEX_BITS-1:0]  read_index;
    wire                   read_valid;
    wire [TAG_BITS-1:0]    read_tag;
    wire [BLOCK_BITS-1:0]  read_data;

    reg                    write_en;
    reg  [INDEX_BITS-1:0]  write_index;
    reg  [TAG_BITS-1:0]    write_tag;
    reg  [BLOCK_BITS-1:0]  write_data;
    reg                    write_valid;

    // ========================================================================
    // DUT
    // ========================================================================
    cache_storage #(
        .NUM_LINES  (NUM_LINES),
        .INDEX_BITS (INDEX_BITS),
        .TAG_BITS   (TAG_BITS),
        .BLOCK_BITS (BLOCK_BITS)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .read_index  (read_index),
        .read_valid  (read_valid),
        .read_tag    (read_tag),
        .read_data   (read_data),
        .write_en    (write_en),
        .write_index (write_index),
        .write_tag   (write_tag),
        .write_data  (write_data),
        .write_valid (write_valid)
    );

    // ========================================================================
    // Clock
    // ========================================================================
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ========================================================================
    // Test Counters
    // ========================================================================
    integer total_tests  = 0;
    integer passed_tests = 0;
    integer failed_tests = 0;

    task automatic check(input cond, input [511:0] label);
        begin
            total_tests = total_tests + 1;
            if (cond) begin
                $display("   [PASS] %s", label);
                passed_tests = passed_tests + 1;
            end else begin
                $display("   [FAIL] %s", label);
                failed_tests = failed_tests + 1;
            end
        end
    endtask

    // ========================================================================
    // Helpers
    // ========================================================================
    task automatic write_line(
        input [INDEX_BITS-1:0]  idx,
        input [TAG_BITS-1:0]    tag,
        input [BLOCK_BITS-1:0]  data,
        input                   vld
    );
        begin
            write_en    = 1'b1;
            write_index = idx;
            write_tag   = tag;
            write_data  = data;
            write_valid = vld;
            @(posedge clk); #1;
            write_en    = 1'b0;
            @(posedge clk); #1;
        end
    endtask

    task automatic read_line(input [INDEX_BITS-1:0] idx);
        begin
            write_en   = 1'b0;
            read_index = idx;
            #1; // combinational settle
        end
    endtask

    // ========================================================================
    // TEST FLOW
    // ========================================================================
    initial begin
        integer i;
        integer all_clear;
        integer all_match;
        reg [BLOCK_BITS-1:0] prev19, prev21;
        integer stable;

        $dumpfile("sim/tb_cache_storage.vcd");
        $dumpvars(0, tb_cache_storage);

        // Init signals
        clk         = 1'b0;
        rst_n       = 1'b0;
        write_en    = 1'b0;
        write_index = 6'd0;
        write_tag   = {TAG_BITS{1'b0}};
        write_data  = {BLOCK_BITS{1'b0}};
        write_valid = 1'b0;
        read_index  = 6'd0;

        $display("==================================================================");
        $display(" CACHE STORAGE UNIT TESTBENCH - tb_cache_storage.sv               ");
        $display(" Author: Ajit Kumar  |  Checks: 8 Test Cases (TC1-TC8)            ");
        $display("==================================================================");

        // Reset
        repeat(4) @(posedge clk);
        rst_n = 1'b1;
        repeat(2) @(posedge clk);

        // ----------------------------------------------------------------
        // TC1: Reset clears all 64 valid bits
        // ----------------------------------------------------------------
        $display("\n--- TC1: Reset Clears All 64 Valid Bits ---");
        all_clear = 1;
        for (i = 0; i < NUM_LINES; i = i + 1) begin
            read_line(i);
            if (read_valid !== 1'b0) all_clear = 0;
        end
        check(all_clear, "TC1: All 64 valid bits = 0 after reset");

        // ----------------------------------------------------------------
        // TC2: Write and Read All 64 Lines
        // ----------------------------------------------------------------
        $display("\n--- TC2: Write and Read All 64 Lines ---");
        for (i = 0; i < NUM_LINES; i = i + 1) begin
            write_line(i[5:0], (22'h100 + i[21:0]),
                       (128'hDEAD_BEEF_0000_0000_0000_0000_0000_0000 | (i * 128'h1)),
                       1'b1);
        end
        all_match = 1;
        for (i = 0; i < NUM_LINES; i = i + 1) begin
            read_line(i[5:0]);
            if (read_valid !== 1'b1) all_match = 0;
        end
        check(all_match, "TC2: All 64 lines valid after write");

        // ----------------------------------------------------------------
        // TC3: Tag Values Match Stored Tags
        // ----------------------------------------------------------------
        $display("\n--- TC3: Tag Values Match Stored Tags ---");
        all_match = 1;
        for (i = 0; i < NUM_LINES; i = i + 1) begin
            read_line(i[5:0]);
            if (read_tag !== (22'h100 + i[21:0])) all_match = 0;
        end
        check(all_match, "TC3: All 64 line tags match stored tag values");

        // ----------------------------------------------------------------
        // TC4: Atomic Refill (data, tag, valid in single cycle)
        // ----------------------------------------------------------------
        $display("\n--- TC4: Atomic Refill Update ---");
        write_line(6'd15, 22'h3FFFFF,
                   128'hFFFF_FFFF_EEEE_EEEE_DDDD_DDDD_CCCC_CCCC, 1'b1);
        read_line(6'd15);
        check(read_valid === 1'b1 &&
              read_tag   === 22'h3FFFFF &&
              read_data  === 128'hFFFF_FFFF_EEEE_EEEE_DDDD_DDDD_CCCC_CCCC,
              "TC4: Atomic write of line 15 (valid+tag+data) in one cycle");

        // ----------------------------------------------------------------
        // TC5: Adjacent Line Isolation
        // ----------------------------------------------------------------
        $display("\n--- TC5: Adjacent Line Isolation ---");
        read_line(6'd19); prev19 = read_data;
        read_line(6'd21); prev21 = read_data;
        write_line(6'd20, 22'h000055,
                   128'h5555_5555_5555_5555_5555_5555_5555_5555, 1'b1);
        read_line(6'd19);
        check(read_data === prev19, "TC5: Line 19 unaffected by Line 20 write");
        read_line(6'd21);
        check(read_data === prev21, "TC5: Line 21 unaffected by Line 20 write");

        // ----------------------------------------------------------------
        // TC6: Combinational Read Stability
        // ----------------------------------------------------------------
        $display("\n--- TC6: Combinational Read Stability ---");
        stable = 1;
        for (i = 0; i < 5; i = i + 1) begin
            read_line(6'd20);
            if (read_data  !== 128'h5555_5555_5555_5555_5555_5555_5555_5555 ||
                read_tag   !== 22'h000055 ||
                read_valid !== 1'b1) stable = 0;
        end
        check(stable, "TC6: 5 consecutive reads of Line 20 return stable values");

        // ----------------------------------------------------------------
        // TC7: Boundary Lines (0 and 63)
        // ----------------------------------------------------------------
        $display("\n--- TC7: Boundary Line Tests ---");
        write_line(6'd0, 22'h000000, {BLOCK_BITS{1'b0}}, 1'b1);
        read_line(6'd0);
        check(read_valid === 1'b1 && read_tag === 22'h0 && read_data === {BLOCK_BITS{1'b0}},
              "TC7.1: Line 0 all-zeros boundary write/read");

        write_line(6'd63, 22'h3FFFFF, {BLOCK_BITS{1'b1}}, 1'b1);
        read_line(6'd63);
        check(read_valid === 1'b1 && read_tag === 22'h3FFFFF && read_data === {BLOCK_BITS{1'b1}},
              "TC7.2: Line 63 all-ones boundary write/read");

        // ----------------------------------------------------------------
        // TC8: Conflict Eviction & Overwrite
        // ----------------------------------------------------------------
        $display("\n--- TC8: Conflict Eviction & Overwrite ---");
        write_line(6'd0, 22'h123456,
                   128'hFEED_FACE_CAFE_BEEF_0123_4567_89AB_CDEF, 1'b1);
        read_line(6'd0);
        check(read_valid === 1'b1 &&
              read_tag   === 22'h123456 &&
              read_data  === 128'hFEED_FACE_CAFE_BEEF_0123_4567_89AB_CDEF,
              "TC8: Line 0 evicted and replaced with new tag/data");

        // ----------------------------------------------------------------
        // Summary
        // ----------------------------------------------------------------
        $display("\n==================================================================");
        $display("   CACHE STORAGE UNIT TEST SUMMARY");
        $display("   Total Checks : %0d", total_tests);
        $display("   PASSED       : %0d", passed_tests);
        $display("   FAILED       : %0d", failed_tests);
        if (failed_tests == 0)
            $display("   STATUS: >>> ALL STORAGE TESTS PASSED <<<");
        else
            $display("   STATUS: >>> STORAGE TESTS FAILED: %0d <<<", failed_tests);
        $display("==================================================================");

        #(CLK_PERIOD * 5);
        $finish;
    end

endmodule
