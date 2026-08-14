# Benchmarks and reproducibility

Measurement drivers, raw per-run data, and the figure generator behind every
figure and table in the SpinGlassPEPS.jl v2.0.0 software-update manuscript. The
drivers run against the package itself
(<https://github.com/euro-hpc-pl/SpinGlassPEPS.jl>, ideally the tagged v2.0.0
release); the numeric provenance for each quoted value is in
[`../measurements.md`](../measurements.md).

## Launch everything

Assumes a `SpinGlassPEPS.jl` checkout alongside the `spinglass-text` folder:

```sh
# from spinglass-text/benchmarks/
PKG=../../SpinGlassPEPS.jl GPU=0 SEED=1 ./run_all.sh
```

`run_all.sh` instantiates/precompiles the package env, runs every driver
(regenerating the raw + summary CSVs here), and renders the figures into
`../figures/`. The crossover and allocation numbers are **timings**, so they are
measured serially on the single device `GPU=<id>` (clean, uncontended); the other
cards on a multi-GPU host are left idle. Expect a few hours end to end —
dominated by per-process JIT and the 2048-spin cells; raw CSVs are written
incrementally so a failed step keeps completed work. Individual drivers can also
be run by hand via their `ENV` variables (see each file's header).

## Contents

| File | Role |
|---|---|
| `run_all.sh` | one-shot launcher for the whole suite |
| `crossover.jl` | driver — one CPU/GPU crossover cell, seeded, N reps → `crossover_raw.csv` |
| `summarize_crossover.py` | `crossover_raw.csv` → `crossover.csv` (min-of-reps, `cpu_s`/`gpu_s`) |
| `alloc.jl` | driver — host allocation profile (wall/GC/bytes) of a fixed solve, seeded, N reps → `alloc_raw.csv` |
| `sweep50.jl` | driver — energy-vs-runtime sweep over the 50×50 instances → `sweep50_cpu.csv` |
| `spread.jl` | driver — Z₂-quotient solution spread; `BETAS=2.0,4.0,6.0` → `div3.csv`, `BETAS=3.0,8.0` → `div3_extra.csv` |
| `xtransform.jl` | driver — pairwise valley distance across lattice transformations → `xtransform.csv` |
| `makefigs.py` | renders the CSVs to `../figures/{quality,crossover,allocation}.{pdf,png}` |
| `*.csv` | committed raw / summary data |

Instances: the crossover uses chimera `chim_3_4_3` (36), `128power` (128), and
`2048power` (2048), shipped in the package's `test/engine/instances/`; the sweep /
spread / transform drivers read the 100 recovered 50×50 instances from the
package's `benchmark/instances/square_50x50/`.

## Which dataset feeds which figure/table

- **`quality.pdf`** (Fig. 1): `sweep50_cpu.csv`, `div3.csv` + `div3_extra.csv`, `xtransform.csv`.
- **`crossover.pdf` / Table 2**: `crossover.csv`.
- **`allocation.pdf`** (Fig. 3): `alloc.csv`.

## Allocation A/B (partly manual)

`alloc.jl` profiles **one** code state (tagged by `LABEL`). Figure 3 compares the
code **before and after** two isolated changes (single-matrix branched-configuration
set; off-heap contraction temporaries) per device. To regenerate `alloc.csv`, run
`alloc.jl` on the relevant pre-change commit(s) of `SpinGlassPEPS.jl` with
`LABEL=before`, and on the current code with `LABEL=after`, then assemble
`alloc.csv` in the `makefigs` format `change,device,metric,before,after`
(`change` ∈ {`branch_states`,`temporaries`}, `device` ∈ {`CPU`,`GPU`},
`metric` ∈ {`wall_s`,`gc_s`,`alloc_GiB`}). `run_all.sh` records the `after` numbers
in `alloc_raw.csv` and leaves the committed `alloc.csv` in place otherwise.

The tested hardware/software and the exact commit for each measurement belong in
`../measurements.md`; pin them to the tagged `v2.0.0` release for a citable run.
