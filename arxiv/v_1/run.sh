#!/usr/bin/env bash
# Build the arXiv version (v_1) and assemble the upload tarball.
#
# Differences from softx/v_1: line numbering is removed and the reader-facing
# supplementary text is embedded in the manuscript with \appendix.
#
# arXiv does not run BibTeX, so manuscript.bbl MUST be part of the upload.
# benchmarks/ is pulled from the repo root into anc/ as machine-readable arXiv
# ancillary data. The appendix itself is part of manuscript.pdf.
set -euo pipefail
cd "$(dirname "$0")"
latexmk -pdf -bibtex -interaction=nonstopmode manuscript.tex

OUT=arxiv-submission.zip
rm -rf .pkg "$OUT"
mkdir -p .pkg/figures .pkg/anc/figures
cp manuscript.tex manuscript.bbl supplementary-content.tex .pkg/
cp figures/*.pdf .pkg/figures/
cp -r ../../benchmarks .pkg/anc/benchmarks
cp ../../figures/* .pkg/anc/figures/
cp ../../benchmarks/README.md .pkg/anc/README.md
rm -rf .pkg/anc/benchmarks/__pycache__
( cd .pkg && zip -q -r -X "../$OUT" manuscript.tex manuscript.bbl \
    supplementary-content.tex figures anc )
rm -rf .pkg
echo "== $OUT ready ($(du -h "$OUT" | cut -f1)); arXiv limit is 50 MB"
