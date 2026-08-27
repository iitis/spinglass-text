#!/usr/bin/env bash
# Build the arXiv version (v_1) and assemble the upload tarball.
#
# Differences from softx/v_1: line numbering removed (arXiv does not accept
# numbered lines). Everything else is identical.
#
# arXiv does not run BibTeX, so manuscript.bbl MUST be part of the upload.
# benchmarks/ is pulled from the repo root into anc/ (arXiv ancillary files)
# rather than duplicated here, keeping one source of truth.
set -euo pipefail
cd "$(dirname "$0")"
latexmk -pdf -bibtex -interaction=nonstopmode manuscript.tex

OUT=arxiv-submission.zip
rm -rf .pkg "$OUT"; mkdir -p .pkg/figures .pkg/anc
cp manuscript.tex manuscript.bbl .pkg/
cp figures/*.pdf .pkg/figures/
cp -r ../../benchmarks .pkg/anc/benchmarks
rm -rf .pkg/anc/benchmarks/__pycache__
( cd .pkg && zip -q -r -X "../$OUT" manuscript.tex manuscript.bbl figures anc )
rm -rf .pkg
echo "== $OUT ready ($(du -h "$OUT" | cut -f1)); arXiv limit is 50 MB"
