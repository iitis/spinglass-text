#!/usr/bin/env bash
#
# Launch the full benchmark suite behind the SpinGlassPEPS.jl v2.0.0 software-update
# manuscript, regenerate the summary CSVs, and render the figures.
#
# Run from spinglass-text/benchmarks/. Assumes a SpinGlassPEPS.jl checkout alongside
# the spinglass-text folder (../../SpinGlassPEPS.jl), ideally the tagged v2.0.0
# release. Writes raw + summary CSVs here and figures into ../figures/.
#
# Multi-GPU hosts: the crossover/allocation numbers are TIMINGS, so each is measured
# serially on ONE pinned device for a clean, uncontended reading -- set GPU=<id>.
# The other cards are left idle; nothing here benefits from concurrent solves.
#
#   PKG=/path/to/SpinGlassPEPS.jl GPU=0 SEED=1 ./run_all.sh
#
# Runtime: dominated by per-process JIT (~1-1.5 min each) and the 2048-spin cells
# (cold ~3 min). Expect a few hours end to end; raw CSVs are written incrementally,
# so a failed step does not lose completed work.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PKG="${PKG:-$(cd "$HERE/../../SpinGlassPEPS.jl" 2>/dev/null && pwd)}"
GPU="${GPU:-0}"
SEED="${SEED:-1}"
export PKG SEED

[ -n "${PKG:-}" ] && [ -d "$PKG" ] || { echo "ERROR: set PKG to a SpinGlassPEPS.jl checkout (found: '${PKG:-}')"; exit 1; }
echo "== SpinGlassPEPS.jl : $PKG"
echo "== package commit   : $(git -C "$PKG" rev-parse --short HEAD 2>/dev/null || echo '(not a git checkout)')"
echo "== timing GPU       : device $GPU"
echo "== base seed        : $SEED"

echo "== instantiate + precompile =="
julia --project="$PKG" -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'

run() { julia --project="$PKG" "$@"; }
# multi-threaded launch: the concurrent-sweep arm needs several Julia threads to overlap
runmt() { julia --project="$PKG" -t "${JTHREADS:-auto}" "$@"; }

# ---------------------------------------------------------------------------
# 1) Crossover: CPU vs one GPU on identical configurations, seeded, min-of-reps.
#    Separate process per (cell, device) so each pays a clean cold+warm timing,
#    alternating CPU then GPU as in the manuscript's protocol.
# ---------------------------------------------------------------------------
CROSS="$HERE/crossover_raw.csv"; rm -f "$CROSS"
# fields: spins sparsity bond reps  (fewer reps for the costly 2048 cells, per the paper)
CELLS=(
  "36 dense 8 7"    "36 dense 16 7"    "36 dense 32 7"    "36 dense 64 7"
  "128 dense 8 7"   "128 dense 16 7"   "128 dense 32 7"   "128 dense 64 7"
  "128 sparse 64 7"
  "2048 dense 8 2"  "2048 dense 16 2"  "2048 dense 32 2"
  "2048 sparse 16 2" "2048 sparse 32 2"
)
for cell in "${CELLS[@]}"; do
  read -r SP SPAR B R <<< "$cell"
  echo "-- crossover: $SP spins, $SPAR, D=$B ($R reps) --"
  SPINS=$SP SPARSITY=$SPAR BOND=$B DEVICE=cpu REPS=$R SEED=$SEED OUT="$CROSS" \
    CUDA_VISIBLE_DEVICES="" run "$HERE/crossover.jl" || echo "  !! CPU cell failed; continuing"
  SPINS=$SP SPARSITY=$SPAR BOND=$B DEVICE=gpu REPS=$R SEED=$SEED OUT="$CROSS" \
    CUDA_VISIBLE_DEVICES="$GPU" run "$HERE/crossover.jl" || echo "  !! GPU cell failed; continuing"
done
python3 "$HERE/summarize_crossover.py" "$CROSS" "$HERE/crossover.csv" || echo "  !! summarize failed"

# ---------------------------------------------------------------------------
# 1b) Concurrent-sweep speed-up (Table 1): the serial 8-transformation loop vs
#     sweep_transformations at admission limit c, as median per-round paired
#     ratios (interleaved arms, full reclaim before each timed section).
#     Launched multi-threaded (runmt) so the concurrent arm can overlap; GPU
#     stops at c=4 (fanning out over one device never beats the serial loop).
# ---------------------------------------------------------------------------
CONC="$HERE/concurrency_raw.csv"; rm -f "$CONC"
echo "-- concurrency (Table 1): CPU, c=1,2,4,8, 5 rounds --"
CASE=both DEVICE=cpu LEVELS=1,2,4,8 ROUNDS=5 SEED=$SEED OUT="$CONC" \
  CUDA_VISIBLE_DEVICES="" runmt "$HERE/concurrency.jl" || echo "  !! concurrency (CPU) failed; continuing"
