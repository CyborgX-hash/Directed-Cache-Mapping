#!/usr/bin/env python3
"""
architectural_experiments.py - Cache Parameter Sensitivity & Architectural Exploration

Author: Priyanshu (Performance Analyst & Synthesis Lead)
Project: Design and Analysis of a Direct-Mapped Cache Controller

Explores 3 architectural design dimensions:
  1. Cache Capacity Variation (256B, 512B, 1KB [baseline], 2KB, 4KB)
  2. Block Size Tradeoffs     (8B, 16B [baseline], 32B, 64B)
  3. Main Memory Latency      (2, 5, 10 [baseline], 20, 50, 100 cycles)

Generates:
  - Multi-panel sensitivity charts: analysis/plots/architectural_experiments.png
  - Tabular summary report: analysis/architectural_experiments_report.txt
"""

import os
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)

os.environ["MPLCONFIGDIR"] = "/tmp/matplotlib_cache"
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

from analysis.statistics import (
    DirectMappedCache, InfiniteCacheReference, FullyAssociativeLRUReference,
    StatisticsAnalyzer, CacheSimulator, CacheStatistics
)
from analysis.amat_calculator import AMATCalculator
from analysis.trace_generator import TraceGenerator


def run_experiment_suite(output_dir: str = "analysis"):
    os.makedirs(output_dir, exist_ok=True)
    plots_dir = os.path.join(output_dir, "plots")
    os.makedirs(plots_dir, exist_ok=True)

    gen = TraceGenerator()
    seq_traces = [r.addr for r in gen.generate_sequential(count=128, start_addr=0x1000, stride=4)]
    rep_traces = [r.addr for r in gen.generate_repeated(repeat_count=32)]
    rnd_traces = [r.addr for r in gen.generate_random(count=128, seed=42)]
    cnf_traces = [r.addr for r in gen.generate_conflict(target_index=0, num_competing_tags=4, loops=32)]

    # =========================================================================
    # Experiment 1: Cache Capacity Variation (Fixed Block Size = 16B)
    # =========================================================================
    capacities = [256, 512, 1024, 2048, 4096]  # Bytes
    cap_labels = ["256B (16L)", "512B (32L)", "1KB (64L)*", "2KB (128L)", "4KB (256L)"]
    cap_seq_hit = []
    cap_cnf_hit = []

    for c in capacities:
        lines = c // 16
        sim = CacheSimulator(num_lines=lines, block_size=16)
        ana = StatisticsAnalyzer(sim)

        st_seq = ana.analyze_trace(seq_traces, f"Seq_{c}")
        st_cnf = ana.analyze_trace(cnf_traces, f"Cnf_{c}")

        cap_seq_hit.append(st_seq.hit_ratio * 100)
        cap_cnf_hit.append(st_cnf.hit_ratio * 100)

    # =========================================================================
    # Experiment 2: Block Size Variation (Fixed Capacity = 1 KB)
    # =========================================================================
    block_sizes = [8, 16, 32, 64]  # Bytes
    blk_labels = ["8B (2W)", "16B (4W)*", "32B (8W)", "64B (16W)"]
    blk_seq_hit = []
    blk_amat_base = []

    for b in block_sizes:
        lines = 1024 // b
        # Custom simulation for variable block size
        # With stride=4 in sequential access:
        words_per_block = b // 4
        # Expected compulsory miss 1 per block, hits = (words_per_block - 1)
        expected_hit_rate = ((words_per_block - 1) / words_per_block) * 100
        blk_seq_hit.append(expected_hit_rate)

        # Refill penalty scales with block size: 10 + (b // 4) cycles
        miss_pen = 10.0 + (b // 4)
        amat = 1.0 + ((1.0 - expected_hit_rate/100.0) * miss_pen)
        blk_amat_base.append(amat)

    # =========================================================================
    # Experiment 3: Memory Latency Scaling (Fixed 1KB, 16B Block)
    # =========================================================================
    latencies = [2, 5, 10, 20, 50, 100]  # Clock cycles
    calc = AMATCalculator(hit_time=1.0)

    # Baseline 1KB hit rates: Sequential (75%), Repeated (98.44%), Conflict (0%)
    amat_seq_lat = [calc.compute_amat(0.25, hit_time=1.0, miss_penalty=L) for L in latencies]
    amat_rep_lat = [calc.compute_amat(0.015625, hit_time=1.0, miss_penalty=L) for L in latencies]
    amat_cnf_lat = [calc.compute_amat(1.0, hit_time=1.0, miss_penalty=L) for L in latencies]

    # =========================================================================
    # Multi-Panel Matplotlib Figure
    # =========================================================================
    fig, axs = plt.subplots(1, 3, figsize=(16, 4.8), dpi=300)

    # Panel 1: Capacity Scaling
    axs[0].plot(cap_labels, cap_seq_hit, marker="o", linewidth=2.2, color="#1f77b4", label="Sequential (Spatial)")
    axs[0].plot(cap_labels, cap_cnf_hit, marker="s", linewidth=2.2, color="#d62728", label="Conflict (Index Contention)")
    axs[0].set_title("(a) Hit Rate vs Cache Capacity", fontweight="bold")
    axs[0].set_ylabel("Hit Ratio (%)")
    axs[0].set_ylim(-5, 105)
    axs[0].grid(True, linestyle="--", alpha=0.6)
    axs[0].legend(loc="center right")
    for i, v in enumerate(cap_seq_hit):
        axs[0].text(i, v + 3, f"{v:.1f}%", ha="center", fontsize=8.5, fontweight="bold")

    # Panel 2: Block Size Sensitivity
    ax2 = axs[1]
    ax2_twin = ax2.twinx()
    b1 = ax2.bar([x - 0.18 for x in range(len(blk_labels))], blk_seq_hit, width=0.35, color="#2ca02c",
                 edgecolor="#222", label="Hit Rate (%)")
    b2 = ax2_twin.bar([x + 0.18 for x in range(len(blk_labels))], blk_amat_base, width=0.35, color="#ff7f0e",
                      edgecolor="#222", label="AMAT (Cycles)")
    ax2.set_title("(b) Sequential Hit Rate & AMAT vs Block Size", fontweight="bold")
    ax2.set_xticks(range(len(blk_labels)))
    ax2.set_xticklabels(blk_labels)
    ax2.set_ylabel("Hit Ratio (%)", color="#2ca02c")
    ax2_twin.set_ylabel("AMAT (Cycles)", color="#ff7f0e")
    ax2.set_ylim(0, 115)
    ax2_twin.set_ylim(0, 8)
    ax2.grid(True, linestyle="--", alpha=0.6)

    # Panel 3: Memory Latency Sensitivity
    axs[2].plot(latencies, amat_cnf_lat, marker="^", linewidth=2.2, color="#d62728", label="Conflict/Random (Miss Rate 100%)")
    axs[2].plot(latencies, amat_seq_lat, marker="o", linewidth=2.2, color="#1f77b4", label="Sequential (Miss Rate 25%)")
    axs[2].plot(latencies, amat_rep_lat, marker="s", linewidth=2.2, color="#2ca02c", label="Repeated (Miss Rate 1.56%)")
    axs[2].set_title("(c) AMAT Sensitivity to Main Memory Latency", fontweight="bold")
    axs[2].set_xlabel("Raw Main Memory Latency (Cycles)")
    axs[2].set_ylabel("AMAT (Cycles)")
    axs[2].set_ylim(0, 105)
    axs[2].grid(True, linestyle="--", alpha=0.6)
    axs[2].legend(loc="upper left")

    fig.suptitle("Direct-Mapped Cache Controller: Architectural Sensitivity & Exploration", fontsize=14, fontweight="bold")
    fig.tight_layout()
    plot_path = os.path.join(plots_dir, "architectural_experiments.png")
    fig.savefig(plot_path, bbox_inches="tight")
    plt.close(fig)
    print(f"[ArchitecturalExperiments] Saved plot: {plot_path}")

    # =========================================================================
    # Report File
    # =========================================================================
    report_path = os.path.join(output_dir, "architectural_experiments_report.txt")
    with open(report_path, "w") as f:
        f.write("# =====================================================================\n")
        f.write("# Direct-Mapped Cache Controller: Architectural Sensitivity Report\n")
        f.write("# Author: Priyanshu (Performance Analyst & Synthesis Lead)\n")
        f.write("# =====================================================================\n\n")

        f.write("1. Cache Capacity Sensitivity (Block Size = 16B):\n")
        f.write("   Capacity  | Lines | Tag Bits | Index Bits | Sequential Hit% | Conflict Hit%\n")
        f.write("   -------------------------------------------------------------------------\n")
        for i, c in enumerate(capacities):
            l = c // 16
            idx_bits = int(np.log2(l))
            tag_bits = 32 - idx_bits - 4
            primary = " (PRIMARY BASELINE)" if c == 1024 else ""
            f.write(f"   {c:4d} B   | {l:5d} | {tag_bits:8d} | {idx_bits:10d} | {cap_seq_hit[i]:14.2f}% | {cap_cnf_hit[i]:12.2f}%{primary}\n")

        f.write("\n2. Block Size Tradeoff (Capacity = 1 KB):\n")
        f.write("   Block Size | Words/Blk | Num Lines | Sequential Hit% | Est. AMAT (Base)\n")
        f.write("   -----------------------------------------------------------------------\n")
        for i, b in enumerate(block_sizes):
            w = b // 4
            l = 1024 // b
            primary = " (PRIMARY BASELINE)" if b == 16 else ""
            f.write(f"   {b:2d} Bytes   | {w:9d} | {l:9d} | {blk_seq_hit[i]:14.2f}% | {blk_amat_base[i]:10.3f} cyc{primary}\n")

        f.write("\n3. Memory Latency Scaling (Baseline 1 KB, 16B Block):\n")
        f.write("   Memory Latency | AMAT Repeated (Hit 98.4%) | AMAT Sequential (Hit 75%) | AMAT Conflict (Hit 0%)\n")
        f.write("   ----------------------------------------------------------------------------------------------\n")
        for i, lat in enumerate(latencies):
            primary = " (PRIMARY BASELINE)" if lat == 10 else ""
            f.write(f"   {lat:3d} cycles     | {amat_rep_lat[i]:18.3f} cyc | {amat_seq_lat[i]:19.3f} cyc | {amat_cnf_lat[i]:16.3f} cyc{primary}\n")

    print(f"[ArchitecturalExperiments] Saved report: {report_path}")


if __name__ == "__main__":
    run_experiment_suite()
