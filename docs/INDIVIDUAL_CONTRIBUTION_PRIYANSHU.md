# Individual Contribution Documentation & Technical Defense

**Candidate:** Priyanshu  
**Role:** Senior Computer Architecture Performance Analyst & Digital Hardware Synthesis Engineer  
**Project:** Design and Analysis of a Direct-Mapped Cache Controller  
**Academic Milestone:** Phase II Capstone RTL & Architecture Defense  
**Git Branch:** `feature/performance-analysis`  

---

## 1. Technical Ownership & Assigned Deliverables

In accordance with the five-member project charter, my technical ownership encompassed performance evaluation, trace generation, statistical analysis, hardware synthesis evaluation, and cross-validation:

1. **`analysis/trace_generator.py`:**
   - Synthesized reproducible access traces for four fundamental architectural traffic patterns:
     - **Sequential Access:** Consecutive word accesses (spatial locality demonstration).
     - **Repeated Access:** Temporal reuse loops to identical addresses and lines.
     - **Random Access:** Configurable seed-based unpredictable access traffic.
     - **Conflict Access:** Stride-aligned index collisions (`0x000`, `0x400`, `0x800`, `0xC00`) targeting line 0.
   - Dual-format trace generation: human-readable CSV with full tag/index/offset decoding and plain hex for Verilog `$readmemh`.

2. **`analysis/statistics.py`:**
   - Implemented independent cycle-accurate Python direct-mapped cache simulator matching the RTL geometry (1 KB, 16B block, 64 lines).
   - Developed rigorous **Hill & Smith 3C Miss Classification Model** using a fully associative reference cache with LRU replacement to separate conflict misses from capacity misses.
   - Verified that $\text{Hit Ratio} + \text{Miss Ratio} = 1.0$ and $\text{Misses} = \text{Compulsory} + \text{Capacity} + \text{Conflict}$.

3. **`analysis/amat_calculator.py`:**
   - Built independent AMAT calculation engine evaluating both the textbook baseline model ($T_{\text{hit}}=1, P_{\text{miss}}=10$) and the hardware cycle-accurate controller model ($P_{\text{hw}} = 14$ cycles, accounting for controller FSM protocol overhead).

4. **Publication-Quality Visualizations (`analysis/generate_plots.py`):**
   - Generated IEEE-formatted comparison figures in `analysis/plots/`:
     - Hit Ratio Comparison (`hit_ratio_comparison.png`)
     - Miss Ratio Comparison (`miss_ratio_comparison.png`)
     - AMAT Comparison (`amat_comparison.png`)
     - Hits vs Misses 3C Breakdown (`hits_vs_misses.png`)
     - Executive System Dashboard (`cache_performance_dashboard.png`)

5. **Hardware Synthesis Evaluation (`analysis/synthesis_evaluation.py`):**
   - Executed logic synthesis on all modules using **Yosys 0.71+post**.
   - Characterized cell counts, sequential vs combinational breakdowns, and flip-flop register bit budgets.
   - Documented why asynchronous RAM reads synthesize into discrete flip-flops rather than Block RAMs.
   - Documented physical separation between synthesizable cache core (1,044 cells) and simulation-only memory (282 cells).

6. **RTL and Python Cross-Validation (`analysis/cross_validation.py` & `tb/tb_trace_cross_val.sv`):**
   - Automated co-simulation comparing Python model predictions against Verilog simulation (`cache_top.v`).
   - Achieved **100% equivalence** across total accesses, hits, misses, refills, and data correctness with 0 discrepancies.

7. **Architectural Sensitivity Analysis (`analysis/architectural_experiments.py`):**
   - Simulated capacity scaling (256B to 4KB), block size tradeoffs (8B to 64B), and memory latency scaling (2 to 100 cycles).

---

## 2. Key Engineering Insights & Decisions

### Decision 1: Rigorous 3C Miss Classification via Fully Associative Reference Cache
- **Problem:** Many student reports incorrectly label all non-compulsory misses as conflict misses.
- **Solution:** I implemented a companion reference cache with identical capacity (64 blocks) and block size (16 bytes), but with full associativity and LRU replacement.
- **Result:** In the conflict workload (4 competing addresses), all 4 blocks easily fit in the 64-block fully associative cache. Therefore, capacity misses are strictly 0, and the 60 misses in the direct-mapped cache are mathematically proven to be 100% conflict misses due to direct index aliasing.

