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

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)

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
        dec = decode_address(addr, num_lines=self.num_lines, block_size=self.block_size)
        line = self.lines[dec.index]
        is_hit = line.valid and (line.tag == dec.tag)
        return is_hit, dec

    def access(self, addr: int, seq_id: int = 0) -> AccessOutcome:
        """
        Process a memory access. Evaluates hit/miss and updates cache state on miss.
        """
        self.access_count += 1
        dec = decode_address(addr, num_lines=self.num_lines, block_size=self.block_size)
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
        dec = decode_address(addr, num_lines=self.dm_cache.num_lines, block_size=self.dm_cache.block_size)
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


# ==============================================================================
# Statistical Metrics Model
# ==============================================================================
@dataclass
class CacheStatistics:
    workload: str
    total_accesses: int
    total_hits: int
    total_misses: int
    hit_ratio: float
    miss_ratio: float
    compulsory_misses: int
    capacity_misses: int
    conflict_misses: int
    refill_count: int

    # Ratios & Validation
    compulsory_ratio: float
    capacity_ratio: float
    conflict_ratio: float
    sum_check: float
    breakdown_valid: bool

    def to_dict(self) -> Dict:
        return {
            "workload": self.workload,
            "total_accesses": self.total_accesses,
            "total_hits": self.total_hits,
            "total_misses": self.total_misses,
            "hit_ratio": round(self.hit_ratio, 4),
            "miss_ratio": round(self.miss_ratio, 4),
            "compulsory_misses": self.compulsory_misses,
            "capacity_misses": self.capacity_misses,
            "conflict_misses": self.conflict_misses,
            "refill_count": self.refill_count,
            "compulsory_ratio": round(self.compulsory_ratio, 4),
            "capacity_ratio": round(self.capacity_ratio, 4),
            "conflict_ratio": round(self.conflict_ratio, 4),
            "hit_plus_miss": round(self.sum_check, 6),
            "breakdown_valid": self.breakdown_valid
        }


# ==============================================================================
# Statistics Analyzer
# ==============================================================================
class StatisticsAnalyzer:
    """
    Analyzes memory access traces, calculates full 3C metrics, validates formulas,
    and formats comprehensive statistical tables.
    """

    def __init__(self, simulator: Optional[CacheSimulator] = None):
        self.sim = simulator or CacheSimulator()

    @staticmethod
    def load_trace_file(filepath: str) -> List[int]:
        """
        Loads addresses from CSV, HEX, or TXT file.
        Automatically recognizes file format.
        """
        addresses = []
        ext = os.path.splitext(filepath)[1].lower()

        with open(filepath, "r") as f:
            if ext == ".csv":
                reader = csv.DictReader(f)
                for row in reader:
                    addr_str = row.get("address") or row.get("addr")
                    if addr_str:
                        addresses.append(int(addr_str, 0))
            elif ext == ".hex":
                for line in f:
                    line = line.strip()
                    if line and not line.startswith("#") and not line.startswith("//"):
                        addresses.append(int(line, 16))
            else:
                # Text file: skip comments and parse hex or int
                for line in f:
                    line = line.strip()
                    if not line or line.startswith("#") or line.startswith("//"):
                        continue
                    parts = line.split()
                    for p in parts:
                        if p.startswith("0x") or p.startswith("0X"):
                            addresses.append(int(p, 16))
                            break
                        elif p.isdigit():
                            addresses.append(int(p, 10))
                            break
        return addresses

    def analyze_trace(self, addresses: List[int], workload_name: str = "Workload") -> CacheStatistics:
        """
        Run trace through cache simulator and compute complete performance statistics.
        """
        outcomes = self.sim.run_trace(addresses)

        total_accesses = len(outcomes)
        hits = sum(1 for o in outcomes if o.is_hit)
        misses = sum(1 for o in outcomes if not o.is_hit)
        compulsory = sum(1 for o in outcomes if o.miss_type == "COMPULSORY")
        capacity = sum(1 for o in outcomes if o.miss_type == "CAPACITY")
        conflict = sum(1 for o in outcomes if o.miss_type == "CONFLICT")
        refills = self.sim.dm_cache.refill_count

        hit_ratio = hits / total_accesses if total_accesses > 0 else 0.0
        miss_ratio = misses / total_accesses if total_accesses > 0 else 0.0

        # Mathematical Validation: Hit Ratio + Miss Ratio = 1
        sum_check = hit_ratio + miss_ratio
        assert abs(sum_check - 1.0) < 1e-9 or total_accesses == 0, (
            f"Validation Failed: Hit Ratio ({hit_ratio}) + Miss Ratio ({miss_ratio}) = {sum_check} != 1.0"
        )

        # 3C Breakdown Validation: Total Misses == Compulsory + Capacity + Conflict
        breakdown_valid = (misses == (compulsory + capacity + conflict))
        assert breakdown_valid, (
            f"3C Breakdown Mismatch: Total Misses ({misses}) != "
            f"Compulsory ({compulsory}) + Capacity ({capacity}) + Conflict ({conflict})"
        )

        compulsory_ratio = compulsory / total_accesses if total_accesses > 0 else 0.0
        capacity_ratio = capacity / total_accesses if total_accesses > 0 else 0.0
        conflict_ratio = conflict / total_accesses if total_accesses > 0 else 0.0

        return CacheStatistics(
            workload=workload_name,
            total_accesses=total_accesses,
            total_hits=hits,
            total_misses=misses,
            hit_ratio=hit_ratio,
            miss_ratio=miss_ratio,
            compulsory_misses=compulsory,
            capacity_misses=capacity,
            conflict_misses=conflict,
            refill_count=refills,
            compulsory_ratio=compulsory_ratio,
            capacity_ratio=capacity_ratio,
            conflict_ratio=conflict_ratio,
            sum_check=sum_check,
            breakdown_valid=breakdown_valid
        )

    def analyze_file(self, filepath: str, workload_name: Optional[str] = None) -> CacheStatistics:
        if workload_name is None:
            base = os.path.basename(filepath)
            workload_name = os.path.splitext(base)[0].replace("_trace", "").capitalize()
        addrs = self.load_trace_file(filepath)
        return self.analyze_trace(addrs, workload_name)

    @staticmethod
    def format_summary_table(stats_list: List[CacheStatistics]) -> str:
        """Format an IEEE-ready ASCII summary table."""
        lines = []
        sep = "=" * 115
        subsep = "-" * 115
        lines.append(sep)
        lines.append(
            f"{'Workload':<14} | {'Accesses':>8} | {'Hits':>6} | {'Misses':>6} | "
            f"{'Hit Rate':>8} | {'Miss Rate':>9} | {'Compulsory':>10} | "
            f"{'Capacity':>8} | {'Conflict':>8} | {'Refills':>7} | {'Sum=1.0'}"
        )
        lines.append(subsep)
        for s in stats_list:
            lines.append(
                f"{s.workload:<14} | {s.total_accesses:>8d} | {s.total_hits:>6d} | {s.total_misses:>6d} | "
                f"{s.hit_ratio*100:>7.2f}% | {s.miss_ratio*100:>8.2f}% | {s.compulsory_misses:>10d} | "
                f"{s.capacity_misses:>8d} | {s.conflict_misses:>8d} | {s.refill_count:>7d} | "
                f"{'VALID' if abs(s.sum_check - 1.0) < 1e-6 else 'FAIL'}"
            )
        lines.append(sep)
        return "\n".join(lines)


