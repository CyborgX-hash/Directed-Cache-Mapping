#!/usr/bin/env python3
"""
amat_calculator.py - Average Memory Access Time (AMAT) Analysis Engine

Author: Priyanshu (Performance Analyst & Synthesis Lead)
Project: Design and Analysis of a Direct-Mapped Cache Controller

Mathematical Foundation:
  AMAT = Hit Time + (Miss Rate * Miss Penalty)

Conventions & Parameters:
  1. Textbook Baseline Convention:
     - Hit Time (T_hit)            : 1 cycle
     - Raw Memory Latency (L_mem)  : 10 cycles
     - Miss Penalty (P_miss)       : 10 cycles (raw memory access time)
     - AMAT_baseline = 1.0 + (Miss_Rate * 10)

  2. Hardware Cycle-Accurate Controller Convention (RTL FSM Timing):
     - Hit Time (T_hit)            : 1 cycle (LOOKUP state hit detection)
     - Raw Memory Latency (L_mem)  : 10 cycles (Main memory wait state)
     - Protocol Overhead (O_ctrl)  : 4 cycles
         * Cycle 1: STATE_LOOKUP (miss detected -> branch to MEM_REQ)
         * Cycle 2: STATE_MEM_REQUEST (assert bus request)
         * Cycle 3: STATE_REFILL (write 128-bit block into RAM)
         * Cycle 4: STATE_RESPOND (present word on CPU data bus)
     - Total Miss Penalty (P_hw)   : L_mem + O_ctrl = 10 + 4 = 14 cycles
     - AMAT_hardware = 1.0 + (Miss_Rate * 14)

  3. Simulation DUT Default:
     - MEM_LATENCY parameter in DUT = 2 cycles
     - P_hw_dut = 2 + 4 = 6 cycles
     - AMAT_dut = 1.0 + (Miss_Rate * 6)
"""

import os
import sys
import argparse
from dataclasses import dataclass
from typing import List, Dict, Optional

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)

# Import statistics analyzer
from analysis.statistics import StatisticsAnalyzer, CacheStatistics


# ==============================================================================
# AMAT Evaluation Model
# ==============================================================================
@dataclass
class AMATResult:
    workload: str
    access_count: int
    hits: int
    misses: int
    hit_ratio: float
    miss_ratio: float

    # Timing Parameters (Cycles)
    hit_time: float
    raw_mem_latency: float
    ctrl_overhead: float
    total_miss_penalty: float

    # Evaluated AMAT values
    amat_baseline: float      # Standard textbook: T_hit + MissRate * L_mem
    amat_hardware: float      # RTL Cycle-Accurate: T_hit + MissRate * (L_mem + O_ctrl)

    def to_dict(self) -> Dict:
        return {
            "workload": self.workload,
            "access_count": self.access_count,
            "hits": self.hits,
            "misses": self.misses,
            "hit_ratio": round(self.hit_ratio, 4),
            "miss_ratio": round(self.miss_ratio, 4),
            "hit_time": self.hit_time,
            "raw_mem_latency": self.raw_mem_latency,
            "ctrl_overhead": self.ctrl_overhead,
            "total_miss_penalty": self.total_miss_penalty,
            "amat_baseline": round(self.amat_baseline, 4),
            "amat_hardware": round(self.amat_hardware, 4)
        }


class AMATCalculator:
    """
    Independent AMAT calculation engine supporting multiple latency conventions,
    parameter sweeps, and architectural sensitivity experiments.
    """

    def __init__(
        self,
        hit_time: float = 1.0,
        raw_mem_latency: float = 10.0,
        ctrl_overhead: float = 4.0
    ):
        self.hit_time = hit_time
        self.raw_mem_latency = raw_mem_latency
        self.ctrl_overhead = ctrl_overhead

    @property
    def total_miss_penalty(self) -> float:
        return self.raw_mem_latency + self.ctrl_overhead

    def compute_amat(
        self,
        miss_rate: float,
        hit_time: Optional[float] = None,
        miss_penalty: Optional[float] = None
    ) -> float:
        """
        Pure formula: AMAT = Hit Time + (Miss Rate * Miss Penalty)
        """
        h_time = hit_time if hit_time is not None else self.hit_time
        m_penalty = miss_penalty if miss_penalty is not None else self.raw_mem_latency
        return h_time + (miss_rate * m_penalty)

    def compute_hardware_amat(
        self,
        miss_rate: float,
        hit_time: Optional[float] = None,
        raw_mem_latency: Optional[float] = None,
        ctrl_overhead: Optional[float] = None
    ) -> float:
        """
        RTL cycle-accurate AMAT accounting for controller states:
        AMAT_hw = Hit Time + Miss Rate * (Raw Memory Latency + Controller Protocol Overhead)
        """
        h_time = hit_time if hit_time is not None else self.hit_time
        mem_lat = raw_mem_latency if raw_mem_latency is not None else self.raw_mem_latency
        overhead = ctrl_overhead if ctrl_overhead is not None else self.ctrl_overhead
        return h_time + (miss_rate * (mem_lat + overhead))

    def evaluate_statistics(self, stats: CacheStatistics) -> AMATResult:
        """
        Calculate complete AMAT metrics from a CacheStatistics record.
        """
        amat_base = self.compute_amat(stats.miss_ratio, self.hit_time, self.raw_mem_latency)
        amat_hw = self.compute_hardware_amat(
            stats.miss_ratio, self.hit_time, self.raw_mem_latency, self.ctrl_overhead
        )

        return AMATResult(
            workload=stats.workload,
            access_count=stats.total_accesses,
            hits=stats.total_hits,
            misses=stats.total_misses,
            hit_ratio=stats.hit_ratio,
            miss_ratio=stats.miss_ratio,
            hit_time=self.hit_time,
            raw_mem_latency=self.raw_mem_latency,
            ctrl_overhead=self.ctrl_overhead,
            total_miss_penalty=self.total_miss_penalty,
            amat_baseline=amat_base,
            amat_hardware=amat_hw
        )

    def evaluate_all(self, stats_list: List[CacheStatistics]) -> List[AMATResult]:
        return [self.evaluate_statistics(s) for s in stats_list]

    @staticmethod
    def format_comparison_table(results: List[AMATResult]) -> str:
        """
        Generate comparison table required by Section 6 of specification.
        """
        lines = []
        sep = "=" * 115
        subsep = "-" * 115
        lines.append(sep)
        lines.append(
            f"{'Workload':<14} | {'Accesses':>8} | {'Hits':>6} | {'Misses':>6} | "
            f"{'Hit Ratio':>9} | {'Miss Ratio':>10} | {'AMAT (Base)':>11} | {'AMAT (RTL-HW)':>13} | {'Speedup':>7}"
        )
        lines.append(subsep)

        # Baseline worst-case reference (100% miss rate)
        worst_base = 1.0 + (1.0 * 10.0)  # 11.0 cycles

        for r in results:
            speedup = worst_base / r.amat_baseline if r.amat_baseline > 0 else 1.0
            lines.append(
                f"{r.workload:<14} | {r.access_count:>8d} | {r.hits:>6d} | {r.misses:>6d} | "
                f"{r.hit_ratio*100:>8.2f}% | {r.miss_ratio*100:>9.2f}% | "
                f"{r.amat_baseline:>9.3f} cyc | {r.amat_hardware:>10.3f} cyc | {speedup:>6.2f}x"
            )
        lines.append(sep)
        return "\n".join(lines)


