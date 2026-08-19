import csv, statistics as st
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import LogLocator

SRC = "sweep50_cpu.csv"
OUT = "energy_vs_runtime.pdf"

rows = list(csv.DictReader(open(SRC)))
for r in rows:
    r["time_s"] = float(r["time_s"]); r["energy"] = float(r["energy"])
    r["sum_eps"] = float(r["sum_eps"]); r["beta"] = float(r["beta"])
    r["max_states"] = int(r["max_states"])

best = {}
for r in rows:
    best[r["instance"]] = min(best.get(r["instance"], 1e18), r["energy"])
def relerr(r):                      # same normalisation as the original Fig. 3
    b = best[r["instance"]]
    return (r["energy"] - b) / (2 * abs(b))

# Colour-blind safe, ordered light->dark with increasing effort.
CMAP = {16: "#9ecae1", 64: "#4292c6", 256: "#2171b5", 1024: "#08306b"}
LINTHRESH = 1e-5   # symlog: exact hits (error == 0) plot at 0 honestly, not at a fake floor

plt.rcParams.update({
    "font.size": 8, "axes.labelsize": 8, "legend.fontsize": 7,
    "xtick.labelsize": 7, "ytick.labelsize": 7, "axes.linewidth": 0.6,
    "figure.dpi": 200,
})
fig, (ax, bx) = plt.subplots(1, 2, figsize=(6.6, 2.7))

# ---- (a) time / quality trade-off, the Fig. 3(a) analogue -------------------
ms_rows = [r for r in rows if r["series"] == "max_states"]
for ms in (16, 64, 256, 1024):
    s = [r for r in ms_rows if r["max_states"] == ms]
    ax.scatter([r["time_s"] for r in s], [relerr(r) for r in s],
               s=14, alpha=0.55, color=CMAP[ms], edgecolors="none",
               label=f"max_states = {ms}", zorder=3)
med_t = [st.median([r["time_s"] for r in ms_rows if r["max_states"] == ms]) for ms in (16,64,256,1024)]
med_e = [st.median([relerr(r) for r in ms_rows if r["max_states"] == ms]) for ms in (16,64,256,1024)]
ax.plot(med_t, med_e, "-", color="0.25", lw=1.1, zorder=4, label="median")
ax.plot(med_t, med_e, "o", color="0.25", ms=3.4, zorder=5)
ax.set_xscale("log"); ax.set_yscale("symlog", linthresh=LINTHRESH)
ax.set_ylim(bottom=0)
ax.axhline(0, color="0.6", lw=0.6, ls=":", zorder=1)
ax.set_xlabel("time to solution [s]")
ax.set_ylabel(r"$(E - E_{\mathrm{best}})\,/\,2|E_{\mathrm{best}}|$")
ax.annotate("best found", (ax.get_xlim()[1], 0), textcoords="offset points",
            xytext=(-3, 4), ha="right", va="bottom", fontsize=6, color="0.45")
ax.set_title("(a) search breadth, $\\beta = 4$", fontsize=8, loc="left")
ax.grid(alpha=0.25, lw=0.4, which="both")
ax.legend(loc="lower left", handletextpad=0.4, borderpad=0.3, framealpha=0.92,
          edgecolor="0.8", fancybox=False)

# ---- (b) beta: quality and discarded weight pull apart ----------------------
betas = [2.0, 3.0, 4.0, 6.0, 8.0]
b_rows = [r for r in rows if r["series"] == "beta"]
q = [st.median([relerr(r) for r in b_rows if r["beta"] == b]) for b in betas]
hit = [sum(1 for r in b_rows if r["beta"] == b and relerr(r) == 0) for b in betas]
ninst = len({r["instance"] for r in b_rows})
e = [st.median([r["sum_eps"] for r in b_rows if r["beta"] == b]) for b in betas]
bx.plot(betas, q, "o-", color="#08306b", lw=1.2, ms=4, label="energy error (median)")
bx.set_yscale("symlog", linthresh=LINTHRESH)
bx.set_ylim(bottom=0)
bx.axhline(0, color="0.6", lw=0.6, ls=":", zorder=1)
for b, y, h in zip(betas, q, hit):
    if h: bx.annotate(f"{h}/{ninst}", (b, y), textcoords="offset points", xytext=(0, 7),
                      ha="center", fontsize=6, color="#08306b")
bx.set_xlabel(r"inverse temperature $\beta$")
bx.set_ylabel(r"$(E - E_{\mathrm{best}})\,/\,2|E_{\mathrm{best}}|$", color="#08306b")
bx.tick_params(axis="y", colors="#08306b")
bx.grid(alpha=0.25, lw=0.4)
cx = bx.twinx()
cx.plot(betas, e, "s--", color="#c1272d", lw=1.2, ms=3.6, label=r"discarded weight $\sum_i\varepsilon_i$")
cx.set_yscale("log"); cx.set_ylabel(r"$\sum_i \varepsilon_i$", color="#c1272d", rotation=90, labelpad=6)
cx.tick_params(axis="y", colors="#c1272d")
bx.set_title("(b) quality and truncation error diverge", fontsize=8, loc="left")
h1, l1 = bx.get_legend_handles_labels(); h2, l2 = cx.get_legend_handles_labels()
bx.legend(h1 + h2, l1 + l2, loc="upper center", bbox_to_anchor=(0.5, -0.28), ncol=2,
          frameon=False, handletextpad=0.4, columnspacing=1.2)

fig.tight_layout(pad=0.5)
fig.savefig(OUT, bbox_inches="tight")
fig.savefig(OUT.replace(".pdf", ".png"), bbox_inches="tight")
print("wrote", OUT)
print("exact hits:", sum(1 for r in ms_rows if relerr(r) == 0), "of", len(ms_rows), "panel-(a) points")
