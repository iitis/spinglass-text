# Benchmarks and reproducibility

Measurement drivers, raw per-run data, and the figure generator behind every
figure and table in the SpinGlassPEPS.jl v2.0.0 software-update manuscript. The
drivers run against the package itself
(<https://github.com/euro-hpc-pl/SpinGlassPEPS.jl>); the numeric provenance for
each quoted value is in [`../measurements.md`](../measurements.md).

## Contents

| File | Role |
|---|---|
| `sweep50.jl` | driver — energy-vs-runtime sweep over the 50×50 (2500-spin) instances; emits `sweep50_cpu.csv` |
| `spread.jl` | driver — solution spread on the Z₂ quotient (diversity); emits `div3.csv` / `div3_extra.csv` |
| `xtransform.jl` | driver — pairwise valley distance across lattice transformations; emits `xtransform.csv` |
| `sweep50_cpu.csv`, `div3.csv`, `div3_extra.csv`, `xtransform.csv` | raw data produced by the drivers above |
| `crossover.csv` | raw CPU-vs-GPU crossover data; produced by the package benchmark harness (`SpinGlassPEPS.jl/benchmark/run.jl`), not by a driver here |
| `alloc.csv` | before/after wall-time, GC time, and allocated bytes for the two allocation changes |
| `makefigs.py` | renders the CSVs to `../figures/{quality,crossover,allocation}.{pdf,png}` |

## Which figure/table each dataset feeds

- **`quality.pdf`** (Fig. 1, `fig:evr`): panels from `sweep50_cpu.csv`
  (energy vs. runtime), `div3.csv` + `div3_extra.csv` (diversity), and
  `xtransform.csv` (cross-transform distances).
- **`crossover.pdf` / Table 2** (`fig:cross` / `tab:cross`): `crossover.csv`.
- **`allocation.pdf`** (Fig. 3, `fig:alloc`): `alloc.csv`.

## Reproducing

Drivers write their CSV to `$OUT` (default `/tmp/...`); point it at this folder
to refresh the committed data, then render:

```sh
PKG=/path/to/SpinGlassPEPS.jl          # a checkout of the v2.0.0 release

OUT=sweep50_cpu.csv NINST=10 julia --project=$PKG sweep50.jl
OUT=div3.csv                 julia --project=$PKG spread.jl
OUT=xtransform.csv           julia --project=$PKG xtransform.jl
# crossover.csv comes from the package harness: julia --project=$PKG $PKG/benchmark/run.jl

python3 makefigs.py                    # -> ../figures/*.pdf and *.png
```

The tested hardware/software and the exact commit for each measurement are
recorded in `../measurements.md`; pin them to the tagged `v2.0.0` release for a
citable reproduction.

> Not yet committed as executable drivers: the exact `crossover.csv` and
> `alloc.csv` measurement scripts (the numbers were produced with the package
> benchmark harness and an allocation A/B). Add them here to close the last
> reproducibility gap the manuscript notes.