# ==============================================================================
# CLI Entry Point
# ==============================================================================
def main():
    parser = argparse.ArgumentParser(description="Direct-Mapped Cache AMAT Calculator")
    parser.add_argument("--traces-dir", type=str, default="traces", help="Directory with trace files")
    parser.add_argument("--hit-time", type=float, default=1.0, help="Hit time in clock cycles (default: 1.0)")
    parser.add_argument("--mem-latency", type=float, default=10.0,
                        help="Raw main memory latency in cycles (default: 10.0)")
    parser.add_argument("--ctrl-overhead", type=float, default=4.0,
                        help="FSM refill and handshake overhead in cycles (default: 4.0)")
    parser.add_argument("--output-report", type=str, default="analysis/amat_report.txt",
                        help="Output report text file")
    args = parser.parse_args()

    analyzer = StatisticsAnalyzer()
    calculator = AMATCalculator(
        hit_time=args.hit_time,
        raw_mem_latency=args.mem_latency,
        ctrl_overhead=args.ctrl_overhead
    )

    patterns = ["sequential", "repeated", "random", "conflict"]
    stats_list = []
    for p in patterns:
        csv_path = os.path.join(args.traces_dir, f"{p}_trace.csv")
        hex_path = os.path.join(args.traces_dir, f"{p}_trace.hex")
        target = csv_path if os.path.exists(csv_path) else hex_path
        if os.path.exists(target):
            stats = analyzer.analyze_file(target, workload_name=p.capitalize())
            stats_list.append(stats)

    results = calculator.evaluate_all(stats_list)
    table = calculator.format_comparison_table(results)

    print("\n" + table + "\n")

    if args.output_report:
        os.makedirs(os.path.dirname(os.path.abspath(args.output_report)), exist_ok=True)
        with open(args.output_report, "w") as f:
            f.write("# =====================================================================\n")
            f.write("# Direct-Mapped Cache Controller: AMAT Performance Report\n")
            f.write("# Author: Priyanshu (Performance Analyst & Synthesis Lead)\n")
            f.write(f"# Baseline Parameters : Hit Time = {args.hit_time} cyc | Raw Mem Latency = {args.mem_latency} cyc\n")
            f.write(f"# Controller Protocol : Overhead = {args.ctrl_overhead} cyc | Total RTL Miss Penalty = {args.mem_latency + args.ctrl_overhead} cyc\n")
            f.write("# =====================================================================\n\n")
            f.write(table + "\n\n")
            f.write("Analytical Derivations:\n")
            for r in results:
                f.write(f"\n--- {r.workload} Workload ---\n")
                f.write(f"  Access Count     : {r.access_count}\n")
                f.write(f"  Hit Ratio        : {r.hit_ratio*100:.2f}%\n")
                f.write(f"  Miss Ratio       : {r.miss_ratio*100:.2f}%\n")
                f.write(f"  AMAT (Baseline)  : {r.hit_time} + ({r.miss_ratio:.4f} * {r.raw_mem_latency}) = {r.amat_baseline:.4f} cycles\n")
                f.write(f"  AMAT (Hardware)  : {r.hit_time} + ({r.miss_ratio:.4f} * ({r.raw_mem_latency} + {r.ctrl_overhead})) = {r.amat_hardware:.4f} cycles\n")
        print(f"[AMATCalculator] Report saved to {args.output_report}")


if __name__ == "__main__":
    main()
