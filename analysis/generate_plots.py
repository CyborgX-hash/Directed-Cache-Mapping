#!/usr/bin/env python3
"""
generate_plots.py - Publication-Quality Matplotlib Visualizer

Author: Priyanshu (Performance Analyst & Synthesis Lead)
Project: Design and Analysis of a Direct-Mapped Cache Controller

Generates IEEE-style figures:
  1. Hit Ratio Comparison        -> analysis/plots/hit_ratio_comparison.png
  2. Miss Ratio Comparison       -> analysis/plots/miss_ratio_comparison.png
  3. AMAT Comparison (Base vs HW)-> analysis/plots/amat_comparison.png
  4. Hits versus Misses Breakdown-> analysis/plots/hits_vs_misses.png
  5. Full System Dashboard       -> analysis/plots/cache_performance_dashboard.png
"""

import os
import sys

# Ensure repository root is on sys.path
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)

os.environ["MPLCONFIGDIR"] = "/tmp/matplotlib_cache"

# Ensure .venv or system matplotlib is accessible
import matplotlib
matplotlib.use("Agg")  # Non-interactive backend
import matplotlib.pyplot as plt
import numpy as np

from analysis.statistics import StatisticsAnalyzer, CacheStatistics
from analysis.amat_calculator import AMATCalculator, AMATResult


def set_plot_style():
    """Configure clean academic / IEEE publication styling."""
    plt.rcParams.update({
        "font.family": "sans-serif",
        "font.sans-serif": ["DejaVu Sans", "Helvetica", "Arial"],
        "axes.edgecolor": "#333333",
        "axes.linewidth": 1.2,
        "axes.grid": True,
        "grid.color": "#e0e0e0",
        "grid.linestyle": "--",
        "grid.alpha": 0.7,
        "figure.autolayout": True,
        "figure.titlesize": 14,
        "axes.titlesize": 13,
        "axes.labelsize": 11,
        "xtick.labelsize": 10,
        "ytick.labelsize": 10,
        "legend.fontsize": 10,
    })


