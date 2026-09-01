#!/usr/bin/env bash
# Build the arXiv version (v_1) and assemble the upload tarball.
#
# Differences from softx/v_1: line numbering is removed and the reader-facing
# supplementary text is included directly in the manuscript with \appendix.
#
# arXiv does not run BibTeX, so manuscript.bbl MUST be part of the upload.
# The appendix is part of manuscript.tex and manuscript.pdf.
set -euo pipefail
cd "$(dirname "$0")"
latexmk -pdf -bibtex -interaction=nonstopmode manuscript.tex

OUT=arxiv-submission.zip
rm -rf .pkg "$OUT"
mkdir -p .pkg/figures
cp manuscript.tex manuscript.bbl .pkg/
cp figures/*.pdf .pkg/figures/
( cd .pkg && zip -q -r -X "../$OUT" manuscript.tex manuscript.bbl \
    figures )
rm -rf .pkg
echo "== $OUT ready ($(du -h "$OUT" | cut -f1)); arXiv limit is 50 MB"
