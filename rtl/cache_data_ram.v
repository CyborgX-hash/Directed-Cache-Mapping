// ============================================================================
// Module: cache_data_ram
// Author: Mihika Mathur
// Project: Design and Analysis of a Direct-Mapped Cache Controller
// Description: Direct-mapped cache data storage array consisting of 64 lines,
//              each holding a 128-bit cache block (16 bytes = 4 x 32-bit words).
//              Total data capacity: 1024 bytes (1 KB).
//
// Hardware Features & Timing:
//   - Synchronous write on rising clock edge when write_enable is asserted.
//   - Combinational asynchronous read indexed by 6-bit index input.
//   - No hardware reset on data array (avoids inferring 8,192 flip-flops;
//     enables FPGA Distributed RAM / LUTRAM synthesis).
//   - Data validity is qualified externally by the valid-bit RAM.
// ============================================================================

`timescale 1ns / 1ps

module cache_data_ram #(
    parameter NUM_LINES   = 64,
    parameter INDEX_WIDTH = 6,
    parameter DATA_WIDTH  = 128
)(
    input  wire                   clk,
    input  wire [INDEX_WIDTH-1:0] index,
    input  wire                   write_enable,
    input  wire [DATA_WIDTH-1:0]  write_data,
    output wire [DATA_WIDTH-1:0]  read_data
);

    // 64-entry x 128-bit memory matrix
    reg [DATA_WIDTH-1:0] data_mem [0:NUM_LINES-1];

    // Asynchronous / Combinational Read Port
    // Provides immediate zero-latency line access for controller LOOKUP state
    assign read_data = data_mem[index];

    // Synchronous Single-Port Write
    // Updates the addressed line atomically during cache block REFILL
    always @(posedge clk) begin
        if (write_enable) begin
            data_mem[index] <= write_data;
        end
    end

endmodule
