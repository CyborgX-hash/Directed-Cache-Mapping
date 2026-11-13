# Cache Storage Architecture Documentation

**Author:** Mihika Mathur  
**Role:** Cache Storage & Address Decoding Engineer  
**Project:** Design and Analysis of a Direct-Mapped Cache Controller  
**Branch:** `feature/cache-storage`

---

## 1. Module Ownership Summary

| Module | File | Author | Status |
|:---|:---|:---|:---|
| Address Decoder | `rtl/address_decoder.v` | Mihika | ✅ Verified |
| Cache Data RAM | `rtl/cache_data_ram.v` | Mihika | ✅ Verified |
| Tag RAM | `rtl/tag_ram.v` | Mihika | ✅ Verified |
| Valid-Bit RAM | `rtl/valid_bit_ram.v` | Mihika | ✅ Verified |
| Cache Storage (integration) | `rtl/cache_storage.v` | Mihika | ✅ Verified |
| Storage Testbench | `tb/cache_storage_tb.v` | Mihika | ✅ 30/30 Pass |
| Address Decoder Testbench | `tb/address_decoder_tb.v` | Mihika | ✅ 17/17 Pass |

---

## 2. Direct-Mapped Cache Address Mapping

### Address Breakdown (32-bit)

```
 31                        10  9        4  3   2  1  0
+----------------------------+----------+-----+------+
|         Tag  (22 bits)     | Idx (6b) |Word |Byte  |
+----------------------------+----------+-----+------+
                                         \_________/
                                        Block Offset (4 bits)
```

| Field | Bits | Width | Purpose |
|:------|:-----|------:|:--------|
| Tag | `[31:10]` | 22 | Identifies which physical memory page occupies this cache line |
| Index | `[9:4]` | 6 | Directly selects 1 of 64 cache lines (2⁶ = 64) |
| Block Offset | `[3:0]` | 4 | Byte address within the 16-byte cache block |
| Word Select | `[3:2]` | 2 | Selects 1 of 4 × 32-bit words inside the block |
| Byte Offset | `[1:0]` | 2 | Sub-word byte addressing |

### Why these widths?

- **Index (6 bits):** `log₂(1024 B / 16 B) = log₂(64) = 6`
- **Block Offset (4 bits):** `log₂(16 bytes) = 4`
- **Tag (22 bits):** `32 - 6 - 4 = 22` — the remaining bits uniquely qualify the physical address

---

## 3. Module Architecture

### 3.1 `address_decoder.v` — Pure Combinational

```
addr[31:0] ──┬──► tag[21:0]       = addr[31:10]
             ├──► index[5:0]      = addr[9:4]
             ├──► offset[3:0]     = addr[3:0]
             ├──► word_sel[1:0]   = addr[3:2]
             └──► byte_offset[1:0]= addr[1:0]
```

- **No clock, no state, no latches.** Zero-cycle latency.
- Parameterized via `TAG_WIDTH`, `INDEX_WIDTH`, `OFFSET_WIDTH` etc. so a single change propagates to all slices.
- Used by both `cache_top` (driven by `cpu_req_addr`) and in the storage testbench (TC7).

---

### 3.2 `cache_data_ram.v` — 64 × 128-bit Data Array

```
      Write Path (synchronous)             Read Path (combinational)
      ─────────────────────────            ──────────────────────────
clk ──► posedge                            index ──► data_mem[index]
write_enable ──► gate                              ──► read_data[127:0]
index ──► data_mem[index]
write_data[127:0] ──► latch
```

**RAM Inference:** Because writes are gated by `posedge clk` and reads are `assign`-based (`wire`), synthesis tools infer this as **Distributed RAM (LUTRAM)** on FPGAs or as a standard register file / SRAM on ASICs — not a flip-flop array — keeping area efficient.

**No Reset on Data Array:** Resetting 8,192 flip-flops (64 × 128) would be extremely expensive in both area and timing. Instead, the **valid-bit RAM** acts as the gatekeeper: data is never consumed unless `valid = 1` AND `stored_tag == request_tag`.

