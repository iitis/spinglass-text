# Provenance for the numbers in the manuscript

Hardware: 20 CPU cores, BLAS on 12 threads, NVIDIA GeForce RTX 5080 (15.5 GiB),
Julia 1.12.3, CUDA.jl 5.11.1. Repository at `lp/monorepo`, base commit `a07a54c`
plus the update described here.

## Protocol (important)

All speed-up figures are **medians of per-round paired ratios** from an
**interleaved** A/B loop: within each round, time the serial arm, then the
concurrent arm, with a full `GC.gc(true)` and (on device) `CUDA.reclaim()` before
*every* timed section.

This matters more than the effect being measured. A naive protocol — warm up, time
all serial repetitions, then all concurrent ones — gave a serial baseline varying
between 3.07 s and 5.76 s for identical work on one case, and 14.3 s versus 38.8 s
on another (2.7×), because whatever ran immediately before left the CUDA memory
pool in a different state. That protocol produced an apparent 1.68× / 1.06×
speed-up where the corrected protocol shows 0.92× / 0.88×. Any future performance
claim about this solver needs the interleaved form.

## Concurrent sweep over the 8 lattice transformations (Table 1)

Speed-up over the serial loop; `c` is the admission limit. Driver:
`benchmarks/concurrency.jl` (case A = `chim_3_4_3`, SVDTruncate/KingSingleNode, D=16,
β=2; case B = `128power`, Zipper/SquareSingleNode, D=32, β=3).

| case | device | c=1 | c=2 | c=4 | c=8 | rounds |
|---|---|---|---|---|---|---|
| Chimera 3×4×3, D=16, `SVDTruncate`/`Dense` | CPU | 0.52 | 0.87 | 1.32 | **1.76** | 5 |
| Chimera 128power, D=32, `Zipper`/`Dense` | CPU | 0.97 | 1.15 | 1.37 | **1.39** | 5 |
| Chimera 3×4×3, D=16, `SVDTruncate`/`Dense` | GPU | 0.68 | 0.92 | 0.80 | — | 7 |
| Chimera 128power, D=32, `Zipper`/`Dense` | GPU | 0.94 | 0.88 | 0.89 | — | 7 |

Serial medians: CPU 0.07 s and 4.16 s; GPU 3.97 s and 14.30 s.

Paired ratio ranges (GPU, `c=2`): 0.80–1.16 and 0.85–1.05. CPU `c=8`: 1.45–3.0 and
1.31–1.96.

### Why GPU concurrency does not pay

- Overlap *does* occur: Σ(per-solve wall time) / total = 5.23× and 5.43× at c=8.
  Per-solve time degrades at the same rate, so total work is conserved.
- GPU utilization ~10% during the sweep (`nvidia-smi`), so the device is not
  saturated.
- Holding c=8 and varying only the BLAS thread policy: total 9.40 s (divided,
  default) / 8.61 s (full per solve) / 9.82 s (single). ≤10% spread, so BLAS
  oversubscription is not the cause. GC share 7–10% versus 3% serial.
- Conclusion: serialization in the CUDA API/allocator, which this solver provokes
  with many small kernels.

## Device-memory governor

Calibration on the 128power instance, D=32: measured peak 617 MiB → reservation
802 MiB (1.3× headroom) → capacity 11.86 GiB (85% of free) → 3 admitted; observed
`peak_reserved` 1605 MiB (two concurrent), `waits` 0. Consensus 3/3, spread 0.

Small instances can measure a peak of 0 because their allocations stay below the
granularity at which the driver reports free memory; the governor then stands down,
which is correct — such a solve cannot exhaust the device.

## Contraction error control

128power instance, `num_states_cl` = 2^6, `max_states` = 2^4, one transformation:

| bond dim | Σε | max ε | bond-limited | kept/offered |
|---|---|---|---|---|
| D=4 | 3.15e-4 | 2.43e-4 | 18 of 18 | 108 / 307 |
| D=32 | 5.56e-14 | 5.51e-14 | 0 of 4 | 192 / 592 |

