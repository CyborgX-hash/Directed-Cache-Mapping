# Direct-Mapped Cache Controller: Comprehensive Performance Analysis & Architecture Report

**Author:** Priyanshu  
**Role:** Senior Computer Architecture Performance Analyst & Digital Hardware Synthesis Engineer  
**Project:** Design and Analysis of a Direct-Mapped Cache Controller  
**Target Architecture:** 1 KB Capacity, 16-Byte Blocks, 64 Lines, 32-Bit Address/Data  

---

## 1. Executive Summary

This report delivers the complete architectural performance evaluation, trace generation methodology, statistical analysis, and hardware cross-validation for a synthesizable 1 KB direct-mapped cache controller.

### Primary Experimental Findings:
1. **Spatial Locality Exploitation (Sequential Access):**  
   Achieves a **75.00% cache hit ratio** with an Average Memory Access Time (AMAT) of **3.500 cycles** (a **3.14$\times$ speedup** over uncached DRAM). Because block size is 16 bytes (4 words), sequential word strides incur exactly 1 compulsory miss followed by 3 hits per block.
2. **Temporal Locality Exploitation (Repeated Access):**  
   Yields a **98.44% cache hit ratio** and an AMAT of **1.156 cycles** (a **9.51$\times$ speedup**). A single initial compulsory miss loads the target line; all subsequent 63 accesses complete with single-cycle hit latency.
3. **Absence of Locality (Random Access):**  
   Produces a **0.00% hit ratio** and an AMAT of **11.000 cycles** (worst case). Unpredictable addresses distributed across a large working set generate 100% compulsory misses.
4. **Direct-Mapped Pathological Thrashing (Conflict Access):**  
   Produces a **0.00% hit ratio** and an AMAT of **11.000 cycles**. Cycling through 4 addresses mapping to the identical cache index (Index 0) creates 4 initial compulsory misses followed by **60 conflict misses** (93.75% of total accesses), despite a total working set of only 64 bytes (6.25% of cache capacity).
5. **RTL Hardware Cross-Validation:**  
   Verified against the full Verilog implementation (`cache_top.v`) simulated with Icarus Verilog (`iverilog` / `vvp`). Achieved **100.0% mathematical equivalence** across total accesses, hits, misses, memory refills, and returned word data with **zero discrepancies**.

---

## 2. Cache Geometry & Address Mapping

The cache system parameters are specified as follows:
- **Total Capacity ($C$):** 1,024 Bytes (1 KB)
- **Block Size ($B$):** 16 Bytes (128 bits)
- **Number of Cache Lines ($S$):** $S = C / B = 1024 / 16 = 64$ lines
- **Words per Block ($W$):** 4 words (32 bits / 4 bytes per word)
- **Physical Address Width:** 32 bits

### Bit-Field Address Decomposition
The 32-bit physical CPU address decomposes into three disjoint fields matching `rtl/address_decoder.v`:

$$\underbrace{\text{Address[31:10]}}_{\text{Tag: 22 bits}} \quad \big| \quad \underbrace{\text{Address[9:4]}}_{\text{Index: 6 bits}} \quad \big| \quad \underbrace{\text{Address[3:2]}}_{\text{Word Select: 2 bits}} \quad \underbrace{\text{Address[1:0]}}_{\text{Byte Offset: 2 bits}}$$

- **Tag Field (`addr[31:10]`):** 22 bits. Uniquely identifies which memory block resides in the mapped line.
- **Index Field (`addr[9:4]`):** 6 bits ($\log_2(64) = 6$). Directly selects 1 of the 64 cache lines.
- **Block Offset Field (`addr[3:0]`):** 4 bits ($\log_2(16) = 4$).
  - `addr[3:2]`: 2-bit word select multiplexing 1 of 4 words from the 128-bit line into `cpu_resp_data`.
  - `addr[1:0]`: 2-bit byte offset (word-aligned accesses hold `addr[1:0] = 2'b00`).

---

## 3. Workload Access Traces & Locality Analysis

Four standardized benchmark traces (64 accesses each) were synthesized via `analysis/trace_generator.py`:

### A. Sequential Access Pattern (Spatial Locality)
- **Generation:** Stride of +4 bytes starting from `0x00001000`.
- **Architectural Mechanics:**  
  Word 0 (`offset = 0x0`) incurs a cold miss and refills the 16-byte block from main memory. Words 1, 2, and 3 (`offsets = 0x4, 0x8, 0xC`) hit immediately in cache storage without bus activity.
- **Spatial Locality Index:** $3 \text{ hits} / 4 \text{ accesses} = 75.0\%$.

### B. Repeated Access Pattern (Temporal Locality)
- **Generation:** 64 accesses directed to the same block (`0x00002000`) across 16 loop iterations.
- **Architectural Mechanics:**  
  Access 0 cold-misses and installs line 0. Accesses 1 through 63 find valid matching tags, demonstrating maximum temporal reuse.

