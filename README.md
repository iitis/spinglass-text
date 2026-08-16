# SoftwareX software-update manuscript — SpinGlassPEPS.jl

Draft of a SoftwareX **Software Update** article covering everything since the
published version (v1.4.1, SoftwareX **31** (2025) 102257).

```
softwarex-update.tex   manuscript
refs.bib               bibliography
measurements.md        provenance for every number quoted in the manuscript
benchmarks/            measurement drivers, raw data, figure scripts (see benchmarks/README.md)
figures/               generated figures included by the manuscript
```

Build (needs `elsarticle.cls`, present in TeX Live):

```sh
latexmk -pdf -bibtex softwarex-update.tex   # run twice; refs resolve on the 2nd pass
```

Currently compiles with **zero** undefined references or citations. The
description section is **839 words of prose plus one table**, i.e. about two pages
at the ~500 words/page implied by SoftwareX's own "3000 words ≈ 6 pages" guidance
for original publications, which is the template's allowance for an update.

## Template compliance

The template (v6, March 2026,
<https://legacyfileshare.elsevier.com/promis_misc/softwarex-software-update-template.docx>)
mandates: title of the form `Version [number] - [title of first publication]`; a
"Refers to" citation with the original DOI; ~100-word abstract; ≤6 keywords; the
C1–C8 metadata table; ≤2 pages of description. All are present, in that order.

SoftwareX states it will only consider articles submitted **using their template**.
This draft is built on `elsarticle` because the branded LaTeX container was not
retrievable (the `legacyfileshare` LaTeX URLs 404; only the `.docx` is public).
Before submission, either obtain the official LaTeX template from the Guide for
Authors and move these sections across unchanged, or fill the `.docx`. The section
order and headings here match it, so this should be mechanical.

Also mandatory and already satisfied by the repository: a documented `README.md`
and a licence file, and a **GitHub** URL in C2 (other hosts are not accepted).

## Decisions you need to make (marked `\todo{}` in red in the PDF)

1. **Tag and register v2.0.0.** Settled: this ships as **2.0.0**, matching
   `Project.toml`. The CHANGELOG's `[Unreleased]` section has been folded into
   `[2.0.0]` accordingly, since no `v2.0.0` tag exists yet (tags currently stop at
   `v1.5.0`). C1 must name a real, tagged, registered release, so the remaining
   action is to tag and register before submission.
2. **Authorship.** Settled: the v2.0.0 update is authored by **Łukasz Pawela** and
   **Bartłomiej Gardas** (the authors of the update). The other names on the 2025
   article authored the original package, not this update.
3. **Acknowledgements.** Placeholder — carry over the funding statements from the
   original article and add anything new.
4. **Zenodo DOI.** The repository README shows a badge for `10.5281/zenodo.3245496`
   but links to `10.5281/zenodo.14627393`. `refs.bib` uses the latter. Reconcile,
   and mint a DOI for the released update version.

*Resolved:* the CPU-vs-GPU claim, previously flagged as the manuscript's
highest-risk statement on the strength of two instances, is now backed by a
14-cell crossover study across three instance sizes, four bond dimensions and both
sparsity modes (Table 2, and `measurements.md`). It has been promoted from a
hedged caveat to a section of its own.

## Claims a reviewer may probe, and where they come from

Every figure in the manuscript is reproducible from `measurements.md`, which
records the protocol and raw numbers. Two points worth being ready for:

- **The negative GPU result is deliberate.** The manuscript states plainly that the
  concurrent sweep does not help on one GPU and explains the mechanism (CUDA
  API/allocator serialization; ~10% device utilization; BLAS policy worth <10%).
  This is stronger than omitting it, and it motivates the stated future direction
  (batching across transformations inside the kernels).
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
