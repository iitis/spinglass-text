#!/usr/bin/env python3
"""concurrency_raw.csv -> concurrency.csv (the Table 1 values).

Takes the median of the per-round paired ratios for each (case, device,
concurrency) and pivots to the manuscript's columns c=1,2,4,8.

    python3 summarize_concurrency.py concurrency_raw.csv concurrency.csv
"""
import csv
import statistics
import sys
from collections import defaultdict

raw, out = sys.argv[1], sys.argv[2]

ratios = defaultdict(list)  # (case, device, c) -> [ratio, ...]
for r in csv.DictReader(open(raw)):
    ratios[(r["case"], r["device"], int(r["concurrency"]))].append(float(r["ratio"]))

LEVELS = [1, 2, 4, 8]
keys = sorted({(case, dev) for (case, dev, _) in ratios})

with open(out, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["case", "device"] + [f"c{c}" for c in LEVELS] + ["rounds"])
    for case, dev in keys:
        row, rounds = [case, dev], 0
        for c in LEVELS:
            v = ratios.get((case, dev, c))
            row.append(f"{statistics.median(v):.2f}" if v else "")
            rounds = max(rounds, len(v) if v else 0)
        w.writerow(row + [rounds])

print("wrote", out, f"({len(keys)} case/device rows)")
