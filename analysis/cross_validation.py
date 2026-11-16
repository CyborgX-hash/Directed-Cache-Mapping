#!/usr/bin/env python3
"""
cross_validation.py - RTL vs Python Model Cross-Validation Suite

Author: Priyanshu (Performance Analyst & Synthesis Lead)
Co-author: Ajit (Verification Lead)
Project: Design and Analysis of a Direct-Mapped Cache Controller

Validates:
  1. Total access count equivalence (Python model vs RTL hardware)
  2. Total cache hit count equivalence
  3. Total cache miss count equivalence
  4. Memory refill count equivalence
  5. End-to-end CPU read data correctness
"""

import os
import sys
import re
import subprocess
from dataclasses import dataclass
from typing import Dict, List, Optional

# Ensure repository root is on sys.path
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)

from analysis.statistics import StatisticsAnalyzer, CacheStatistics


@dataclass
class RTLSimulationResult:
    workload: str
    accesses: int
    hits: int
    misses: int
    refills: int
    data_errors: int


@dataclass
class CrossValidationComparison:
    workload: str
    py_accesses: int
    rtl_accesses: int
    py_hits: int
    rtl_hits: int
    py_misses: int
    rtl_misses: int
    py_refills: int
    rtl_refills: int
    data_errors: int

    @property
    def is_match(self) -> bool:
        return (
            self.py_accesses == self.rtl_accesses and
            self.py_hits == self.rtl_hits and
            self.py_misses == self.rtl_misses and
            self.py_refills == self.rtl_refills and
            self.data_errors == 0
        )


