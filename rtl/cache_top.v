// ============================================================================
// Module: cache_top
// Author: Saksham (Integration Lead & Top-Level Architect)
// Project: Design and Analysis of a Direct-Mapped Cache Controller
// Description: Top-level system integrating all 5 team members' sub-modules:
//              - address_decoder  (Mihika)
//              - cache_storage    (Harsh)
//              - tag_comparator   (Priyanshu)
//              - cache_controller (Saksham)
//              - memory_interface (Harsh & Priyanshu)
//              - main_memory      (Ajit)
//
// System Specifications:
//   - Direct-mapped, read-only cache with 16-byte block refill
//   - 1 KB total data capacity (64 lines x 16 bytes)
//   - 32-bit CPU address: Tag[31:10], Index[9:4], Offset[3:0]
// ============================================================================

`timescale 1ns / 1ps

module cache_top #(
    parameter ADDR_WIDTH   = 32,
    parameter DATA_WIDTH   = 32,
    parameter BLOCK_WIDTH  = 128,
    parameter TAG_WIDTH    = 22,
    parameter INDEX_WIDTH  = 6,
    parameter OFFSET_WIDTH = 4,
    parameter NUM_LINES    = 64,
    parameter MEM_LATENCY  = 2
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // CPU Interface
    input  wire                   cpu_req_val,
    input  wire [ADDR_WIDTH-1:0]  cpu_req_addr,
    output wire                   cpu_req_ready,
    output wire                   cpu_resp_val,
    output wire [DATA_WIDTH-1:0]  cpu_resp_data,

    // Status / Observability Outputs
    output wire [2:0]             fsm_state,
    output wire                   hit_out,
    output wire                   miss_out
);

    // ========================================================================
    // Internal Interconnect Wires
    // ========================================================================

    // Address Decoder Wires
    wire [TAG_WIDTH-1:0]    dec_tag;
    wire [INDEX_WIDTH-1:0]  dec_index;
    wire [OFFSET_WIDTH-1:0] dec_offset;
    wire [1:0]              dec_word_sel;
    wire [1:0]              dec_byte_offset;

    // Cache Storage Wires
    wire [INDEX_WIDTH-1:0]  storage_read_index;
    wire                    storage_read_valid;
    wire [TAG_WIDTH-1:0]    storage_read_tag;
    wire [BLOCK_WIDTH-1:0]  storage_read_data;

    wire                    storage_write_en;
    wire [INDEX_WIDTH-1:0]  storage_write_index;
    wire [TAG_WIDTH-1:0]    storage_write_tag;
    wire [BLOCK_WIDTH-1:0]  storage_write_data;
    wire                    storage_write_valid;

    // Tag Comparator Wires
    wire                    cmp_hit;
    wire                    cmp_miss;

    // Memory Interface (Controller <-> Memory Interface)
    wire                    ctrl_mem_req_val;
    wire [ADDR_WIDTH-1:0]   ctrl_mem_req_addr;
    wire                    ctrl_mem_req_ready;
    wire [BLOCK_WIDTH-1:0]  ctrl_mem_resp_data;

    // Memory Interface (Memory Interface <-> Main Memory)
    wire                    bus_mem_req_val;
    wire [ADDR_WIDTH-1:0]   bus_mem_req_addr;
    wire                    bus_mem_req_ready;
    wire [BLOCK_WIDTH-1:0]  bus_mem_resp_data;

    // Output assignments for diagnostics
    assign hit_out  = cmp_hit;
    assign miss_out = cmp_miss;

    // ========================================================================
    // 1. Address Decoder (Mihika)
    // ========================================================================
    address_decoder u_address_decoder (
        .addr        (cpu_req_addr),
        .tag         (dec_tag),
        .index       (dec_index),
        .offset      (dec_offset),
        .word_sel    (dec_word_sel),
        .byte_offset (dec_byte_offset)
    );

    // ========================================================================
    // 2. Cache Storage (Harsh)
    // ========================================================================
    cache_storage #(
        .NUM_LINES  (NUM_LINES),
        .INDEX_BITS (INDEX_WIDTH),
        .TAG_BITS   (TAG_WIDTH),
        .BLOCK_BITS (BLOCK_WIDTH)
    ) u_cache_storage (
        .clk         (clk),
        .rst_n       (rst_n),
        .read_index  (storage_read_index),
        .read_valid  (storage_read_valid),
        .read_tag    (storage_read_tag),
        .read_data   (storage_read_data),
        .write_en    (storage_write_en),
        .write_index (storage_write_index),
        .write_tag   (storage_write_tag),
        .write_data  (storage_write_data),
        .write_valid (storage_write_valid)
    );

    // ========================================================================
    // 3. Tag Comparator (Priyanshu)
    // ========================================================================
    tag_comparator u_tag_comparator (
        .tag_in      (storage_write_tag), // Latched request tag driven by controller
        .cache_tag   (storage_read_tag),  // Tag read from current line in cache
        .cache_valid (storage_read_valid),// Valid bit of current line
        .hit         (cmp_hit),
        .miss        (cmp_miss)
    );

    // ========================================================================
    // 4. Cache Controller (Saksham)
    // ========================================================================
    cache_controller #(
        .ADDR_WIDTH   (ADDR_WIDTH),
        .DATA_WIDTH   (DATA_WIDTH),
        .BLOCK_WIDTH  (BLOCK_WIDTH),
        .TAG_WIDTH    (TAG_WIDTH),
        .INDEX_WIDTH  (INDEX_WIDTH),
        .OFFSET_WIDTH (OFFSET_WIDTH)
    ) u_cache_controller (
        .clk               (clk),
        .rst_n             (rst_n),

        // CPU Interface
        .cpu_req_val       (cpu_req_val),
        .cpu_req_addr      (cpu_req_addr),
        .cpu_req_ready     (cpu_req_ready),
        .cpu_resp_val      (cpu_resp_val),
        .cpu_resp_data     (cpu_resp_data),

        // Cache Storage Interface
        .cache_read_index  (storage_read_index),
        .cache_hit         (cmp_hit),
        .cache_miss        (cmp_miss),
        .cache_read_data   (storage_read_data),
        .cache_write_en    (storage_write_en),
        .cache_write_index (storage_write_index),
        .cache_write_tag   (storage_write_tag),
        .cache_write_data  (storage_write_data),
        .cache_write_valid (storage_write_valid),

        // Memory Interface
        .mem_req_val       (ctrl_mem_req_val),
        .mem_req_addr      (ctrl_mem_req_addr),
        .mem_req_ready     (ctrl_mem_req_ready),
        .mem_resp_data     (ctrl_mem_resp_data),

        // Diagnostics
        .fsm_state         (fsm_state)
    );

    // ========================================================================
    // 5. Memory Interface Bridge (Harsh & Priyanshu)
    // ========================================================================
    memory_interface #(
        .ADDR_BITS  (ADDR_WIDTH),
        .BLOCK_BITS (BLOCK_WIDTH)
    ) u_memory_interface (
        .ctrl_mem_req_val   (ctrl_mem_req_val),
        .ctrl_mem_req_addr  (ctrl_mem_req_addr),
        .ctrl_mem_req_ready (ctrl_mem_req_ready),
        .ctrl_mem_resp_data (ctrl_mem_resp_data),

        .mem_req_val        (bus_mem_req_val),
        .mem_req_addr       (bus_mem_req_addr),
        .mem_req_ready      (bus_mem_req_ready),
        .mem_resp_data      (bus_mem_resp_data)
    );

    // ========================================================================
    // 6. Main Memory (Ajit)
    // ========================================================================
    main_memory #(
        .LATENCY    (MEM_LATENCY),
        .BLOCK_BITS (BLOCK_WIDTH),
        .ADDR_BITS  (ADDR_WIDTH)
    ) u_main_memory (
        .clk           (clk),
        .rst_n         (rst_n),
        .mem_req_val   (bus_mem_req_val),
        .mem_req_addr  (bus_mem_req_addr),
        .mem_req_ready (bus_mem_req_ready),
        .mem_resp_data (bus_mem_resp_data)
    );

endmodule
