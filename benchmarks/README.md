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
cards on a multi-GPU host are left idle. Allocation is reported as bytes, and its
post-change totals were reproduced on both tested systems. The concurrency step is
the one exception: its concurrent arm is launched multi-threaded (`-t auto`;
override with `JTHREADS=N`) so the per-transformation solves can overlap. Expect a
few hours end to end, dominated by per-process JIT and the 2048-spin cells. Raw
CSVs are written incrementally, so a failed step keeps completed work. Individual
drivers can also be run by hand via their `ENV` variables (see each file's header).

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
- **`crossover.pdf` / Table 2**: `crossover.csv`.
- **Table 1** (concurrency): `concurrency.csv`, giving median ratios, hand-filled into the LaTeX table (it is a table, not a figure).
- **`allocation.pdf`** (Fig. 3): `alloc.csv` (the `alloc_GiB` rows; the figure is bytes-only).
- **Prose, contraction error control**: `eps_stats.csv` (the bond-limited flag
  counts only bond-capped truncations discarding more than `NEGLIGIBLE_DISCARD =
  1e-12`, the manuscript's $10^{-12}$ reporting threshold), giving Σε = 3.1e-4 / 5.6e-14,
  18-of-18 vs 0-of-4 bond-limited, 108/307 and 192/592 kept/offered, both arms
  E = −210.933334. Deterministic and device-independent (CPU = GPU).
- **Prose, profiling**: `profile.csv` — on the H100, GPU busy 6.6%, host CUDA-API
  share 27.0% (the manuscript's "about a quarter"), remainder 66.5% host-side
  Julia work, kernel-batching ceiling 1.37× (the manuscript's ≈1.4×), 35,945
  device activities. Profiling adds overhead, so the fractions are taken against
  the profiled span, not the unprofiled `wall_s`.
- **Prose, β ladder**: `ladder_raw.csv`, five interleaved rounds on the Xeon
  Platinum 8462Y+ (named in the header comment; the machine of Tables 1–2).
  Energies (−3334.0801, −3336.7734, −3336.7734) and the cold-arm Σε (3.2e-3,
  1.7e-4, 1.9e-5) reproduce on any machine, and warm rungs report Σε = 0 by
  construction. The quotable timings are the medians of paired per-round
  cold/warm ratios (the driver prints them). Rung 1, cold in both arms, medians
  1.01, which is the protocol-cleanliness check; the warmed rungs median 1.32
  and 1.34 (≈25% faster), or ≈16% over the whole ladder. Absolute rung times
  varied 23–38 s across rounds on the same machine, so quote ratios, not
  seconds.

## Protocol notes

- **Interleaved paired ratios.** All speed-up figures are medians of per-round
  paired ratios from an interleaved A/B loop, with a full `GC.gc(true)` (and
  `CUDA.reclaim()` on device) before *every* timed section. A naive protocol
  (warm up, time all A, then all B) left the CUDA memory pool in whatever state
  the previous arm produced, inflating one serial baseline by up to 2.7×
  (14.3 s vs 38.8 s for identical work) and fabricating an apparent 1.68×
  speed-up where the corrected protocol showed 0.92×. This is the manuscript's
  "methodological caution".
- **`max_states` is held at 128 in the crossover** because the branch-and-bound
  search runs on the host in both arms: a larger value adds the same absolute
  time to both and pushes the ratio toward 1 without the device doing the tensor
  work any better.
- **Run timings on an idle machine.** One run executed concurrently with the
  full test suite returned a different (better) energy for 1 of 30 points; RNG
  seed, BLAS reduction order, and batch sizing were tested and eliminated as
  causes. Aside from that anomaly, six seeds and five BLAS thread counts
  reproduced energies bit-for-bit.

## Allocation (bytes-only)

Figure 3 reports **allocated bytes** before/after the two changes (single-matrix
branched-configuration set; off-heap contraction temporaries). The post-change totals
were **reproduced on both tested systems**; on the H100 system the 2048-spin bond-32
solve allocated 32.3 GiB on CPU and 24.1 GiB on GPU.

`alloc.jl` profiles one code state (tagged by `LABEL`); `run_all.sh` records the
current (`after`) numbers in `alloc_raw.csv`, and `alloc.jl` at `LABEL=before` on a
pre-change checkout gives the `before`. The committed `alloc.csv` keeps the
`change,device,metric,before,after` format (`change` ∈ {`branch_states`,`temporaries`},
`device` ∈ {`CPU`,`GPU`}, `metric` ∈ {`wall_s`,`gc_s`,`alloc_GiB`}); the figure uses
only the `alloc_GiB` rows. Its `before` figures were measured against earlier code and
are not driver-regenerated; the committed results record the tested environments.

## Recorded measurements (not re-runnable from v2.0.0)

These back manuscript prose but measure the **superseded code**, so no driver of
the current release can regenerate them: the line or the code state they describe
no longer exists. They were taken on the RTX 5080 dev machine (20 logical cores,
BLAS on 12 threads), branch `lp/monorepo`, base commit `a07a54c` plus the update.
Allocated **bytes** do not depend on the host or device model, which is the same
argument the allocation figure rests on, so the byte shares below are not
5080-specific; only the concurrency result at the end is.

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
- **RTX 5080 concurrency (negative result)**: on the consumer GPU the
  concurrent sweep never beat the serial loop (0.68–0.94× at every admission
  level, ~10% device utilization; the limit is CUDA API/allocator
  serialization with this solver's many small kernels). This is why
  `concurrency = :auto` stays at 1 on any GPU. Table 1's positive GPU numbers
  are the H100 run committed in `concurrency_raw.csv`.

## Provenance of the committed CSVs

| Dataset | Machine |
|---|---|
| `crossover_raw.csv`, `concurrency_raw.csv`, `alloc_raw.csv` (after-arms) | Xeon Platinum 8462Y+ + one NVIDIA H100 |
| `sweep50_cpu.csv`, `div3.csv`, `div3_extra.csv` | Xeon Platinum 8462Y+ (H100 server), CPU |
| `xtransform.csv` | reproduced byte-for-byte on the H100 server (see `xtransform_multithread.csv`) |
| `xtransform_multithread.csv` | H100 server, multithreaded re-run; byte-identical to `xtransform.csv`, kept as the cross-machine determinism check. `makefigs.py` reads `xtransform.csv` |
| `profile.csv` | Xeon Platinum 8462Y+ + one NVIDIA H100 |
| `eps_stats.csv` | device-independent (verified CPU = GPU) |
| `ladder_raw.csv` | Xeon Platinum 8462Y+ (H100 server), 5 interleaved rounds |

Pin the package to the tagged `v2.0.0` release for a citable run.