def generate_all_plots(traces_dir: str = "traces", output_dir: str = "analysis/plots"):
    os.makedirs(output_dir, exist_ok=True)
    set_plot_style()

    analyzer = StatisticsAnalyzer()
    calculator = AMATCalculator(hit_time=1.0, raw_mem_latency=10.0, ctrl_overhead=4.0)

    patterns = ["Sequential", "Repeated", "Random", "Conflict"]
    stats_list = []

    for p in patterns:
        csv_file = os.path.join(traces_dir, f"{p.lower()}_trace.csv")
        stats = analyzer.analyze_file(csv_file, workload_name=p)
        stats_list.append(stats)

    amat_results = calculator.evaluate_all(stats_list)

    workloads = [s.workload for s in stats_list]
    hit_rates = [s.hit_ratio * 100 for s in stats_list]
    miss_rates = [s.miss_ratio * 100 for s in stats_list]
    hits = [s.total_hits for s in stats_list]
    misses = [s.total_misses for s in stats_list]
    compulsory = [s.compulsory_misses for s in stats_list]
    conflict = [s.conflict_misses for s in stats_list]
    amat_base = [r.amat_baseline for r in amat_results]
    amat_hw = [r.amat_hardware for r in amat_results]

    colors = {
        "Sequential": "#1f77b4",  # Blue
        "Repeated":   "#2ca02c",  # Green
        "Random":     "#ff7f0e",  # Orange
        "Conflict":   "#d62728"   # Red
    }
    palette = [colors[w] for w in workloads]

    # =========================================================================
    # 1. Hit Ratio Comparison
    # =========================================================================
    fig, ax = plt.subplots(figsize=(7, 4.5), dpi=300)
    bars = ax.bar(workloads, hit_rates, color=palette, width=0.55, edgecolor="#222222", linewidth=1.2)
    ax.set_ylabel("Hit Ratio (%)")
    ax.set_title("Direct-Mapped Cache: Hit Ratio Across Access Patterns (1 KB, 16B Block)")
    ax.set_ylim(0, 115)
    for bar in bars:
        h = bar.get_height()
        ax.text(bar.get_x() + bar.get_width()/2.0, h + 2.0, f"{h:.2f}%",
                ha="center", va="bottom", fontweight="bold", fontsize=10)
    ax.axhline(50, color="#888888", linestyle=":", linewidth=1, label="50% Threshold")
    ax.legend(loc="upper right")
    fig_path = os.path.join(output_dir, "hit_ratio_comparison.png")
    fig.savefig(fig_path, bbox_inches="tight")
    plt.close(fig)
    print(f"[PlotGenerator] Saved: {fig_path}")

    # =========================================================================
    # 2. Miss Ratio Comparison
    # =========================================================================
    fig, ax = plt.subplots(figsize=(7, 4.5), dpi=300)
    bars = ax.bar(workloads, miss_rates, color=palette, width=0.55, edgecolor="#222222", linewidth=1.2)
    ax.set_ylabel("Miss Ratio (%)")
    ax.set_title("Direct-Mapped Cache: Miss Ratio Across Access Patterns")
    ax.set_ylim(0, 115)
    for bar in bars:
        h = bar.get_height()
        ax.text(bar.get_x() + bar.get_width()/2.0, h + 2.0, f"{h:.2f}%",
                ha="center", va="bottom", fontweight="bold", fontsize=10)
    fig_path = os.path.join(output_dir, "miss_ratio_comparison.png")
    fig.savefig(fig_path, bbox_inches="tight")
    plt.close(fig)
    print(f"[PlotGenerator] Saved: {fig_path}")

    # =========================================================================
    # 3. AMAT Comparison (Baseline vs Hardware Cycle-Accurate)
    # =========================================================================
    fig, ax = plt.subplots(figsize=(7.5, 4.5), dpi=300)
    x = np.arange(len(workloads))
    width = 0.35

    bars1 = ax.bar(x - width/2, amat_base, width, label="Textbook AMAT (Mem Latency=10 cyc)",
                   color="#3470a3", edgecolor="#222222", linewidth=1.0)
    bars2 = ax.bar(x + width/2, amat_hw, width, label="Hardware AMAT (Latency=10 + 4 cyc)",
                   color="#d95f02", edgecolor="#222222", linewidth=1.0)

    ax.set_ylabel("Average Memory Access Time (Cycles)")
    ax.set_title("AMAT Comparison: Baseline Model vs RTL Controller Model")
    ax.set_xticks(x)
    ax.set_xticklabels(workloads)
    ax.set_ylim(0, 18)
    ax.legend(loc="upper left")

    for bar in bars1:
        h = bar.get_height()
        ax.text(bar.get_x() + bar.get_width()/2.0, h + 0.3, f"{h:.2f}",
                ha="center", va="bottom", fontsize=8.5)
    for bar in bars2:
        h = bar.get_height()
        ax.text(bar.get_x() + bar.get_width()/2.0, h + 0.3, f"{h:.2f}",
                ha="center", va="bottom", fontsize=8.5, fontweight="bold")

    fig_path = os.path.join(output_dir, "amat_comparison.png")
    fig.savefig(fig_path, bbox_inches="tight")
    plt.close(fig)
    print(f"[PlotGenerator] Saved: {fig_path}")

    # =========================================================================
    # 4. Hits vs Misses Breakdown (Stacked Bar with 3C classification)
    # =========================================================================
    fig, ax = plt.subplots(figsize=(8, 4.8), dpi=300)
    bars_hits = ax.bar(workloads, hits, label="Cache Hits", color="#2ca02c",
                       width=0.55, edgecolor="#222222", linewidth=1.0)
    bars_comp = ax.bar(workloads, compulsory, bottom=hits, label="Compulsory Misses",
                       color="#1f77b4", width=0.55, edgecolor="#222222", linewidth=1.0)
    bars_conf = ax.bar(workloads, conflict, bottom=np.array(hits) + np.array(compulsory),
                       label="Conflict Misses", color="#d62728", width=0.55,
                       edgecolor="#222222", linewidth=1.0)

    ax.set_ylabel("Access Count (Total = 64)")
    ax.set_title("Cache Hits vs Misses with 3C Miss Classification Breakdown")
    ax.set_ylim(0, 75)
    ax.legend(loc="upper right")

    for i, w in enumerate(workloads):
        ax.text(i, 66, f"Hits: {hits[i]}\nMiss: {misses[i]}",
                ha="center", va="bottom", fontsize=9, fontweight="bold")

    fig_path = os.path.join(output_dir, "hits_vs_misses.png")
    fig.savefig(fig_path, bbox_inches="tight")
    plt.close(fig)
    print(f"[PlotGenerator] Saved: {fig_path}")

    # =========================================================================
    # 5. Combined Executive Dashboard (2x2 Grid)
    # =========================================================================
    fig, axs = plt.subplots(2, 2, figsize=(13, 9), dpi=300)

    # Subplot (0, 0): Hit Rate
    axs[0, 0].bar(workloads, hit_rates, color=palette, width=0.55, edgecolor="#222222")
    axs[0, 0].set_title("(a) Cache Hit Ratio (%)", fontweight="bold")
    axs[0, 0].set_ylabel("Hit Ratio (%)")
    axs[0, 0].set_ylim(0, 115)
    for i, v in enumerate(hit_rates):
        axs[0, 0].text(i, v + 2, f"{v:.1f}%", ha="center", fontweight="bold")

    # Subplot (0, 1): Miss Rate
    axs[0, 1].bar(workloads, miss_rates, color=palette, width=0.55, edgecolor="#222222")
    axs[0, 1].set_title("(b) Cache Miss Ratio (%)", fontweight="bold")
    axs[0, 1].set_ylabel("Miss Ratio (%)")
    axs[0, 1].set_ylim(0, 115)
    for i, v in enumerate(miss_rates):
        axs[0, 1].text(i, v + 2, f"{v:.1f}%", ha="center", fontweight="bold")

    # Subplot (1, 0): AMAT
    x = np.arange(len(workloads))
    w = 0.35
    axs[1, 0].bar(x - w/2, amat_base, w, label="Baseline (T_hit=1, P_miss=10)", color="#3470a3", edgecolor="#222")
    axs[1, 0].bar(x + w/2, amat_hw, w, label="Hardware (T_hit=1, P_hw=14)", color="#d95f02", edgecolor="#222")
    axs[1, 0].set_title("(c) Average Memory Access Time (Cycles)", fontweight="bold")
    axs[1, 0].set_ylabel("AMAT (Cycles)")
    axs[1, 0].set_xticks(x)
    axs[1, 0].set_xticklabels(workloads)
    axs[1, 0].set_ylim(0, 18)
    axs[1, 0].legend(fontsize=8.5)
    for i in range(len(workloads)):
        axs[1, 0].text(i - w/2, amat_base[i] + 0.3, f"{amat_base[i]:.2f}", ha="center", fontsize=8)
        axs[1, 0].text(i + w/2, amat_hw[i] + 0.3, f"{amat_hw[i]:.2f}", ha="center", fontsize=8, fontweight="bold")

    # Subplot (1, 1): Hits vs Misses Stacked
    axs[1, 1].bar(workloads, hits, label="Hits", color="#2ca02c", width=0.55, edgecolor="#222")
    axs[1, 1].bar(workloads, compulsory, bottom=hits, label="Compulsory Misses", color="#1f77b4", width=0.55, edgecolor="#222")
    axs[1, 1].bar(workloads, conflict, bottom=np.array(hits) + np.array(compulsory),
                  label="Conflict Misses", color="#d62728", width=0.55, edgecolor="#222")
    axs[1, 1].set_title("(d) Access Outcome Decomposition", fontweight="bold")
    axs[1, 1].set_ylabel("Access Count")
    axs[1, 1].set_ylim(0, 75)
    axs[1, 1].legend(fontsize=8.5)

    fig.suptitle("Direct-Mapped Cache Controller: Architecture Performance Dashboard", fontsize=15, fontweight="bold")
    dashboard_path = os.path.join(output_dir, "cache_performance_dashboard.png")
    fig.savefig(dashboard_path, bbox_inches="tight")
    plt.close(fig)
    print(f"[PlotGenerator] Saved: {dashboard_path}")


if __name__ == "__main__":
    generate_all_plots()
