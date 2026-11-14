# Memory Subsystem & Refill Interface Architecture

**Author:** Harsh Kumar (Memory Subsystem & Refill Interface Lead)  
**Project:** Design and Analysis of a Direct-Mapped Cache Controller  
**Course/Track:** Computer Architecture & RTL Hardware Design (Capstone Phase II)

---

## 1. Subsystem Overview & Architectural Purpose

In a memory hierarchy, the cache controller manages fast local storage (SRAM), while the **Memory Subsystem** models the high-capacity, higher-latency backing storage (DRAM / Main Memory) and the interconnect bridge required to service cache misses.

When the direct-mapped cache experiences a miss (compulsory or conflict), the cache controller stalls CPU service, generates a block-aligned read request, and coordinates with the memory subsystem to transfer an entire **16-byte (128-bit) cache block**.

```
+---------------------------------------------------------------------------------------+
|                                     CACHE CORE                                        |
|  +-------------------------+                     +---------------------------------+  |
|  |    cache_controller     |                     |          cache_storage          |  |
|  |    (Author: Saksham)    |                     |         (Author: Mihika)        |  |
|  +-------------------------+                     +---------------------------------+  |
|        |             ^                                            ^                   |
|        | ctrl_req    | ctrl_resp                                  | refill_block      |
+========|=============|============================================|===================+
         |             |                                            |
         v             |                                            |
+------------------------------------+                              |
|          memory_interface          |                              |
|        (Author: Harsh Kumar)       |                              |
|   - 16-byte block alignment        |                              |
|   - Handshake bridge & isolation   |                              |
+------------------------------------+                              |
         | bus_req     ^ bus_resp                                   |
         v             |                                            |
+------------------------------------+                              |
|            main_memory             |                              |
|        (Author: Harsh Kumar)       |                              |
|   - Parameterized access latency   |                              |
|   - 3-state Moore FSM              |                              |
|   - Deterministic memory array     |------------------------------+
|   - 4-word block assembly          |
+------------------------------------+
```

### Harsh's Technical Ownership:
1. **`rtl/memory_interface.v`:** Bus protocol bridge enforcing 16-byte address block alignment, isolating controller transactions, and routing 128-bit blocks.
2. **`rtl/main_memory.v`:** Synthesizable-compatible behavioral main memory model with configurable clock latency, 3-state Moore FSM, and deterministic data initialization.
3. **Deterministic Memory Initialization:** Address-based mathematical data generation and internal memory array backing for 256 cache blocks (4 KB).
4. **Parameterized Latency Counter:** Cycle-accurate latency simulation (default 10 cycles, tested from 1 to 10 cycles) without artificial simulation delays.
5. **Memory Subsystem Verification:** Exhaustive standalone testbench (`tb/memory_subsystem_tb.v`) validating 11 test scenarios with 100% test coverage.

---

## 2. Interface Signal Definitions & Handshake Protocol

The memory subsystem interfaces with the cache controller using a 4-signal request/response handshake:

| Signal Name | Width | Direction (to Memory) | Description |
|:---|:---:|:---:|:---|
| `mem_req_val` | 1 bit | Input | Request valid strobe. Pulsed high for exactly 1 cycle by controller. |
| `mem_req_addr` | 32 bits | Input | 32-bit physical address requested by controller. |
| `mem_req_ready` | 1 bit | Output | Response ready completion strobe. Asserted for 1 cycle when data is valid. |
| `mem_resp_data` | 128 bits | Output | Complete 16-byte cache block containing four 32-bit words. |

### Handshake Protocol Rules:
1. **Request Initiation:** The cache controller asserts `mem_req_val = 1'b1` and drives `mem_req_addr`.
2. **Address Latching:** On the next rising clock edge, the memory interface latches `mem_req_addr` into `latched_addr_q`, masks offset bits `[3:0]` to enforce 16-byte alignment, and starts the latency counter.
3. **Single-Pulse Request Rule:** The controller deasserts `mem_req_val = 1'b0` on the following cycle and waits in `STATE_MEM_WAIT`.
4. **Busy State Isolation:** While memory latency is being counted (`MEM_ACCESS`), any incoming pulses on `mem_req_val` or alterations to `mem_req_addr` are strictly ignored.
5. **Completion Strobe:** When the latency counter expires, memory enters `MEM_RESPONSE`, drives `mem_resp_data` with the 128-bit block, and asserts `mem_req_ready = 1'b1` for exactly 1 clock cycle.
6. **Data Capture & Return:** The controller captures `mem_resp_data` on the rising clock edge of the completion pulse. Memory deasserts `mem_req_ready = 1'b0` and returns to `MEM_IDLE`.

---

## 3. Memory Interface FSM Architecture

