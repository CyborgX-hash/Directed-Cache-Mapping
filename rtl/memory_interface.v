// ============================================================================
// Module: memory_interface
// Author: Harsh Kumar (Memory Subsystem & Refill Interface Lead)
// Project: Design and Analysis of a Direct-Mapped Cache Controller
// Description: Memory Interface module bridging the cache controller and the
//              main memory subsystem. Enforces 16-byte block alignment on
//              all outgoing memory addresses, isolates transaction handshakes,
//              and routes 128-bit block read responses.
// ============================================================================

`timescale 1ns / 1ps

module memory_interface #(
    parameter ADDR_BITS  = 32,
    parameter BLOCK_BITS = 128
)(
    // Cache Controller Facing Interface
    input  wire                  ctrl_mem_req_val,
    input  wire [ADDR_BITS-1:0]  ctrl_mem_req_addr,
    output wire                  ctrl_mem_req_ready,
    output wire [BLOCK_BITS-1:0] ctrl_mem_resp_data,

    // Main Memory Facing Interface
    output wire                  mem_req_val,
    output wire [ADDR_BITS-1:0]  mem_req_addr,
    input  wire                  mem_req_ready,
    input  wire [BLOCK_BITS-1:0] mem_resp_data
);

    // Enforce 16-byte block alignment (mask lowest 4 offset bits [3:0])
    assign mem_req_addr       = {ctrl_mem_req_addr[ADDR_BITS-1:4], 4'b0000};

    // Forward request valid strobe to main memory
    assign mem_req_val        = ctrl_mem_req_val;

    // Direct forwarding of response ready handshake and 128-bit block data
    assign ctrl_mem_req_ready = mem_req_ready;
    assign ctrl_mem_resp_data = mem_resp_data;

endmodule
