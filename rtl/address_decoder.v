// ============================================================================
// Module: address_decoder
// Author: Mihika Mathur
// Project: Design and Analysis of a Direct-Mapped Cache Controller
// Description: Fully parameterized combinational address decoder that decomposes
//              a 32-bit CPU memory address into Tag, Index, Block Offset, Word
//              Select, and Byte Offset fields for direct-mapped cache lookup.
//
// Architectural Breakdown (32-bit address):
//   +----------------------------+---------+-----+----+
//   |         Tag (22)           |Index (6)|Word |Byte|
//   +----------------------------+---------+-----+----+
//   31                         10 9       4 3   2 1  0
//                                          \________/
//                                         Block Offset (4)
//
// Slicing Formulas:
//   - Tag:         addr[31:10] (22 bits -> Identifies physical memory page/block)
//   - Index:       addr[9:4]   (6 bits  -> Directly addresses 1 of 64 cache lines)
//   - Offset:      addr[3:0]   (4 bits  -> Addresses 1 of 16 bytes within block)
//   - Word Select: addr[3:2]   (2 bits  -> Selects 1 of 4 32-bit words)
//   - Byte Offset: addr[1:0]   (2 bits  -> Selects 1 of 4 bytes within word)
// ============================================================================

`timescale 1ns / 1ps

module address_decoder #(
    parameter ADDR_WIDTH     = 32,
    parameter TAG_WIDTH      = 22,
    parameter INDEX_WIDTH    = 6,
    parameter OFFSET_WIDTH   = 4,
    parameter WORD_SEL_WIDTH = 2,
    parameter BYTE_SEL_WIDTH = 2
)(
    input  wire [ADDR_WIDTH-1:0]     addr,
    output wire [TAG_WIDTH-1:0]      tag,
    output wire [INDEX_WIDTH-1:0]    index,
    output wire [OFFSET_WIDTH-1:0]   offset,
    output wire [WORD_SEL_WIDTH-1:0] word_sel,
    output wire [BYTE_SEL_WIDTH-1:0] byte_offset
);

    // Parametric Bit-Slice Assignments
    assign tag         = addr[ADDR_WIDTH-1 : ADDR_WIDTH - TAG_WIDTH];
    assign index       = addr[ADDR_WIDTH - TAG_WIDTH - 1 : OFFSET_WIDTH];
    assign offset      = addr[OFFSET_WIDTH-1 : 0];
    assign word_sel    = addr[OFFSET_WIDTH-1 : BYTE_SEL_WIDTH];
    assign byte_offset = addr[BYTE_SEL_WIDTH-1 : 0];

endmodule