### Decision 2: Distinction Between Raw Memory Latency and Total Controller Miss Penalty
- **Problem:** Textbook formulas assume miss penalty is just raw DRAM access time ($L_{\text{mem}} = 10$). In actual digital RTL, the cache controller finite state machine consumes protocol cycles.
- **Solution:** I analyzed `rtl/cache_controller.v` and derived the exact 4-cycle controller protocol overhead:
  - `STATE_LOOKUP` (1 cyc): miss detection.
  - `STATE_MEM_REQUEST` (1 cyc): assert memory bus strobe.
  - `STATE_REFILL` (1 cyc): write 128-bit block into RAM.
  - `STATE_RESPOND` (1 cyc): multiplex selected word to CPU.
- **Result:** Provided both $\text{AMAT}_{\text{base}} = 1.0 + (M \times 10)$ and $\text{AMAT}_{\text{hw}} = 1.0 + (M \times 14)$, demonstrating deep hardware timing comprehension.

### Decision 3: Documenting Asynchronous Read Synthesis in Yosys
- **Observation:** Yosys synthesized `cache_data_ram.v` into 8,192 flip-flops ($dffe) instead of Block RAM.
- **Engineering Analysis:** I identified that `assign rdata = mem[raddr]` specifies an asynchronous combinational read port, whereas hardware BRAM primitives in FPGAs and ASIC SRAM compilers require clocked synchronous reads. This documentation provides a direct roadmap for ASIC tapeout optimization.

---

## 3. Interview Defense Q&A Preparation

### Q1: Why does sequential access achieve exactly a 75% hit rate in your baseline cache?
> **Answer:** Our cache uses 16-byte blocks with 32-bit (4-byte) words, meaning each cache block stores exactly 4 consecutive words. With sequential word-aligned access (stride = 4 bytes), accessing Word 0 triggers a compulsory miss and loads the entire 16-byte block into cache line $i$. Accesses to Word 1, Word 2, and Word 3 of the same block hit immediately in cache storage. Thus, for every 4 consecutive accesses, exactly 1 miss and 3 hits occur, yielding a deterministic hit ratio of $3/4 = 75.00\%$.

### Q2: Why does the conflict access pattern produce a 0% hit rate despite accessing only 64 bytes in a 1,024-byte cache?
> **Answer:** The conflict pattern cycles through 4 addresses: `0x00000000`, `0x00000400`, `0x00000800`, and `0x00000C00`. In our 1 KB cache, the index field is bits [9:4] and block offset is bits [3:0]. Because the stride between these addresses is 0x400 (1,024 bytes), bits [9:0] are identical (`00_0000_0000_2`), causing all 4 addresses to map to Index 0. In a direct-mapped cache, each index has only 1 line. Accessing B evicts A; accessing C evicts B; accessing D evicts C; and re-accessing A finds it evicted by D. This results in perpetual ping-pong eviction (thrashing), driving the hit rate to 0%.

### Q3: How do you prove that the conflict misses are not capacity misses?
> **Answer:** By running the access trace through an idealized fully associative cache of identical capacity (64 blocks, 1 KB) using LRU replacement. In the fully associative cache, all 4 unique blocks reside simultaneously in storage (consuming only 4 out of 64 available block slots). After 4 initial compulsory misses, the fully associative cache achieves a 100% hit rate on all subsequent accesses (0 capacity misses). Because the misses occur exclusively in the direct-mapped cache and hit in the fully associative cache, they are rigorously classified as conflict misses under Hill & Smith's 3C taxonomy.

### Q4: How did you verify that your Python performance predictions match the actual RTL implementation?
> **Answer:** I created `tb/tb_trace_cross_val.sv` and `analysis/cross_validation.py`. The Python trace generator exported plain hex address files for each access pattern. The Verilog testbench ingested each trace using `$readmemh`, drove the signals through `cache_top.v`, monitored `hit_out`, `miss_out`, `fsm_state`, and `cache_write_en` (refills), and checked the returned 32-bit data against the expected word. The Python cross-validator collected the hardware telemetry and confirmed a 100% match across total accesses (64/64), hits (48/48, 63/63, 0/0, 0/0), misses, refills, and data correctness with zero errors.

### Q5: What is the hardware resource cost of the synthesizable cache controller IP?
> **Answer:** When synthesized with Yosys, the synthesizable cache core requires 1,044 cells, comprising 195 sequential cell instances (9,827 physical flip-flop bits, including 8,192 data bits, 1,408 tag bits, 64 valid bits, and 163 controller buffer/state bits) and 852 combinational logic gates. Simulation-only behavioral memory (`main_memory.v`) requires 282 cells and must be excluded from physical on-chip silicon area budgets.
