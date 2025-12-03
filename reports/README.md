# Synthesis Reports & Timing Analysis

This directory contains complete synthesis reports from Intel Quartus Prime for the final CGOL Torus XLR design.

---

## Summary

**Achieved Performance:**
- **Fmax:** 79.15 MHz (Slow 1200mV 85C Model)
- **Logic Elements:** 2,468 / ~50K available (5%)
- **Registers:** 707
- **Memory Bits:** 1,327,704 / 1.6M available
- **M10K Blocks:** 5

**Target FPGA:** Intel Cyclone V (5CEBA4F23C7)

---

## Key Findings

### Critical Path Analysis

The design achieved timing closure at **79.15 MHz** through systematic optimization:

**Primary Bottlenecks Addressed:**
1. **Fanout Reduction:** Heavy wires like `triple_row_buf_crnt_idx` initially reported as critical—resolved via state decoupling and index signal isolation
2. **MUX Depth Minimization:** One-hot state encoding replaced 3-bit binary, reducing conditional logic depth
3. **Explicit Truncation:** Grid dimensions (16, 32, 48, 64) allowed truncated comparisons using 3 MSBs instead of full 7-bit equality checks

**State-Specific Optimizations:**
- **DBL_LOAD:** Introduced `dbl_load_idx` to decouple triple_row_buf indexing from critical paths
- **LST_LOAD:** Explicit index assignment (idx=2) eliminates dynamic indexing overhead
- **READ State:** Fully decoupled—minimal logic depth through aggressive state separation

### Resource Utilization

| Resource Type | Used | Available | Utilization |
|--------------|------|-----------|-------------|
| ALMs | 23,948 | ~50,000 | ~48% |
| Logic Elements | 2,468 | ~50,000 | ~5% |
| Registers | 707 | ~100,000 | <1% |
| Memory Bits | 1,327,704 | 1,638,400 | 81% |
| M10K Blocks | 5 | 164 | 3% |

**Design Characteristics:**
- Memory-intensive (81% memory utilization for grid storage)
- Logic-efficient (5% LE utilization demonstrates optimized combinational logic)
- Register-light (careful DFF allocation for area-performance trade-offs)

---

## Timing Closure Strategy

### 1. State Machine Optimization

**One-Hot Encoding:**
```systemverilog
typedef enum logic [6:0] {
    IDLE      = 7'b0000001,
    DBL_LOAD  = 7'b0000010,
    LST_LOAD  = 7'b0000100,
    WRITE     = 7'b0001000,
    READ      = 7'b0010000,
    LAST      = 7'b0100000,
    DONE      = 7'b1000000
} state_machine;
```

**Impact:** 4-DFF cost, significant reduction in MUX depth for state transitions.

### 2. Bit-Masking for Comparisons

**Row Completion Check:**
```systemverilog
// Instead of: if (grid_rd_row_idx[6:4] == grid_height[6:4])
// Use truncated comparison knowing dimensions are 16/32/48/64:
if (grid_rd_row_idx[6:4] == grid_height[6:4]) next_state = LAST;
```

**Impact:** Reduced comparator complexity from 7-bit to 3-bit.

### 3. Signal Grouping & Consolidation

Consolidated small signal groups from 2-3 separate always blocks into single blocks based on mutual exclusivity analysis:

**Before:** Split across multiple blocks → high fanout on control signals  
**After:** Grouped by condition → 7 MHz improvement (72 → 79 MHz)

### 4. CGOL Rules Optimization

**Modified Rule Encoding:**
- Traditional: Count 8 neighbors, subtract `i_cell` if alive
- Optimized: Count 9 elements (including `i_cell`), use adjusted thresholds

**20-bit Lookup Mask:**
```systemverilog
M_CGOL = 20'b0000_0000_0010_1100_0000
// Bit index = {sum_neighs[3:0], i_cell}
// Set bits at indices: 6, 7, 9 (binary: 00110, 00111, 01001)
```

**Impact:** Eliminated subtractor, single-LUT evaluation per cell.

---

## Design Iterations

### Version 1: Pre-HW-SW Handshake (81.54 MHz)
- **Performance:** 4.2 cycles/row
- **Resources:** 2,362 LEs, 642 registers
- **Characteristics:** Highest Fmax, but required SW polling per iteration

### Version 2: Final Design (79.15 MHz)
- **Performance:** 2.06 cycles/row
- **Resources:** 2,468 LEs (+106), 707 registers (+65)
- **Characteristics:** Single done signal for N iterations, 2× throughput improvement

**Trade-off Analysis:**
- Cost: ~2.4 MHz Fmax reduction, 106 LEs, 65 registers
- Gain: 50% reduction in cycles/row, eliminated per-iteration HW-SW handshake overhead
- **Conclusion:** Area cost justified by throughput improvement and reduced SW overhead

---

## Report Files Guide

### Timing Reports
- **`cgol_xlr_tor.sta.rpt`** - Full static timing analysis
  - Section 6: Fmax summary (79.15 MHz)
  - Sections 7-11: Setup/hold/recovery analysis per clock domain
  - Section 26: Multicorner timing analysis

### Resource Reports  
- **`cgol_xlr_tor.fit.summary`** - Fitter resource utilization
  - Logic element breakdown
  - Memory bit allocation
  - Pin assignments

- **`cgol_xlr_tor.map.summary`** - Technology mapping results
  - Pre-fitter logic utilization estimates
  - Memory inference results

### Additional Reports
- **`cgol_xlr_tor.flow.rpt`** - Complete compilation flow
  - Analysis & Synthesis → Fitter → Assembler → Timing Analyzer
  - All compilation stages passed with 0 errors

---

## Key Optimization Techniques

**For Future Designs:**

1. **State Decoupling:** Free states are cheap—use them to isolate critical paths rather than consolidating logic
2. **Explicit vs. Inferred:** Explicit signal assignments often synthesize better than inferred behavior
3. **Fanout Management:** Monitor high-fanout signals in synthesis reports; introduce intermediate staging where necessary
4. **Mutual Exclusivity:** Parallel `if` statements for non-mutually-exclusive signals; `if-else` chains for mutually exclusive conditions
5. **Area-Performance Trade-offs:** Strategic DFF allocation (e.g., `dbl_load_idx`) can unlock MHz gains at minimal cost

---

## Timing Margin

**Achieved:** 79.15 MHz  
**FPGA Limit:** ~50 MHz (system clock constraint)

**Headroom:** 29 MHz margin ensures robust operation across:
- Process variation
- Temperature extremes  
- Voltage fluctuations

Design is over-optimized for target platform, demonstrating thorough timing closure methodology.

---

## Verification Notes

All synthesis results validated through:
1. **Gate-level simulation** (post-synthesis netlist)
2. **Hardware testing** (FPGA with 7-segment display timing measurement)
3. **Cross-validation** across 9 test patterns (2M iterations each)

**Measured FPGA Performance:** 2.06-2.25 cycles/row across patterns (consistent with simulation)

---

## References

For complete architectural details and design rationale, see:
- Main project documentation: [`docs/CGOL_Torus_Documentation.pdf`](../docs/CGOL_Torus_Documentation.pdf)
- Source code: [`src/cgol_xlr_tor.sv`](../src/cgol_xlr_tor.sv)
