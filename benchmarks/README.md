# Benchmarks and reproducibility

Measurement drivers, raw per-run data and the figure generator behind every number
quoted in the SpinGlassPEPS.jl v2.0.0 software-update manuscript, whether it
appears in a figure, a table or the prose. The drivers run against the package itself
(<https://github.com/euro-hpc-pl/SpinGlassPEPS.jl>, ideally the tagged v2.0.0
release). Every quoted value either regenerates from a driver here, with its
results committed as CSVs, or is listed under **Recorded measurements** below
together with the protocol that produced it.

## Launch everything

Assumes a `SpinGlassPEPS.jl` checkout alongside the `spinglass-text` folder:

```sh
# from spinglass-text/benchmarks/
PKG=../../SpinGlassPEPS.jl GPU=0 SEED=1 ./run_all.sh
```

`run_all.sh` instantiates/precompiles the package env, runs every driver
(regenerating the raw + summary CSVs here), and renders the figures into
`../figures/`. The crossover numbers are **timings**, so they are
measured serially on the single device `GPU=<id>` (clean, uncontended); the other
cards on a multi-GPU host are left idle. Allocation is reported as bytes. The
archived post-change measurements are from the Xeon/H100 system. The concurrency
step is the one exception: its concurrent arm is launched multi-threaded (`-t auto`;
override with `JTHREADS=N`) so the per-transformation solves can overlap. Expect a
few hours end to end, dominated by per-process JIT and the 2048-spin cells. Raw
CSVs are written incrementally, so a failed step keeps completed work. Individual
drivers can also be run by hand via their `ENV` variables (see each file's header).

`SEED` is the base seed. The energy/runtime and within-order diversity drivers
use `SEED + instance`, reseed immediately before every solve, and record the
derived seed in each newly generated CSV row. Reusing one stream per instance
provides common random numbers across search breadth and inverse temperature,
keeps results independent of loop order, and aligns matching configurations in
the two drivers.

## Contents

| File | Role |
|---|---|
| `run_all.sh` | one-shot launcher for the whole suite |
| `crossover.jl` | driver: one CPU/GPU crossover cell, seeded, N reps → `crossover_raw.csv` |
| `summarize_crossover.py` | `crossover_raw.csv` → `crossover.csv` (min-of-reps, `cpu_s`/`gpu_s`) |
| `concurrency.jl` | driver: concurrent-sweep speed-up (Table 1); serial loop vs `sweep_transformations` at limit `c`, paired per-round ratios → `concurrency_raw.csv` |
| `summarize_concurrency.py` | `concurrency_raw.csv` → `concurrency.csv` (median ratios pivoted to `c=1,2,4,8`) |
| `alloc.jl` | driver: host allocation profile (wall/GC/bytes) of a fixed solve, seeded, N reps → `alloc_raw.csv` |
| `sweep50.jl` | driver: energy-vs-runtime sweep over the 50×50 instances → `sweep50_cpu.csv` |
| `spread.jl` | driver: Z₂-quotient solution spread; `BETAS=2.0,4.0,6.0` → `div3.csv`, `BETAS=3.0,8.0` → `div3_extra.csv` |
| `xtransform.jl` | driver: pairwise valley distance across lattice transformations → `xtransform.csv` |
| `eps_stats.jl` | driver: contraction-error diagnostics (Σε, max ε, bond-limited count, kept/offered) on `128power` at D=4/32 → `eps_stats.csv` |
| `ladder.jl` | driver: β-ladder cold vs warm-started boundary MPS (per-rung wall time, Σε, energy), `2048power` bond 16 → `ladder_raw.csv` |
| `profile.jl` | driver: host/device attribution of one solve (GPU busy, host CUDA-API share, kernel-batching ceiling) and the top allocation line → `profile.csv` |
| `makefigs.py` | renders the CSVs to `../figures/{quality,crossover,allocation}.{pdf,png}` |
| `plot50.py` | standalone renderer for `energy_vs_runtime.{pdf,png}` from `sweep50_cpu.csv` (superseded by `makefigs.py`; not used by the manuscript) |
| `energy_vs_runtime.{pdf,png}` | output of `plot50.py` |
| `*.csv` | committed raw / summary data |

Instances: the crossover, eps-stats, and ladder drivers use chimera `chim_3_4_3`
(36), `128power` (128), and `2048power` (2048), shipped in the package's
`test/engine/instances/`; the sweep / spread / transform drivers read the 100
recovered 50×50 instances from the package's `benchmark/instances/square_50x50/`.

## Which dataset feeds which figure/table/number

- **`quality.pdf`** (Fig. 1): `sweep50_cpu.csv`, `div3.csv` + `div3_extra.csv`, `xtransform.csv`.
- **`crossover.pdf`** (Fig. 2) and supplementary Table S1: `crossover.csv`.
- **Table 1** (concurrency): `concurrency.csv`, giving median ratios, hand-filled into the LaTeX table (it is a table, not a figure).
- **`allocation.pdf`** (Fig. 3): `alloc.csv` (the `alloc_GiB` rows; the figure is bytes-only).
- **Prose, contraction error control**: `eps_stats.csv` (the bond-limited flag
  counts only bond-capped truncations discarding more than `NEGLIGIBLE_DISCARD =
  1e-12`, the manuscript's $10^{-12}$ reporting threshold), giving Σε = 3.1e-4 / 5.6e-14,
  18-of-18 vs 0-of-4 bond-limited, 108/307 and 192/592 kept/offered, both arms
  E = −210.933334. The archived file records the deterministic CPU run.
- **Prose, profiling**: `profile.csv` — on the H100, GPU busy 6.6%, host CUDA-API
  coverage 27.0%, and 35,945 device activities. The two coverage intervals may
  overlap. At least 66.5% of the profiled span is outside their union. Removing
  the complete measured API share gives an Amdahl-style ceiling of 1.37×, not an
  observed speed-up. Profiling adds overhead, so the fractions are taken against
  the profiled span rather than the unprofiled `wall_s`.
- **Prose, β ladder**: `ladder_raw.csv`, five interleaved rounds on the Xeon
  Platinum 8462Y+ named in the header comment and used for Table 1 and
  supplementary Table S1.
  Energies (−3334.0801, −3336.7734, −3336.7734) and the cold-arm Σε (3.2e-3,
  1.7e-4, 1.9e-5) are recorded for all five rounds. The warm rungs record
  Σε = 0 because no truncating factorization occurs. This value does not measure
  the warm-start variational gap. The quotable timings are the medians of paired per-round
  cold/warm ratios (the driver prints them). Rung 1, cold in both arms, medians
  1.01, which is the protocol-cleanliness check; the warmed rungs median 1.32
  and 1.34 (24–25% lower wall time), or ≈16% over the whole ladder. Absolute rung times
  varied 23–38 s across rounds on the same machine, so quote ratios, not
  seconds.

## Supplementary results

### Table S1. CPU/GPU crossover

Values are CPU/GPU wall-clock ratios for identical configurations. A value below
one indicates shorter CPU wall time. n.m. indicates not measured.

| Spins | $D=8$ | $D=16$ | $D=32$ | $D=64$ |
|---|---:|---:|---:|---:|
| 36, dense | 0.02 | 0.02 | 0.02 | 0.02 |
| 128, dense | 0.14 | 0.21 | 0.36 | 0.46 |
| 128, sparse | n.m. | n.m. | n.m. | 0.68 |
| 2048, dense | 0.50 | 0.64 | 0.90 | n.m. |
| 2048, sparse | n.m. | 0.78 | 1.45 | n.m. |

All measurements used `Zipper`, `SquareSingleNode`, $\beta=3$ and
`max_states=128`. CPU and GPU arms ran in separate alternating processes on an
Intel Xeon Platinum 8462Y+ and one NVIDIA H100. The raw timings are in
`crossover_raw.csv`, and `crossover.csv` contains the summarized ratios.

### Diversity analysis

The 2500-spin square-lattice instances have no local fields, so every state and
its global spin flip have equal energy. We therefore use the quotient distance
$\min(d,N-d)$. Its maximum is 1250, and the diversity threshold from the
original article is 625. In 49 of 50 runs at `max_states=1024`, the maximum
quotient distance from a returned state to the best state was at most 399. The
exception was instance 1 at $\beta=8$. Its energy was 8.12 above the best energy
among the five fixed-order $\beta$ runs for that instance, and it did not return
the exact global spin flip.

Changing the contraction order produced a broader set of solutions. Four of
five instances yielded two or three valleys across the eight lattice
transformations, with pairwise quotient distances up to 1249. The underlying
data are in `div3.csv`, `div3_extra.csv` and `xtransform.csv`.

## Protocol notes

- **Interleaved paired ratios.** All speed-up figures are medians of per-round
  paired ratios from an interleaved A/B loop. The concurrency driver performs a
  full `GC.gc(true)` and, on device, `CUDA.reclaim()` before every timed section.
  The ladder driver reclaims before each complete cold or warm arm. A naive protocol
  (warm up, time all A, then all B) left the CUDA memory pool in whatever state
  the previous arm produced, inflating one serial baseline by up to 2.7×
  (14.3 s vs 38.8 s for identical work) and fabricating an apparent 1.68×
  speed-up where the corrected protocol showed 0.92×. These development values
  have no retained raw log. Every reported speed-up uses interleaved arms and the
  reclamation protocol described above.
- **`max_states` is held at 128 in the crossover** because the branch-and-bound
  search runs on the host in both arms. Holding it fixed isolates the
  device-dependent contraction work.
- **Run timings on an idle machine.** One run executed concurrently with the
  full test suite returned a different energy for 1 of 30 points. The source of
  the difference remains unresolved, and that run is excluded from the timing
  results.

## Allocation (bytes-only)

Figure 3 reports **allocated bytes** before/after the two changes (single-matrix
branched-configuration set; off-heap contraction temporaries). On the Xeon/H100
system, the post-change 2048-spin bond-32 solve allocated 32.3 GiB on CPU and
24.1 GiB on GPU.

`alloc.jl` profiles one code state (tagged by `LABEL`); `run_all.sh` records the
current (`after`) numbers in `alloc_raw.csv`, and `alloc.jl` at `LABEL=before` on a
pre-change checkout gives the `before`. The committed `alloc.csv` keeps the
`change,device,metric,before,after` format (`change` ∈ {`branch_states`,`temporaries`},
`device` ∈ {`CPU`,`GPU`}, `metric` ∈ {`wall_s`,`gc_s`,`alloc_GiB`}); the figure uses
only the `alloc_GiB` rows. Its `before` figures were measured against earlier code and
are not driver-regenerated. This README records the available development
code-state and protocol context.

## Recorded measurements (not re-runnable from v2.0.0)

These back manuscript prose but measure the **superseded code**, so no driver of
the current release can regenerate them: the line or the code state they describe
no longer exists. They were taken on a development machine (not the H100 server),
branch `lp/monorepo`, base commit `a07a54c` plus the update. The exact machine
configuration and raw development logs were not retained. These values are
historical observations rather than results regenerated by this archive.

- **Allocation attribution** (`Profile.Allocs`, 2% sampling, pre-change code):
  the `branch_states` line = **52.7%** of allocated bytes at 128 spins (70.9%
  at 2048 spins on the GPU path). This is the number that motivated the two
  allocation changes.
- **Pre-change arms of Figure 3** (alternating separate-process paired runs,
  pre-change checkout): the `before` column of `alloc.csv` (92.06/25.05 GiB
  states-change arms, 90.9 GiB temporaries arm). The isolated-kernel result
  behind the manuscript's "no faster in isolation" comes from the same pre-change
  series: `ManualAllocator` was ≈7% *slower* per call, while cutting one
  contraction's footprint from 257.5 MiB to 0.5 MiB.
- **Consumer-GPU concurrency (historical negative result)**: on an unrecorded
  consumer GPU the
  concurrent sweep never beat the serial loop (0.68–0.94× at every admission
  level, about 10% device utilization). No raw log or complete environment record
  is available, so this observation is not used as quantitative evidence in the
  manuscript. Table 1's positive GPU numbers are the H100 run committed in
  `concurrency_raw.csv`.

## Provenance of the committed CSVs

| Dataset | Machine |
|---|---|
| `crossover_raw.csv`, `concurrency_raw.csv`, `alloc_raw.csv` (after-arms) | Xeon Platinum 8462Y+ + one NVIDIA H100 |
| `sweep50_cpu.csv`, `div3.csv`, `div3_extra.csv` | Xeon Platinum 8462Y+ (H100 server), CPU |
| `xtransform.csv` | reproduced byte-for-byte on the H100 server (see `xtransform_multithread.csv`) |
| `xtransform_multithread.csv` | H100 server, multithreaded re-run; byte-identical to `xtransform.csv`. `makefigs.py` reads `xtransform.csv` |
| `profile.csv` | Xeon Platinum 8462Y+ + one NVIDIA H100 |
| `eps_stats.csv` | Xeon Platinum 8462Y+ CPU |
| `ladder_raw.csv` | Xeon Platinum 8462Y+ (H100 server), 5 interleaved rounds |

Pin the package to the tagged `v2.0.0` release for a citable run.