Both find E = −210.933334, i.e. D=4 already sufficed here — the diagnostic reports
how much margin there was, which was previously unobservable.

## β ladder with warm-started boundary MPS

2048power instance (16×16×8, `num_states_cl` = 2^8), `Zipper`/`Sparse`, bond 16,
β = 1.5, 2.25, 3.0, single run each:

| | total | per-rung wall time | Σε per rung |
|---|---|---|---|
| cold | 147.8 s | 50.07, 48.24, 49.34 | 3.2e-3, 1.69e-4, 1.89e-5 |
| warm | 133.6 s | 50.67, 41.67, 41.22 | 3.2e-3, 0, 0 |

Identical energies (−3334.0801, −3336.7734, −3336.7734). ≈15% per warmed rung
(48.24→41.67, 49.34→41.22); 9.6% over the ladder, diluted by rung 1 which has
nothing to warm from. On a search-dominated instance (128power) the gain is 4–6%
at D=16–48 and nil at D=128.

The zero Σε on warmed rungs is **not** superior accuracy: a warm start optimizes
within a fixed bond dimension and never performs a truncating factorization, so the
error appears as a variational gap that the truncation log does not measure. This is
why the two must not be combined, and why the package warns.

## Test status of the described version

All groups pass on both legs. GPU: tensors 1392, engine 7141, umbrella 542. CPU
(`CUDA_VISIBLE_DEVICES=""`): tensors 795, networks 973, exhaustive pass, engine
7142, umbrella 542. Documentation builds with no missing docstrings and no broken
cross-references.

## Host-side attribution (what actually costs time on the GPU path)

Profiled with `CUDA.@profile` and Julia's samplers on one solve of the 128power
instance, bond 32, `Zipper`/`Dense` (1.73 s wall):

| | |
|---|---|
| GPU busy | 101 ms — **5.85%** |
| Host time inside CUDA API calls | 398 ms — 23% |
| Remainder (~71%) | host-side Julia work |
| Kernel launches | ~34,500 (mean kernel ~3 µs) |
| Host↔device copies | 23,262 (11,191 D2H + 12,071 H2D) |
| Pool allocations | 46,666 |
| Stream synchronizations | 22,382 |
| Busiest kernel | cuTENSOR `contraction_tiny_mnk_kernel`, 4,092 × 3.63 µs |

Excluding parked threads, the non-idle host self-time splits roughly: allocation
~38%, cuTENSOR/CUDA API issuance ~54%, **CPU LAPACK ~3%**. The last figure refuted
our expectation that the CPU-fallback factorizations dominated; they do not.

Allocation profiling (`Profile.Allocs`, 2% sampling) localized the cost to a single
line, `branch_states` in the branch-and-bound search: **52.7% of allocated bytes**,
~3.5M allocations per solve. This is search bookkeeping, not tensor contraction.

### Effect of the fix

Alternating separate-process paired runs, 5 timed solves each, medians:

| device | arm | wall | allocations |
|---|---|---|---|
| GPU | old | 1.11 s | 0.7354 GiB |
| GPU | new | 1.02–1.04 s | 0.5705 GiB (**−22.4%**) |
| CPU | old | 0.3574 s | 1.3563 GiB |
| CPU | new | 0.3169 s (**1.13×**) | 1.1940 GiB (**−12.0%**) |

Energies identical. The GPU wall-time gain is real but noisy (the old arm spans
1.048–1.129 s); the allocation figures are deterministic.

Two measurement traps encountered here, recorded so they are not repeated: an
in-process A/B that redefines a method with `@eval` inside the running function
does **not** take effect (Julia world age), and reported a spurious 0% difference;
and comparing across separately written scripts is not controlled. Only alternating
separate processes running an identical script gave stable numbers.

