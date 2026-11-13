// ============================================================================
// Testbench: address_decoder_tb
// Author: Mihika Mathur
// Project: Design and Analysis of a Direct-Mapped Cache Controller
// Description: Unit testbench for parameterized address decoder verifying:
//              - Tag extraction (address[31:10], 22 bits)
//              - Index extraction (address[9:4], 6 bits)
//              - Block offset extraction (address[3:0], 4 bits)
//              - Word select extraction (address[3:2], 2 bits)
//              - Byte offset extraction (address[1:0], 2 bits)
//              - Boundary addresses (0x00000000, 0xFFFFFFFF, line 0, line 63)
//              - Multiple addresses sharing same index but different tags
// ============================================================================

`timescale 1ns / 1ps

module address_decoder_tb;

    // Parameters
    localparam ADDR_WIDTH     = 32;
    localparam TAG_WIDTH      = 22;
    localparam INDEX_WIDTH    = 6;
    localparam OFFSET_WIDTH   = 4;
    localparam WORD_SEL_WIDTH = 2;
    localparam BYTE_SEL_WIDTH = 2;

    // Testbench Signals
    reg  [ADDR_WIDTH-1:0]     addr;
    wire [TAG_WIDTH-1:0]      tag;
    wire [INDEX_WIDTH-1:0]    index;
    wire [OFFSET_WIDTH-1:0]   offset;
    wire [WORD_SEL_WIDTH-1:0] word_sel;
    wire [BYTE_SEL_WIDTH-1:0] byte_offset;

    // Test Tracking
    integer total_tests  = 0;
    integer passed_tests = 0;
    integer failed_tests = 0;

    // Instantiate Device Under Test
    address_decoder #(
        .ADDR_WIDTH     (ADDR_WIDTH),
        .TAG_WIDTH      (TAG_WIDTH),
        .INDEX_WIDTH    (INDEX_WIDTH),
        .OFFSET_WIDTH   (OFFSET_WIDTH),
        .WORD_SEL_WIDTH (WORD_SEL_WIDTH),
        .BYTE_SEL_WIDTH (BYTE_SEL_WIDTH)
    ) dut (
        .addr        (addr),
        .tag         (tag),
        .index       (index),
        .offset      (offset),
        .word_sel    (word_sel),
        .byte_offset (byte_offset)
    );

    // Verification Task
    task verify_address(
        input [ADDR_WIDTH-1:0]     test_addr,
        input [TAG_WIDTH-1:0]      exp_tag,
        input [INDEX_WIDTH-1:0]    exp_index,
        input [OFFSET_WIDTH-1:0]   exp_offset,
        input [WORD_SEL_WIDTH-1:0] exp_word_sel,
        input [BYTE_SEL_WIDTH-1:0] exp_byte_offset,
        input [255:0]              test_desc
    );
        begin
            total_tests = total_tests + 1;
            addr = test_addr;
            #5; // Allow combinational propagation

            if (tag !== exp_tag || index !== exp_index || offset !== exp_offset ||
                word_sel !== exp_word_sel || byte_offset !== exp_byte_offset) begin
                $display("[FAIL] %0s | Addr: 0x%08h", test_desc, test_addr);
                $display("       Expected: Tag=0x%06h, Idx=0x%02h, Off=0x%01h, Word=%0d, Byte=%0d",
                         exp_tag, exp_index, exp_offset, exp_word_sel, exp_byte_offset);
                $display("       Observed: Tag=0x%06h, Idx=0x%02h, Off=0x%01h, Word=%0d, Byte=%0d",
                         tag, index, offset, word_sel, byte_offset);
                failed_tests = failed_tests + 1;
            end else begin
                $display("[PASS] %0s | Addr: 0x%08h -> Tag: 0x%06h, Idx: %2d, Off: 0x%01h, Word: %0d, Byte: %0d",
                         test_desc, test_addr, tag, index, offset, word_sel, byte_offset);
                passed_tests = passed_tests + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("sim/address_decoder_tb.vcd");
        $dumpvars(0, address_decoder_tb);

        $display("==================================================================");
        $display("   ADDRESS DECODER UNIT VERIFICATION SUITE                        ");
        $display("   Author: Mihika Mathur                                          ");
        $display("==================================================================");

        // Test 1: Zero Address Boundary
        verify_address(32'h0000_0000, 22'h000000, 6'd0, 4'h0, 2'd0, 2'd0, "Boundary Min (All Zeroes)");

        // Test 2: Maximum Address Boundary
        verify_address(32'hFFFF_FFFF, 22'h3FFFFF, 6'd63, 4'hF, 2'd3, 2'd3, "Boundary Max (All Ones)");

        // Test 3: System Test Address from Saksham's top TB
        verify_address(32'h0000_1040, 22'h000004, 6'd4, 4'h0, 2'd0, 2'd0, "Saksham Addr 1 (Cold Miss)");

        // Test 4: Different word in same block
        verify_address(32'h0000_1048, 22'h000004, 6'd4, 4'h8, 2'd2, 2'd0, "Saksham Addr 2 (Word 2 Hit)");

        // Test 5: Conflict address (identical index 4, different tag 8)
        verify_address(32'h0000_2040, 22'h000008, 6'd4, 4'h0, 2'd0, 2'd0, "Saksham Addr 3 (Conflict Miss)");

        // Test 6: Word selection sweep within one block
        verify_address(32'hAAAA_0000, 22'h2AAA80, 6'd0, 4'h0, 2'd0, 2'd0, "Word 0 Offset 0");
        verify_address(32'hAAAA_0004, 22'h2AAA80, 6'd0, 4'h4, 2'd1, 2'd0, "Word 1 Offset 4");
        verify_address(32'hAAAA_0008, 22'h2AAA80, 6'd0, 4'h8, 2'd2, 2'd0, "Word 2 Offset 8");
        verify_address(32'hAAAA_000C, 22'h2AAA80, 6'd0, 4'hC, 2'd3, 2'd0, "Word 3 Offset 12");

        // Test 7: Byte offset sweep
        verify_address(32'hAAAA_000D, 22'h2AAA80, 6'd0, 4'hD, 2'd3, 2'd1, "Byte Offset 1");
        verify_address(32'hAAAA_000E, 22'h2AAA80, 6'd0, 4'hE, 2'd3, 2'd2, "Byte Offset 2");
        verify_address(32'hAAAA_000F, 22'h2AAA80, 6'd0, 4'hF, 2'd3, 2'd3, "Byte Offset 3");

        // Test 8: Index boundary checks: Index 0, Index 1, Index 62, Index 63
        verify_address(32'h0000_0000, 22'h000000, 6'd0,  4'h0, 2'd0, 2'd0, "Index 0 Boundary");
        verify_address(32'h0000_0010, 22'h000000, 6'd1,  4'h0, 2'd0, 2'd0, "Index 1 Boundary");
        verify_address(32'h0000_03E0, 22'h000000, 6'd62, 4'h0, 2'd0, 2'd0, "Index 62 Boundary");
        verify_address(32'h0000_03F0, 22'h000000, 6'd63, 4'h0, 2'd0, 2'd0, "Index 63 Boundary");

        // Test 9: Complex arbitrary pattern
        // 0x12345678:
        //   [31:10] = 0x12345678 >> 10 = 0x48D15 (22 bits)
        //   [9:4]   = (0x12345678 >> 4) & 0x3F = 0x27 = 39 (6 bits)
        //   [3:0]   = 0x12345678 & 0x0F = 0x8 (4 bits)
        //   [3:2]   = 2'b10 = 2
        //   [1:0]   = 2'b00 = 0
        verify_address(32'h1234_5678, 22'h048D15, 6'd39, 4'h8, 2'd2, 2'd0, "Arbitrary Hex 0x12345678");

        $display("\n==================================================================");
        $display("   VERIFICATION SUMMARY                                           ");
        $display("   Total Checks:  %0d", total_tests);
        $display("   Passed Checks: %0d", passed_tests);
        $display("   Failed Checks: %0d", failed_tests);
        if (failed_tests == 0) begin
            $display("   STATUS: >>> ALL ADDRESS DECODER TESTS PASSED <<<");
        end else begin
            $display("   STATUS: >>> TESTS FAILED <<<");
        end
        $display("==================================================================");

        #10;
        $finish;
    end

endmodule
