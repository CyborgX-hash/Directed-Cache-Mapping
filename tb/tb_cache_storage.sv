// ============================================================================
// Module: tb_cache_storage
// Author: Ajit Kumar (Verification & Testbench Lead)
// Project: Design and Analysis of a Direct-Mapped Cache Controller
// Description: Advanced SystemVerilog unit testbench for the unified cache
//              storage subsystem (cache_data_ram, tag_ram, valid_bit_ram)
//              and address decoder integration.
//
// Verification Scope:
//   - TC1: Valid bits reset to zero on active-low reset
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

        // Power-on reset
        #(CLK_PERIOD * 3);
        rst_n = 1'b1;
        #(CLK_PERIOD * 2);

        $display("\n--- TC1: Verify Valid Bit Reset to Zero on All 64 Lines ---");
        begin : tc1_verify
            integer all_zero = 1;
            for (i = 0; i < NUM_LINES; i = i + 1) begin
                read_index = i[INDEX_BITS-1:0];
                #2;
                if (read_valid !== 1'b0) begin
                    all_zero = 0;
                    $display("[FAIL] TC1: Line %0d valid bit is not 0 after reset!", i);
                end
            end
            check(all_zero == 1, "TC1: All 64 lines reset with valid=0");
        end

        #(CLK_PERIOD * 5);
        $display("\n==================================================================");
        $display("   STORAGE TESTBENCH BASELINE INITIALIZATION COMPLETE             ");
        $display("==================================================================");
        $finish;
    end

endmodule
