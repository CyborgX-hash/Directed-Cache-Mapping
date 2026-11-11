// ============================================================================
// Module: cache_storage
// Author: Harsh
// Project: Design and Analysis of a Direct-Mapped Cache Controller
// Description: Direct-mapped cache data, tag, and valid bit array.
//              64 cache lines x 16-byte (128-bit) block data + 22-bit tag + 1-bit valid.
//              Total storage capacity: 1024 bytes (1 KB) data payload.
// ============================================================================

`timescale 1ns / 1ps

module cache_storage #(
    parameter NUM_LINES  = 64,
    parameter INDEX_BITS = 6,
    parameter TAG_BITS   = 22,
    parameter BLOCK_BITS = 128
)(
    input  wire                  clk,
    input  wire                  rst_n,        // Active-low synchronous reset

    // Read interface
    input  wire [INDEX_BITS-1:0] read_index,
    output wire                  read_valid,
    output wire [TAG_BITS-1:0]   read_tag,
    output wire [BLOCK_BITS-1:0] read_data,

    // Write / Refill interface
    input  wire                  write_en,
    input  wire [INDEX_BITS-1:0] write_index,
    input  wire [TAG_BITS-1:0]   write_tag,
    input  wire [BLOCK_BITS-1:0] write_data,
    input  wire                  write_valid
);

    // Storage arrays
    reg                  valid_array [0:NUM_LINES-1];
    reg [TAG_BITS-1:0]   tag_array   [0:NUM_LINES-1];
    reg [BLOCK_BITS-1:0] data_array  [0:NUM_LINES-1];

    integer i;

    // Asynchronous read (distributed RAM / register-file access)
    assign read_valid = valid_array[read_index];
    assign read_tag   = tag_array[read_index];
    assign read_data  = data_array[read_index];

    // Synchronous write & synchronous reset
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_LINES; i = i + 1) begin
                valid_array[i] <= 1'b0;
                tag_array[i]   <= {TAG_BITS{1'b0}};
                data_array[i]  <= {BLOCK_BITS{1'b0}};
            end
        end else if (write_en) begin
            valid_array[write_index] <= write_valid;
            tag_array[write_index]   <= write_tag;
            data_array[write_index]  <= write_data;
        end
    end

endmodule
