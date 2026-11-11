# Direct-Mapped Cache Controller: Verification & Simulation Report

**Authors:** Saksham (Integration Lead) & Ajit (Verification Lead)  
**Simulator:** Icarus Verilog v13.0 (stable) / VVP runtime  
**Test Suite:** [`tb/cache_top_tb.v`](file:///Users/sakshamsontakke/Desktop/Direct-cache-Map/tb/cache_top_tb.v) & [`tb/cache_controller_tb.v`](file:///Users/sakshamsontakke/Desktop/Direct-cache-Map/tb/cache_controller_tb.v)  
**Status:** **100% Passed (12/12 Top-Level Checks + Unit Tests Passed)**

---

## 1. Test Matrix & Results Summary

| Test ID | Scenario Description | Tested Address | Expected Event | Result | Status |
|:---:|:---|:---:|:---:|:---:|:---:|
| **Test 1** | Compulsory Miss on Cold Access | `0x0000_1040` | `hit == 0`, refills line 4 | Returns `0x0000_1040` | **PASS** |
| **Test 2** | Cache Hit on Re-Access | `0x0000_1040` | `hit == 1`, 2-cycle turnaround | Returns `0x0000_1040` | **PASS** |
| **Test 3a** | Spatial Locality Hit (Word 2) | `0x0000_1048` | `hit == 1`, same block | Returns `0x0000_1048` | **PASS** |
| **Test 3b** | Spatial Locality Hit (Word 3) | `0x0000_104C` | `hit == 1`, same block | Returns `0x0000_104C` | **PASS** |
| **Test 4** | Conflict Miss (Same Index, Diff Tag) | `0x0000_2040` | `hit == 0`, replaces line 4 | Returns `0x0000_2040` | **PASS** |
| **Test 5a** | Hit on Newly Replaced Block (Word 1) | `0x0000_2044` | `hit == 1`, line 4 valid | Returns `0x0000_2044` | **PASS** |
| **Test 5b** | Miss on Evicted Old Block | `0x0000_1040` | `hit == 0`, refills line 4 | Returns `0x0000_1040` | **PASS** |
| **Test 6** | Reset Invalidates All Cache Lines | `0x0000_1040` | `hit == 0` (was valid, now reset) | Returns `0x0000_1040` | **PASS** |
| **Test 7a** | Back-to-Back Request A (Miss) | `0x0000_3000` | `hit == 0`, refills line 0 | Returns `0x0000_3000` | **PASS** |
| **Test 7b** | Back-to-Back Request B (Hit) | `0x0000_3004` | `hit == 1`, Word 1 hit | Returns `0x0000_3004` | **PASS** |
| **Test 7c** | Back-to-Back Request C (Miss) | `0x0000_4000` | `hit == 0`, refills line 0 | Returns `0x0000_4000` | **PASS** |
| **Test 7d** | Back-to-Back Request D (Hit) | `0x0000_400C` | `hit == 1`, Word 3 hit | Returns `0x0000_400C` | **PASS** |

---

## 2. Simulation Execution Logs

### Top-Level System Simulation:
```
$ iverilog -Wall -g2012 -o sim/cache_top_tb.vvp \
    rtl/address_decoder.v rtl/tag_comparator.v rtl/cache_storage.v \
    rtl/main_memory.v rtl/memory_interface.v rtl/cache_controller.v \
    rtl/cache_top.v tb/cache_top_tb.v
$ vvp sim/cache_top_tb.vvp

VCD info: dumpfile sim/cache_top_tb.vcd opened for output.
==================================================================
   DIRECT-MAPPED CACHE CONTROLLER SYSTEM VERIFICATION SUITE       
   Authors: Saksham, Mihika, Harsh, Priyanshu, Ajit               
==================================================================

--- Test 1: Compulsory Miss (Cold Access) ---
[PASS] Test 1 - Cold Access Miss: Addr=0x00001040 | Hit=0 | Data=0x00001040

--- Test 2: Cache Hit (Same Address) ---
[PASS] Test 2 - Re-access Hit: Addr=0x00001040 | Hit=1 | Data=0x00001040

--- Test 3: Spatial Locality Hit (Different Word, Same Block) ---
[PASS] Test 3 - Word 2 Hit: Addr=0x00001048 | Hit=1 | Data=0x00001048
[PASS] Test 3 - Word 3 Hit: Addr=0x0000104c | Hit=1 | Data=0x0000104c

--- Test 4: Conflict Miss (Same Index, Different Tag) ---
[PASS] Test 4 - Conflict Miss Replacement: Addr=0x00002040 | Hit=0 | Data=0x00002040

--- Test 5: Verify Replaced Block Data & Re-fetch Old Block ---
[PASS] Test 5 - New Block Hit: Addr=0x00002044 | Hit=1 | Data=0x00002044
[PASS] Test 5 - Evicted Block Re-fetch Miss: Addr=0x00001040 | Hit=0 | Data=0x00001040

--- Test 6: Cache Invalidation via Reset ---
Applying active-low reset pulse...
[PASS] Test 6 - Post-Reset Compulsory Miss: Addr=0x00001040 | Hit=0 | Data=0x00001040

--- Test 7: Backpressure & Consecutive Seamless Requests ---
[PASS] Test 7 - Request A (Miss): Addr=0x00003000 | Hit=0 | Data=0x00003000
[PASS] Test 7 - Request B (Immediate Hit): Addr=0x00003004 | Hit=1 | Data=0x00003004
[PASS] Test 7 - Request C (Miss): Addr=0x00004000 | Hit=0 | Data=0x00004000
[PASS] Test 7 - Request D (Immediate Hit): Addr=0x0000400c | Hit=1 | Data=0x0000400c

==================================================================
   VERIFICATION SUMMARY RESULTS                                   
   Total Checks:  12
   Passed Checks: 12
   Failed Checks: 0
   STATUS: >>> ALL INTEGRATION TESTS PASSED SUCCESSFULLY! <<<
==================================================================
```

### Standalone Controller Unit Simulation:
```
$ iverilog -Wall -g2012 -o sim/cache_controller_tb.vvp \
    rtl/cache_controller.v tb/cache_controller_tb.v
$ vvp sim/cache_controller_tb.vvp

--- Cache Controller Unit Verification ---
[PASS] Reset State: IDLE (state=000, ready=1)
[PASS] Standalone Hit Path: Word 2 selected accurately (0xcccc3333)
[PASS] Returned to IDLE cleanly.
[PASS] MEM_REQUEST pulse: Aligned Addr=0xb0000240, mem_req_val=1
[PASS] REFILL control signals verified (write_en=1, valid=1, data matched).
[PASS] Standalone Miss Path: Word 3 selected accurately (0x4444ffff)
[PASS] ALL UNIT TESTS COMPLETED SUCCESSFULLY.
```

---

## 3. Waveform Artifacts

The simulation produces value change dump files at:
- `sim/cache_top_tb.vcd` (Top-level full trace)

Signals tracked in the trace include:
- `dut.clk`, `dut.rst_n`
- `dut.cpu_req_val`, `dut.cpu_req_addr`, `dut.cpu_req_ready`
- `dut.cpu_resp_val`, `dut.cpu_resp_data`
- `dut.fsm_state` (`STATE_IDLE` -> `STATE_LOOKUP` -> `STATE_MEM_REQUEST` -> `STATE_MEM_WAIT` -> `STATE_REFILL` -> `STATE_RESPOND`)
- `dut.hit_out`, `dut.miss_out`
- `dut.u_cache_storage.valid_array`, `dut.u_cache_storage.tag_array`
- `dut.bus_mem_req_val`, `dut.bus_mem_req_ready`, `dut.bus_mem_resp_data`
