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
    integer total_tests     = 0;
    integer passed_tests    = 0;
    integer failed_tests    = 0;
    integer total_cycles    = 0;
    integer hit_count       = 0;
    integer miss_count      = 0;
    integer conflict_count  = 0;
    integer compulsory_count = 0;

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

    always @(posedge clk) begin
        total_cycles = total_cycles + 1;
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
        begin
            total_tests   = total_tests + 1;
            idx           = addr[9:4];
            tg            = addr[31:10];
            expected_hit  = is_ref_hit(addr);
            expected_data = get_expected_word(addr);
            hit_sampled   = 1'b0;

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
    // Top-Level Verification Flow
    // ========================================================================
    initial begin
        $dumpfile("sim/tb_cache_top.vcd");
        $dumpvars(0, tb_cache_top);

        // Signal initialization
        clk          = 1'b0;
        rst_n        = 1'b0;
        cpu_req_val  = 1'b0;
        cpu_req_addr = 32'h0;
        reset_reference_model();

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
        // Execute Progressive Test Scenarios
        // --------------------------------------------------------------------
        run_test_cold_cache();
        run_test_temporal_locality();
        run_test_spatial_locality();
        run_test_conflict_miss();

        #(CLK_PERIOD * 5);
        $display("\n==================================================================");
        $display("   BASELINE TESTBENCH INITIALIZATION SUCCESSFUL                   ");
        $display("==================================================================");
        $finish;
    end

endmodule
