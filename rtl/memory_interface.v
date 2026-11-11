// ============================================================================
// Module: memory_interface
// Author: Harsh & Priyanshu
// Project: Design and Analysis of a Direct-Mapped Cache Controller
// Description: Bridges cache controller memory requests to main memory.
//              Enforces 16-byte block alignment on outgoing addresses and
//              forwards handshakes and block data.
// ============================================================================

`timescale 1ns / 1ps

module memory_interface #(
    parameter ADDR_BITS  = 32,
    parameter BLOCK_BITS = 128
)(
    // Cache controller facing
    input  wire                  ctrl_mem_req_val,
    input  wire [ADDR_BITS-1:0]  ctrl_mem_req_addr,
    output wire                  ctrl_mem_req_ready,
    output wire [BLOCK_BITS-1:0] ctrl_mem_resp_data,

    // Main memory facing
    output wire                  mem_req_val,
    output wire [ADDR_BITS-1:0]  mem_req_addr,
    input  wire                  mem_req_ready,
    input  wire [BLOCK_BITS-1:0] mem_resp_data
);

    // Enforce 16-byte block alignment (mask lowest 4 bits)
    assign mem_req_addr       = {ctrl_mem_req_addr[ADDR_BITS-1:4], 4'b0000};
    assign mem_req_val        = ctrl_mem_req_val;

    // Return channels directly forwarded
    assign ctrl_mem_req_ready = mem_req_ready;
    assign ctrl_mem_resp_data = mem_resp_data;

endmodule