echo "-- concurrency (Table 1): GPU, c=1,2,4, 7 rounds --"
CASE=both DEVICE=gpu LEVELS=1,2,4 ROUNDS=7 SEED=$SEED OUT="$CONC" \
  CUDA_VISIBLE_DEVICES="$GPU" runmt "$HERE/concurrency.jl" || echo "  !! concurrency (GPU) failed; continuing"
python3 "$HERE/summarize_concurrency.py" "$CONC" "$HERE/concurrency.csv" || echo "  !! summarize concurrency failed"

# ---------------------------------------------------------------------------
# 2) Energy-vs-runtime sweep, solution spread (2 beta sets), cross-transform.
#    Existing drivers; read the 100 recovered 50x50 instances from the package.
# ---------------------------------------------------------------------------
echo "-- energy-vs-runtime sweep (CPU) --"
OUT="$HERE/sweep50_cpu.csv" NINST=10 DEV=cpu CUDA_VISIBLE_DEVICES="" run "$HERE/sweep50.jl" \
  || echo "  !! sweep50 failed"
echo "-- solution spread, beta 2,4,6 --"
OUT="$HERE/div3.csv"       NINST=10 BETAS="2.0,4.0,6.0" CUDA_VISIBLE_DEVICES="$GPU" run "$HERE/spread.jl" \
  || echo "  !! spread(2,4,6) failed"
echo "-- solution spread, beta 3,8 --"
OUT="$HERE/div3_extra.csv" NINST=10 BETAS="3.0,8.0"     CUDA_VISIBLE_DEVICES="$GPU" run "$HERE/spread.jl" \
  || echo "  !! spread(3,8) failed"
echo "-- cross-transformation valley distances --"
OUT="$HERE/xtransform.csv" NINST=5 CUDA_VISIBLE_DEVICES="$GPU" run "$HERE/xtransform.jl" \
  || echo "  !! xtransform failed"

# ---------------------------------------------------------------------------
# 2b) Prose numbers: contraction-error diagnostics and the beta-ladder warm
#     start. eps_stats is deterministic and device-independent; the ladder rows
#     are timings and record the machine in the CSV header comment -- across
#     machines quote the ratios, not the absolute times.
# ---------------------------------------------------------------------------
echo "-- contraction-error diagnostics (eps_stats) --"
rm -f "$HERE/eps_stats.csv"
BONDS=4,32 SEED=$SEED OUT="$HERE/eps_stats.csv" CUDA_VISIBLE_DEVICES="" run "$HERE/eps_stats.jl" \
  || echo "  !! eps_stats failed"
echo "-- beta-ladder warm start (2048power, CPU) --"
rm -f "$HERE/ladder_raw.csv"
ROUNDS=1 SEED=$SEED OUT="$HERE/ladder_raw.csv" CUDA_VISIBLE_DEVICES="" run "$HERE/ladder.jl" \
  || echo "  !! ladder failed"

# ---------------------------------------------------------------------------
# 3) Allocation profile of the CURRENT ('after') code, both devices.
#    The A/B before/after split in Figure 3 needs the pre-change code; see below.
# ---------------------------------------------------------------------------
ALLOC="$HERE/alloc_raw.csv"; rm -f "$ALLOC"
for DEV in cpu gpu; do
  VIS=""; [ "$DEV" = gpu ] && VIS="$GPU"
  echo "-- allocation profile ($DEV, current code) --"
  SPINS=2048 SPARSITY=dense BOND=32 DEVICE=$DEV REPS=3 SEED=$SEED LABEL=after OUT="$ALLOC" \
    CUDA_VISIBLE_DEVICES="$VIS" run "$HERE/alloc.jl" || echo "  !! alloc ($DEV) failed"
done
cat <<'NOTE'

-- allocation A/B (manual): Figure 3 compares the code BEFORE and AFTER two
   isolated changes (single-matrix branched-configuration set; off-heap contraction
   temporaries). To regenerate it, check out the relevant pre-change commit(s) of
   SpinGlassPEPS.jl, rebuild, and re-run alloc.jl with LABEL=before appending to
   alloc_raw.csv, then hand-assemble alloc.csv in the makefigs format:
       change,device,metric,before,after
   with change in {branch_states, temporaries}, device in {CPU, GPU},
   metric in {wall_s, gc_s, alloc_GiB}. This run records only the 'after' numbers
   in alloc_raw.csv; alloc.csv (the figure input) is left as committed otherwise.
NOTE

# ---------------------------------------------------------------------------
# 4) Render figures into ../figures/ (uses the fresh CSVs above + committed alloc.csv).
# ---------------------------------------------------------------------------
echo "-- rendering figures into ../figures/ --"
python3 "$HERE/makefigs.py" || echo "  !! makefigs failed (needs matplotlib + a LaTeX PGF backend)"

echo "== done. Raw + summary CSVs in $HERE ; figures in $HERE/../figures/ =="