### C. Random Access Pattern (Unpredictable Working Set)
- **Generation:** Uniform pseudorandom word-aligned addresses seeded reproducibly (`seed = 42`) across address space `0x00000000` to `0x0003FFFF`.
- **Architectural Mechanics:**  
  Each access targets a fresh, un-cached memory block, exercising cold cache performance under zero spatial or temporal correlation.

### D. Conflict Access Pattern (Direct-Mapped Thrashing)
- **Generation:** Modulo-stride accesses cycling through 4 addresses mapping to identical cache index 0:
  - `0x00000000` (Tag `0x000000`, Index `0`)
  - `0x00000400` (Tag `0x000001`, Index `0`)
  - `0x00000800` (Tag `0x000002`, Index `0`)
  - `0x00000C00` (Tag `0x000003`, Index `0`)
- **Architectural Mechanics:**  
  Because direct-mapped cache allows only 1 block per index, access $i$ evicts block $i-1$. In every subsequent loop iteration, re-accessing a previously fetched block misses because a competing tag displaced it.

---

## 4. 3C Miss Classification Reference Model

To prevent the common analytical error of labeling all non-compulsory misses as conflict misses, `analysis/statistics.py` implements the rigorous **Hill & Smith (1989) 3C Reference Model**:

```
                       +---------------------------------------+
                       |             Cache Miss                |
                       +---------------------------------------+
                                           |
                    Does block exist in infinite-capacity cache?
                                     /           \
                                  NO /             \ YES
                                    v               v
                        +------------------+    Does block exist in 64-block
                        | Compulsory Miss  |    Fully-Associative LRU Cache?
                        |   (Cold Miss)    |             /           \
                        +------------------+          NO /             \ YES
                                                        v               v
                                            +------------------+  +------------------+
                                            |  Capacity Miss   |  |  Conflict Miss   |
                                            | (Working Set > C)|  | (Mapping Clash)  |
                                            +------------------+  +------------------+
```

### Definitions:
1. **Compulsory Miss:** First reference to a physical memory block in the program execution. Unavoidable regardless of cache size or associativity.
2. **Capacity Miss:** Occurs when the program working set exceeds cache capacity ($C = 1 \text{ KB}$ / 64 blocks). Occurs even in an idealized fully associative cache with LRU replacement.
3. **Conflict Miss:** Miss that occurs in the direct-mapped cache, but would have **HIT** in a fully associative cache of identical capacity (64 blocks) with LRU replacement. Caused strictly by mapping collisions in set index 0.

---

## 5. AMAT Mathematical Formulations & Latency Conventions

The Average Memory Access Time (AMAT) is computed using two explicitly defined engineering conventions:

$$\text{AMAT} = T_{\text{hit}} + (M \times P_{\text{miss}})$$

where $T_{\text{hit}}$ is hit time, $M$ is miss rate ($0.0 \le M \le 1.0$), and $P_{\text{miss}}$ is miss penalty.

### Convention 1: Textbook Baseline Model
- **Hit Time ($T_{\text{hit}}$):** 1.0 clock cycle.
- **Raw Main Memory Latency ($L_{\text{mem}}$):** 10.0 clock cycles.
- **Miss Penalty ($P_{\text{miss}}$):** 10.0 clock cycles (assumes idealized memory refill).
- **Formula:** $\text{AMAT}_{\text{base}} = 1.0 + (M \times 10.0)$.

### Convention 2: Hardware RTL Cycle-Accurate Model
Derived directly from the finite state machine transitions in `rtl/cache_controller.v`:
- **Hit Handshake:** `STATE_IDLE` $\to$ `STATE_LOOKUP` $\to$ `STATE_RESPOND` ($T_{\text{hit}} = 1$ cycle lookup).
- **Miss Handshake Overhead ($O_{\text{ctrl}} = 4$ cycles):**
  1. `STATE_LOOKUP` (miss detected: 1 cycle)
  2. `STATE_MEM_REQUEST` (assert `mem_req_val` pulse: 1 cycle)
  3. `STATE_MEM_WAIT` (await `mem_req_ready`: $L_{\text{mem}} = 10$ cycles)
  4. `STATE_REFILL` (write 128-bit block into RAM: 1 cycle)
  5. `STATE_RESPOND` (multiplex word and assert `cpu_resp_val`: 1 cycle)
- **Total Hardware Miss Penalty:** $P_{\text{hw}} = L_{\text{mem}} + O_{\text{ctrl}} = 10 + 4 = 14$ cycles.
- **Formula:** $\text{AMAT}_{\text{hw}} = 1.0 + (M \times 14.0)$.

---

## 6. Hardware Performance Comparison Table

