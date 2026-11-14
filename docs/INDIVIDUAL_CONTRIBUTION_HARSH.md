# Individual Contribution Documentation & Technical Defense

**Candidate:** Harsh Kumar  
**Role:** Memory Subsystem & Refill Interface Lead  
**Project:** Design and Analysis of a Direct-Mapped Cache Controller  
**Academic Milestone:** Phase II Capstone RTL Defense  
**Branch:** [`feature/main-memory-interface`](https://github.com/)

---

## 1. Technical Ownership & Assigned Deliverables

In accordance with the project charter and team division of responsibilities, my exclusive technical deliverables and ownership areas were:

1. **`rtl/main_memory.v`:**
   - Architecture and RTL implementation of the behavioral/synthesizable main memory subsystem.
   - Implementation of the 3-state Moore FSM (`MEM_IDLE`, `MEM_ACCESS`, `MEM_RESPONSE`).
   - Parameterized clock cycle latency modeling without simulation-only artificial delays (`#delays`).
   - Block address latching and busy-state isolation to prevent accidental duplicate acceptance.
   - 128-bit block generation assembling four distinct 32-bit words per block.

2. **`rtl/memory_interface.v`:**
   - Architecture and design of the hardware bus bridge between the cache controller and main memory.
   - Enforcement of strict 16-byte block alignment (`mem_req_addr = {ctrl_mem_req_addr[31:4], 4'b0000}`).
   - Handshake forwarding and isolation (`ctrl_mem_req_val` -> `mem_req_val`, `mem_req_ready` -> `ctrl_mem_req_ready`).
   - Full 128-bit block return routing.

3. **Memory Initialization & Data Integrity:**
   - Deterministic address-based mathematical data generation ensuring predictable verification across the entire 4 GB address space.
   - Modeled memory array backing for 256 cache lines (4 KB) with `initial` block population.
   - Verification of deterministic consistency (repeated reads always return identical data).

4. **Subsystem Verification & Waveform Generation:**
   - Authored the standalone verification testbench [`tb/memory_subsystem_tb.v`](file:///Users/harshkumar/air_qunality_14november/Directed-Cache-Mapping/tb/memory_subsystem_tb.v).
   - Validated 11 comprehensive test scenarios achieving 100% test pass rate.
   - Generated simulation waveform artifacts ([`sim/memory_subsystem_tb.vcd`](file:///Users/harshkumar/air_qunality_14november/Directed-Cache-Mapping/sim/memory_subsystem_tb.vcd)).
   - Validated seamless integration with Saksham's top-level system ([`tb/cache_top_tb.v`](file:///Users/harshkumar/air_qunality_14november/Directed-Cache-Mapping/tb/cache_top_tb.v)) with zero regressions (12/12 passed).

5. **Documentation & Git Governance:**
   - Authored [`docs/MEMORY_SUBSYSTEM_ARCHITECTURE.md`](file:///Users/harshkumar/air_qunality_14november/Directed-Cache-Mapping/docs/MEMORY_SUBSYSTEM_ARCHITECTURE.md) and [`docs/MEMORY_VERIFICATION_REPORT.md`](file:///Users/harshkumar/air_qunality_14november/Directed-Cache-Mapping/docs/MEMORY_VERIFICATION_REPORT.md).
   - Maintained clean, progressive git history with 8 atomic commits on branch `feature/main-memory-interface`.

---

## 2. Key Architectural Decisions & Engineering Rationale

### Decision 1: 3-State Moore FSM vs Ad-Hoc Flag Counter
- **Rationale:** Rather than relying on unstructured boolean flags (e.g., `serving`), I implemented a formal 3-state Moore FSM (`MEM_IDLE`, `MEM_ACCESS`, `MEM_RESPONSE`).
- **Hardware Benefits:**
  1. *Deterministic Timing:* Output `mem_req_ready = (state_q == MEM_RESPONSE)` is a single-cycle glitch-free pulse strictly coupled to state registers.
  2. *Observability:* FSM state output port `fsm_state[1:0]` enables cycle-accurate waveform inspection during RTL simulation and post-synthesis debugging.
  3. *Synthesis Efficiency:* A 2-bit state register synthesizes into minimal logic gates while guaranteeing mutual exclusivity between idle, waiting, and responding states.

### Decision 2: 16-Byte Block Alignment Enforcement in `memory_interface.v`
- **Rationale:** Cache refills must always transfer full cache lines aligned to 16-byte boundaries. If the CPU requests an unaligned byte address (e.g., `0x0000_1047`), the cache controller passes this request down.
- **Hardware Implementation:** `memory_interface.v` forces `mem_req_addr = {ctrl_mem_req_addr[31:4], 4'b0000}`. Zeroing the lower 4 offset bits guarantees that main memory always operates strictly on block base addresses, preventing misaligned word corruption during refills.

### Decision 3: Deterministic Address-Based Data Generation with Memory Array Backing
- **Rationale:** Random or uninitialized memory in simulation leads to non-deterministic tests and difficult debugging.
- **Hardware Architecture:** I implemented a hybrid scheme:
  1. *Physical Address Mapping:* Each 32-bit word in a block reflects its exact byte address (`block_base + 0`, `block_base + 4`, `block_base + 8`, `block_base + 12`). This allows any testbench to compute the expected data analytically.
  2. *Array Backing:* 256 cache blocks (4 KB) are backed by an internal initialized array `mem_array[0:255]`. Addresses within this window read directly from storage; addresses beyond this window use the mathematical formula, providing infinite address coverage without exploding memory consumption during simulation.

### Decision 4: Busy State Isolation (Filtering Spurious Requests)
- **Rationale:** In high-speed pipelined designs or multi-master buses, spurious valid pulses can occur while a memory transaction is in flight.
- **Hardware Mechanism:** In `MEM_ACCESS`, `mem_req_val` is completely ignored. `latched_addr_q` is frozen upon leaving `MEM_IDLE`. Only after `MEM_RESPONSE` completes and the FSM returns to `MEM_IDLE` can a new transaction be latched. This guarantees race-free operation.

### Decision 5: Non-Intrusive Integration with Peer Subsystems
- **Rationale:** Saksham owns `cache_controller.v` and `cache_top.v`; Mihika owns `cache_storage.v`.
- **Adherence:** My modules (`main_memory.v` and `memory_interface.v`) strictly matched the existing port signatures in `cache_top.v` without requiring a single modification to peer code. Top-level tests passed 12/12 on the very first integration run.

---

## 3. Git Progression History

The design was committed progressively on branch `feature/main-memory-interface` following the 8 mandated development phases:

| Step | Commit Hash | Commit Message | Scope of Work |
|:---:|:---:|:---|:---|
| **1** | `6567be0` | `Create main memory model: establish architecture, ports, and modular interface` | Refactor module header, parameterization, and port definitions. |
| **2** | `b5bd62f` | `Add deterministic memory initialization: 4-word block mapping and array backing` | Implement `mem_array` storage and address calculation logic. |
| **3** | `547f9f3` | `Implement memory latency counter: parameterized wait-state generation` | Parameterized cycle counter supporting 1 to 255 wait cycles. |
| **4** | `181e49b` | `Implement memory interface FSM: 3-state Moore model (IDLE, ACCESS, RESPONSE)` | Formal 3-state FSM with busy isolation and diagnostic outputs. |
| **5** | `5f0c1c4` | `Add block response logic: atomic 128-bit bus drive and ready handshake` | Registered 128-bit block delivery and single-cycle ready strobe. |
| **6** | `537cfea` | `Create memory subsystem testbench: 11 exhaustive test scenarios covering latency, handshake, and block integrity` | Author standalone testbench (`tb/memory_subsystem_tb.v`). |
| **7** | `dab4ccb` | `Verify handshake behavior: validate standalone testbench and top-level cache integration (100% pass)` | Verification report, timing diagrams, and simulation validation. |
| **8** | *(Current)* | `Document interface and latency: architecture specifications and contribution report` | Full subsystem architecture and individual contribution reports. |

---

## 4. Verification & Simulation Results Summary

- **Subsystem Testbench:** [`tb/memory_subsystem_tb.v`](file:///Users/harshkumar/air_qunality_14november/Directed-Cache-Mapping/tb/memory_subsystem_tb.v) -> **11 / 11 checks passed (100%)**
- **Top-Level Integration Testbench:** [`tb/cache_top_tb.v`](file:///Users/harshkumar/air_qunality_14november/Directed-Cache-Mapping/tb/cache_top_tb.v) -> **12 / 12 checks passed (100%)**
- **Simulation Artifacts:**
  - `sim/memory_subsystem_tb.vcd` (31 KB)
  - `sim/cache_top_tb.vcd` (36 KB)

---

## 5. Technical Interview Defense & Viva Q&A Preparation

### Q1: Why did you separate `main_memory.v` and `memory_interface.v` rather than merging them into one module?
> **Answer:** Modularity and separation of concerns are fundamental in hardware engineering.  
> `memory_interface.v` represents the **system bus adapter / bridge** that resides on the cache controller side of the bus. Its sole responsibility is protocol qualification: enforcing 16-byte block alignment (`mem_req_addr = {ctrl_addr[31:4], 4'b0000}`) and isolating controller handshakes.  
> `main_memory.v` represents the **off-chip or external memory subsystem** containing the physical storage array, latency simulation counter, and memory service FSM.  
> Keeping them distinct allows changing the memory technology (e.g., swapping behavioral SRAM for DDR4 or AXI-compliant memory) without touching the cache-to-bus interface logic.

### Q2: How does your FSM prevent accidental repeated acceptance of the same memory request?
> **Answer:** In `rtl/main_memory.v`, requests are accepted exclusively in `MEM_IDLE`. When `mem_req_val` asserts in `MEM_IDLE`, the address is latched into `latched_addr_q` on the rising clock edge, and the FSM immediately advances to `MEM_ACCESS`.  
> While in `MEM_ACCESS`, the next-state logic unconditionally ignores the external `mem_req_val` input. Even if the bus master holds `mem_req_val` high for multiple cycles or toggles it spuriously, the memory subsystem continues counting its configured latency for the originally latched address until completion. Only after `MEM_RESPONSE` completes and the FSM returns to `MEM_IDLE` can a new request be recognized.

### Q3: Why is memory access latency modeled using synchronous counters rather than simulation delays (`#100ns`)?
> **Answer:** Using `#` delays in Verilog produces non-synthesizable simulation code that cannot be targeted to FPGAs or standard-cell ASICs. Furthermore, `#` delays are decoupled from clock edges, which can introduce race conditions and setup/hold timing ambiguities.  
> By implementing an explicit synchronous counter (`latency_cnt_q`) operating on `posedge clk`, the access latency is cycle-accurate, synthesizable-compatible, and dynamically configurable across clock frequencies.

### Q4: How do you guarantee that all four 32-bit words in a 128-bit returned block are distinguishable and correctly placed?
> **Answer:** In `rtl/main_memory.v`, the 128-bit block is constructed as `{word3, word2, word1, word0}`. Each word is calculated deterministically from the block base address:
> - Word 0 (`bits [31:0]`) = `block_base_addr | 0x0`
> - Word 1 (`bits [63:32]`) = `block_base_addr | 0x4`
> - Word 2 (`bits [95:64]`) = `block_base_addr | 0x8`
> - Word 3 (`bits [127:96]`) = `block_base_addr | 0xC`  
> Because each word incorporates its exact byte offset, every word within a block has a distinct value differing by 4. When Saksham's cache controller multiplexer extracts Word $k$ using `req_word_sel = addr[3:2]`, the CPU receives the exact physical word requested.

### Q5: What happens if an active-low reset pulse (`rst_n == 0`) occurs in the middle of a memory access?
> **Answer:** The reset is implemented as an active-low asynchronous assertion with synchronous recovery (`always @(posedge clk or negedge rst_n)`). If `rst_n` falls mid-transaction, `state_q` is immediately forced to `MEM_IDLE`, `latency_cnt_q` is cleared to `8'd0`, and `mem_req_ready` is deasserted to `1'b0`. This guarantees the memory returns to a known quiescent state without leaving dangling ready pulses or corrupting subsequent reads. Scenario 10 in [`tb/memory_subsystem_tb.v`](file:///Users/harshkumar/air_qunality_14november/Directed-Cache-Mapping/tb/memory_subsystem_tb.v) directly verifies this behavior.

### Q6: How does the memory handshake coordinate with Saksham's 6-state cache controller FSM?
> **Answer:** On a cache miss, Saksham's controller enters `STATE_MEM_REQUEST`, asserting `mem_req_val = 1` for one cycle, then advances to `STATE_MEM_WAIT` where `mem_req_val = 0`.  
> My memory subsystem detects `mem_req_val == 1` in `MEM_IDLE`, latches the block address, and counts `LATENCY` cycles in `MEM_ACCESS`. When complete, my FSM enters `MEM_RESPONSE` and asserts `mem_req_ready = 1` for one cycle. Saksham's controller samples `mem_req_ready` on that rising clock edge, captures `mem_resp_data` into its refill buffer, and advances to `STATE_REFILL`. Both state machines return cleanly to their respective idle/next states without bus contention or deadlocks.
