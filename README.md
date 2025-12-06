# Hardware-Accelerated Conway's Game of Life on FPGA

**High-performance FPGA implementation achieving 2.06 cycles/row at 79 MHz with optimized pipelined FSM and torus topology support.**

---

## Performance Results

| Metric | Value |
|--------|-------|
| **Fmax (Design)** | 78.88 MHz |
| Clock Frequency | 50 MHz (FPGA system limit) |
| **Throughput** | 24.27 M rows/second (at 50 MHz) |
| **Grid Support** | Up to 64×64 (multiples of 8) |
| **Topology** | Torus (wraparound boundaries) |
| **FPGA Platform** | Altera MAX10 (DE10-Lite) |

**Benchmark:** 2M iterations on 64×64 grid completed in **5.28 seconds** (validated on hardware)

---

## Technical Overview

### Architecture

- **Pipelined FSM with interleaved read-write operations:** Achieves 2.06 cycles/row through simultaneous memory access - reading next row while writing previous row. Strategic state decoupling (DBL_LOAD, LST_LOAD states) isolates complex indexing logic from critical READ state.

- **Double-buffering for torus boundary handling:** Stores first two rows (row[0], row[1]) enabling natural write sequence 1,2,...,N-1,0 without modulo operations. Trade-off: 128 DFF cost for 4M cycle savings.

- **Two-stage tree adder processing:** Stage 1 computes vertical column sums (3 cells per column), Stage 2 reuses these sums for horizontal neighbor aggregation. Reduces critical path depth vs. flat summation.

### Performance Optimizations

- **20-bit CGOL lookup mask:** Single-LUT cell evaluation via `M_CGOL[{sum_neighs, i_cell}]` eliminates comparators and subtractor. Modified 9-neighbor rule (includes current cell) avoids subtraction operation.

- **Strategic state decoupling:** Created dedicated DBL_LOAD and LST_LOAD states to offload complex indexing and buffer management from critical READ state. Initially zero-cost within 3-bit binary encoding headroom, achieved 4 MHz improvement by isolating bottleneck logic.

- **One-hot state encoding with bit-masking:** Direct state checking (`if (state[READ_IDX])`) replaces equality comparisons, reducing MUX depth. Additional 1-2 MHz gain at cost of 4 DFF when transitioning from binary encoding.

- **Critical path decoupling:** Dedicated staging signals (e.g., `dbl_load_idx`) break high-fanout paths. Explicit index assignments in LOAD states eliminate dynamic indexing overhead from READ state.

- **Truncated comparisons:** Leverages known grid dimensions (16/32/48/64) for 3-bit MSB comparison instead of full 7-bit equality checks.

- **HW-SW handshake optimization:** Single done signal for N iterations eliminates per-iteration overhead (~16M cycle savings across 2M iterations).

### Optimization Methodology

- **Iterative STA-driven refinement:** Continuous analysis of synthesis reports (STA for timing, MAP for estimates, FIT for actual usage) guided design evolution from 62 MHz → 81.54 MHz peak performance.

- **Signal consolidation via mutual-exclusivity analysis:** Restructured sequential logic by grouping signals based on activation conditions rather than functional boundaries. Result: 7 MHz improvement through reduced MUX depth and control signal fanout.

- **Quantified trade-offs:** Final design trades 2 MHz Fmax (81.54 → 79 MHz) for 2× throughput improvement via HW-SW handshake optimization. All major decisions measured and documented.

---

## Key Features

**Architecture:**
- Pipelined FSM with interleaved READ-WRITE mechanism
- Double-buffering for torus edge handling (eliminates modulo operations)
- Two-stage tree adder: vertical column sums + horizontal neighbor aggregation
- HW-SW handshake optimization (single done signal for N iterations)

**Optimizations:**
- One-hot state encoding with bit-masking for critical path reduction
- Modified CGOL rules (9-neighbor evaluation) eliminates subtractor
- Explicit signal truncation and fanout reduction for timing closure
- Synthesis-aware design: reformulated logic for single-LUT evaluation

---

## Design Highlights

### Pipelined FSM
Achieved 2-cycle-per-row throughput through:
- Interleaved memory read/write operations
- STA-guided strategic state decoupling to minimize critical paths
- Fake initial write for pipeline timing alignment

### Torus Topology
Efficient wraparound handling via:
- Double-buffer storing first two rows (row[0], row[1])
- Write sequence: 1, 2, ..., N-1, 0 (overwrites fake initial write)
- Eliminates expensive modulo operations

### Bit-Masking Optimization
Critical path reduction using 20-bit lookup mask:
```systemverilog
localparam M_CGOL = 20'b0000_0000_0010_1100_0000;
updated_row[i] = M_CGOL[{sum_neighs, i_cell}];
```
Replaces comparators and conditional logic with single-LUT evaluation.

---

## Technical Stack

- **HDL:** SystemVerilog
- **Programming:** C
- **Simulation:** Cadence Xcelium + SimVision
- **Synthesis:** Intel Quartus Prime
- **Resources:** 2,323 LEs (5%), 707 registers (1%)

---

## Design Evolution

This repository represents the culmination of iterative optimization:

**Early Design (75 MHz):**
- 4.2 cycles/row
- Basic pipelined FSM
- No HW-SW handshake optimization

**Final Design (79 MHz):**
- 2.06 cycles/row  
- Full HW-SW handshake (single done signal for N iterations)
- Aggressive STA-driven & Synthesis-aware timing closure optimizations
- ~60 DFF, ~100 LE cost for handshake optimization

Trade-off: Small area increase for 2× throughput improvement.

---

## Documentation

For comprehensive design details, see [`docs/CGOL_Torus_Documentation.pdf`](docs/CGOL_Torus_Documentation.pdf), which covers:
- Complete architectural walkthrough
- State machine design and timing analysis
- Optimization techniques and trade-offs
- Full verification results across all test patterns
- Synthesis reports and timing closure methodology

For synthesis analysis and timing breakdown, see [`reports/README.md`](reports/README.md).

---

## Verification

Validated across 9 test patterns (16×64 to 64×64 grids) with 2M iterations each:
- Functional correctness verified in simulation (Xcelium)
- Hardware validation on FPGA with 7-segment display timing measurement
- All patterns achieve 2.06-2.25 cycles/row (varies by grid dimensions)

---

## About This Project

Developed as part of Intel/WeebitNano-sponsored hackathon with competition 
objectives of minimal clock cycles per row and fastest execution time for 2M 
iterations. Extended beyond requirements to explore timing closure and FPGA 
performance limits through STA-driven, synthesis-aware optimizations.

**Grade:** 100/100

---

## Author

**Daniel Bernath**  
B.Sc. Electrical Engineering (Nanoelectronics & Signal Processing)  
Bar-Ilan University, 2025

[LinkedIn](https://linkedin.com/in/bernathdaniel) | [GitHub](https://github.com/bernathDaniel)