| Workload | Accesses | Hits | Misses | Hit Ratio | Miss Ratio | Compulsory | Capacity | Conflict | Refills | AMAT (Base) | AMAT (RTL-HW) | Speedup vs Uncached |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Sequential** | 64 | 48 | 16 | **75.00%** | 25.00% | 16 | 0 | 0 | 16 | **3.500 cyc** | **4.500 cyc** | **3.14$\times$** |
| **Repeated** | 64 | 63 | 1 | **98.44%** | 1.56% | 1 | 0 | 0 | 1 | **1.156 cyc** | **1.219 cyc** | **9.51$\times$** |
| **Random** | 64 | 0 | 64 | **0.00%** | 100.00% | 64 | 0 | 0 | 64 | **11.000 cyc** | **15.000 cyc** | **1.00$\times$** |
| **Conflict** | 64 | 0 | 64 | **0.00%** | 100.00% | 4 | 0 | 60 | 64 | **11.000 cyc** | **15.000 cyc** | **1.00$\times$** |

### Mathematical Validation:
- $\text{Hit Ratio} + \text{Miss Ratio} = 1.000000$ (Validated for all workloads).
- $\text{Total Misses} = \text{Compulsory} + \text{Capacity} + \text{Conflict}$ (Validated for all workloads).

---

## 7. Performance Visualizations

All graphs were rendered via matplotlib (`analysis/generate_plots.py`) at 300 DPI publication resolution:

1. **Hit Ratio Comparison:** `analysis/plots/hit_ratio_comparison.png`
2. **Miss Ratio Comparison:** `analysis/plots/miss_ratio_comparison.png`
3. **AMAT Comparison (Base vs HW):** `analysis/plots/amat_comparison.png`
4. **Hits vs Misses Decomposition:** `analysis/plots/hits_vs_misses.png`
5. **Executive Dashboard (4-in-1):** `analysis/plots/cache_performance_dashboard.png`
6. **Architectural Sensitivity Analysis:** `analysis/plots/architectural_experiments.png`

---

## 8. RTL and Python Cross-Validation Results

The Python simulation predictions were cross-validated against cycle-accurate Icarus Verilog simulations executing `tb/tb_trace_cross_val.sv` on the synthesizable top-level `rtl/cache_top.v`:

| Workload | Accesses (Py / RTL) | Hits (Py / RTL) | Misses (Py / RTL) | Refills (Py / RTL) | Returned Data Errors | Verification Verdict |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **Sequential** | 64 / 64 | 48 / 48 | 16 / 16 | 16 / 16 | 0 | **PASS (100% Match)** |
| **Repeated** | 64 / 64 | 63 / 63 | 1 / 1 | 1 / 1 | 0 | **PASS (100% Match)** |
| **Random** | 64 / 64 | 0 / 0 | 64 / 64 | 64 / 64 | 0 | **PASS (100% Match)** |
| **Conflict** | 64 / 64 | 0 / 0 | 64 / 64 | 64 / 64 | 0 | **PASS (100% Match)** |

**Cross-Validation Conclusion:**  
100% agreement observed across all 5 verification dimensions with **zero simulation discrepancies**.

---

## 9. Architectural Sensitivity Exploration

Executed via `analysis/architectural_experiments.py`:

### A. Cache Capacity Scaling (Fixed Block Size = 16B)
| Cache Capacity | Lines | Tag Bits | Index Bits | Sequential Hit% | Conflict Hit% | Architectural Significance |
| :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **256 B** | 16 | 24 | 4 | 75.00% | 0.00% | Severe thrashing on Index 0 |
| **512 B** | 32 | 23 | 5 | 75.00% | 0.00% | Severe thrashing on Index 0 |
| **1 KB (Baseline)**| **64** | **22** | **6** | **75.00%** | **0.00%** | **Mandatory primary configuration** |
| **2 KB** | 128 | 21 | 7 | 75.00% | 0.00% | Stride 0x400 still aliases to Index 0 |
| **4 KB** | 256 | 20 | 8 | 75.00% | **96.88%** | **Index width expands to 8 bits; all 4 blocks map to distinct lines!** |

### B. Block Size Tradeoff (Fixed Capacity = 1 KB)
- **8 Bytes (2 words):** Sequential Hit Rate = 50.00%, AMAT = 7.000 cycles.
- **16 Bytes (4 words - Baseline):** Sequential Hit Rate = 75.00%, AMAT = 4.500 cycles.
- **32 Bytes (8 words):** Sequential Hit Rate = 87.50%, AMAT = 3.250 cycles.
- **64 Bytes (16 words):** Sequential Hit Rate = 93.75%, AMAT = 2.625 cycles.  
*(Tradeoff: Larger blocks increase transfer latency and pollution under non-sequential workloads).*

### C. Main Memory Latency Sensitivity
- For **Repeated Workloads** (98.44% hit rate), AMAT degrades by only **1.53 cycles** as DRAM latency scales from 2 to 100 cycles.
- For **Conflict / Random Workloads** (0% hit rate), AMAT scales linearly from **3.0 to 101.0 cycles**, underscoring the critical importance of conflict mitigation techniques (such as 2-way / 4-way set associativity or victim caches).
