# SoftwareX software-update manuscript for SpinGlassPEPS.jl

Draft of a SoftwareX **Software Update** article covering everything since the
published version (v1.4.1, SoftwareX **31** (2025) 102257).

```
softx/v_1/             SoftwareX submission version (official update template,
                       v6, March 2026). Includes the main manuscript and the
                       standalone SupplementMethods.tex wrapper. run.sh builds
                       the two PDFs, benchmark-data archive and LaTeX-source
                       archive
arxiv/v_1/             arXiv version: line numbering removed and the same
                       supplementary content included under \appendix. run.sh
                       builds the manuscript and arxiv-submission.zip (tex +
                       .bbl + supplementary source + figures + ancillary data)

benchmarks/            runnable drivers + committed raw/summary results behind every
                       figure, table, and prose number (see benchmarks/README.md)
figures/               where benchmarks/makefigs.py renders the figures; copy them
                       into a version folder when preparing a revision
```

There is no working copy at the root: each version folder is self-contained and
frozen, and the next revision starts by copying the previous one (`softx/v_1` →
`softx/v_2`). Build either version with its own `run.sh`:

```sh
cd softx/v_1 && ./run.sh      # journal PDFs and upload archives
cd arxiv/v_1 && ./run.sh      # arXiv PDF and arxiv-submission.zip
```

The SoftwareX build produces four upload items: `manuscript.pdf`,
`SupplementMethods.pdf`, `BenchmarkData.zip` and `SourceFiles.zip`. The first
two are the manuscript and the file captioned Supplementary Material 1. The
benchmark archive is captioned Supplementary Data 1. Editorial Manager item
types are journal-configured, so select the available supplemental type and a
non-unpacking archive type for `BenchmarkData.zip`. Select `LaTeX source files`
for `SourceFiles.zip` when that exact type is offered. Do not classify the source
archive as supplementary material. Built PDFs and archives are gitignored
because the run scripts regenerate them. The source archive is flat, as required
by Elsevier's LaTeX instructions.

The arXiv PDF contains the full supplement as Sections S1--S5 after the
`\appendix` command. Its upload archive includes `supplementary-content.tex`,
the required `manuscript.bbl`, and `benchmarks/` as ancillary files.

Every benchmark is runnable from `benchmarks/` and its results are committed
there as CSVs; `benchmarks/makefigs.py` regenerates the manuscript figures into
`figures/`. The few values that cannot be re-run from v2.0.0 by definition (the
pre-change arms of the before/after comparisons, which measure the superseded
code) are recorded with their protocol in `benchmarks/README.md`.

Building needs `elsarticle.cls`, present in TeX Live. Both versions compile with
**zero** undefined references or citations.

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

1. **Zenodo deposit authorship (optional).** The v2.0.0 record's creator list is
   auto-generated from GitHub contributors and includes raw usernames
   (`annamariadziubyna`, `zpuchala`); worth curating on Zenodo since that record
   is the citable archive.
2. **Select the benchmark archive item type before upload.** Editorial Manager
   unpacks ZIP files by default. Use the journal's non-unpacking supplementary
   archive type if it is available. Otherwise upload the data files individually
   or deposit the archive in a data repository and cite its DOI. Upload
   `SupplementMethods.pdf` separately, use the caption Supplementary Material 1,
   and select the supplemental item type offered by the journal.

*Done:* v2.0.0 is tagged, released, registered in the Julia General registry, and
archived on Zenodo (`10.5281/zenodo.22134580`, pinned in `refs.bib`). C1 names a
real release, C2 points at `/tree/v2.0.0`, and C7 at the deployed `/v2.0.0/` docs
(`DOCUMENTER_NEWEST = v2.0.0`; `/stable/` now serves the same build). The package
README badge now displays and links to the concept DOI
`10.5281/zenodo.14627392`.

*Settled:* authorship (Łukasz Pawela and Bartłomiej Gardas, i.e. the authors of
the update; the other names on the 2025 article authored the original package);
acknowledgements (NCN Sonata Bis 10, No. 2020/38/E/ST3/00269, B.G., and Sonata
Bis 15, No. 2025/58/E/ST6/00422, Ł.P., carried over from the bruteforce SoftwareX
paper); the official template port; the ~100-word abstract.

## Claims a reviewer may probe, and where they come from

The main concurrency table and Supplementary Table S1 recompute from committed
raw CSVs via the supplied summarizers. The other numerical supplementary tables
are direct summaries of committed CSV records. `makefigs.py` regenerates the
figures byte-identically from those records. The
contraction-error examples and the β-ladder result quoted in prose have their own
drivers (`eps_stats.jl`, `ladder.jl`, `profile.jl`) with committed results. What
remains recorded-only (with protocol, in `benchmarks/README.md`) is what cannot be
re-run from v2.0.0: the 52.7% allocation share of the `branch_states` line as
published, the pre-change arms of the allocation comparison, and the 2.7× warm-up
caution. All of those measure the superseded code.

- **The single-GPU concurrency result is device-dependent, and the manuscript says
  which device.** On the H100 the concurrent sweep pays (1.69×/1.44× at c=2/c=4,
  Table 1). The package retains a conservative default of one solve on GPU. An
  older consumer-GPU result is kept only as an explicitly unarchived historical
  observation in `benchmarks/README.md`, not as quantitative evidence in the
  manuscript.
- **The timing artifact is documented in the supplement.** An earlier measurement
  reported a spurious 1.68× speed-up after the serial arm ran immediately after a
  concurrent warm-up. The supplementary protocol notes explain the interleaving
  and memory-pool reclamation used for all reported ratios.

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
eliminating them entirely caps at ≈1.4×; the majority of a solve is host-side Julia
work. Reducing allocation returned more, for far less effort. Recorded here because
"batch the kernels" is the intuitive next step and the measurements say otherwise.