---

### 3.3 `tag_ram.v` — 64 × 22-bit Tag Array

```
      Write Path (synchronous)             Read Path (combinational)
      ─────────────────────────            ──────────────────────────
clk ──► posedge                            index ──► tag_mem[index]
write_enable ──► gate                              ──► read_tag[21:0]
index ──► tag_mem[index]
write_tag[21:0] ──► latch
```

**Same architecture as cache_data_ram**, just 22-bit wide entries. Having an independent `write_enable` means the controller can update the tag at the same time as the data in a single atomic write cycle (STATE_REFILL), preventing any cycle where data is live under an old tag.

---

### 3.4 `valid_bit_ram.v` — 64 × 1-bit Valid Flags

```
      Reset Path (synchronous, priority)
      ────────────────────────────────────
rst_n low ──► all valid_mem[i] <= 0  (for i in 0..63)

      Write Path                           Read Path
      ────────────────────────────         ──────────────────────
write_enable & posedge clk ──►            index ──► valid_mem[index]
  valid_mem[index] <= write_valid                 ──► read_valid
```

**Why synchronous reset?** Avoids glitch-driven spurious clears. The reset clears all 64 bits in a single clock cycle (synchronous for-loop in `always @(posedge clk)`), guaranteeing a clean state before the first lookup.

**False-Hit Prevention:** On power-up or any reset, `valid_mem[i] = 0` for all `i`. The tag comparator computes `hit = valid AND (tag_in == cache_tag)`. With `valid = 0`, hits are impossible regardless of whatever random bits the data/tag arrays may hold — these arrays do not need to be reset.

---

### 3.5 `cache_storage.v` — Structural Integration Module

```
                 ┌────────────────────────────────────────────┐
                 │             cache_storage                  │
  read_index ───►│──► u_data_ram.index (read)                 │──► read_data
  write_index ──►│──► u_data_ram.index (write)                │
  write_data  ──►│──► u_data_ram.write_data                   │
                 │                                            │
  read_index ───►│──► u_tag_ram.index (read)                  │──► read_tag
  write_index ──►│──► u_tag_ram.index (write)                 │
  write_tag   ──►│──► u_tag_ram.write_tag                     │
                 │                                            │
  read_index ───►│──► u_valid_ram.index (read)                │──► read_valid
  write_index ──►│──► u_valid_ram.index (write)               │
  write_valid ──►│──► u_valid_ram.write_valid                 │
                 │                                            │
  write_en    ──►│──► all three write_enable lines (atomic)   │
  rst_n       ──►│──► u_valid_ram.rst_n                       │
  clk         ──►│──► all three clk                           │
                 └────────────────────────────────────────────┘
```

**Key Design Decision — Index Mux:** When `write_en = 1`, all three RAMs use `write_index`; otherwise they use `read_index`. This ensures the read path is always clean and the write path atomically updates the correct line in a single cycle.

**Atomic Write Guarantee:** `write_en` gates all three sub-modules simultaneously. In STATE_REFILL, one rising clock edge commits the new 128-bit data block, its 22-bit tag, and `valid = 1` together. There is no intermediate state where tag is new but data is old, or data is new but valid is still 0.

---

## 4. Cache Lookup Timing Diagram

```
         IDLE          LOOKUP         MEM_REQ   MEM_WAIT   REFILL   RESPOND
clk:  __|‾|_|‾|_|   __|‾|_|‾|_|   ___|‾|_   ___|‾|_   ___|‾|_  ___|‾|_
                         │               │
cpu_req_val asserted──►  │               │
address latched────────► │               │
                    index ──► all 3 RAMs │
                    read_data/tag/valid  │
                    comparator evaluates─►
                    HIT: data→buf, →RESPOND
                    MISS: →MEM_REQ──────►│
                                    mem_req_val=1 ──► memory
                                         │  mem_req_ready=1
                                              data_buffer←mem_resp
                                                     write_en=1
                                                     (data+tag+valid atomic)
                                                              cpu_resp_val=1
```

