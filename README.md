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
- **Harsh:** `cache_storage.v` (Cache data/tag/valid storage arrays)
- **Priyanshu:** `tag_comparator.v`, `memory_interface.v` (Comparator and bus alignment)
- **Ajit:** `main_memory.v`, testbench verification infrastructure
- **Saksham (Integration Lead):** `cache_controller.v`, `cache_top.v`, FSM architecture, hit/miss sequencing, CPU response, system integration
