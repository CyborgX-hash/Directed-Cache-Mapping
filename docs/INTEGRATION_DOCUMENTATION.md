# Direct-Mapped Cache Controller: Top-Level System Integration Documentation

**Author:** Saksham (Integration Lead & FSM Architect)  
**Project:** Design and Analysis of a Direct-Mapped Cache Controller  
**Course/Track:** Computer Architecture & RTL Hardware Design (Academic Phase II)

---

## 1. System Specifications & Geometry

The integrated system implements a high-performance, synthesizable, read-only direct-mapped cache architecture with a block-refill miss policy.

| Architectural Parameter | Value | Hardware Justification / Notes |
|:---|:---|:---|
| **Cache Capacity** | 1024 Bytes (1 KB) | Total user data payload (excludes tag/valid metadata). |
| **Block Size** | 16 Bytes (128 bits) | Exploits spatial locality (4 consecutive 32-bit words). |
| **Number of Cache Lines** | 64 Lines | Calculated as $1024\text{ B} / 16\text{ B} = 64$. |
| **Address Width** | 32 Bits | Standard unsegmented CPU memory address. |
| **Tag Width** | 22 Bits | `address[31:10]` provides unique physical address qualification. |
| **Index Width** | 6 Bits | `address[9:4]` directly indexes $2^6 = 64$ lines. |
| **Block Offset Width** | 4 Bits | `address[3:0]` addresses 16 bytes within each block. |
| **Word Selection** | 2 Bits | `address[3:2]` extracts 1 of 4 words ($2^2 = 4$). |
| **Byte Offset** | 2 Bits | `address[1:0]` word-aligned sub-byte addressing. |
| **Refill Policy** | 16-Byte Block | Full 128-bit line refill on compulsory or conflict miss. |

```
Address Breakdown (32 bits):
 31                        10 9       4 3   2 1  0
+----------------------------+---------+-----+----+
|         Tag (22)           |Index (6)|Word |Byte|
+----------------------------+---------+-----+----+
                                        \________/
                                       Block Offset (4)
```

---

## 2. Integrated Subsystem Modules & Team Interface Ownership