---

## 5. How Tag, Index, Offset, and Valid Bits Work Together

1. **CPU issues address** `A` (32 bits).
2. `address_decoder` splits: `tag = A[31:10]`, `index = A[9:4]`, `offset = A[3:0]`.
3. `index` selects the **same row** in all three RAMs simultaneously (zero latency).
4. **Tag comparator** evaluates: `hit = (read_valid == 1) AND (read_tag == tag)`.
   - If **HIT**: `read_data` is routed to the CPU; `word_sel` picks the correct 32-bit word.
   - If **MISS**: controller requests a 16-byte block from main memory using the block-aligned address `{tag, index, 4'b0000}`.
5. On **REFILL**: the new block is written back via `write_en`, atomically updating data, tag, and valid in one clock cycle.
6. **Next lookup** to the same index with the same tag → HIT.

---

## 6. Engineering Decisions & Trade-offs

| Decision | Rationale |
|:---------|:----------|
| Combinational read ports | Zero-latency line inspection in LOOKUP state. No additional pipeline register needed. |
| No reset on data/tag RAMs | Prevents inferring thousands of reset flip-flops. Valid-bit exclusively guards correctness. |
| Synchronous reset on valid RAM | Clean, glitch-free invalidation of all 64 lines in exactly one clock cycle. |
| Single write_en for all 3 RAMs | Guarantees atomic data+tag+valid commit; eliminates any intra-cycle hazard window. |
| Parameterized dimensions | WIDTH changes in one place propagate to all sub-modules and testbenches. |
| Independent index mux | Allows read and write to target different lines while sharing one index bus. |

---

## 7. Verification Results Summary

### Storage Testbench (`tb/cache_storage_tb.v`)

| Test Case | Description | Result |
|:----------|:------------|:------:|
| TC1 | Valid bits = 0 after reset | ✅ PASS |
| TC2 | Write + read all 64 lines | ✅ PASS |
| TC3 | Tag independent write all 64 lines | ✅ PASS |
| TC4 | Correct data at specific index | ✅ PASS |
| TC5 | Correct tag at specific index | ✅ PASS |
| TC6 | Adjacent line isolation | ✅ PASS |
| TC7 | Address decoder field separation | ✅ PASS |
| TC8 | Repeated reads are stable | ✅ PASS |
| TC9 | Boundary (line 0, line 63, all-0, all-1) | ✅ PASS |
| TC10 | Conflict eviction (same index, different tag) | ✅ PASS |
| **Total** | | **30 / 30** |

### Address Decoder Testbench (`tb/address_decoder_tb.v`)

| Tests | Result |
|:------|:------:|
| Boundary min/max | ✅ PASS |
| Project addresses (0x1040, 0x1048, 0x2040) | ✅ PASS |
| Word/byte offset sweep | ✅ PASS |
| Index boundary (0, 1, 62, 63) | ✅ PASS |
| Arbitrary hex pattern | ✅ PASS |
| **Total** | **17 / 17** |

### Full System Integration (`tb/cache_top_tb.v`)

| Tests | Result |
|:------|:------:|
| Compulsory miss, hit, spatial locality, conflict, reset, pipelining | **12 / 12** ✅ |

---

## 8. Git Commit History (feature/cache-storage)

```
e93270e  Fix bugs and validate: storage testbench 30/30 pass, integration 12/12 pass
f188ea0  Create storage testbench: 30 checks covering valid-bit reset, all-line write/read, isolation, decoder, repeated reads, boundary, and conflict eviction
1f3d8e3  Integrate cache_storage: structural assembly of data RAM, tag RAM, and valid-bit RAM sub-modules
b64e64a  Implement valid-bit RAM: 64 valid bits with synchronous reset-to-zero and independent write
ab092bf  Implement tag RAM: 64x22-bit array with synchronous write and combinational read
fc4ce3e  Implement cache data RAM: 64x128-bit array with synchronous write and combinational read
19806c4  Implement address decoder: parameterized bit slicing for tag, index, and offsets
```
