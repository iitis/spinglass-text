#!/usr/bin/env python3
"""Summarize crossover_raw.csv -> crossover.csv (the makefigs.py input).

Takes the min-of-repetitions wall time per (spins, sparsity, bond) for each
device and pivots to the columns makefigs.py expects: spins,sparsity,bond,cpu_s,gpu_s.

    python3 summarize_crossover.py crossover_raw.csv crossover.csv
"""
import csv
import sys
from collections import defaultdict

raw, out = sys.argv[1], sys.argv[2]

best = defaultdict(dict)  # (spins, sparsity, bond) -> {device: min t_solve}
for r in csv.DictReader(open(raw)):
    key = (int(r["spins"]), r["sparsity"], int(r["bond"]))
    dev, t = r["device"], float(r["t_solve"])
    best[key][dev] = min(best[key].get(dev, float("inf")), t)

with open(out, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["spins", "sparsity", "bond", "cpu_s", "gpu_s"])
    for spins, spar, bond in sorted(best):
        d = best[(spins, spar, bond)]
        cpu = f"{d['cpu']:.3f}" if "cpu" in d else ""
        gpu = f"{d['gpu']:.3f}" if "gpu" in d else ""
        w.writerow([spins, spar, bond, cpu, gpu])

print("wrote", out, f"({len(best)} cells)")
