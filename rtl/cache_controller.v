// ============================================================================
// Module: cache_controller
// Author: Saksham (Integration Lead & FSM Architect)
// Project: Design and Analysis of a Direct-Mapped Cache Controller
// Description: Finite State Machine (FSM) controlling direct-mapped cache
//              operations: request latching, hit/miss detection, memory refill,
//              and CPU response generation.
//
// Stage 1: FSM State Architecture & Interface Skeleton
// ============================================================================

`timescale 1ns / 1ps

module cache_controller #(
    parameter ADDR_WIDTH  = 32,
    parameter DATA_WIDTH  = 32,
    parameter BLOCK_WIDTH = 128,
    parameter TAG_WIDTH   = 22,
    parameter INDEX_WIDTH = 6,
    parameter OFFSET_WIDTH= 4
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // CPU Interface
    input  wire                   cpu_req_val,
    input  wire [ADDR_WIDTH-1:0]  cpu_req_addr,
    output reg                    cpu_req_ready,
    output reg                    cpu_resp_val,
    output reg  [DATA_WIDTH-1:0]  cpu_resp_data,

    // Cache Storage Interface
    output wire [INDEX_WIDTH-1:0] cache_read_index,
    input  wire                   cache_hit,
    input  wire                   cache_miss,
    input  wire [BLOCK_WIDTH-1:0] cache_read_data,
    output reg                    cache_write_en,
    output wire [INDEX_WIDTH-1:0] cache_write_index,
    output wire [TAG_WIDTH-1:0]   cache_write_tag,
    output reg  [BLOCK_WIDTH-1:0] cache_write_data,
    output reg                    cache_write_valid,

    // Memory Interface
    output reg                    mem_req_val,
    output wire [ADDR_WIDTH-1:0]  mem_req_addr,
    input  wire                   mem_req_ready,
    input  wire [BLOCK_WIDTH-1:0] mem_resp_data
);

    // ========================================================================
    // State Encoding (3-bit Gray / Binary)
    // ========================================================================
    localparam [2:0]
        STATE_IDLE        = 3'b000,
        STATE_LOOKUP      = 3'b001,
        STATE_MEM_REQUEST = 3'b010,
        STATE_MEM_WAIT    = 3'b011,
        STATE_REFILL      = 3'b100,
        STATE_RESPOND     = 3'b101;

    reg [2:0] state_q, state_d;

    // Synchronous FSM State Register with Active-Low Reset
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= STATE_IDLE;
        end else begin
            state_q <= state_d;
        end
    end

    // Temporary tie-offs for Stage 1 skeleton
    assign cache_read_index  = {INDEX_WIDTH{1'b0}};
    assign cache_write_index = {INDEX_WIDTH{1'b0}};
    assign cache_write_tag   = {TAG_WIDTH{1'b0}};
    assign mem_req_addr      = {ADDR_WIDTH{1'b0}};

    // Next-State Logic (Skeleton)
    always @(*) begin
        state_d           = state_q;
        cpu_req_ready     = 1'b0;
        cpu_resp_val      = 1'b0;
        cpu_resp_data     = {DATA_WIDTH{1'b0}};
        cache_write_en    = 1'b0;
        cache_write_data  = {BLOCK_WIDTH{1'b0}};
        cache_write_valid = 1'b0;
        mem_req_val       = 1'b0;

        case (state_q)
            STATE_IDLE: begin
                cpu_req_ready = 1'b1;
                if (cpu_req_val) begin
                    state_d = STATE_LOOKUP;
                end
            end

            STATE_LOOKUP: begin
                if (cache_hit) begin
                    state_d = STATE_RESPOND;
                end else begin
                    state_d = STATE_MEM_REQUEST;
                end
            end

            STATE_MEM_REQUEST: begin
                mem_req_val = 1'b1;
                state_d     = STATE_MEM_WAIT;
            end

            STATE_MEM_WAIT: begin
                if (mem_req_ready) begin
                    state_d = STATE_REFILL;
                end
            end

            STATE_REFILL: begin
                state_d = STATE_RESPOND;
            end

            STATE_RESPOND: begin
                cpu_resp_val = 1'b1;
                state_d      = STATE_IDLE;
            end

            default: begin
                state_d = STATE_IDLE;
            end
        endcase
    end

endmodule
