# SoftwareX software-update manuscript for SpinGlassPEPS.jl

Draft of a SoftwareX **Software Update** article covering everything since the
published version (v1.4.1, SoftwareX **31** (2025) 102257).

```
softwarex-update.tex   manuscript (built on the official update template, v6, March 2026)
refs.bib               bibliography
figures/               generated figures included by the manuscript
benchmarks/            runnable drivers + committed raw/summary results behind every
                       figure, table, and prose number (see benchmarks/README.md)
```

Every benchmark is runnable from `benchmarks/` and its results are committed
there as CSVs; `benchmarks/makefigs.py` regenerates the manuscript figures into
`figures/`. The few values that cannot be re-run from v2.0.0 by definition
(profiling attribution and the pre-change arms of before/after comparisons, both
of which measure the superseded code) are recorded with their protocol in
`benchmarks/README.md`.

Build (needs `elsarticle.cls`, present in TeX Live):

```sh
latexmk -pdf -bibtex softwarex-update.tex   # run twice; refs resolve on the 2nd pass
```

Compiles with **zero** undefined references or citations.

## Template compliance

The manuscript is built directly on the official SoftwareX software-update LaTeX
template (v6, March 2026,
<https://legacyfileshare.elsevier.com/promis_misc/softwarex-software-update-template.tex>),
with the template's instruction header and `\uline{}` placeholders removed as the
template directs. It mandates: title of the form
`Version [number] - [title of first publication]`; a "Refers to" citation with the
original DOI; ~100-word abstract; ≤6 keywords; the C1–C8 metadata table; the
description of the update. All are present, in that order, plus the template's
`\linenumbers`.

The description section runs longer than the template's "up to two pages of text"
allowance. Deliberate: reviewers tend to ask for extensions, and the journal-wide
cap (4000 words, ≤6 figures) is respected with room to spare.

Also mandatory and already satisfied by the repository: a documented `README.md`
and a licence file, and a **GitHub** URL in C2 (other hosts are not accepted).

## Remaining pre-submission actions

1. **Tag and register v2.0.0.** This ships as **2.0.0**, matching `Project.toml`;
   tags currently stop at `v1.5.0`. C1 must name a real, tagged, registered
   release: push the `lp/monorepo` work, merge, tag `v2.0.0`, register in the
   Julia General registry. (Marked as a `%% TODO` comment in the tex header.)
2. **Zenodo DOI.** The manuscript now cites the **concept DOI**
   (`10.5281/zenodo.14627392`, always resolves to the latest deposit) and says
   "the package is archived on Zenodo", which is true today. Once the v2.0.0 tag
   mints a new deposit, optionally pin the version-specific DOI in `refs.bib`
   (marked as a TODO comment there). Also reconcile the repo README badge, which shows
   `10.5281/zenodo.3245496` while linking `10.5281/zenodo.14627393`.

*Settled:* authorship (Łukasz Pawela and Bartłomiej Gardas, i.e. the authors of
the update; the other names on the 2025 article authored the original package);
acknowledgements (NCN Sonata Bis 10, No. 2020/38/E/ST3/00269, B.G., and Sonata
Bis 15, No. 2025/58/E/ST6/00422, Ł.P., carried over from the bruteforce SoftwareX
paper); the official template port; the ~100-word abstract.

## Claims a reviewer may probe, and where they come from

Every figure and table is reproducible from `benchmarks/`: both tables recompute
bit-for-bit from the committed raw CSVs via the summarizers, and `makefigs.py`
regenerates the figures byte-identically from the committed CSVs. The
contraction-error examples and the β-ladder result quoted in prose have their own
drivers (`eps_stats.jl`, `ladder.jl`) with committed results. What remains
recorded-only (with protocol, in `benchmarks/README.md`) is what cannot be re-run
from v2.0.0: the profiling attribution (52.7% allocation share, ~quarter CUDA-API
share and the ≈1.3× cap), the pre-change arms of the allocation comparison, and
the 2.7× warm-up caution. All of those are measurements of the superseded code, or
one-off profiler sessions.

- **The single-GPU concurrency result is device-dependent, and the manuscript says
  which device.** On the H100 the concurrent sweep pays (1.69×/1.44× at c=2/c=4,
  Table 1); on a consumer RTX 5080 it never beat the serial loop (0.68–0.94×,
  benchmarks/README.md “Recorded measurements”), which is why the package keeps `concurrency = :auto` at 1 on
  GPU. Table 1's caption names the H100.
- **The methodological caution is included on purpose.** An earlier version of our
  own measurement reported a 1.68× speed-up that did not exist, caused by timing
  the serial arm immediately after a concurrent warm-up. Reporting this protects
  the paper's other performance numbers and is useful to anyone benchmarking this
  solver.

## Not covered by this manuscript

Deliberately out of scope, and listed here so they are not forgotten:

- The original paper's own benchmark set (50×50×1 and 50×50×2 square-lattice-with-
  diagonals versus SBM and CPLEX). `benchmark/run.jl` covers only Chimera-family
  cases; those instances are not in the repository. A figure overlaying published
  Fig. 3 would be the strongest possible evidence for this update and is not yet
  possible.
- Pegasus/Zephyr benchmark coverage.
- Warm starting the top boundary MPS (`mps_top`); recording the variational
  optimization gap so error control also applies to warm-started rows.
- The allocator treatment for the sparse contraction path. The crossover data says
  sparse at bond ≥32 is precisely where the GPU earns its keep, so this is where
  remaining allocation work would matter most.

**Kernel-level batching across transformations was investigated and dropped**, and
the manuscript says so rather than listing it as future work. The device sits mostly
idle, but host-side CUDA API calls account for only about a quarter of wall time, so
eliminating them entirely caps at ≈1.3×; the majority of a solve is host-side Julia
work. Reducing allocation returned more, for far less effort. Recorded here because
"batch the kernels" is the intuitive next step and the measurements say otherwise.