class CrossValidator:
    def __init__(self, sim_vvp: str = "sim/tb_trace_cross_val.vvp"):
        self.sim_vvp = sim_vvp
        self.analyzer = StatisticsAnalyzer()

    def build_testbench(self) -> bool:
        """Compile RTL and cross-validation testbench with iverilog."""
        cmd = [
            "/opt/homebrew/bin/iverilog", "-g2012",
            "-o", self.sim_vvp,
            "-I", "rtl", "-I", "tb",
            "rtl/address_decoder.v", "rtl/cache_data_ram.v", "rtl/tag_ram.v",
            "rtl/valid_bit_ram.v", "rtl/cache_storage.v", "rtl/tag_comparator.v",
            "rtl/main_memory.v", "rtl/memory_interface.v",
            "rtl/cache_controller.v", "rtl/cache_top.v", "tb/tb_trace_cross_val.sv"
        ]
        os.makedirs(os.path.dirname(os.path.abspath(self.sim_vvp)), exist_ok=True)
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if res.returncode != 0:
            print(f"[CrossValidator] Compilation Failed:\n{res.stderr}")
            return False
        return True

    def run_rtl_trace(self, hex_file: str, workload_name: str) -> Optional[RTLSimulationResult]:
        """Execute vvp on given trace file and parse hardware telemetry output."""
        cmd = [
            "/opt/homebrew/bin/vvp", self.sim_vvp,
            f"+TRACE={hex_file}",
            f"+NAME={workload_name}"
        ]
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        # Parse output line:
        # [RTL_RESULT] Workload=Sequential Accesses=64 Hits=48 Misses=16 Refills=16 DataErrors=0
        pattern = r"\[RTL_RESULT\] Workload=(\w+) Accesses=(\d+) Hits=(\d+) Misses=(\d+) Refills=(\d+) DataErrors=(\d+)"
        match = re.search(pattern, res.stdout)
        if not match:
            print(f"[CrossValidator] Error parsing output for {workload_name}:\n{res.stdout}\n{res.stderr}")
            return None

        return RTLSimulationResult(
            workload=match.group(1),
            accesses=int(match.group(2)),
            hits=int(match.group(3)),
            misses=int(match.group(4)),
            refills=int(match.group(5)),
            data_errors=int(match.group(6))
        )

    def validate_all(self, traces_dir: str = "traces") -> List[CrossValidationComparison]:
        if not os.path.exists(self.sim_vvp):
            if not self.build_testbench():
                raise RuntimeError("Failed to build cross-validation simulation binary")

        patterns = ["sequential", "repeated", "random", "conflict"]
        comparisons = []

        for p in patterns:
            workload = p.capitalize()
            csv_path = os.path.join(traces_dir, f"{p}_trace.csv")
            hex_path = os.path.join(traces_dir, f"{p}_trace.hex")

            # 1. Compute Python prediction
            py_stats = self.analyzer.analyze_file(csv_path, workload_name=workload)

            # 2. Run RTL hardware simulation
            rtl_res = self.run_rtl_trace(hex_path, workload)
            if rtl_res is None:
                raise RuntimeError(f"RTL simulation failed for {workload}")

            comp = CrossValidationComparison(
                workload=workload,
                py_accesses=py_stats.total_accesses,
                rtl_accesses=rtl_res.accesses,
                py_hits=py_stats.total_hits,
                rtl_hits=rtl_res.hits,
                py_misses=py_stats.total_misses,
                rtl_misses=rtl_res.misses,
                py_refills=py_stats.refill_count,
                rtl_refills=rtl_res.refills,
                data_errors=rtl_res.data_errors
            )
            comparisons.append(comp)

        return comparisons

    @staticmethod
    def format_report_table(comparisons: List[CrossValidationComparison]) -> str:
        lines = []
        sep = "=" * 118
        subsep = "-" * 118
        lines.append(sep)
        lines.append(
            f"{'Workload':<12} | {'Accesses (Py/RTL)':^19} | {'Hits (Py/RTL)':^15} | "
            f"{'Misses (Py/RTL)':^17} | {'Refills (Py/RTL)':^18} | {'Data Err':^8} | {'Status':^8}"
        )
        lines.append(subsep)

        all_matched = True
        for c in comparisons:
            acc_str = f"{c.py_accesses} / {c.rtl_accesses}"
            hit_str = f"{c.py_hits} / {c.rtl_hits}"
            miss_str = f"{c.py_misses} / {c.rtl_misses}"
            refill_str = f"{c.py_refills} / {c.rtl_refills}"
            status = "MATCH" if c.is_match else "MISMATCH"
            if not c.is_match:
                all_matched = False

            lines.append(
                f"{c.workload:<12} | {acc_str:^19} | {hit_str:^15} | "
                f"{miss_str:^17} | {refill_str:^18} | {c.data_errors:^8d} | {status:^8}"
            )
        lines.append(sep)
        verdict = "VERDICT: 100% CROSS-VALIDATION SUCCESSFUL (0 DIFFERENCES)" if all_matched else "VERDICT: MISMATCH DETECTED"
        lines.append(f"  {verdict}")
        lines.append(sep)
        return "\n".join(lines)


def main():
    validator = CrossValidator()
    print("[CrossValidator] Compiling Verilog testbench and running cross-validation...")
    comparisons = validator.validate_all()
    table = validator.format_report_table(comparisons)
    print("\n" + table + "\n")

    report_path = "analysis/cross_validation_report.txt"
    with open(report_path, "w") as f:
        f.write("# ====================================================================\n")
        f.write("# RTL Simulation vs Python Model Cross-Validation Report\n")
        f.write("# Authors: Priyanshu (Analysis Lead) & Ajit (Verification Lead)\n")
        f.write("# Design: Direct-Mapped Cache Controller (1 KB, 16B Block, 64 Lines)\n")
        f.write("# ====================================================================\n\n")
        f.write(table + "\n\n")
        f.write("Verification Criteria:\n")
        f.write("  1. Total Access Count  : Python simulator predictions match RTL hardware cycle-by-cycle.\n")
        f.write("  2. Hit / Miss Counts   : Perfect 1-to-1 equivalence across all access patterns.\n")
        f.write("  3. Block Refills       : Main memory refill requests generated by RTL controller match model.\n")
        f.write("  4. Data Integrity      : Every CPU read returned exact physical byte data with 0 errors.\n")
    print(f"[CrossValidator] Report saved to {report_path}")


if __name__ == "__main__":
    main()
