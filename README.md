# Design and Analysis of a Direct-Mapped Cache Controller

## 1. System Specifications
- **Cache Capacity:** 1 KB (1024 bytes)
- **Block Size:** 16 bytes (128 bits)
- **Address Width:** 32 bits
- **Number of Cache Lines:** 64 lines
- **Words per Block:** 4 words (32 bits per word)
- **Tag Width:** 22 bits (`address[31:10]`)
- **Index Width:** 6 bits (`address[9:4]`)
- **Block Offset:** 4 bits (`address[3:0]`)
- **Word Selection:** 2 bits (`address[3:2]`)
- **Refill Policy:** 16-byte block refill on miss, read-only cache

## 2. Team Division of Responsibilities
- **Mihika:** `address_decoder.v` (Address mapping and sub-field decoding)
- **Harsh:** `main_memory.v`, `memory_interface.v` (Main memory model, refill interface, latency simulation, and verification)
- **Priyanshu:** `tag_comparator.v` (Comparator logic and hit/miss evaluation)
- **Ajit:** Verification infrastructure and analysis
- **Saksham (Integration Lead):** `cache_controller.v`, `cache_top.v`, FSM architecture, hit/miss sequencing, CPU response, system integration

## 3. Simulation & Verification Execution

### A. Memory Subsystem Verification (11 Checks - Harsh)
```bash
iverilog -Wall -g2012 -o sim/memory_subsystem_tb.vvp \
    rtl/memory_interface.v rtl/main_memory.v tb/memory_subsystem_tb.v
vvp sim/memory_subsystem_tb.vvp
```

### B. Top-Level Cache Integration Verification (12 Checks - All Scenarios)
```bash
iverilog -Wall -g2012 -o sim/cache_top_tb.vvp rtl/*.v tb/cache_top_tb.v
vvp sim/cache_top_tb.vvp
```

### C. Standalone Cache Storage Verification (30 Checks - Mihika)
```bash
iverilog -Wall -g2012 -o sim/cache_storage_tb.vvp rtl/*.v tb/cache_storage_tb.v
vvp sim/cache_storage_tb.vvp
```

### D. Standalone Controller Unit Verification (Saksham)
```bash
iverilog -Wall -g2012 -o sim/cache_controller_tb.vvp rtl/cache_controller.v tb/cache_controller_tb.v
vvp sim/cache_controller_tb.vvp
```
