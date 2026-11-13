// ============================================================================
// Module: cache_storage
// Author: Mihika Mathur
// Project: Design and Analysis of a Direct-Mapped Cache Controller
// Description: Structural integration of the three direct-mapped cache storage
//              sub-arrays into a single unified storage subsystem:
//                - cache_data_ram  : 64 x 128-bit block data
//                - tag_ram         : 64 x 22-bit tag storage
//                - valid_bit_ram   : 64 x 1-bit valid flags (reset-to-zero)
//
// Interface Contract (agreed with Saksham, Integration Lead):
//   Read Interface:
//     - read_index   : 6-bit index used to address all three RAMs simultaneously
//     - read_data    : 128-bit block returned from cache_data_ram
//     - read_tag     : 22-bit tag returned from tag_ram
//     - read_valid   : 1-bit valid flag returned from valid_bit_ram
//   Write / Refill Interface:
//     - write_en     : Global write enable gating data, tag, and valid writes
//     - write_index  : 6-bit index identifying the line to refill
//     - write_data   : 128-bit memory block to store into cache_data_ram
//     - write_tag    : 22-bit tag to store into tag_ram
//     - write_valid  : Valid bit value to store into valid_bit_ram (1 = valid)
//
// All three write enables are derived from the single write_en signal so that
// data, tag, and valid bit are updated atomically in the same clock cycle
// (STATE_REFILL), eliminating any transient state where data is live under
// an old tag or old valid bit.
//
// Combinational reads are latency-free, allowing the cache controller to
// inspect any cache line in STATE_LOOKUP within the same clock cycle.
// ============================================================================

`timescale 1ns / 1ps

module cache_storage #(
    parameter NUM_LINES   = 64,
    parameter INDEX_BITS  = 6,
    parameter TAG_BITS    = 22,
    parameter BLOCK_BITS  = 128
)(
    input  wire                   clk,
    input  wire                   rst_n,          // Active-low synchronous reset

    // Read Interface (combinational)
    input  wire [INDEX_BITS-1:0]  read_index,
    output wire                   read_valid,
    output wire [TAG_BITS-1:0]    read_tag,
    output wire [BLOCK_BITS-1:0]  read_data,

    // Write / Refill Interface (synchronous)
    input  wire                   write_en,
    input  wire [INDEX_BITS-1:0]  write_index,
    input  wire [TAG_BITS-1:0]    write_tag,
    input  wire [BLOCK_BITS-1:0]  write_data,
    input  wire                   write_valid
);

    // =========================================================================
    // Sub-module Instantiation
    // All three RAMs share the identical read/write index so that the returned
    // data, tag, and valid bit always correspond to the same cache line.
    // =========================================================================

    // 1. Cache Data RAM: stores the 128-bit block payload
    cache_data_ram #(
        .NUM_LINES   (NUM_LINES),
        .INDEX_WIDTH (INDEX_BITS),
        .DATA_WIDTH  (BLOCK_BITS)
    ) u_data_ram (
        .clk          (clk),
        .index        (write_en ? write_index : read_index),
        .write_enable (write_en),
        .write_data   (write_data),
        .read_data    (read_data)
    );

    // 2. Tag RAM: stores the 22-bit address tag per line
    tag_ram #(
        .NUM_LINES   (NUM_LINES),
        .INDEX_WIDTH (INDEX_BITS),
        .TAG_WIDTH   (TAG_BITS)
    ) u_tag_ram (
        .clk          (clk),
        .index        (write_en ? write_index : read_index),
        .write_enable (write_en),
        .write_tag    (write_tag),
        .read_tag     (read_tag)
    );

    // 3. Valid-Bit RAM: stores valid flag; resets all bits to 0 on rst_n
    valid_bit_ram #(
        .NUM_LINES   (NUM_LINES),
        .INDEX_WIDTH (INDEX_BITS)
    ) u_valid_ram (
        .clk          (clk),
        .rst_n        (rst_n),
        .index        (write_en ? write_index : read_index),
        .write_enable (write_en),
        .write_valid  (write_valid),
        .read_valid   (read_valid)
    );

endmodule
