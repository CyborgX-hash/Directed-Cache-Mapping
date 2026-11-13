// ============================================================================
// Testbench: cache_storage_tb
// Author: Mihika Mathur
// Project: Design and Analysis of a Direct-Mapped Cache Controller
// Description: Storage subsystem verification suite covering all 8 required
//              test scenarios:
//
//  TC1: Valid bits reset to zero on rst_n
//  TC2: Data can be written to all 64 lines and read back correctly
//  TC3: Tags can be written independently to all 64 lines
//  TC4: Correct data is returned for a selected index (read-after-write)
//  TC5: Correct tags are returned for a selected index
//  TC6: Updating one cache line does not corrupt an adjacent line
//  TC7: Address decoder correctly separates tag, index, and offset
//       (via address_decoder instantiated inline)
//  TC8: Cache storage behaves correctly on repeated reads (stability)
//  TC9: Boundary addresses — line 0, line 63, all-zero / all-one write data
//  TC10: Same-index / different-tag conflict — eviction overwrites cleanly
// ============================================================================

`timescale 1ns / 1ps

module cache_storage_tb;

    // Parameters
    localparam NUM_LINES   = 64;
    localparam INDEX_BITS  = 6;
    localparam TAG_BITS    = 22;
    localparam BLOCK_BITS  = 128;
    localparam CLK_PERIOD  = 10;

    // Clock and Reset
    reg clk;
    reg rst_n;

    // Storage DUT Signals
    reg  [INDEX_BITS-1:0]  read_index;
    wire                   read_valid;
    wire [TAG_BITS-1:0]    read_tag;
    wire [BLOCK_BITS-1:0]  read_data;

    reg                    write_en;
    reg  [INDEX_BITS-1:0]  write_index;
    reg  [TAG_BITS-1:0]    write_tag;
    reg  [BLOCK_BITS-1:0]  write_data;
    reg                    write_valid;

    // Address Decoder DUT Signals
    reg  [31:0]            dec_addr;
    wire [TAG_BITS-1:0]    dec_tag;
    wire [INDEX_BITS-1:0]  dec_index;
    wire [3:0]             dec_offset;
    wire [1:0]             dec_word_sel;
    wire [1:0]             dec_byte_offset;

    // Test Tracking
    integer total_tests  = 0;
    integer passed_tests = 0;
    integer failed_tests = 0;
    integer i;

    // =========================================================================
    // DUT Instantiation: cache_storage
    // =========================================================================
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

    // =========================================================================
    // DUT Instantiation: address_decoder (TC7)
    // =========================================================================
    address_decoder #(
        .ADDR_WIDTH     (32),
        .TAG_WIDTH      (TAG_BITS),
        .INDEX_WIDTH    (INDEX_BITS),
        .OFFSET_WIDTH   (4),
        .WORD_SEL_WIDTH (2),
        .BYTE_SEL_WIDTH (2)
    ) u_dec (
        .addr        (dec_addr),
        .tag         (dec_tag),
        .index       (dec_index),
        .offset      (dec_offset),
        .word_sel    (dec_word_sel),
        .byte_offset (dec_byte_offset)
    );

    // =========================================================================
    // Clock Generator
    // =========================================================================
    always #(CLK_PERIOD / 2) clk = ~clk;

    // =========================================================================
    // Helper Tasks
    // =========================================================================

    // Write a single cache line and de-assert write_en
    task write_line(
        input [INDEX_BITS-1:0]  widx,
        input [TAG_BITS-1:0]    wtag,
        input [BLOCK_BITS-1:0]  wdata,
        input                   wvalid
    );
        begin
            @(negedge clk);
            write_en    = 1'b1;
            write_index = widx;
            write_tag   = wtag;
            write_data  = wdata;
            write_valid = wvalid;
            @(posedge clk);        // latch on rising edge
            #1;
            write_en    = 1'b0;
        end
    endtask

    // Read a cache line (combinational – just set index and read)
    task read_line(input [INDEX_BITS-1:0] ridx);
        begin
            @(negedge clk);
            read_index = ridx;
            #2;                    // allow combinational settle
        end
    endtask

    // Check a single condition and print result
    task check(
        input        condition,
        input [511:0] description
    );
        begin
            total_tests = total_tests + 1;
            if (condition) begin
                $display("[PASS] %0s", description);
                passed_tests = passed_tests + 1;
            end else begin
                $display("[FAIL] %0s", description);
                failed_tests = failed_tests + 1;
            end
        end
    endtask

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        $dumpfile("sim/cache_storage_tb.vcd");
        $dumpvars(0, cache_storage_tb);

        // Initialize signals
        clk         = 1'b0;
        rst_n       = 1'b0;
        write_en    = 1'b0;
        write_index = 6'd0;
        write_tag   = 22'd0;
        write_data  = 128'd0;
        write_valid = 1'b0;
        read_index  = 6'd0;
        dec_addr    = 32'd0;

        $display("==================================================================");
        $display("   CACHE STORAGE SUBSYSTEM VERIFICATION SUITE                    ");
        $display("   Author: Mihika Mathur                                          ");
        $display("==================================================================");

        // =====================================================================
        // TC1: Valid bits reset to zero
        // =====================================================================
        $display("\n--- TC1: Valid bits reset to zero on rst_n ---");
        // Apply reset for 3 cycles
        @(posedge clk); @(posedge clk); @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        rst_n = 1'b0;
        @(posedge clk); @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // Sample every line and confirm valid=0
        begin : tc1_block
            integer all_zero;
            all_zero = 1;
            for (i = 0; i < NUM_LINES; i = i + 1) begin
                read_index = i[INDEX_BITS-1:0];
                #2;
                if (read_valid !== 1'b0) all_zero = 0;
            end
            check(all_zero, "TC1 - All 64 valid bits are 0 after reset");
        end

        // =====================================================================
        // TC2: Write data to all 64 lines and read back correctly
        // =====================================================================
        $display("\n--- TC2: Write and read back all 64 lines ---");
        // Write unique 128-bit pattern per line: {line_idx[7:0] replicated}
        for (i = 0; i < NUM_LINES; i = i + 1) begin
            write_line(
                i[INDEX_BITS-1:0],
                i[TAG_BITS-1:0],
                {16{i[7:0]}},     // 128-bit = 16 repetitions of 8-bit index
                1'b1
            );
        end
        // Verify every line
        begin : tc2_block
            integer all_match;
            all_match = 1;
            for (i = 0; i < NUM_LINES; i = i + 1) begin
                read_line(i[INDEX_BITS-1:0]);
                if (read_data !== {16{i[7:0]}}) all_match = 0;
            end
            check(all_match, "TC2 - Data matches expected pattern across all 64 lines");
        end

        // =====================================================================
        // TC3: Tags written independently to all 64 lines
        // =====================================================================
        $display("\n--- TC3: Tag write independently to all lines ---");
        begin : tc3_block
            integer tag_ok;
            tag_ok = 1;
            for (i = 0; i < NUM_LINES; i = i + 1) begin
                read_line(i[INDEX_BITS-1:0]);
                // Expected tag = i (written in TC2)
                if (read_tag !== i[TAG_BITS-1:0]) tag_ok = 0;
            end
            check(tag_ok, "TC3 - Tags match expected values across all 64 lines");
        end

        // =====================================================================
        // TC4: Correct data returned for a specific index (read-after-write)
        // =====================================================================
        $display("\n--- TC4: Correct data returned for specific index ---");
        write_line(6'd17, 22'hABCDE, 128'hDEAD_BEEF_CAFE_1234_5678_9ABC_DEF0_1122, 1'b1);
        read_line(6'd17);
        check(read_data === 128'hDEAD_BEEF_CAFE_1234_5678_9ABC_DEF0_1122,
              "TC4 - Correct 128-bit data returned for index 17");
        check(read_valid === 1'b1,
              "TC4 - Valid bit = 1 for index 17 after write");

        // =====================================================================
        // TC5: Correct tag returned for a specific index
        // =====================================================================
        $display("\n--- TC5: Correct tag returned for specific index ---");
        // TC4 already wrote tag=0xABCDE to line 17
        read_line(6'd17);
        check(read_tag === 22'hABCDE,
              "TC5 - Correct 22-bit tag (0xABCDE) returned for index 17");

        // =====================================================================
        // TC6: Updating one line does not corrupt an adjacent line
        // =====================================================================
        $display("\n--- TC6: Neighbor-line isolation after write ---");
        // Sample lines 16, 18 before modifying line 17 again
        read_line(6'd16);
        begin : tc6_check16_before
            reg [BLOCK_BITS-1:0] data_16_before;
            reg [TAG_BITS-1:0]   tag_16_before;
            data_16_before = read_data;
            tag_16_before  = read_tag;

            read_line(6'd18);
            begin : tc6_check18_before
                reg [BLOCK_BITS-1:0] data_18_before;
                reg [TAG_BITS-1:0]   tag_18_before;
                data_18_before = read_data;
                tag_18_before  = read_tag;

                // Now overwrite line 17 with completely different data
                write_line(6'd17, 22'h00001, 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF, 1'b1);

                // Re-read lines 16 and 18 and confirm no change
                read_line(6'd16);
                check((read_data === data_16_before) && (read_tag === tag_16_before),
                      "TC6 - Line 16 unchanged after write to line 17");

                read_line(6'd18);
                check((read_data === data_18_before) && (read_tag === tag_18_before),
                      "TC6 - Line 18 unchanged after write to line 17");
            end
        end

        // =====================================================================
        // TC7: Address decoder correctly separates tag, index, offset
        // =====================================================================
        $display("\n--- TC7: Address decoder field separation ---");
        // Address: 0x0000_1040 -> Tag=4, Index=4, Offset=0, Word=0, Byte=0
        dec_addr = 32'h0000_1040;
        #5;
        check(dec_tag === 22'h000004,  "TC7 - Tag=0x4 for addr 0x00001040");
        check(dec_index === 6'd4,      "TC7 - Index=4 for addr 0x00001040");
        check(dec_offset === 4'h0,     "TC7 - Offset=0 for addr 0x00001040");
        check(dec_word_sel === 2'd0,   "TC7 - Word=0 for addr 0x00001040");

        // Address: 0x0000_2040 -> Tag=8, Index=4 (same index, different tag = conflict)
        dec_addr = 32'h0000_2040;
        #5;
        check(dec_tag === 22'h000008,  "TC7 - Tag=0x8 for addr 0x00002040 (conflict pair)");
        check(dec_index === 6'd4,      "TC7 - Index=4 matches 0x00001040 (proves conflict)");

        // Address: 0xFFFF_FFFF boundary
        dec_addr = 32'hFFFF_FFFF;
        #5;
        check(dec_tag === 22'h3FFFFF,  "TC7 - Tag=0x3FFFFF for addr 0xFFFFFFFF");
        check(dec_index === 6'd63,     "TC7 - Index=63 for addr 0xFFFFFFFF");

        // =====================================================================
        // TC8: Repeated reads return stable data (combinational idempotence)
        // =====================================================================
        $display("\n--- TC8: Repeated reads return stable identical data ---");
        begin : tc8_block
            reg [BLOCK_BITS-1:0] first_read;
            reg [TAG_BITS-1:0]   first_tag;
            reg                  first_valid;
            integer stable;

            write_line(6'd33, 22'h1A2B3, 128'hABCD_1234_5678_DEAD_BEEF_CAFE_0000_FFFF, 1'b1);
            read_line(6'd33);
            first_read  = read_data;
            first_tag   = read_tag;
            first_valid = read_valid;

            stable = 1;
            repeat (5) begin
                read_line(6'd33);
                if (read_data !== first_read || read_tag !== first_tag ||
                    read_valid !== first_valid) stable = 0;
            end
            check(stable, "TC8 - 5 repeated reads to line 33 all return identical results");
        end

        // =====================================================================
        // TC9: Boundary conditions – line 0 / line 63, all-zero / all-one data
        // =====================================================================
        $display("\n--- TC9: Boundary lines and extreme data patterns ---");
        // Line 0 with all-zeros
        write_line(6'd0, 22'h000000, 128'h0, 1'b1);
        read_line(6'd0);
        check(read_data === 128'h0,            "TC9 - Line 0: all-zero data reads back correctly");
        check(read_tag  === 22'h000000,        "TC9 - Line 0: zero tag reads back correctly");
        check(read_valid === 1'b1,             "TC9 - Line 0: valid=1 after write");

        // Line 63 with all-ones
        write_line(6'd63, 22'h3FFFFF, {BLOCK_BITS{1'b1}}, 1'b1);
        read_line(6'd63);
        check(read_data === {BLOCK_BITS{1'b1}}, "TC9 - Line 63: all-ones data reads back correctly");
        check(read_tag  === 22'h3FFFFF,         "TC9 - Line 63: all-ones tag reads back correctly");

        // Write valid=0 to line 63 (invalidation)
        write_line(6'd63, 22'h3FFFFF, {BLOCK_BITS{1'b1}}, 1'b0);
        read_line(6'd63);
        check(read_valid === 1'b0, "TC9 - Line 63: explicit invalidation sets valid=0");

        // =====================================================================
        // TC10: Same-index / different-tag conflict eviction
        // =====================================================================
        $display("\n--- TC10: Conflict eviction - same index, different tags ---");
        // Write first block with Tag_A into line 7
        write_line(6'd7, 22'h000AAA, 128'h1111_2222_3333_4444_5555_6666_7777_8888, 1'b1);
        read_line(6'd7);
        check(read_tag   === 22'h000AAA, "TC10 - Initial line 7: Tag_A stored correctly");
        check(read_valid === 1'b1,       "TC10 - Initial line 7: valid=1 after first write");

        // Evict with Tag_B (conflict replacement)
        write_line(6'd7, 22'h000BBB, 128'h9999_AAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000, 1'b1);
        read_line(6'd7);
        check(read_tag  === 22'h000BBB,
              "TC10 - After eviction, line 7 holds Tag_B");
        check(read_data === 128'h9999_AAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000,
              "TC10 - After eviction, line 7 data is Tag_B block (not stale Tag_A)");
        check(read_valid === 1'b1,
              "TC10 - After eviction, line 7 valid=1");

        // Confirm lines 6 and 8 are unaffected
        read_line(6'd6);
        check(read_tag !== 22'h000BBB, "TC10 - Line 6 not contaminated by conflict eviction to line 7");
        read_line(6'd8);
        check(read_tag !== 22'h000BBB, "TC10 - Line 8 not contaminated by conflict eviction to line 7");

        // =====================================================================
        // Summary
        // =====================================================================
        $display("\n==================================================================");
        $display("   VERIFICATION SUMMARY                                           ");
        $display("   Total Checks:  %0d", total_tests);
        $display("   Passed Checks: %0d", passed_tests);
        $display("   Failed Checks: %0d", failed_tests);
        if (failed_tests == 0) begin
            $display("   STATUS: >>> ALL STORAGE TESTBENCH CHECKS PASSED <<<");
        end else begin
            $display("   STATUS: >>> %0d CHECKS FAILED - PLEASE REVIEW <<<", failed_tests);
        end
        $display("==================================================================");

        #(CLK_PERIOD * 5);
        $finish;
    end

endmodule
