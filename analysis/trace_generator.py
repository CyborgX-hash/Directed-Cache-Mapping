#!/usr/bin/env python3
"""
trace_generator.py
Direct-Mapped Cache Controller Memory Access Trace Generator

Author: Priyanshu (Performance Analyst & Synthesis Lead)
Project: Design and Analysis of a Direct-Mapped Cache Controller

Cache Architectural Configuration:
  - Total Capacity : 1024 Bytes (1 KB)
  - Block Size     : 16 Bytes (128 bits)
  - Address Width  : 32 bits
  - Cache Lines    : 64 lines (Index: 6 bits)
  - Words / Block  : 4 words (Word width: 32 bits)
  - Tag Width      : 22 bits (address[31:10])
  - Index Width    : 6 bits  (address[9:4])
  - Offset Width   : 4 bits  (address[3:0])
  - Word Select    : 2 bits  (address[3:2])
  - Byte Offset    : 2 bits  (address[1:0])
"""

import os
import csv
import argparse
from dataclasses import dataclass
from typing import List, Optional


# ==============================================================================
# Architectural Constants
# ==============================================================================
ADDR_WIDTH   = 32
CACHE_SIZE   = 1024
BLOCK_SIZE   = 16
NUM_LINES    = 64
WORDS_PER_BLOCK = 4
WORD_SIZE    = 4  # bytes

TAG_WIDTH    = 22
INDEX_WIDTH  = 6
OFFSET_WIDTH = 4

TAG_MASK     = (1 << TAG_WIDTH) - 1
INDEX_MASK   = (1 << INDEX_WIDTH) - 1
OFFSET_MASK  = (1 << OFFSET_WIDTH) - 1


# ==============================================================================
# Address Decoding
# ==============================================================================
@dataclass
class DecodedAddress:
    addr: int
    tag: int
    index: int
    offset: int
    word_sel: int
    byte_offset: int
    block_addr: int

    def __str__(self) -> str:
        return (f"Addr=0x{self.addr:08x} [Tag=0x{self.tag:06x} "
                f"Idx={self.index:02d} (0x{self.index:02x}) "
                f"Offset=0x{self.offset:1x} Word={self.word_sel}]")


def decode_address(addr: int) -> DecodedAddress:
    """
    Decodes a 32-bit address into Tag (31:10), Index (9:4), and Offset (3:0).
    Matches rtl/address_decoder.v exactly.
    """
    addr = addr & 0xFFFFFFFF
    tag = (addr >> 10) & TAG_MASK
    index = (addr >> 4) & INDEX_MASK
    offset = addr & OFFSET_MASK
    word_sel = (offset >> 2) & 0x3
    byte_offset = offset & 0x3
    block_addr = addr & ~OFFSET_MASK

    return DecodedAddress(
        addr=addr,
        tag=tag,
        index=index,
        offset=offset,
        word_sel=word_sel,
        byte_offset=byte_offset,
        block_addr=block_addr
    )


# ==============================================================================
# Access Record
# ==============================================================================
@dataclass
class TraceRecord:
    seq_id: int
    addr: int
    op: str
    pattern_type: str
    decoded: DecodedAddress
    description: str = ""

    def to_csv_row(self) -> List[str]:
        return [
            str(self.seq_id),
            f"0x{self.addr:08x}",
            self.op,
            self.pattern_type,
            f"0x{self.decoded.tag:06x}",
            str(self.decoded.index),
            f"0x{self.decoded.offset:01x}",
            str(self.decoded.word_sel),
            self.description
        ]


