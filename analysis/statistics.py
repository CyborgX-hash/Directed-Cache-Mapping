#!/usr/bin/env python3
"""
statistics.py - Cache Performance Statistics Analyzer & Cache Simulator

Author: Priyanshu (Performance Analyst & Synthesis Lead)
Project: Design and Analysis of a Direct-Mapped Cache Controller

Architecture Configuration:
  - Cache Capacity : 1024 Bytes (1 KB)
  - Block Size     : 16 Bytes
  - Total Lines    : 64 lines
  - Tag Width      : 22 bits (addr[31:10])
  - Index Width    : 6 bits  (addr[9:4])
  - Offset Width   : 4 bits  (addr[3:0])
  - Word Select    : 2 bits  (addr[3:2])

Miss Classification Reference Model (Hill & Smith 3C Model):
  - Compulsory Miss: First reference to a memory block (misses in infinite cache).
  - Capacity Miss  : Miss in a fully-associative cache of size 1 KB (64 blocks) with LRU,
                     excluding compulsory misses.
  - Conflict Miss  : Miss in direct-mapped cache that would HIT in the fully-associative
                     cache of identical capacity (caused purely by mapping collisions).
"""

import os
import sys
import csv
from dataclasses import dataclass, field
from typing import List, Dict, Tuple, Optional, Set
from collections import OrderedDict

# Import address decoding utilities from trace_generator
from analysis.trace_generator import (
    decode_address, DecodedAddress,
    TAG_WIDTH, INDEX_WIDTH, OFFSET_WIDTH, NUM_LINES, BLOCK_SIZE, CACHE_SIZE
)


# ==============================================================================
# Simulation Data Structures
# ==============================================================================
@dataclass
class CacheLine:
    line_index: int
    valid: bool = False
    tag: int = 0
    last_access_cycle: int = 0


@dataclass
class AccessOutcome:
    seq_id: int
    addr: int
    decoded: DecodedAddress
    is_hit: bool
    miss_type: Optional[str]  # None (if hit), 'COMPULSORY', 'CAPACITY', 'CONFLICT'
    evicted: bool
    evicted_tag: Optional[int]
    refill_block_addr: int


# ==============================================================================
# Direct-Mapped Cache Simulator
# ==============================================================================
class DirectMappedCache:
    """
    Cycle-accurate architectural simulator for the 1 KB direct-mapped cache.
    Replicates RTL behavior of rtl/cache_top.v, rtl/cache_storage.v, and
    rtl/tag_comparator.v.
    """

    def __init__(self, num_lines: int = NUM_LINES, block_size: int = BLOCK_SIZE):
        self.num_lines = num_lines
        self.block_size = block_size
        self.lines: List[CacheLine] = [CacheLine(i) for i in range(num_lines)]
        self.reset()

    def reset(self):
        """Hardware reset: clears all valid bits, matching rtl/valid_bit_ram.v."""
        for line in self.lines:
            line.valid = False
            line.tag = 0
            line.last_access_cycle = 0
        self.access_count = 0
        self.hit_count = 0
        self.miss_count = 0
        self.refill_count = 0

    def probe(self, addr: int) -> Tuple[bool, DecodedAddress]:
        """
        Pure combinational lookup without updating state.
        Returns (is_hit, decoded_address).
        """
        dec = decode_address(addr)
        line = self.lines[dec.index]
        is_hit = line.valid and (line.tag == dec.tag)
        return is_hit, dec

    def access(self, addr: int, seq_id: int = 0) -> AccessOutcome:
        """
        Process a memory access. Evaluates hit/miss and updates cache state on miss.
        """
        self.access_count += 1
        dec = decode_address(addr)
        line = self.lines[dec.index]

        is_hit = line.valid and (line.tag == dec.tag)
        evicted = False
        evicted_tag = None

        if is_hit:
            self.hit_count += 1
            line.last_access_cycle = seq_id
            return AccessOutcome(
                seq_id=seq_id,
                addr=addr,
                decoded=dec,
                is_hit=True,
                miss_type=None,
                evicted=False,
                evicted_tag=None,
                refill_block_addr=dec.block_addr
            )
        else:
            self.miss_count += 1
            self.refill_count += 1
            if line.valid:
                evicted = True
                evicted_tag = line.tag

            # Perform block refill into line
            line.valid = True
            line.tag = dec.tag
            line.last_access_cycle = seq_id

            return AccessOutcome(
                seq_id=seq_id,
                addr=addr,
                decoded=dec,
                is_hit=False,
                miss_type="MISS",  # Will be classified by 3C analyzer
                evicted=evicted,
                evicted_tag=evicted_tag,
                refill_block_addr=dec.block_addr
            )


