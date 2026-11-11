// ============================================================================
// Module: address_decoder
// Author: Mihika
// Project: Design and Analysis of a Direct-Mapped Cache Controller
// Description: Decodes a 32-bit CPU memory address into Tag, Index, Block Offset,
//              and Word Select fields according to direct-mapped cache specifications.
//
// Address Breakdown:
//   - Tag:          address[31:10] (22 bits)
//   - Index:        address[9:4]   (6 bits -> 64 lines)
//   - Block Offset: address[3:0]   (4 bits -> 16 bytes per block)
//   - Word Select:  address[3:2]   (2 bits -> 4 words per block)
//   - Byte Select:  address[1:0]   (2 bits -> 4 bytes per word)
// ============================================================================

`timescale 1ns / 1ps

module address_decoder (
    input  wire [31:0] addr,
    output wire [21:0] tag,
    output wire [5:0]  index,
    output wire [3:0]  offset,
    output wire [1:0]  word_sel,
    output wire [1:0]  byte_offset
);

    assign tag         = addr[31:10];
    assign index       = addr[9:4];
    assign offset      = addr[3:0];
    assign word_sel    = addr[3:2];
    assign byte_offset = addr[1:0];

endmodule
