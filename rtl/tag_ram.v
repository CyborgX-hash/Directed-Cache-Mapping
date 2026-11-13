// ============================================================================
// Module: tag_ram
// Author: Mihika Mathur
// Project: Design and Analysis of a Direct-Mapped Cache Controller
// Description: Direct-mapped cache tag storage array consisting of 64 entries,
//              each holding a 22-bit tag (address[31:10]).
//
// Hardware Features & Timing:
//   - Synchronous write on posedge clk controlled by independent write_enable.
//   - Combinational asynchronous read indexed by 6-bit index input.
//   - Operates synchronously alongside cache_data_ram using the identical index.
//   - No reset on tag array (avoids inferring 1,408 flip-flops; tag validity
//     is strictly qualified by valid_bit_ram to prevent false hits).
// ============================================================================

`timescale 1ns / 1ps

module tag_ram #(
    parameter NUM_LINES   = 64,
    parameter INDEX_WIDTH = 6,
    parameter TAG_WIDTH   = 22
)(
    input  wire                   clk,
    input  wire [INDEX_WIDTH-1:0] index,
    input  wire                   write_enable,
    input  wire [TAG_WIDTH-1:0]   write_tag,
    output wire [TAG_WIDTH-1:0]   read_tag
);

    // 64-entry x 22-bit tag memory matrix
    reg [TAG_WIDTH-1:0] tag_mem [0:NUM_LINES-1];

    // Combinational Read Port
    // Feeds stored tag directly into tag comparator during LOOKUP state
    assign read_tag = tag_mem[index];

    // Synchronous Write Port
    // Overwrites old tag with new incoming tag during line replacement
    always @(posedge clk) begin
        if (write_enable) begin
            tag_mem[index] <= write_tag;
        end
    end

endmodule

