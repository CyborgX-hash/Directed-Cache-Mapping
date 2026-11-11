// ============================================================================
// Module: cache_controller
// Author: Saksham (Integration Lead & FSM Architect)
// Project: Design and Analysis of a Direct-Mapped Cache Controller
// Description: Finite State Machine (FSM) controlling direct-mapped cache
//              operations: request latching, hit/miss detection, memory refill,
//              and CPU response generation.
//
// Stage 2: CPU Request Address Latching & Address Decoding
// ============================================================================

`timescale 1ns / 1ps

module cache_controller #(
    parameter ADDR_WIDTH   = 32,
    parameter DATA_WIDTH   = 32,
    parameter BLOCK_WIDTH  = 128,
    parameter TAG_WIDTH    = 22,
    parameter INDEX_WIDTH  = 6,
    parameter OFFSET_WIDTH = 4
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
    // State Encoding
    // ========================================================================
    localparam [2:0]
        STATE_IDLE        = 3'b000,
        STATE_LOOKUP      = 3'b001,
        STATE_MEM_REQUEST = 3'b010,
        STATE_MEM_WAIT    = 3'b011,
        STATE_REFILL      = 3'b100,
        STATE_RESPOND     = 3'b101;

    reg [2:0] state_q, state_d;

    // ========================================================================
    // Request Latching Registers
    // ========================================================================
    reg [ADDR_WIDTH-1:0] latched_addr_q, latched_addr_d;
    reg                  latch_addr_en;

    // Field extractions from latched address
    wire [TAG_WIDTH-1:0]    req_tag      = latched_addr_q[31:10];
    wire [INDEX_WIDTH-1:0]  req_index    = latched_addr_q[9:4];
    wire [OFFSET_WIDTH-1:0] req_offset   = latched_addr_q[3:0];
    wire [1:0]              req_word_sel = latched_addr_q[3:2];

    // Read index to cache storage connects directly to latched index
    assign cache_read_index  = (state_q == STATE_IDLE && cpu_req_val) ? cpu_req_addr[9:4] : req_index;
    assign cache_write_index = req_index;
    assign cache_write_tag   = req_tag;
    assign mem_req_addr      = {req_tag, req_index, 4'b0000};

    // ========================================================================
    // Synchronous State & Address Latching
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q        <= STATE_IDLE;
            latched_addr_q <= {ADDR_WIDTH{1'b0}};
        end else begin
            state_q        <= state_d;
            if (latch_addr_en) begin
                latched_addr_q <= latched_addr_d;
            end
        end
    end

    // ========================================================================
    // Next-State and Combinational Control Logic
    // ========================================================================
    always @(*) begin
        state_d           = state_q;
        latched_addr_d    = latched_addr_q;
        latch_addr_en     = 1'b0;

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
                    latched_addr_d = cpu_req_addr;
                    latch_addr_en  = 1'b1;
                    state_d        = STATE_LOOKUP;
                end
            end

            STATE_LOOKUP: begin
                // In LOOKUP, cpu_req_ready is 0; latched_addr_q is held constant
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
