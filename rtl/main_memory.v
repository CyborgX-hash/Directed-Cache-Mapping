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
    output wire                  mem_req_ready,
    output reg  [BLOCK_BITS-1:0] mem_resp_data,

    // Diagnostic / Verification Observability Ports
    output wire [1:0]            fsm_state
);

    // ========================================================================
    // State Encodings (3-State Moore FSM)
    // ========================================================================
    localparam [1:0]
        MEM_IDLE     = 2'b00,
        MEM_ACCESS   = 2'b01,
        MEM_RESPONSE = 2'b10;

    reg [1:0] state_q, state_d;
    assign fsm_state = state_q;

    // Single-cycle ready strobe asserted strictly during MEM_RESPONSE state
    assign mem_req_ready = (state_q == MEM_RESPONSE);

    // ========================================================================
    // Internal Registers & Buffers
    // ========================================================================
    reg [ADDR_BITS-1:0]  latched_addr_q, latched_addr_d;
    reg [7:0]            latency_cnt_q,  latency_cnt_d;
    reg [BLOCK_BITS-1:0] resp_data_d;

    // ========================================================================
    // Deterministic Memory Initialization & Data Generation
    // ========================================================================
    reg [BLOCK_BITS-1:0] mem_array [0:MEM_DEPTH-1];

    // Enforce 16-byte block alignment on latched address (mask [3:0])
    wire [ADDR_BITS-1:0] block_base_addr = {latched_addr_q[ADDR_BITS-1:4], 4'b0000};

    // Deterministic 32-bit word calculation matching physical byte addresses
    wire [31:0] word0 = block_base_addr | 32'h0000_0000;
    wire [31:0] word1 = block_base_addr | 32'h0000_0004;
    wire [31:0] word2 = block_base_addr | 32'h0000_0008;
    wire [31:0] word3 = block_base_addr | 32'h0000_000C;

    wire [BLOCK_BITS-1:0] calc_block_data = {word3, word2, word1, word0};

    // Modeled storage indexing (lower 8 block bits for 256 entries)
    wire [7:0] block_index      = latched_addr_q[11:4];
    wire       in_modeled_depth = (latched_addr_q[ADDR_BITS-1:12] == 20'h0);
    wire [BLOCK_BITS-1:0] selected_block = in_modeled_depth ? mem_array[block_index] : calc_block_data;

    // Array initialization
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

    // ========================================================================
    // Synchronous FSM State & Register Updates
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q        <= MEM_IDLE;
            latched_addr_q <= {ADDR_BITS{1'b0}};
            latency_cnt_q  <= 8'd0;
            mem_resp_data  <= {BLOCK_BITS{1'b0}};
        end else begin
            state_q        <= state_d;
            latched_addr_q <= latched_addr_d;
            latency_cnt_q  <= latency_cnt_d;
            mem_resp_data  <= resp_data_d;
        end
    end

    // ========================================================================
    // Next-State Logic & Block Response Sequencing
    // ========================================================================
    always @(*) begin
        state_d        = state_q;
        latched_addr_d = latched_addr_q;
        latency_cnt_d  = latency_cnt_q;
        resp_data_d    = mem_resp_data;

        case (state_q)
            // ----------------------------------------------------------------
            // MEM_IDLE: Await incoming memory read request
            // ----------------------------------------------------------------
            MEM_IDLE: begin
                latency_cnt_d = 8'd0;
                if (mem_req_val) begin
                    latched_addr_d = {mem_req_addr[ADDR_BITS-1:4], 4'b0000};
                    if (LATENCY <= 1) begin
                        // 1-cycle turnaround: immediately assemble 128-bit block response
                        resp_data_d = (mem_req_addr[ADDR_BITS-1:12] == 20'h0) ?
                                      mem_array[mem_req_addr[11:4]] :
                                      { ((mem_req_addr[ADDR_BITS-1:4] << 4) | 32'hC),
                                        ((mem_req_addr[ADDR_BITS-1:4] << 4) | 32'h8),
                                        ((mem_req_addr[ADDR_BITS-1:4] << 4) | 32'h4),
                                        ((mem_req_addr[ADDR_BITS-1:4] << 4) | 32'h0) };
                        state_d     = MEM_RESPONSE;
                    end else begin
                        latency_cnt_d = 8'd1;
                        state_d       = MEM_ACCESS;
                    end
                end
            end

            // ----------------------------------------------------------------
            // MEM_ACCESS: Wait-state counting & busy isolation
            // ----------------------------------------------------------------
            MEM_ACCESS: begin
                // In MEM_ACCESS, external bus changes (mem_req_val, mem_req_addr)
                // are strictly ignored to prevent accidental repeated acceptance.
                if (latency_cnt_q < (LATENCY - 1)) begin
                    latency_cnt_d = latency_cnt_q + 1'b1;
                    state_d       = MEM_ACCESS;
                end else begin
                    // Latency period met: latch complete 128-bit block into response register
                    resp_data_d = selected_block;
                    state_d     = MEM_RESPONSE;
                end
            end

            // ----------------------------------------------------------------
            // MEM_RESPONSE: Present 128-bit block data and complete handshake
            // ----------------------------------------------------------------
            MEM_RESPONSE: begin
                resp_data_d = selected_block;
                // Single-pulse response: return to IDLE for subsequent requests
                state_d     = MEM_IDLE;
            end

            default: begin
                state_d = MEM_IDLE;
            end
        endcase
    end

endmodule
