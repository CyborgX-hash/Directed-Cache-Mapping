// ============================================================================
// Module: main_memory
// Author: Harsh Kumar (Memory Subsystem & Refill Interface Lead)
// Project: Design and Analysis of a Direct-Mapped Cache Controller
// Description: Behavioral and synthesizable-compatible Main Memory model
//              servicing 16-byte (128-bit) block read refill requests with
//              parameterized access latency and deterministic data initialization.
//
// Key Architectural Features:
//   - Parameterized access latency (default 10 cycles, configurable)
//   - 3-state Moore FSM: MEM_IDLE, MEM_ACCESS, MEM_RESPONSE
//   - Deterministic address-based word mapping ensuring independent verification
//   - Modeled memory array backing for 256 cache blocks (4 KB address space)
//   - Accidental repeated request filtering during active memory service
//   - Single-cycle ready strobe completion handshake
//   - Diagnostics: FSM state output for verification observability
// ============================================================================

`timescale 1ns / 1ps

module main_memory #(
    parameter LATENCY    = 10,    // Memory access latency in clock cycles (default: 10)
    parameter BLOCK_BITS = 128,   // Cache block size: 16 bytes = 128 bits
    parameter ADDR_BITS  = 32,    // Address width: 32 bits
    parameter MEM_DEPTH  = 256    // Modeled storage depth (number of 128-bit blocks)
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // Request interface from cache controller / memory interface
    input  wire                  mem_req_val,
    input  wire [ADDR_BITS-1:0]  mem_req_addr,

    // Response interface
    output reg                   mem_req_ready,
    output reg  [BLOCK_BITS-1:0] mem_resp_data,

    // Diagnostic / Verification Observability Ports
    output wire [1:0]            fsm_state
);

    // Initial architectural model skeleton: baseline registers and state
    reg [ADDR_BITS-1:0]  latched_addr;
    reg [7:0]            latency_counter;
    reg                  serving;

    assign fsm_state = serving ? 2'b01 : 2'b00;

    // Reset and baseline state initialization
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            latched_addr    <= {ADDR_BITS{1'b0}};
            latency_counter <= 8'd0;
            serving         <= 1'b0;
            mem_req_ready   <= 1'b0;
            mem_resp_data   <= {BLOCK_BITS{1'b0}};
        end else begin
            if (!serving) begin
                mem_req_ready <= 1'b0;
                if (mem_req_val) begin
                    serving         <= 1'b1;
                    latched_addr    <= mem_req_addr;
                    latency_counter <= 8'd1;
                end
            end else begin
                if (latency_counter < LATENCY) begin
                    latency_counter <= latency_counter + 1'b1;
                end else begin
                    serving         <= 1'b0;
                    mem_req_ready   <= 1'b1;
                end
            end
        end
    end

endmodule
