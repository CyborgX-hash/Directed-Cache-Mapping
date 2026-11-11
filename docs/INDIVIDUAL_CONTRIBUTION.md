# Individual Contribution Documentation & Technical Defense

**Candidate:** Saksham Sontakke  
**Role:** Integration Lead, Cache Controller Architect, & Top-Level System Integrator  
**Project:** Design and Analysis of a Direct-Mapped Cache Controller  
**Academic Milestone:** Phase II Capstone RTL Defense

---

## 1. Technical Ownership & Assigned Deliverables

In accordance with the project charter, my exclusive design and implementation responsibilities were:

1. **`rtl/cache_controller.v`:**
   - Architecture and design of the master 6-state Moore/Mealy hybrid FSM.
   - Address latching logic and sub-field routing.
   - Cache hit/miss branching and comparator integration.
   - Handshake timing with external memory (`MEM_REQUEST` pulse, `MEM_WAIT` stall).
   - Atomic cache line refill sequencing (`REFILL` state write gating).
   - 4-to-1 32-bit word extraction multiplexer and `cpu_resp_val` generation.

2. **`rtl/cache_top.v`:**
   - Top-level structural integration uniting all five team members' modules:
     - `address_decoder` (Mihika)
     - `cache_storage` (Harsh)
     - `tag_comparator` (Priyanshu)
     - `cache_controller` (Saksham)
     - `memory_interface` (Harsh & Priyanshu)
     - `main_memory` (Ajit)
   - Zero-logic top-level principle: no storage or FSM logic duplicated inside top.

3. **Verification & Testbench Integration:**
   - Authored the standalone controller testbench (`tb/cache_controller_tb.v`).
   - Co-developed the comprehensive system testbench (`tb/cache_top_tb.v`) with Ajit, establishing 100% test coverage across all 7 mandated architectural failure modes.

4. **Documentation & Git Governance:**
   - Authored integration documentation, state machine diagrams, verification reports, and presentation defenses.
   - Maintained clean Git progression on branch `feature/cache-controller-integration`.

---

## 2. Key Architectural Decisions & Engineering Rationale

### Decision 1: Address Latching in `STATE_IDLE`
- **Rationale:** CPUs frequently deassert or alter request lines once a memory request has been accepted. By latching `cpu_req_addr` into `latched_addr_q` on the cycle entering `LOOKUP`, the controller isolates internal operations from CPU signal jitter.
- **Backpressure:** Setting `cpu_req_ready = 1'b0` immediately upon leaving `IDLE` informs the CPU bus that the cache pipeline is busy.

### Decision 2: Single-Cycle `MEM_REQUEST` Handshake Protocol
- **Rationale:** To avoid duplicate memory requests, `mem_req_val` is asserted strictly for one cycle in `STATE_MEM_REQUEST`, then deasserted in `STATE_MEM_WAIT`. The controller waits statically until `mem_req_ready` goes high. This prevents the memory subsystem from queueing redundant fetches.

### Decision 3: Atomic Storage Write in `STATE_REFILL`
- **Rationale:** The 128-bit memory block is captured into `data_buffer_q` when `mem_req_ready` asserts. In the subsequent `STATE_REFILL` cycle, the cache storage line is updated atomically: data array, tag array, and valid bit are committed simultaneously on the rising clock edge, eliminating transient states where data is valid under an old tag.

### Decision 4: Seamless Consecutive Transactions
- **Rationale:** When returning from `STATE_RESPOND` to `STATE_IDLE`, `cpu_req_ready` goes high. If the CPU has a pending request on the bus, the FSM immediately latches the new address and advances to `STATE_LOOKUP` without inserting idle bubble cycles or requiring a system reset.

---

## 3. Interview Defense Q&A Preparation

### Q1: Why use a 6-state FSM rather than collapsing `MEM_REQUEST` and `MEM_WAIT`?
> *Answer:* Separating `MEM_REQUEST` and `MEM_WAIT` guarantees a strictly compliant single-cycle request pulse on the memory bus. If they were collapsed into a single state, holding `mem_req_val` until `mem_req_ready` could cause pipelined or multi-channel memory controllers to treat prolonged assertion as multiple requests. Furthermore, distinct states make pipeline stall cycles explicitly observable during debugging.

### Q2: How does the controller guarantee that no stale data is delivered on a miss?
> *Answer:* On a miss, `STATE_LOOKUP` does not route the storage read data into `data_buffer_q`. Instead, the FSM transitions through `MEM_REQUEST` and `MEM_WAIT`. `data_buffer_q` is only loaded once `mem_req_ready` asserts from the main memory. In `STATE_RESPOND`, the multiplexer selects the output word exclusively from `data_buffer_q`, guaranteeing that the CPU receives the newly fetched memory block.

### Q3: How are conflict misses handled?
> *Answer:* In direct mapping, two distinct physical addresses that share identical index bits (`address[9:4]`) map to the exact same cache line. When the second address is requested, the line is already valid (`valid == 1`), but the stored tag does not match the requested tag. The tag comparator asserts `miss`, the controller transitions to `MEM_REQUEST`, retrieves the new block, and in `STATE_REFILL` overwrites the old block and replaces the old tag with the new tag.

### Q4: What happens if a reset occurs mid-transaction?
> *Answer:* An active-low reset pulse immediately drives `state_q <= STATE_IDLE`, resets `latched_addr_q`, and clears all 64 valid bits in `cache_storage`. Ongoing memory transactions are aborted and `cpu_req_ready` returns to 1, restoring the system to a clean, known initial state.