# ==============================================================================
# Trace Generator
# ==============================================================================
class TraceGenerator:
    """
    Generates reproducible memory access traces for cache performance analysis.
    """

    def __init__(self):
        self.traces: List[TraceRecord] = []

    def clear(self):
        self.traces.clear()

    # --------------------------------------------------------------------------
    # Pattern A: Sequential Access (Spatial Locality)
    # --------------------------------------------------------------------------
    def generate_sequential(
        self,
        count: int = 64,
        start_addr: int = 0x00001000,
        stride: int = 4,
        op: str = "READ"
    ) -> List[TraceRecord]:
        """
        Generate consecutive word accesses with fixed stride (default 4 bytes).
        Objective: Analyze spatial locality across cache blocks.
        Each 16-byte block holds 4 consecutive 32-bit words.
        With stride=4, exactly 1 compulsory miss occurs followed by 3 hits per block.
        """
        self.clear()
        curr_addr = start_addr

        for i in range(count):
            dec = decode_address(curr_addr)
            desc = f"Sequential access #{i}: Word {dec.word_sel} of Block 0x{dec.block_addr:08x}"
            record = TraceRecord(
                seq_id=i,
                addr=curr_addr,
                op=op,
                pattern_type="SEQUENTIAL",
                decoded=dec,
                description=desc
            )
            self.traces.append(record)
            curr_addr = (curr_addr + stride) & 0xFFFFFFFF

        return list(self.traces)

    # --------------------------------------------------------------------------
    # File Exporters
    # --------------------------------------------------------------------------
    def save_csv(self, filepath: str):
        """Save trace to CSV with complete decoded metadata."""
        os.makedirs(os.path.dirname(os.path.abspath(filepath)), exist_ok=True)
        headers = [
            "seq_id", "address", "operation", "pattern",
            "tag_hex", "index_dec", "offset_hex", "word_sel", "description"
        ]
        with open(filepath, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(headers)
            for r in self.traces:
                writer.writerow(r.to_csv_row())
        print(f"[TraceGenerator] Saved {len(self.traces)} records to CSV: {filepath}")

    def save_hex(self, filepath: str):
        """Save plain hex addresses (one per line) for Verilog $readmemh."""
        os.makedirs(os.path.dirname(os.path.abspath(filepath)), exist_ok=True)
        with open(filepath, "w") as f:
            for r in self.traces:
                f.write(f"{r.addr:08x}\n")
        print(f"[TraceGenerator] Saved {len(self.traces)} addresses to HEX: {filepath}")

    def save_txt(self, filepath: str):
        """Save human-readable formatted trace table."""
        os.makedirs(os.path.dirname(os.path.abspath(filepath)), exist_ok=True)
        with open(filepath, "w") as f:
            f.write("# ====================================================================\n")
            f.write("# Direct-Mapped Cache Controller Access Trace\n")
            f.write(f"# Total Accesses: {len(self.traces)}\n")
            f.write("# Seq   Address      Op    Pattern     Tag      Idx Off Wrd  Description\n")
            f.write("# ====================================================================\n")
            for r in self.traces:
                f.write(
                    f"{r.seq_id:4d}  0x{r.addr:08x}  {r.op:4s}  {r.pattern_type:10s}  "
                    f"0x{r.decoded.tag:06x}  {r.decoded.index:2d}   "
                    f"0x{r.decoded.offset:01x}   {r.decoded.word_sel}   {r.description}\n"
                )
        print(f"[TraceGenerator] Saved {len(self.traces)} records to TXT: {filepath}")


# ==============================================================================
# CLI Entry Point
# ==============================================================================
def main():
    parser = argparse.ArgumentParser(description="Memory Access Trace Generator")
    parser.add_argument("--pattern", type=str, default="sequential",
                        choices=["sequential"], help="Trace pattern")
    parser.add_argument("--count", type=int, default=64, help="Number of memory accesses")
    parser.add_argument("--start", type=lambda x: int(x, 0), default=0x00001000,
                        help="Starting address (hex or dec)")
    parser.add_argument("--stride", type=int, default=4, help="Address stride in bytes")
    parser.add_argument("--output-dir", type=str, default="traces", help="Output directory")

    args = parser.parse_args()
    gen = TraceGenerator()

    if args.pattern == "sequential":
        gen.generate_sequential(count=args.count, start_addr=args.start, stride=args.stride)
        gen.save_csv(os.path.join(args.output_dir, "sequential_trace.csv"))
        gen.save_hex(os.path.join(args.output_dir, "sequential_trace.hex"))
        gen.save_txt(os.path.join(args.output_dir, "sequential_trace.txt"))


if __name__ == "__main__":
    main()