## CPU vs GPU by instance size (crossover study)

Same configuration solved on each device, separate alternating processes, 7 timed
solves per cell (2 for the 2048-spin case), `max_states = 128` fixed so the
host-side search cost does not confound the device comparison.
`SquareSingleNode{GaugesEnergy}`, `Dense`, `Zipper`, β = 3. Re-run on the 4×H100
server (Intel Xeon Platinum 8462Y+ + NVIDIA H100); the numbers below (and `crossover.csv`/`crossover_raw.csv`) are that run,
while the other sections of this file are the original RTX 5080 measurements.

| spins | bond | CPU (s) | GPU (s) | CPU/GPU |
|---|---|---|---|---|
| 36 (3×4×3) | 8 | 0.007 | 0.365 | 0.02 |
| 36 | 16 | 0.008 | 0.366 | 0.02 |
| 36 | 32 | 0.007 | 0.361 | 0.02 |
| 36 | 64 | 0.008 | 0.361 | 0.02 |
| 128 (4×4×8) | 8 | 0.121 | 1.031 | 0.12 |
| 128 | 16 | 0.170 | 0.840 | 0.20 |
| 128 | 32 | 0.263 | 0.858 | 0.31 |
| 128 | 64 | 0.374 | 0.842 | 0.44 |
| 2048 (16×16×8) | 8 | 17.08 | 36.03 | 0.47 |
| 2048 | 16 | 22.07 | 33.28 | 0.66 |

Ratios below 1 mean the host path is faster. Energies agree exactly in every cell
(−16.4, −210.933334, −3336.773383), so both paths compute the same thing.

**The CPU path is faster in every cell of this bond-16 sweep**, by ~45× at 36 spins
narrowing to ~1.5× at 2048 spins and bond 16. The ratio rises with both instance
size and bond dimension; extending to bond 32 (see `crossover.csv`) the device
overtakes the host only in the largest sparse case — 2048 spins, bond 32, GPU ~1.4×
faster (ratio 1.42) — while the dense case at that size still favours the host
(0.91).

Note the direction of the `max_states` bias: the branch-and-bound search is
host-side on both devices, so a larger `max_states` adds roughly the same absolute
time to both arms and pushes the ratio toward 1 *without* the device doing the
tensor work any better. Holding it at 128 therefore isolates the device-sensitive
part rather than flattering either arm.

Caveats: one consumer GPU (RTX 5080); `Dense` only in the table above (the
`Sparse` path, which Pegasus and Zephyr use and whose kernels are batched
differently, is measured separately); one geometry and strategy.

## Allocation reductions

Both measured with alternating separate-process paired runs on the 2048-spin
instance, bond 32, `max_states = 128`; medians. Energies identical
(−3336.773383) throughout.

### Matrix-backed branched configurations (`branch_states_view`)

| device | wall | allocations | GC |
|---|---|---|---|
| GPU | 26.62 → 23.00 s (**1.157×**) | 25.05 → 23.96 GiB (−4%) | 4.97 → 3.16 s (−36%) |
| CPU | 25.10 → 23.61 s (1.063×) | 92.06 → 91.05 GiB (−1%) | 8.23 → 7.50 s |

Note the shape of this result: allocated *bytes* barely move, while GC falls 36% and
wall time improves 16% on GPU. Collection cost tracks the number of live objects,
not their volume, and the previous form created one small vector per branched state —
tens of thousands per call. This site is 70.9% of host-allocated bytes on the GPU
path (52.7% at 128 spins), the largest single allocation source in a solve.

### Contraction temporaries off the collected heap (`ManualAllocator`)

Applied to the seven multi-tensor contractions in `contractions/dense.jl`, selected
per call so device arrays keep the default allocator (`ManualAllocator` returns host
memory).

