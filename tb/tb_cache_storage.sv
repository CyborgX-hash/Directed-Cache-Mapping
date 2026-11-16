// ============================================================================
// Module: tb_cache_storage
// Author: Ajit Kumar (Verification & Testbench Lead)
// Project: Design and Analysis of a Direct-Mapped Cache Controller
// Description: Advanced SystemVerilog unit testbench for the unified cache
//              storage subsystem (cache_data_ram, tag_ram, valid_bit_ram)
//              and address decoder integration.
//
// Verification Scope:
//   - TC1: Valid bits reset to zero on active-low reset (all 64 lines)
//   - TC2: All 64 lines write-after-read data integrity
//   - TC3: Independent tag array write and read verification
//   - TC4: Atomic refill update (data, tag, valid in single cycle)
//   - TC5: Adjacent line isolation (no cross-talk corruption)
//   - TC6: Combinational read stability under repeated reads
//   - TC7: Address boundary conditions (Index 0, Index 63, Min/Max Tags)
//   - TC8: Conflict eviction and replacement verification
// ============================================================================

`timescale 1ns / 1ps

module tb_cache_storage;

    // Parameters
    localparam NUM_LINES   = 64;
    localparam INDEX_BITS  = 6;
    localparam TAG_BITS    = 22;
    localparam BLOCK_BITS  = 128;
    localparam CLK_PERIOD  = 10;

    // Clock and Reset
    reg clk;
    reg rst_n;

    // Storage Interface Signals
    reg  [INDEX_BITS-1:0]  read_index;
    wire                   read_valid;
    wire [TAG_BITS-1:0]    read_tag;
    wire [BLOCK_BITS-1:0]  read_data;

    reg                    write_en;
    reg  [INDEX_BITS-1:0]  write_index;
    reg  [TAG_BITS-1:0]    write_tag;
    reg  [BLOCK_BITS-1:0]  write_data;
    reg                    write_valid;

    // Test Tracking
    integer total_tests  = 0;
    integer passed_tests = 0;
    integer failed_tests = 0;
    integer i;

    // Instantiate DUT: cache_storage
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

    // Clock Generator: 100 MHz
    always #(CLK_PERIOD / 2) clk = ~clk;

    // Synchronous write task
    task automatic write_line(
        input [INDEX_BITS-1:0] widx,
        input [TAG_BITS-1:0]   wtag,
        input [BLOCK_BITS-1:0] wdata,
        input                  wvalid
    );
        begin
            @(negedge clk);
            write_en    = 1'b1;
            write_index = widx;
            write_tag   = wtag;
            write_data  = wdata;
            write_valid = wvalid;
            @(posedge clk);
            #1;
            write_en    = 1'b0;
        end
    endtask

    // Combinational read task
    task automatic read_line(input [INDEX_BITS-1:0] ridx);
        begin
            @(negedge clk);
            read_index = ridx;
            #2;
        end
    endtask

    // Verification check assertion task
    task automatic check(
        input        condition,
        input string description
    );
        begin
            total_tests = total_tests + 1;
            if (condition) begin
                $display("[PASS] %s", description);
                passed_tests = passed_tests + 1;
            end else begin
                $display("[FAIL] %s", description);
                failed_tests = failed_tests + 1;
            end
        end
    endtask

    // Storage Verification Flow
    initial begin
        $dumpfile("sim/tb_cache_storage.vcd");
        $dumpvars(0, tb_cache_storage);

        // Signal initialization
        clk         = 1'b0;
        rst_n       = 1'b0;
        write_en    = 1'b0;
        write_index = 6'd0;
        write_tag   = 22'd0;
        write_data  = 128'd0;
        write_valid = 1'b0;
        read_index  = 6'd0;

        $display("==================================================================");
        $display("   CACHE STORAGE UNIT TESTBENCH (tb_cache_storage.sv)             ");
        $display("   Author: Ajit Kumar (Verification & Testbench Lead)             ");
        $display("==================================================================");

        // --------------------------------------------------------------------
        // TC1: Valid bits reset to zero on all 64 lines
        // --------------------------------------------------------------------
        $display("\n--- TC1: Verify Valid Bit Reset to Zero on All 64 Lines ---");
        #(CLK_PERIOD * 3);
        rst_n = 1'b1;
        #(CLK_PERIOD * 2);

        begin : tc1_verify
            integer all_zero = 1;
            for (i = 0; i < NUM_LINES; i = i + 1) begin
                read_line(i[INDEX_BITS-1:0]);
                if (read_valid !== 1'b0) begin
                    all_zero = 0;
                    $display("[FAIL] TC1: Line %0d valid bit is not 0 after reset!", i);
                end
            end
            check(all_zero == 1, "TC1: All 64 lines reset with valid=0");
        end

        // --------------------------------------------------------------------
        // TC2: Write and read back unique data across all 64 lines
        // --------------------------------------------------------------------
        $display("\n--- TC2: Write & Read Back Unique 128-bit Data for All 64 Lines ---");
        for (i = 0; i < NUM_LINES; i = i + 1) begin
            write_line(i[INDEX_BITS-1:0], (22'h100 + i), {4{32'hA000_0000 | i}}, 1'b1);
        end

        begin : tc2_verify
            integer all_match = 1;
            for (i = 0; i < NUM_LINES; i = i + 1) begin
                read_line(i[INDEX_BITS-1:0]);
                if (read_data !== {4{32'hA000_0000 | i}} || read_valid !== 1'b1) begin
                    all_match = 0;
                    $display("[FAIL] TC2: Line %0d data mismatch! Got: 0x%032h", i, read_data);
                end
            end
            check(all_match == 1, "TC2: All 64 lines read-after-write data integrity verified");
        end

        // --------------------------------------------------------------------
        // TC3: Independent Tag Verification across all 64 lines
        // --------------------------------------------------------------------
        $display("\n--- TC3: Independent Tag Array Read/Write Verification ---");
        begin : tc3_verify
            integer tag_match = 1;
            for (i = 0; i < NUM_LINES; i = i + 1) begin
                read_line(i[INDEX_BITS-1:0]);
                if (read_tag !== (22'h100 + i)) begin
                    tag_match = 0;
                    $display("[FAIL] TC3: Line %0d tag mismatch! Expected: 0x%06h, Got: 0x%06h",
                             i, (22'h100 + i), read_tag);
                end
            end
            check(tag_match == 1, "TC3: All 64 lines tag values match stored tags");
        end

        // --------------------------------------------------------------------
        // TC4: Atomic Refill (Data, Tag, Valid in Single Cycle)
        // --------------------------------------------------------------------
        $display("\n--- TC4: Atomic Refill Update (Data, Tag, Valid in Single Cycle) ---");
        write_line(6'd15, 22'h3FFFFF, 128'hFFFF_FFFF_EEEE_EEEE_DDDD_DDDD_CCCC_CCCC, 1'b1);
        read_line(6'd15);
        check(read_valid == 1'b1 && read_tag == 22'h3FFFFF &&
              read_data == 128'hFFFF_FFFF_EEEE_EEEE_DDDD_DDDD_CCCC_CCCC,
              "TC4: Single-cycle atomic update of line 15 (valid, tag, data)");

        // --------------------------------------------------------------------
        // TC5: Adjacent Line Isolation (No Cross-Talk)
        // --------------------------------------------------------------------
        $display("\n--- TC5: Adjacent Line Isolation Test ---");
        // Overwrite Line 20, ensure Line 19 and Line 21 remain untouched
        read_line(6'd19);
        begin : tc5_verify
            reg [BLOCK_BITS-1:0] prev_data_19;
            reg [BLOCK_BITS-1:0] prev_data_21;
            read_line(6'd19);
            prev_data_19 = read_data;
            read_line(6'd21);
            prev_data_21 = read_data;

            // Overwrite Line 20 with new data
            write_line(6'd20, 22'h000055, 128'h5555_5555_5555_5555_5555_5555_5555_5555, 1'b1);

            // Re-read 19 and 21
            read_line(6'd19);
            check(read_data == prev_data_19, "TC5: Line 19 unaffected by Line 20 write");
            read_line(6'd21);
            check(read_data == prev_data_21, "TC5: Line 21 unaffected by Line 20 write");
        end

        // --------------------------------------------------------------------
        // TC6: Combinational Read Stability
        // --------------------------------------------------------------------
        $display("\n--- TC6: Combinational Read Stability (Repeated Reads) ---");
        begin : tc6_verify
            integer stable = 1;
            for (i = 0; i < 5; i = i + 1) begin
                read_line(6'd20);
                if (read_data !== 128'h5555_5555_5555_5555_5555_5555_5555_5555 ||
                    read_tag !== 22'h000055 || read_valid !== 1'b1) begin
                    stable = 0;
                end
            end
            check(stable == 1, "TC6: Combinational read values perfectly stable across multiple cycles");
        end

        // --------------------------------------------------------------------
        // TC7: Boundary Lines (Line 0 and Line 63)
        // --------------------------------------------------------------------
        $display("\n--- TC7: Boundary Address Tests (Line 0 & Line 63) ---");
        write_line(6'd0, 22'h000000, 128'h0, 1'b1);
        read_line(6'd0);
        check(read_valid == 1'b1 && read_tag == 22'h0 && read_data == 128'h0,
              "TC7.1: Line 0 boundary with all-zeros write");

        write_line(6'd63, 22'h3FFFFF, {128{1'b1}}, 1'b1);
        read_line(6'd63);
        check(read_valid == 1'b1 && read_tag == 22'h3FFFFF && read_data == {128{1'b1}},
              "TC7.2: Line 63 boundary with all-ones write");

        // --------------------------------------------------------------------
        // TC8: Conflict Eviction & Overwrite
        // --------------------------------------------------------------------
        $display("\n--- TC8: Conflict Eviction & Overwrite ---");
        // Overwrite Line 0 with new tag and data
        write_line(6'd0, 22'h123456, 128'hFEED_FACE_CAFE_BEEF_0123_4567_89AB_CDEF, 1'b1);
        read_line(6'd0);
        check(read_valid == 1'b1 && read_tag == 22'h123456 &&
              read_data == 128'hFEED_FACE_CAFE_BEEF_0123_4567_89AB_CDEF,
              "TC8: Line 0 cleanly evicted and updated with new tag/data");

        // Summary
        $display("\n==================================================================");
        $display("   CACHE STORAGE UNIT VERIFICATION SUMMARY                        ");
        $display("   Total Checks:  %0d", total_tests);
        $display("   Passed Checks: %0d", passed_tests);
        $display("   Failed Checks: %0d", failed_tests);
        if (failed_tests == 0) begin
            $display("   STATUS: >>> ALL STORAGE TESTS PASSED SUCCESSFULLY! <<<");
        end else begin
            $display("   STATUS: >>> SOME STORAGE TESTS FAILED! <<<");
        end
        $display("==================================================================");

        #(CLK_PERIOD * 5);
        $finish;
    end

endmodule