# ==============================================================================
# Reference Models for 3C Miss Classification
# ==============================================================================
class InfiniteCacheReference:
    """
    Reference model: Cache with infinite capacity.
    An access is a COMPULSORY (cold) miss if and only if the block has
    never been referenced before in the trace.
    """
    def __init__(self):
        self.seen_blocks: Set[int] = set()

    def reset(self):
        self.seen_blocks.clear()

    def access(self, block_addr: int) -> bool:
        """Returns True if hit (block seen before), False if compulsory miss."""
        if block_addr in self.seen_blocks:
            return True
        else:
            self.seen_blocks.add(block_addr)
            return False


class FullyAssociativeLRUReference:
    """
    Reference model: Fully associative cache with the exact same capacity
    (64 blocks) and block size (16 bytes), using optimal Least-Recently Used (LRU)
    replacement.
    Used to mathematically separate CAPACITY misses from CONFLICT misses.
    """
    def __init__(self, capacity_blocks: int = NUM_LINES):
        self.capacity = capacity_blocks
        # OrderedDict maintains insertion / access order for LRU
        self.blocks: OrderedDict[int, int] = OrderedDict()

    def reset(self):
        self.blocks.clear()

    def access(self, block_addr: int) -> bool:
        """
        Returns True if hit in fully-associative cache, False if miss.
        Updates LRU order on every access.
        """
        if block_addr in self.blocks:
            # Move accessed block to the most-recently-used end
            self.blocks.move_to_end(block_addr)
            return True
        else:
            if len(self.blocks) >= self.capacity:
                # Evict least recently used block (first item)
                self.blocks.popitem(last=False)
            self.blocks[block_addr] = 1
            return False


# ==============================================================================
# Integrated Cache Simulator Engine
# ==============================================================================
class CacheSimulator:
    """
    Unified simulation engine executing direct-mapped simulation alongside
    infinite and fully-associative reference models for rigorous 3C classification.
    """

    def __init__(self, num_lines: int = NUM_LINES, block_size: int = BLOCK_SIZE):
        self.dm_cache = DirectMappedCache(num_lines, block_size)
        self.inf_ref = InfiniteCacheReference()
        self.fa_ref = FullyAssociativeLRUReference(num_lines)
        self.history: List[AccessOutcome] = []

    def reset(self):
        self.dm_cache.reset()
        self.inf_ref.reset()
        self.fa_ref.reset()
        self.history.clear()

    def step(self, addr: int, seq_id: int) -> AccessOutcome:
        """
        Simulate a single access and perform definitive 3C miss classification.
        """
        dec = decode_address(addr)
        block = dec.block_addr

        # 1. Check reference models
        inf_hit = self.inf_ref.access(block)
        fa_hit = self.fa_ref.access(block)

        # 2. Simulate direct-mapped cache
        outcome = self.dm_cache.access(addr, seq_id)

        # 3. Classify miss if direct-mapped missed
        if not outcome.is_hit:
            if not inf_hit:
                # Never referenced before -> Compulsory
                outcome.miss_type = "COMPULSORY"
            elif not fa_hit:
                # Missed even in fully-associative cache of same capacity -> Capacity
                outcome.miss_type = "CAPACITY"
            else:
                # Hit in fully-associative, but missed in direct-mapped -> Conflict
                outcome.miss_type = "CONFLICT"

        self.history.append(outcome)
        return outcome

    def run_trace(self, addresses: List[int]) -> List[AccessOutcome]:
        """Run complete trace of addresses through simulator."""
        self.reset()
        for seq, addr in enumerate(addresses):
            self.step(addr, seq)
        return self.history


if __name__ == "__main__":
    # Self-test simulator
    sim = CacheSimulator()
    test_addrs = [0x00001000, 0x00001004, 0x00001008, 0x0000100C]
    outcomes = sim.run_trace(test_addrs)
    for o in outcomes:
        print(f"Seq {o.seq_id}: Addr=0x{o.addr:08x} Hit={o.is_hit} Type={o.miss_type}")
