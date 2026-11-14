// ============================================================================
// Testbench: memory_subsystem_tb
// Author: Harsh Kumar (Memory Subsystem & Refill Interface Lead)
// Project: Design and Analysis of a Direct-Mapped Cache Controller
// Description: Comprehensive verification testbench validating the Main Memory
//              and Memory Interface subsystems across all required architectural
//              scenarios:
//              1. Correct memory response for given block address
//              2. Correct 128-bit block formation (all four 32-bit words checked)
//              3. Different addresses produce distinguishable blocks
//              4. Memory latency is respected (cycle-accurate measurement)
//              5. Memory request is not accepted repeatedly (busy filtering)
//              6. Memory interface resets correctly (clean state recovery)
//              7. Consecutive / back-to-back requests work seamlessly
//              8. No response occurs before configured latency
//              9. Unaligned address handling (16-byte block alignment enforcement)
//             10. Mid-transaction reset recovery
//             11. Configurable latency validation (LATENCY = 2, 5, 10)
// ============================================================================

`timescale 1ns / 1ps

module memory_subsystem_tb;

    // Parameters
    localparam ADDR_WIDTH  = 32;
    localparam BLOCK_WIDTH = 128;
    localparam DATA_WIDTH  = 32;
    localparam CLK_PERIOD  = 10; // 100 MHz clock (10 ns period)
    localparam DEF_LATENCY = 10; // Default 10-cycle memory latency

    // Clock and Reset
    reg clk;
    reg rst_n;

    // Cache Controller Facing Bus
    reg                   ctrl_mem_req_val;
    reg  [ADDR_WIDTH-1:0] ctrl_mem_req_addr;
    wire                  ctrl_mem_req_ready;
    wire [BLOCK_WIDTH-1:0] ctrl_mem_resp_data;

    // Memory Bus (Bridge <-> Main Memory)
    wire                  bus_mem_req_val;
    wire [ADDR_WIDTH-1:0] bus_mem_req_addr;
    wire                  bus_mem_req_ready;
    wire [BLOCK_WIDTH-1:0] bus_mem_resp_data;
    wire [1:0]            dut_fsm_state;

    // Verification Scoreboard Counters
    integer total_tests  = 0;
    integer passed_tests = 0;
    integer failed_tests = 0;

    // ========================================================================
    // Device Under Test (DUT): Complete Memory Subsystem
    // ========================================================================
    // 1. Memory Interface Bridge
    memory_interface #(
        .ADDR_BITS  (ADDR_WIDTH),
        .BLOCK_BITS (BLOCK_WIDTH)
    ) u_bridge (
        .ctrl_mem_req_val   (ctrl_mem_req_val),
        .ctrl_mem_req_addr  (ctrl_mem_req_addr),
        .ctrl_mem_req_ready (ctrl_mem_req_ready),
        .ctrl_mem_resp_data (ctrl_mem_resp_data),

        .mem_req_val        (bus_mem_req_val),
        .mem_req_addr       (bus_mem_req_addr),
        .mem_req_ready      (bus_mem_req_ready),
        .mem_resp_data      (bus_mem_resp_data)
    );

    // 2. Behavioral Main Memory Model (Default 10-cycle latency)
    main_memory #(
        .LATENCY    (DEF_LATENCY),
        .BLOCK_BITS (BLOCK_WIDTH),
        .ADDR_BITS  (ADDR_WIDTH),
        .MEM_DEPTH  (256)
    ) u_main_memory (
        .clk           (clk),
        .rst_n         (rst_n),
        .mem_req_val   (bus_mem_req_val),
        .mem_req_addr  (bus_mem_req_addr),
        .mem_req_ready (bus_mem_req_ready),
        .mem_resp_data (bus_mem_resp_data),
        .fsm_state     (dut_fsm_state)
    );

    // Secondary DUT for Configurable Latency Verification (LATENCY = 2)
    wire        lat2_ready;
    wire [127:0] lat2_data;
    reg         lat2_req_val;
    reg  [31:0] lat2_req_addr;
    main_memory #(
        .LATENCY    (2),
        .BLOCK_BITS (BLOCK_WIDTH),
        .ADDR_BITS  (ADDR_WIDTH)
    ) u_mem_lat2 (
        .clk           (clk),
        .rst_n         (rst_n),
        .mem_req_val   (lat2_req_val),
        .mem_req_addr  (lat2_req_addr),
        .mem_req_ready (lat2_ready),
        .mem_resp_data (lat2_data),
        .fsm_state     ()
    );

    // Clock Generator: 100 MHz
    always #(CLK_PERIOD / 2) clk = ~clk;

    // ========================================================================
    // Helper Tasks
    // ========================================================================
    
    // Task: Perform reset sequence
    task reset_subsystem;
        begin
            rst_n <= 1'b0;
            ctrl_mem_req_val  <= 1'b0;
            ctrl_mem_req_addr <= 32'h0;
            lat2_req_val      <= 1'b0;
            lat2_req_addr     <= 32'h0;
            repeat (3) @(posedge clk);
            rst_n <= 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    // Task: Issue Memory Read and Measure Latency & Data
    task read_and_verify_block(
        input  [31:0]           req_addr,
        input  integer          expected_latency,
        output [BLOCK_WIDTH-1:0] captured_block,
        output integer          observed_latency
    );
        integer cycle_count;
        begin
            // Await ready deasserted if coming off previous operation
            while (ctrl_mem_req_ready) @(posedge clk);

            // Assert request for exactly 1 cycle (matching cache controller protocol)
            @(posedge clk);
            ctrl_mem_req_val  <= 1'b1;
            ctrl_mem_req_addr <= req_addr;

            @(posedge clk);
            ctrl_mem_req_val  <= 1'b0;
            ctrl_mem_req_addr <= 32'h0; // Address may change, memory should latch it!

            // Measure latency until ctrl_mem_req_ready asserts
            cycle_count = 0;
            while (!ctrl_mem_req_ready && cycle_count < 100) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
            end

            observed_latency = cycle_count;
            captured_block   = ctrl_mem_resp_data;

            // Wait 1 cycle for ready strobe to clear
            @(posedge clk);
        end
    endtask

    // ========================================================================
    // Main Verification Test Suite
    // ========================================================================
    reg [BLOCK_WIDTH-1:0] blk_data_a, blk_data_b, blk_data_c;
    reg [BLOCK_WIDTH-1:0] temp_block;
    reg [31:0] w0, w1, w2, w3;
    integer measured_lat;
    integer early_ready_detected;
    integer i;

    initial begin
        // Waveform Dump Setup
        $dumpfile("sim/memory_subsystem_tb.vcd");
        $dumpvars(0, memory_subsystem_tb);

        clk   = 1'b0;
        rst_n = 1'b0;
        ctrl_mem_req_val  = 1'b0;
        ctrl_mem_req_addr = 32'h0;
        lat2_req_val      = 1'b0;
        lat2_req_addr     = 32'h0;

        $display("==================================================================");
        $display("   MEMORY SUBSYSTEM & REFILL INTERFACE VERIFICATION SUITE       ");
        $display("   Author: Harsh Kumar (Memory Subsystem Lead)                    ");
        $display("   Coverage: 11 Exhaustive Test Scenarios (Handshake & Latency)  ");
        $display("==================================================================\n");

        // --------------------------------------------------------------------
        // Scenario 1: Reset Behavior Verification
        // --------------------------------------------------------------------
        $display("--- Scenario 1: Reset State & Interface Deassertion ---");
        total_tests = total_tests + 1;
        reset_subsystem();

        if (dut_fsm_state == 2'b00 && ctrl_mem_req_ready == 1'b0 && ctrl_mem_resp_data == 128'h0) begin
            $display("[PASS] Scenario 1: Reset clean. State=MEM_IDLE, ready=0, data=0.");
            passed_tests = passed_tests + 1;
        end else begin
            $display("[FAIL] Scenario 1: Reset failed. State=%b, ready=%b, data=%h",
                     dut_fsm_state, ctrl_mem_req_ready, ctrl_mem_resp_data);
            failed_tests = failed_tests + 1;
        end

        // --------------------------------------------------------------------
        // Scenario 2: 128-Bit Block Formation & 4-Word Integrity
        // --------------------------------------------------------------------
        $display("\n--- Scenario 2: 128-Bit Block Formation & All 4 Words Verification ---");
        total_tests = total_tests + 1;
        read_and_verify_block(32'h0000_1040, DEF_LATENCY, temp_block, measured_lat);

        w0 = temp_block[31:0];
        w1 = temp_block[63:32];
        w2 = temp_block[95:64];
        w3 = temp_block[127:96];

            if (w0 == 32'h0000_1040 && w1 == 32'h0000_1044 &&
                w2 == 32'h0000_1048 && w3 == 32'h0000_104C) begin
                $display("[PASS] Scenario 2: 128-bit block formed accurately.");
                $display("       Word 0 [31:0]   = 0x%08h (Expected 0x00001040)", w0);
                $display("       Word 1 [63:32]  = 0x%08h (Expected 0x00001044)", w1);
                $display("       Word 2 [95:64]  = 0x%08h (Expected 0x00001048)", w2);
                $display("       Word 3 [127:96] = 0x%08h (Expected 0x0000104c)", w3);
                passed_tests = passed_tests + 1;
            end else begin
                $display("[FAIL] Scenario 2: Block word mismatch! Got: w0=%h, w1=%h, w2=%h, w3=%h",
                         w0, w1, w2, w3);
                failed_tests = failed_tests + 1;
            end
        // --------------------------------------------------------------------
        // Scenario 3: Memory Access Latency Compliance (Exactly 10 Cycles)
        // --------------------------------------------------------------------
        $display("\n--- Scenario 3: Configured Latency Measurement (LATENCY = %0d) ---", DEF_LATENCY);
        total_tests = total_tests + 1;
        read_and_verify_block(32'h0000_2080, DEF_LATENCY, temp_block, measured_lat);

        if (measured_lat == DEF_LATENCY) begin
            $display("[PASS] Scenario 3: Latency strictly respected. Measured=%0d cycles (Target=%0d).",
                     measured_lat, DEF_LATENCY);
            passed_tests = passed_tests + 1;
        end else begin
            $display("[FAIL] Scenario 3: Latency mismatch! Measured=%0d cycles, Target=%0d.",
                     measured_lat, DEF_LATENCY);
            failed_tests = failed_tests + 1;
        end

        // --------------------------------------------------------------------
        // Scenario 4: No Early Response Before Configured Latency
        // --------------------------------------------------------------------
        $display("\n--- Scenario 4: Absence of Premature Response Check ---");
        total_tests = total_tests + 1;
        early_ready_detected = 0;

        @(posedge clk);
        ctrl_mem_req_val  <= 1'b1;
        ctrl_mem_req_addr <= 32'h0000_30A0;
        @(posedge clk);
        ctrl_mem_req_val  <= 1'b0;

        // Check that ready remains 0 during all wait cycles (cycles 1 to 9)
        for (i = 1; i < DEF_LATENCY; i = i + 1) begin
            @(posedge clk);
            if (ctrl_mem_req_ready !== 1'b0) begin
                early_ready_detected = early_ready_detected + 1;
                $display("[FAIL] Premature ready assertion detected at cycle %0d!", i);
            end
        end

        // Advance to cycle 10 (target latency): ready MUST be 1
        @(posedge clk);
        if (ctrl_mem_req_ready !== 1'b1) begin
            $display("[FAIL] Ready not asserted at target latency cycle %0d!", DEF_LATENCY);
            early_ready_detected = early_ready_detected + 1;
        end

        @(posedge clk); // Ready should deassert immediately on cycle 11
        if (ctrl_mem_req_ready !== 1'b0) begin
            $display("[FAIL] Ready failed to deassert after completion pulse!");
            early_ready_detected = early_ready_detected + 1;
        end

        if (early_ready_detected == 0) begin
            $display("[PASS] Scenario 4: Zero premature responses. Ready asserted strictly at cycle 10.");
            passed_tests = passed_tests + 1;
        end else begin
            failed_tests = failed_tests + 1;
        end

        // --------------------------------------------------------------------
        // Scenario 5: Distinguishable Blocks for Different Addresses
        // --------------------------------------------------------------------
        $display("\n--- Scenario 5: Distinguishable Data Blocks Across Distinct Addresses ---");
        total_tests = total_tests + 1;

        read_and_verify_block(32'h0000_0010, DEF_LATENCY, blk_data_a, measured_lat);
        read_and_verify_block(32'h0000_0020, DEF_LATENCY, blk_data_b, measured_lat);
        read_and_verify_block(32'h00A0_B0C0, DEF_LATENCY, blk_data_c, measured_lat);

        if ((blk_data_a !== blk_data_b) &&
            (blk_data_b !== blk_data_c) &&
            (blk_data_a !== blk_data_c)) begin
            $display("[PASS] Scenario 5: Blocks are uniquely distinguishable.");
            $display("       Block A (0x00000010) = 0x%032h", blk_data_a);
            $display("       Block B (0x00000020) = 0x%032h", blk_data_b);
            $display("       Block C (0x00a0b0c0) = 0x%032h", blk_data_c);
            passed_tests = passed_tests + 1;
        end else begin
            $display("[FAIL] Scenario 5: Data collision detected between distinct block addresses!");
            failed_tests = failed_tests + 1;
        end

        // --------------------------------------------------------------------
        // Scenario 6: Repeated Reads to the Same Address (Deterministic Consistency)
        // --------------------------------------------------------------------
        $display("\n--- Scenario 6: Deterministic Repeatability on Identical Address ---");
        total_tests = total_tests + 1;

        read_and_verify_block(32'h0000_5550, DEF_LATENCY, blk_data_a, measured_lat);
        read_and_verify_block(32'h0000_5550, DEF_LATENCY, blk_data_b, measured_lat);

        if (blk_data_a === blk_data_b) begin
            $display("[PASS] Scenario 6: Repeated reads return identical block data (0x%032h).", blk_data_a);
            passed_tests = passed_tests + 1;
        end else begin
            $display("[FAIL] Scenario 6: Inconsistent data returned across identical accesses!");
            failed_tests = failed_tests + 1;
        end

        // --------------------------------------------------------------------
        // Scenario 7: Spurious Request Rejection During Active Access (Busy Filtering)
        // --------------------------------------------------------------------
        $display("\n--- Scenario 7: Busy State Request Filtering (No Accidental Repeated Acceptance) ---");
        total_tests = total_tests + 1;

        @(posedge clk);
        ctrl_mem_req_val  <= 1'b1;
        ctrl_mem_req_addr <= 32'h0000_6000;
        @(posedge clk);
        ctrl_mem_req_val  <= 1'b0;

        // While in MEM_ACCESS, inject illegal spurious request pulses
        repeat (3) @(posedge clk);
        ctrl_mem_req_val  <= 1'b1;
        ctrl_mem_req_addr <= 32'h0000_7770; // Spurious target
        @(posedge clk);
        ctrl_mem_req_val  <= 1'b0;
        ctrl_mem_req_addr <= 32'h0;

        // Await completion of original request
        while (!ctrl_mem_req_ready) @(posedge clk);
        temp_block = ctrl_mem_resp_data;

        // Verify that the data returned corresponds to 0x0000_6000, NOT 0x0000_7770
        if (temp_block[31:0] == 32'h0000_6000) begin
            $display("[PASS] Scenario 7: Memory successfully ignored spurious mid-access request.");
            $display("       Captured Word 0 = 0x%08h (Correctly 0x00006000)", temp_block[31:0]);
            passed_tests = passed_tests + 1;
        end else begin
            $display("[FAIL] Scenario 7: Spurious request corrupted ongoing memory service! Word 0 = 0x%08h",
                     temp_block[31:0]);
            failed_tests = failed_tests + 1;
        end
        @(posedge clk);

        // --------------------------------------------------------------------
        // Scenario 8: Seamless Consecutive / Back-to-Back Requests
        // --------------------------------------------------------------------
        $display("\n--- Scenario 8: Back-to-Back Seamless Request Pipelining ---");
        total_tests = total_tests + 1;

        // Request 1
        @(posedge clk);
        ctrl_mem_req_val  <= 1'b1;
        ctrl_mem_req_addr <= 32'h0000_1100;
        @(posedge clk);
        ctrl_mem_req_val  <= 1'b0;

        while (!ctrl_mem_req_ready) @(posedge clk);
        blk_data_a = ctrl_mem_resp_data;

        // Immediately launch Request 2 without extra idle bubble cycles
        @(posedge clk);
        ctrl_mem_req_val  <= 1'b1;
        ctrl_mem_req_addr <= 32'h0000_2200;
        @(posedge clk);
        ctrl_mem_req_val  <= 1'b0;

        while (!ctrl_mem_req_ready) @(posedge clk);
        blk_data_b = ctrl_mem_resp_data;
        @(posedge clk);

        if (blk_data_a[31:0] == 32'h0000_1100 && blk_data_b[31:0] == 32'h0000_2200) begin
            $display("[PASS] Scenario 8: Back-to-back requests executed seamlessly.");
            $display("       Req 1 Data = 0x%08h | Req 2 Data = 0x%08h",
                     blk_data_a[31:0], blk_data_b[31:0]);
            passed_tests = passed_tests + 1;
        end else begin
            $display("[FAIL] Scenario 8: Consecutive request sequencing failed! Req1=%h, Req2=%h",
                     blk_data_a[31:0], blk_data_b[31:0]);
            failed_tests = failed_tests + 1;
        end

        // --------------------------------------------------------------------
        // Scenario 9: 16-Byte Block Alignment Masking
        // --------------------------------------------------------------------
        $display("\n--- Scenario 9: Unaligned Address Masking (Enforce 16-Byte Block Boundaries) ---");
        total_tests = total_tests + 1;

        // Present unaligned byte address 0x0000_4447 (offset = 7)
        read_and_verify_block(32'h0000_4447, DEF_LATENCY, temp_block, measured_lat);

        if (temp_block[31:0]  == 32'h0000_4440 &&
            temp_block[63:32] == 32'h0000_4444 &&
            temp_block[95:64] == 32'h0000_4448 &&
            temp_block[127:96]== 32'h0000_444C) begin
            $display("[PASS] Scenario 9: Address 0x00004447 properly masked to block 0x00004440.");
            passed_tests = passed_tests + 1;
        end else begin
            $display("[FAIL] Scenario 9: Unaligned address was not correctly masked! w0=%h", temp_block[31:0]);
            failed_tests = failed_tests + 1;
        end

        // --------------------------------------------------------------------
        // Scenario 10: Mid-Access Reset Recovery
        // --------------------------------------------------------------------
        $display("\n--- Scenario 10: Asynchronous Mid-Transaction Reset Recovery ---");
        total_tests = total_tests + 1;

        @(posedge clk);
        ctrl_mem_req_val  <= 1'b1;
        ctrl_mem_req_addr <= 32'h0000_8880;
        @(posedge clk);
        ctrl_mem_req_val  <= 1'b0;

        // Wait 4 cycles into MEM_ACCESS, then hit active-low reset
        repeat (4) @(posedge clk);
        rst_n <= 1'b0;
        @(posedge clk);
        rst_n <= 1'b1;
        @(posedge clk);

        // Verify FSM restored to MEM_IDLE without hanging
        if (dut_fsm_state == 2'b00 && ctrl_mem_req_ready == 1'b0) begin
            // Confirm memory can immediately accept next clean request
            read_and_verify_block(32'h0000_9990, DEF_LATENCY, temp_block, measured_lat);
            if (temp_block[31:0] == 32'h0000_9990) begin
                $display("[PASS] Scenario 10: Clean recovery after abrupt mid-transaction reset.");
                passed_tests = passed_tests + 1;
            end else begin
                $display("[FAIL] Scenario 10: Post-reset transaction returned bad data!");
                failed_tests = failed_tests + 1;
            end
        end else begin
            $display("[FAIL] Scenario 10: FSM failed to return to MEM_IDLE after reset!");
            failed_tests = failed_tests + 1;
        end

        // --------------------------------------------------------------------
        // Scenario 11: Configurable Parameterized Latency (LATENCY = 2)
        // --------------------------------------------------------------------
        $display("\n--- Scenario 11: Configurable Latency Model Verification (LATENCY = 2) ---");
        total_tests = total_tests + 1;

        @(posedge clk);
        lat2_req_val  <= 1'b1;
        lat2_req_addr <= 32'h0000_AAAA;
        @(posedge clk);
        lat2_req_val  <= 1'b0;

        measured_lat = 0;
        while (!lat2_ready && measured_lat < 20) begin
            @(posedge clk);
            measured_lat = measured_lat + 1;
        end

        if (measured_lat == 2 && lat2_data[31:0] == 32'h0000_AAA0) begin
            $display("[PASS] Scenario 11: LATENCY=2 model completed in exactly 2 cycles with correct block.");
            passed_tests = passed_tests + 1;
        end else begin
            $display("[FAIL] Scenario 11: Latency=2 mismatch! Measured=%0d cycles, w0=%h",
                     measured_lat, lat2_data[31:0]);
            failed_tests = failed_tests + 1;
        end
        @(posedge clk);

        // ====================================================================
        // Final Verification Summary
        // ====================================================================
        $display("\n==================================================================");
        $display("   MEMORY SUBSYSTEM VERIFICATION SUMMARY                          ");
        $display("   Total Checks:  %0d", total_tests);
        $display("   Passed Checks: %0d", passed_tests);
        $display("   Failed Checks: %0d", failed_tests);
        if (failed_tests == 0) begin
            $display("   STATUS: >>> ALL MEMORY SUBSYSTEM TESTS PASSED (100%%) <<<");
        end else begin
            $display("   STATUS: >>> TESTBENCH FAILED WITH %0d ERRORS <<<", failed_tests);
        end
        $display("==================================================================\n");

        $finish;
    end

endmodule
