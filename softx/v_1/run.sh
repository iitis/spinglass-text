#!/usr/bin/env bash
# Build the SoftwareX submission version (v_1). Self-contained: manuscript.tex,
# refs.bib and figures/ live in this directory.
set -euo pipefail
cd "$(dirname "$0")"
latexmk -pdf -bibtex -interaction=nonstopmode manuscript.tex
echo "== built manuscript.pdf; submit this plus refs.bib, figures/ and the"
echo "== benchmarks/ supplementary payload (see ../../benchmarks/)."