| scope | device | wall | allocations | GC |
|---|---|---|---|---|
| 2 kernels | CPU | 23.12 → 20.24 s (1.142×) | 91.0 → 42.6 GiB (−53%) | 7.17 → 5.14 s |
| 7 kernels | CPU | 24.17 → 19.35 s (**1.249×**) | 90.9 → 32.0 GiB (**−65%**) | 7.66 → 4.20 s |
| 7 kernels | GPU | 22.88 → 22.29 s (1.027×) | unchanged | 3.13 → 2.88 s |

In isolation `ManualAllocator` is ~7% *slower* per call (malloc/free versus Julia's
bump allocator) and reduces one representative contraction's footprint from
257.5 MiB to 0.5 MiB — only the output stays GC-managed. The end-to-end gain is
therefore entirely the collection it avoids, which is why it had to be measured in a
full solve rather than a microbenchmark. The GPU figure is within noise of neutral,
as intended: the selector keeps the device path on the default allocator.

## Solution spread and diversity (Figure 2d)

Scripts `figures/spread.jl` (within one contraction order) and
`figures/xtransform.jl` (across the eight lattice transformations); data
`div3.csv`, `div3_extra.csv`, `xtransform.csv`.

**The Z2 gauge is not optional here.** All 100 shipped `square_50x50` instances
have zero local fields (verified: no nonzero self-coupling line in any file), so
`E(s) = E(-s)` exactly and every state has a degenerate mirror at Hamming
distance `N`. The published Fig. 3(c) diversity metric — solutions within
approximation ratio 0.01, pairwise Hamming distance `> N/2` — therefore scores
that mirror as a second solution for free, and returns 2 in 29 of 30 runs on this
family. The number carries no information about the solver.

**Fixing the gauge by pinning a spin is a trap, and we fell into it.** Mapping each
state to the representative with `s[1] = +1` sends a state that differs from the
mirror *at spin 1* to the wrong representative: it lands ~`N` away instead of ~0.
That produced three spurious "distinct valleys" (instances 3 and 6, distances
2463--2498) which do not exist. Use the quotient distance, which needs no gauge
choice:

    dq(a,b) = min(d(a,b), N - d(a,b))        in [0, N/2]

With it, the quotient diversity is 1 in all 50 within-order runs.

| | within one order | across 8 transformations |
|---|---|---|
| states compared | 1024 | 8 (one per transformation) |
| distinct valleys (`dq > N/4`) | 1, in all 50 runs | 2--3 on 4 of 5 instances |
| median distance to best | 10--70 | 86--971 |
| max pairwise distance | 11--190 | 355--1249 (of 1250) |

Cross-transformation states are decoded to Ising spins with
`decode_potts_hamiltonian_state`, which zips against the *untransformed* vertex
order — so it is not obviously transformation-aware. Verified before use: all
eight transformations reproduce their reported energy from the decoded spins, on
`3x3x2`, and the same check runs inline for all 40 solves here.

One case clears the `N/4` threshold within a single order (instance 1, β=8). It is
a degraded contraction, not a second optimum: its energy is 8 above that
instance's best and it fails to return even the exact mirror. It is marked
separately in the figure rather than averaged in.

## Reproducibility of the solver

`Zipper` draws a random sketch for its randomized range finder from the global RNG
(`src/tensors/zipper.jl:77`, both CPU and GPU); `sweep_transformations` seeds per
task, a bare `low_energy_spectrum` does not. In testing the range finder was not
fragile — six seeds and five BLAS thread counts (1--12) returned the same energy to
the last bit, and two independent full runs of the 30-point spread measurement
agreed on 30/30 energies bit-for-bit.

One anomaly is on record and unexplained: a run executed under heavy load
(concurrent with the full test suite) returned a different, *better* energy for one
of 30 points (instance 2, β=2: -1965.2314 against -1964.6078 in 19 other
observations). RNG seed, BLAS reduction order, CPU batch sizing (fixed at 4 GiB,
not load-dependent) and script configuration were each tested and eliminated. Run
measurements on an idle machine.