To maintain strict modularity and adhere to the academic team ownership guidelines, the top-level module ([`cache_top.v`](file:///Users/sakshamsontakke/Desktop/Direct-cache-Map/rtl/cache_top.v)) integrates six dedicated sub-modules without rewriting or duplicating peer logic:

```
                                  +---------------------------------------------+
                                  |                  CPU Core                   |
                                  +---------------------------------------------+
                                         | cpu_req_val           ^ cpu_resp_val
                                         | cpu_req_addr[31:0]    | cpu_resp_data[31:0]
                                         v                       |
+========================================|=======================|======================================+
| cache_top                              |                       |                                      |
|                                        v                       |                                      |
|  +--------------------+        +-------------------------------+                                      |
|  | address_decoder    |        |        cache_controller       |<--------------------+                |
|  | (Author: Mihika)   |        |        (Author: Saksham)      |                     |                |
|  +--------------------+        +-------------------------------+                     |                |
|          | addr[31:0]            |               |               ^                   |                |
|          |                       | req_index     | refill_block  | cmp_hit/miss      |                |
|          v                       v               v               |                   |                |
|     Sub-field wires        +-------------------------------+     |             +-------------------+  |
|     (tag, index,           |         cache_storage         |-----+             |  tag_comparator   |  |
|      offset, word_sel)     |         (Author: Harsh)       |------------------>| (Author: Priyanshu|  |
|                            +-------------------------------+ storage_read_tag +-------------------+  |
|                                                                                                       |
|                                +-----------------------------------+                                  |
|                                |         memory_interface          |                                  |
|                                |    (Author: Harsh & Priyanshu)    |                                  |
|                                +-----------------------------------+                                  |
|                                        |                   ^                                          |
|                                        | bus_mem_req       | bus_mem_resp                             |
|                                        v                   |                                          |
|                                +-----------------------------------+                                  |
|                                |            main_memory            |                                  |
|                                |          (Author: Ajit)           |                                  |
|                                +-----------------------------------+                                  |
+=======================================================================================================+
```

### Module Responsibilities:
1. **`address_decoder` (Mihika):** Pure combinational module extracting `tag[21:0]`, `index[5:0]`, `offset[3:0]`, `word_sel[1:0]`, and `byte_offset[1:0]` from the 32-bit CPU address.
2. **`cache_storage` (Harsh):** Synchronous/asynchronous dual-ported array storing 64 cache lines:
   - `valid_array`: $64 \times 1\text{ bit}$
   - `tag_array`: $64 \times 22\text{ bits}$
   - `data_array`: $64 \times 128\text{ bits}$
   - Asynchronous read port allows zero-wait combinational line inspection during `LOOKUP`.
   - Synchronous write port performs single-cycle atomic block updates during `REFILL`.
3. **`tag_comparator` (Priyanshu):** Validates whether `storage_read_valid == 1'b1` AND `tag_in == storage_read_tag`. Produces `hit` and `miss = ~hit`.
4. **`cache_controller` (Saksham):** Master 6-state FSM governing address latching, lookup dispatch, miss handling, memory bus sequencing, line replacement, and CPU word multiplexing.
5. **`memory_interface` (Harsh & Priyanshu):** Hardware bus bridge ensuring 16-byte address alignment (`{addr[31:4], 4'b0000}`) and isolating memory transaction signals.
6. **`main_memory` (Ajit):** Parameterized behavioral memory subsystem delivering 128-bit blocks after configurable clock latency cycles.

---

## 3. Protocol Definitions & Timing

### CPU Handshake Protocol:
- **Initiation (`IDLE`):** When `cpu_req_ready == 1'b1`, the CPU may assert `cpu_req_val` along with `cpu_req_addr`.
- **Address Latching:** The controller latches `cpu_req_addr` into `latched_addr_q` on the rising clock edge and immediately deasserts `cpu_req_ready = 1'b0`.
- **Response (`RESPOND`):** When data is ready (either from immediate cache hit or following a refill), `cpu_resp_val` is asserted for 1 clock cycle with `cpu_resp_data` holding the requested 32-bit word.
- **Backpressure:** The CPU must wait while `cpu_req_ready == 1'b0`. Any changes to `cpu_req_addr` or `cpu_req_val` while busy do not corrupt the active access.

### Memory Handshake Protocol:
- **Request (`MEM_REQUEST`):** Controller asserts `mem_req_val = 1'b1` with block-aligned `mem_req_addr` for exactly one cycle.
- **Wait (`MEM_WAIT`):** Controller deasserts `mem_req_val = 1'b0` to prevent duplicate transactions, waiting until `mem_req_ready == 1'b1`.
- **Refill (`REFILL`):** Upon receiving `mem_req_ready`, memory response block is registered and written into cache storage with valid bit set.

---

## 4. Architectural Safety Features & Hazard Avoidance

1. **Zero False Hits on Reset:** All 64 valid bits are cleared on `rst_n` deassertion. Uninitialized tag data cannot cause a false match because `hit = cache_valid && (tag_in == cache_tag)`.
2. **Elimination of Inferred Latches:** Every combinational path (`always @(*)`) specifies full default assignments to all driven signals prior to case branching.
3. **Strict Block Alignment:** Main memory requests force `addr[3:0] = 4'b0000`, guaranteeing that line fills start on clean 16-byte boundaries.
4. **No Stale Data Responses:** The CPU response multiplexer samples solely from the newly validated buffer, ensuring that words delivered on a miss correspond to the freshly fetched memory block.
5. **Back-to-Back Request Pipelining:** As soon as `RESPOND` finishes, the controller transitions to `IDLE` with `cpu_req_ready = 1'b1`, accepting subsequent requests without stalling or requiring a reset.
