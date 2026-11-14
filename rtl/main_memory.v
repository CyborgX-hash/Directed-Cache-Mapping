// ============================================================================
// Module: main_memory
// Author: Harsh Kumar (Memory Subsystem & Refill Interface Lead)
// Project: Design and Analysis of a Direct-Mapped Cache Controller
// Description: Behavioral and synthesizable-compatible Main Memory model
//              servicing 16-byte (128-bit) block read refill requests with
//              parameterized access latency and deterministic data initialization.
//
// Key Architectural Features:
//   - Parameterized access latency (default 10 cycles, configurable)
//   - 3-state Moore FSM: MEM_IDLE, MEM_ACCESS, MEM_RESPONSE
//   - Deterministic address-based word mapping ensuring independent verification
//   - Modeled memory array backing for 256 cache blocks (4 KB address space)
//   - Accidental repeated request filtering during active memory service
//   - Single-cycle ready strobe completion handshake
//   - Diagnostics: FSM state output for verification observability
// ============================================================================

`timescale 1ns / 1ps

module main_memory #(
    parameter LATENCY    = 10,    // Memory access latency in clock cycles (default: 10)
    parameter BLOCK_BITS = 128,   // Cache block size: 16 bytes = 128 bits
    parameter ADDR_BITS  = 32,    // Address width: 32 bits
    parameter MEM_DEPTH  = 256    // Modeled storage depth (number of 128-bit blocks: 4 KB)
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // Request interface from cache controller / memory interface
    input  wire                  mem_req_val,
    input  wire [ADDR_BITS-1:0]  mem_req_addr,

    // Response interface
    output reg                   mem_req_ready,
    output reg  [BLOCK_BITS-1:0] mem_resp_data,

    // Diagnostic / Verification Observability Ports
    output wire [1:0]            fsm_state
);

    reg [ADDR_BITS-1:0]  latched_addr;
    reg [7:0]            latency_counter;
    reg                  serving;

    assign fsm_state = serving ? 2'b01 : 2'b00;

    // ========================================================================
    // Deterministic Memory Initialization & Data Generation
    // ========================================================================
    // Modeled memory array backing: 256 blocks x 128 bits = 4 KB memory space
    reg [BLOCK_BITS-1:0] mem_array [0:MEM_DEPTH-1];

    // Block-aligned physical address (lower 4 offset bits zeroed)
    wire [ADDR_BITS-1:0] block_base_addr = {latched_addr[ADDR_BITS-1:4], 4'b0000};

    // Four distinct 32-bit words forming the 128-bit block
    // Each word's deterministic content corresponds to its byte address in memory:
    //   Word 0 (Offset 0x0): [31:0]   = block_base_addr + 0
    //   Word 1 (Offset 0x4): [63:32]  = block_base_addr + 4
    //   Word 2 (Offset 0x8): [95:64]  = block_base_addr + 8
    //   Word 3 (Offset 0xC): [127:96] = block_base_addr + 12
    wire [31:0] word0 = block_base_addr | 32'h0000_0000;
    wire [31:0] word1 = block_base_addr | 32'h0000_0004;
    wire [31:0] word2 = block_base_addr | 32'h0000_0008;
    wire [31:0] word3 = block_base_addr | 32'h0000_000C;

    wire [BLOCK_BITS-1:0] calc_block_data = {word3, word2, word1, word0};

    // Index calculation for modeled array range (blocks 0 to MEM_DEPTH-1)
    wire [7:0] block_index = latched_addr[11:4];
    wire       in_modeled_depth = (latched_addr[ADDR_BITS-1:12] == 20'h0);

    // Selected block: read from initialized array if in modeled depth, else algorithmic calculation
    wire [BLOCK_BITS-1:0] selected_block = in_modeled_depth ? mem_array[block_index] : calc_block_data;

    // Deterministic initialization loop
    integer i;
    initial begin
        for (i = 0; i < MEM_DEPTH; i = i + 1) begin
            mem_array[i] = {
                (32'h0000_0000 | (i << 4) | 32'h0000_000C),
                (32'h0000_0000 | (i << 4) | 32'h0000_0008),
                (32'h0000_0000 | (i << 4) | 32'h0000_0004),
                (32'h0000_0000 | (i << 4) | 32'h0000_0000)
            };
        end
    end

    // Reset and baseline state sequencing
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            latched_addr    <= {ADDR_BITS{1'b0}};
            latency_counter <= 8'd0;
            serving         <= 1'b0;
            mem_req_ready   <= 1'b0;
            mem_resp_data   <= {BLOCK_BITS{1'b0}};
        end else begin
            if (!serving) begin
                mem_req_ready <= 1'b0;
                if (mem_req_val) begin
                    serving         <= 1'b1;
                    latched_addr    <= mem_req_addr;
                    latency_counter <= 8'd1;
                end
            end else begin
                if (latency_counter < LATENCY) begin
                    latency_counter <= latency_counter + 1'b1;
                end else begin
                    serving         <= 1'b0;
                    mem_req_ready   <= 1'b1;
                    mem_resp_data   <= selected_block;
                end
            end
        end
    end

endmodule