# ==============================================================================
# CLI Entry Point
# ==============================================================================
def main():
    import argparse
    parser = argparse.ArgumentParser(description="Cache Performance Statistics Analyzer")
    parser.add_argument("--trace", type=str, help="Specific trace file to analyze")
    parser.add_argument("--traces-dir", type=str, default="traces", help="Directory containing traces")
    parser.add_argument("--output-report", type=str, default="analysis/statistics_report.txt",
                        help="Output text report filepath")
    args = parser.parse_args()

    analyzer = StatisticsAnalyzer()
    stats_list: List[CacheStatistics] = []

    if args.trace:
        stats = analyzer.analyze_file(args.trace)
        stats_list.append(stats)
    else:
        # Analyze standard benchmark traces
        patterns = ["sequential", "repeated", "random", "conflict"]
        for p in patterns:
            # Try CSV first, then HEX
            csv_path = os.path.join(args.traces_dir, f"{p}_trace.csv")
            hex_path = os.path.join(args.traces_dir, f"{p}_trace.hex")
            target = csv_path if os.path.exists(csv_path) else hex_path
            if os.path.exists(target):
                stats = analyzer.analyze_file(target, workload_name=p.capitalize())
                stats_list.append(stats)
            else:
                print(f"[Warning] Trace file not found: {target}")

    table = analyzer.format_summary_table(stats_list)
    print("\n" + table + "\n")

    if args.output_report:
        os.makedirs(os.path.dirname(os.path.abspath(args.output_report)), exist_ok=True)
        with open(args.output_report, "w") as f:
            f.write("# Direct-Mapped Cache Controller: Performance Statistics Report\n")
            f.write("# Cache Geometry: 1 KB, 64 Lines, 16-Byte Blocks, Direct-Mapped\n")
            f.write("# Reference Model: 1 KB Fully Associative LRU for 3C Miss Classification\n\n")
            f.write(table + "\n\n")
            f.write("Detailed 3C Architectural Breakdown:\n")
            for s in stats_list:
                f.write(f"\n--- {s.workload} Access Workload ---\n")
                f.write(f"  Total Accesses      : {s.total_accesses}\n")
                f.write(f"  Cache Hits          : {s.total_hits} ({s.hit_ratio*100:.2f}%)\n")
                f.write(f"  Cache Misses        : {s.total_misses} ({s.miss_ratio*100:.2f}%)\n")
                f.write(f"  Compulsory Misses   : {s.compulsory_misses} ({s.compulsory_ratio*100:.2f}% of accesses)\n")
                f.write(f"  Capacity Misses     : {s.capacity_misses} ({s.capacity_ratio*100:.2f}% of accesses)\n")
                f.write(f"  Conflict Misses     : {s.conflict_misses} ({s.conflict_ratio*100:.2f}% of accesses)\n")
                f.write(f"  Refill Operations   : {s.refill_count}\n")
                f.write(f"  Hit Rate + Miss Rate: {s.sum_check:.6f} (Validation: PASS)\n")
        print(f"[StatisticsAnalyzer] Saved report to {args.output_report}")


if __name__ == "__main__":
    main()