The memory subsystem is governed by a 3-state Moore Finite State Machine implemented in `rtl/main_memory.v`:

```
               +-----------------------------------------+
               |                                         |
               v                                         |
        +--------------+   mem_req_val == 1              |
+------>|   MEM_IDLE   |---------------------+           |
| reset |   (2'b00)    |                     |           |
+------>+--------------+                     |           |
               ^                             v           |
               |                     +---------------+   |
               |                     |  MEM_ACCESS   |   |
               |                     |    (2'b01)    |   |
               |                     +---------------+   |
               |                             |           |
               |     latency expired         |           |
               |  (latency_cnt == LATENCY)   |           |
               |                             v           |
               |                     +---------------+   |
               |                     | MEM_RESPONSE  |   |
               |                     |    (2'b10)    |   |
               |                     +---------------+   |
               |                             |           |
               +-----------------------------+-----------+
```

### State Specifications:
1. **`MEM_IDLE` (`2'b00`):**
   - Default quiescent state.
   - Outputs: `mem_req_ready = 1'b0`.
   - Latency counter held at zero: `latency_cnt_d = 8'd0`.
   - Next-state logic: When `mem_req_val == 1'b1`, captures `latched_addr_d = {mem_req_addr[31:4], 4'b0000}`. If `LATENCY <= 1`, advances directly to `MEM_RESPONSE`; otherwise sets `latency_cnt_d = 8'd1` and advances to `MEM_ACCESS`.

2. **`MEM_ACCESS` (`2'b01`):**
   - Active memory access / stall cycle wait state.
   - Outputs: `mem_req_ready = 1'b0`.
   - Busy filtering: Spurious request signals on `mem_req_val` are ignored.
   - Synchronous progression: Increments `latency_cnt_q` on each rising clock edge.
   - Transition: When `latency_cnt_q == (LATENCY - 1)`, prepares `resp_data_d = selected_block` and transitions to `MEM_RESPONSE`.

3. **`MEM_RESPONSE` (`2'b10`):**
   - Response presentation state.
   - Outputs: `mem_req_ready = 1'b1` (single-cycle completion pulse).
   - Data drive: `mem_resp_data` presents the stable 128-bit block.
   - Transition: Unconditionally transitions to `MEM_IDLE` on the subsequent rising clock edge, guaranteeing a single-cycle pulse.

---

## 4. Deterministic Data Initialization & Memory Array Architecture

To enable independent verification and automated grading, data returned by main memory is deterministic, address-predictable, and uniquely distinguishable.

### 16-Byte Block & 32-Bit Word Geometry:
Every 16-byte block contains four 32-bit words ordered in little-endian word layout:
```
127                           96 95                            64 63                            32 31                             0
+-------------------------------+-------------------------------+-------------------------------+-------------------------------+
|     Word 3 (Offset 0xC)       |      Word 2 (Offset 0x8)      |      Word 1 (Offset 0x4)      |      Word 0 (Offset 0x0)      |
+-------------------------------+-------------------------------+-------------------------------+-------------------------------+
```

### Address-Based Mathematical Calculation:
Each word's content corresponds exactly to its 32-bit physical byte address:
- $\text{Word } 0 = \text{block\_base\_addr} \mid 32\text{'h0000\_0000}$
- $\text{Word } 1 = \text{block\_base\_addr} \mid 32\text{'h0000\_0004}$
- $\text{Word } 2 = \text{block\_base\_addr} \mid 32\text{'h0000\_0008}$
- $\text{Word } 3 = \text{block\_base\_addr} \mid 32\text{'h0000\_000C}$

### Internal Memory Array Backing:
- **Depth:** Parameter `MEM_DEPTH = 256` blocks ($256 \times 16\text{ B} = 4096\text{ Bytes} = 4\text{ KB}$).
- **Initialization:** An `initial` loop initializes `mem_array[0:255]` with the exact deterministic pattern at simulation start.
- **Extended Address Space:** Addresses beyond 4 KB fall back to the hardware calculation formula, ensuring coverage across the full 4 GB physical address space.

---

## 5. Latency Modeling & Parameterization

Main memory access is parameterized via `parameter LATENCY = 10`:

| Latency Setting | Turnaround Cycles | Architectural Context |
|:---:|:---:|:---|
| `LATENCY = 1` | 1 Cycle | Ideal SRAM baseline / ultra-fast cache-line refill |
| `LATENCY = 2` | 2 Cycles | Fast synchronous on-chip BRAM / integration test default |
| `LATENCY = 5` | 5 Cycles | High-speed DDR interface / medium penalty |
| `LATENCY = 10` | 10 Cycles | Standard off-chip SDRAM penalty / realistic miss latency |

No artificial simulation delays (`#10`) are used in synthesizable logic paths; all latency is counted synchronously using clock edges.
