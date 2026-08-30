#!/usr/bin/env bash
# Build the SoftwareX submission files. The explanatory supplement and benchmark
# archive are separate upload items. LaTeX sources remain a third item.
set -euo pipefail
cd "$(dirname "$0")"

latexmk -pdf -bibtex -interaction=nonstopmode manuscript.tex
latexmk -pdf -interaction=nonstopmode SupplementMethods.tex

STAGE=.submission-package
DATA=BenchmarkData.zip
SOURCE=SourceFiles.zip
rm -rf "$STAGE" "$DATA" "$SOURCE"
mkdir -p "$STAGE/data" "$STAGE/source"

cp -r ../../benchmarks "$STAGE/data/benchmarks"
cp -r ../../figures "$STAGE/data/figures"
cp ../../benchmarks/README.md "$STAGE/data/README.md"
rm -rf "$STAGE/data/benchmarks/__pycache__"
( cd "$STAGE/data" && zip -q -r -X "../../$DATA" README.md benchmarks figures )

cp manuscript.tex manuscript.bbl refs.bib SupplementMethods.tex \
   supplementary-content.tex "$STAGE/source/"
cp figures/*.pdf "$STAGE/source/"
( cd "$STAGE/source" && zip -q -r -X "../../$SOURCE" \
    manuscript.tex manuscript.bbl refs.bib SupplementMethods.tex \
    supplementary-content.tex quality.pdf crossover.pdf allocation.pdf )

rm -rf "$STAGE"

echo "== manuscript.pdf: Manuscript"
echo "== SupplementMethods.pdf: captioned Supplementary Material 1"
echo "== $DATA: captioned Supplementary Data 1"
echo "== select a non-unpacking supplemental archive type for $DATA"
echo "== $SOURCE: item type 'LaTeX source files' when offered"
