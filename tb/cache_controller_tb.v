// ============================================================================
// Testbench: cache_controller_tb
// Author: Saksham (FSM Architect)
// Project: Design and Analysis of a Direct-Mapped Cache Controller
// Description: Unit testbench for cache_controller.v validating isolated
//              FSM transitions, protocol handshakes, and signal timings.
// ============================================================================

`timescale 1ns / 1ps

module cache_controller_tb;

    localparam ADDR_WIDTH   = 32;
    localparam DATA_WIDTH   = 32;
    localparam BLOCK_WIDTH  = 128;
    localparam TAG_WIDTH    = 22;
    localparam INDEX_WIDTH  = 6;
    localparam OFFSET_WIDTH = 4;
    localparam CLK_PERIOD   = 10;

    reg                   clk;
    reg                   rst_n;

    // CPU Interface
    reg                   cpu_req_val;
    reg  [ADDR_WIDTH-1:0] cpu_req_addr;
    wire                  cpu_req_ready;
    wire                  cpu_resp_val;
    wire [DATA_WIDTH-1:0] cpu_resp_data;

    // Cache Storage Interface
    wire [INDEX_WIDTH-1:0] cache_read_index;
    reg                   cache_hit;
    reg                   cache_miss;
    reg  [BLOCK_WIDTH-1:0] cache_read_data;
    wire                  cache_write_en;
    wire [INDEX_WIDTH-1:0] cache_write_index;
    wire [TAG_WIDTH-1:0]   cache_write_tag;
    wire [BLOCK_WIDTH-1:0] cache_write_data;
    wire                  cache_write_valid;

    // Memory Interface
    wire                  mem_req_val;
    wire [ADDR_WIDTH-1:0] mem_req_addr;
    reg                   mem_req_ready;
    reg  [BLOCK_WIDTH-1:0] mem_resp_data;

    // Diagnostics
    wire [2:0]            fsm_state;

    // Instantiate DUT
    cache_controller #(
        .ADDR_WIDTH   (ADDR_WIDTH),
        .DATA_WIDTH   (DATA_WIDTH),
        .BLOCK_WIDTH  (BLOCK_WIDTH),
        .TAG_WIDTH    (TAG_WIDTH),
        .INDEX_WIDTH  (INDEX_WIDTH),
        .OFFSET_WIDTH (OFFSET_WIDTH)
    ) dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .cpu_req_val       (cpu_req_val),
        .cpu_req_addr      (cpu_req_addr),
        .cpu_req_ready     (cpu_req_ready),
        .cpu_resp_val      (cpu_resp_val),
        .cpu_resp_data     (cpu_resp_data),
        .cache_read_index  (cache_read_index),
        .cache_hit         (cache_hit),
        .cache_miss        (cache_miss),
        .cache_read_data   (cache_read_data),
        .cache_write_en    (cache_write_en),
        .cache_write_index (cache_write_index),
        .cache_write_tag   (cache_write_tag),
        .cache_write_data  (cache_write_data),
        .cache_write_valid (cache_write_valid),
        .mem_req_val       (mem_req_val),
        .mem_req_addr      (mem_req_addr),
        .mem_req_ready     (mem_req_ready),
        .mem_resp_data     (mem_resp_data),
        .fsm_state         (fsm_state)
    );

    always #(CLK_PERIOD / 2) clk = ~clk;

    initial begin
        clk           = 1'b0;
        rst_n         = 1'b0;
        cpu_req_val   = 1'b0;
        cpu_req_addr  = 32'h0;
        cache_hit     = 1'b0;
        cache_miss    = 1'b1;
        cache_read_data = 128'h0;
        mem_req_ready = 1'b0;
        mem_resp_data = 128'h0;

        $display("--- Cache Controller Unit Verification ---");
        #(CLK_PERIOD * 2);
        rst_n = 1'b1;
        @(posedge clk);

        // Verify Reset State
        if (fsm_state !== 3'b000 || cpu_req_ready !== 1'b1) begin
            $display("[FAIL] FSM Reset State Mismatch!");
            $finish;
        end
        $display("[PASS] Reset State: IDLE (state=000, ready=1)");

        // --------------------------------------------------------------------
        // Scenario 1: Isolated Hit Sequence
        // --------------------------------------------------------------------
        @(posedge clk);
        cpu_req_val     <= 1'b1;
        cpu_req_addr    <= 32'hA000_0148; // Word 2
        // Setup cache response for lookup
        cache_hit       <= 1'b1;
        cache_miss      <= 1'b0;
        cache_read_data <= {32'hDDDD_4444, 32'hCCCC_3333, 32'hBBBB_2222, 32'hAAAA_1111};

        @(posedge clk);
        cpu_req_val     <= 1'b0;
        // At this edge, FSM enters LOOKUP; cache_hit and cache_read_data are evaluated

        @(posedge clk);
        #1;
        // At this edge, FSM enters RESPOND
        if (cpu_resp_val !== 1'b1 || cpu_resp_data !== 32'hCCCC_3333) begin
            $display("[FAIL] Hit response mismatch! Expected=0xCCCC3333, Got=0x%08h", cpu_resp_data);
            $finish;
        end
        $display("[PASS] Standalone Hit Path: Word 2 selected accurately (0x%08h)", cpu_resp_data);

        @(posedge clk);
        #1;
        // Reset cache signals
        cache_hit       <= 1'b0;
        cache_miss      <= 1'b1;
        cache_read_data <= 128'h0;

        // Back to IDLE
        if (fsm_state !== 3'b000 || cpu_req_ready !== 1'b1) begin
            $display("[FAIL] Post-hit return to IDLE failed!");
            $finish;
        end
        $display("[PASS] Returned to IDLE cleanly.");

        // --------------------------------------------------------------------
        // Scenario 2: Isolated Miss Sequence with Memory Refill
        // --------------------------------------------------------------------
        @(posedge clk);
        cpu_req_val  <= 1'b1;
        cpu_req_addr <= 32'hB000_024C; // Word 3
        cache_hit    <= 1'b0;
        cache_miss   <= 1'b1;

        @(posedge clk);
        cpu_req_val <= 1'b0;
        // In LOOKUP: miss is asserted

        @(posedge clk);
        #1;
        // In MEM_REQUEST
        if (mem_req_val !== 1'b1 || mem_req_addr !== 32'hB000_0240) begin
            $display("[FAIL] MEM_REQUEST address/val mismatch! Addr=0x%08h, Val=%b", mem_req_addr, mem_req_val);
            $finish;
        end
        $display("[PASS] MEM_REQUEST pulse: Aligned Addr=0x%08h, mem_req_val=1", mem_req_addr);

        @(posedge clk);
        #1;
        // In MEM_WAIT: verify single pulse
        if (mem_req_val !== 1'b0) begin
            $display("[FAIL] Protocol violation: mem_req_val held high during MEM_WAIT!");
            $finish;
        end

        // Wait 2 cycles in MEM_WAIT
        repeat (2) @(posedge clk);

        // Memory responds
        mem_req_ready <= 1'b1;
        mem_resp_data <= {32'h4444_FFFF, 32'h3333_EEEE, 32'h2222_DDDD, 32'h1111_CCCC};

        @(posedge clk);
        mem_req_ready <= 1'b0;
        #1;

        // In REFILL: verify cache write control
        if (cache_write_en !== 1'b1 || cache_write_valid !== 1'b1 || cache_write_data !== {32'h4444_FFFF, 32'h3333_EEEE, 32'h2222_DDDD, 32'h1111_CCCC}) begin
            $display("[FAIL] REFILL write control mismatch!");
            $finish;
        end
        $display("[PASS] REFILL control signals verified (write_en=1, valid=1, data matched).");

        @(posedge clk);
        #1;
        // In RESPOND: verify Word 3 selection
        if (cpu_resp_val !== 1'b1 || cpu_resp_data !== 32'h4444_FFFF) begin
            $display("[FAIL] Miss response data mismatch! Expected=0x4444FFFF, Got=0x%08h", cpu_resp_data);
            $finish;
        end
        $display("[PASS] Standalone Miss Path: Word 3 selected accurately (0x%08h)", cpu_resp_data);

        @(posedge clk);
        $display("[PASS] ALL UNIT TESTS COMPLETED SUCCESSFULLY.");
        $finish;
    end

endmodule
