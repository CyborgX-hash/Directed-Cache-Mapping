// ============================================================================
// Module: main_memory
// Author: Ajit
// Project: Design and Analysis of a Direct-Mapped Cache Controller
// Description: Behavioral / synthesizable memory model that services 16-byte
//              (128-bit) block read requests with parameterized latency.
//              Provides deterministic block data for verification.
// ============================================================================

`timescale 1ns / 1ps

module main_memory #(
    parameter LATENCY    = 2,     // Access latency in clock cycles
    parameter BLOCK_BITS = 128,   // 16 bytes = 128 bits
    parameter ADDR_BITS  = 32
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // Request interface from controller / memory interface
    input  wire                  mem_req_val,
    input  wire [ADDR_BITS-1:0]  mem_req_addr,

    // Response interface
    output reg                   mem_req_ready,
    output reg  [BLOCK_BITS-1:0] mem_resp_data
);

    reg [3:0] latency_counter;
    reg       serving;
    reg [ADDR_BITS-1:0] latched_addr;

    // Helper to generate distinct 32-bit words per block for clear verification
    wire [31:0] block_base = {latched_addr[31:4], 4'b0000};
    wire [31:0] word0 = block_base | 32'h0000_0000;
    wire [31:0] word1 = block_base | 32'h0000_0004;
    wire [31:0] word2 = block_base | 32'h0000_0008;
    wire [31:0] word3 = block_base | 32'h0000_000C;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            latency_counter <= 4'd0;
            serving         <= 1'b0;
            mem_req_ready   <= 1'b0;
            mem_resp_data   <= {BLOCK_BITS{1'b0}};
            latched_addr    <= {ADDR_BITS{1'b0}};
        end else begin
            if (!serving) begin
                mem_req_ready <= 1'b0;
                if (mem_req_val) begin
                    serving         <= 1'b1;
                    latched_addr    <= mem_req_addr;
                    latency_counter <= 4'd1;
                    if (LATENCY <= 1) begin
                        mem_req_ready <= 1'b1;
                        mem_resp_data <= {word3, word2, word1, word0};
                        serving       <= 1'b0;
                    end
                end
            end else begin
                if (latency_counter < LATENCY) begin
                    latency_counter <= latency_counter + 1'b1;
                end else begin
                    mem_req_ready <= 1'b1;
                    mem_resp_data <= {word3, word2, word1, word0};
                    serving       <= 1'b0;
                end
            end
        end
    end

endmodule
