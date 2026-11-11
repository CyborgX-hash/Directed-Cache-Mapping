// ============================================================================
// Module: tag_comparator
// Author: Priyanshu
// Project: Design and Analysis of a Direct-Mapped Cache Controller
// Description: Compares CPU address tag with cache storage tag, qualified by
//              the cache line valid bit, to generate hit and miss indications.
// ============================================================================

`timescale 1ns / 1ps

module tag_comparator (
    input  wire [21:0] tag_in,       // Tag decoded from CPU request address
    input  wire [21:0] cache_tag,    // Tag retrieved from cache line
    input  wire        cache_valid,  // Valid bit of the indexed cache line
    output wire        hit,          // 1 if valid and tags match
    output wire        miss          // 1 if invalid or tag mismatch
);

    assign hit  = cache_valid && (tag_in == cache_tag);
    assign miss = ~hit;

endmodule
