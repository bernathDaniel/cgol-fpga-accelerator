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

### Architecture Highlights

- **Pipelined FSM with interleaved read-write operations:** Achieves 2 cycles/row steady-state throughput through READ-WRITE ping-pong mechanism with single-port SRAM. Overall 2.06 cycles/row accounts for initial 3-row loading overhead and done state. Fake initial write aligns pipeline timing for seamless interleaved operation.

- **Double-buffering for torus boundary handling:** Stores first two rows (row[0], row[1]) enabling natural write sequence 1,2,...,N-1,0 without modulo operations. Trade-off: 128 DFF cost for 4M cycle savings.

- **Two-stage tree adder processing:** Stage 1 computes vertical column sums (3 cells per column), Stage 2 reuses these sums for horizontal neighbor aggregation. Reduces critical path depth vs. flat summation.

- **20-bit CGOL lookup mask:** Single-LUT cell evaluation via `M_CGOL[{sum_neighs, i_cell}]` eliminates comparators and subtractor. Modified 9-neighbor rule (includes current cell) avoids subtraction operation.

### Performance Optimizations

- **Strategic state decoupling:** Created dedicated DBL_LOAD and LST_LOAD states to separate initial loading phase from steady-state pipeline operation, offloading logic from bottleneck READ state. Initially zero-cost within 3-bit binary encoding headroom (up to 8 states available), achieved 4 MHz improvement by distributing combinational and sequential logic across multiple states.

- **One-hot state encoding with bit-masking:** Bit-masking state checks (`if (state[READ_IDX])`) eliminate decode logic - each state bit directly serves as MUX selector vs. requiring 3-bit comparison in binary encoding. Additional 1-2 MHz gain at cost of 4 DFF when transitioning from binary encoding.

- **Fanout reduction via explicit indexing in LOAD states:** Triple buffer index signals (`triple_buf_*_idx`) drive massive fanout (192+ DFFs across buffers + processing logic). During deterministic loading phase, replaced dynamic indexing with dedicated signals (`dbl_load_idx` toggle, hardcoded `[2]` in LST_LOAD) to reduce fanout on high-utilization nets during critical operations.

- **Truncated comparisons:** Exploited known grid dimensions (16/32/48/64) for 3-bit MSB comparison instead of full 7-bit equality checks.

- **HW-SW handshake optimization:** Single done signal for N iterations eliminates per-iteration overhead (~16M cycle savings across 2M iterations). Final trade-off: sacrificed 2 MHz Fmax (81.54 → 79 MHz) for 2× throughput improvement.

### Optimization Methodology

- **Iterative STA-driven refinement:** Continuous analysis of synthesis reports (STA, MAP & FIT) guided design evolution from 62 MHz → 81.54 MHz peak performance.

- **Checkpoint-based development:** Maintained version control through ~20 design checkpoints, enabling safe experimentation and rollback of unsuccessful optimizations. Systematic iteration from initial working design through peak performance exploration.

- **Signal consolidation via mutual-exclusivity analysis:** Restructured sequential logic by grouping signals based on activation conditions rather than functional boundaries. Result: 7 MHz improvement through reduced MUX width & depth and control signal fanout.

- **Quantified trade-offs:** All major design decisions evaluated with measured impact (e.g., "4 DFF for 4 MHz," "128 DFF for 4M cycles," "2 MHz Fmax for 2× throughput"). Documented trade-off analysis guided optimization priorities throughout development.

---

## Technical Stack

- **HDL:** SystemVerilog
- **Programming:** C
- **Simulation:** Cadence Xcelium + SimVision
- **Development:** Git, Unix/Linux, Shell Scripting
- **Synthesis:** Intel Quartus Prime
- **Resources:** 2,323 LEs (5%), 707 registers (1%)

---

## Documentation

For comprehensive design details, see [`docs/CGOL_Torus_Documentation.pdf`](docs/CGOL_Torus_Documentation.pdf), which covers:
- Complete architectural walkthrough
- State machine design and timing analysis
- Optimization techniques and trade-offs
- Full verification results across all test patterns
- Synthesis reports and timing closure methodology

Synthesis reports (STA, MAP, FIT) available in [`reports/`](reports/) directory.

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
