#!/usr/bin/env python3
"""Figures for the SpinGlassPEPS.jl software-update article.

Rendered through matplotlib's PGF backend with pdflatex, so glyphs and maths are
set by the same engine as the manuscript and match `elsarticle` at 11pt.

    python3 makefigs.py            # writes *.pdf (and *.png previews) into ../figures/

Inputs, all produced by the scripts archived alongside:
    sweep50_cpu.csv   10 x 2500-spin instances, max_states and beta series
    div3.csv          solution spread on the Z2 quotient (optional; panel skipped)
    crossover.csv     CPU vs GPU on identical configurations
    alloc.csv         before/after for the two allocation changes
"""
import csv
import os
import statistics as st

import matplotlib

matplotlib.use("pgf")
matplotlib.rcParams.update({
    "pgf.texsystem": "pdflatex",
    "text.usetex": True,
    "pgf.rcfonts": False,
    "font.family": "serif",
    "pgf.preamble": r"\usepackage{amsmath}\usepackage{amssymb}",
    "font.size": 8,
    "axes.labelsize": 8,
    "axes.titlesize": 8,
    "legend.fontsize": 7,
    "xtick.labelsize": 7,
    "ytick.labelsize": 7,
    "axes.linewidth": 0.6,
    "lines.linewidth": 1.1,
    "grid.linewidth": 0.4,
    "legend.frameon": False,
})
import matplotlib.pyplot as plt  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
LINTHRESH = 1e-5          # symlog: exact hits (error == 0) plot at zero, honestly
SEQ = ["#9ecae1", "#4292c6", "#2171b5", "#08306b"]   # light -> dark with effort
ACCENT = "#c1272d"


def load(name):
    path = os.path.join(HERE, name)
    if not os.path.exists(path):
        return None
    with open(path) as fh:
        return list(csv.DictReader(fh))


def save(fig, stem):
    fig.savefig(os.path.join(HERE, "..", "figures", stem + ".pdf"), bbox_inches="tight")
    fig.savefig(os.path.join(HERE, "..", "figures", stem + ".png"), bbox_inches="tight", dpi=200)
    plt.close(fig)
    print("wrote", stem + ".pdf")


# --------------------------------------------------------------------------
# Figure 1 -- the Fig. 3 analogue: cost/quality, per instance, and the beta scan
# --------------------------------------------------------------------------
def figure_quality():
    rows = load("sweep50_cpu.csv")
    for r in rows:
        r["time_s"] = float(r["time_s"]); r["energy"] = float(r["energy"])
        r["sum_eps"] = float(r["sum_eps"]); r["beta"] = float(r["beta"])
        r["max_states"] = int(r["max_states"]); r["inst"] = int(r["instance"])
    best = {}
    for r in rows:
        best[r["inst"]] = min(best.get(r["inst"], 1e18), r["energy"])

    def err(r):
        b = best[r["inst"]]
        return (r["energy"] - b) / (2 * abs(b))

    div = load("div3.csv")
    extra = load("div3_extra.csv")
    if div and extra:
        div = div + extra
    if div:
        fig, axgrid = plt.subplots(2, 2, figsize=(6.9, 4.7))
        ax, bx, cx, ex = axgrid[0, 0], axgrid[0, 1], axgrid[1, 0], axgrid[1, 1]
    else:
        fig, axes = plt.subplots(1, 3, figsize=(6.9, 2.5))
        ax, bx, cx, ex = axes[0], axes[1], axes[2], None

    # (a) time to solution vs quality, one series per search breadth
    ms_rows = [r for r in rows if r["series"] == "max_states"]
    breadths = sorted({r["max_states"] for r in ms_rows})
    for col, ms in zip(SEQ, breadths):
        s = [r for r in ms_rows if r["max_states"] == ms]
        ax.scatter([r["time_s"] for r in s], [err(r) for r in s], s=11, alpha=0.55,
                   color=col, edgecolors="none", zorder=3, label=rf"$M={ms}$")
    med_t = [st.median([r["time_s"] for r in ms_rows if r["max_states"] == m]) for m in breadths]
    med_e = [st.median([err(r) for r in ms_rows if r["max_states"] == m]) for m in breadths]
    ax.plot(med_t, med_e, "-o", color="0.25", ms=3, zorder=5, label="median")
    ax.set_xscale("log")
    ax.set_yscale("symlog", linthresh=LINTHRESH)
    ax.set_ylim(bottom=0)
    ax.axhline(0, color="0.6", lw=0.6, ls=":", zorder=1)
    ax.set_xlabel(r"time to solution [s]")
    ax.set_ylabel(r"$(E-E_{\mathrm{best}})/2|E_{\mathrm{best}}|$")
    ax.set_title(r"(a) cost vs.\ quality, $\beta=4$", loc="left")
    ax.grid(alpha=0.25, which="both")
    ax.legend(loc="lower left", handletextpad=0.3, borderpad=0.2, labelspacing=0.25)

    # (b) instance-wise, mirroring the original panel (b)
    insts = sorted(best)
    for col, ms in zip(SEQ, breadths):
        s = {r["inst"]: err(r) for r in ms_rows if r["max_states"] == ms}
        bx.plot(insts, [s.get(i, float("nan")) for i in insts], "o", ms=3.2,
                color=col, label=rf"$M={ms}$")
    bx.set_yscale("symlog", linthresh=LINTHRESH)
    bx.set_ylim(bottom=0)
    bx.axhline(0, color="0.6", lw=0.6, ls=":", zorder=1)
    bx.set_xlabel(r"instance"); bx.set_xticks(insts)
    bx.set_ylabel(r"$(E-E_{\mathrm{best}})/2|E_{\mathrm{best}}|$")
    bx.set_title(r"(b) per instance", loc="left")
    bx.grid(alpha=0.25, which="both")

    # (c) the beta scan: quality and discarded weight pull apart
    b_rows = [r for r in rows if r["series"] == "beta"]
    betas = sorted({r["beta"] for r in b_rows})
    q = [st.median([err(r) for r in b_rows if r["beta"] == b]) for b in betas]
    e = [st.median([r["sum_eps"] for r in b_rows if r["beta"] == b]) for b in betas]
    hit = [sum(1 for r in b_rows if r["beta"] == b and err(r) == 0) for b in betas]
    n_inst = len(insts)
    cx.plot(betas, q, "o-", color=SEQ[-1], ms=3.6, label=r"energy error")
    import matplotlib.patheffects as pe
    for b, y, h in zip(betas, q, hit):
        if h:
            cx.annotate(rf"${h}/{n_inst}$", (b, y), textcoords="offset points",
                        xytext=(0, 8), ha="center", va="bottom", fontsize=6,
                        color=SEQ[-1], zorder=6,
                        path_effects=[pe.withStroke(linewidth=1.6, foreground="white")])
    cx.set_yscale("symlog", linthresh=LINTHRESH)
    cx.set_ylim(bottom=0)
    cx.axhline(0, color="0.6", lw=0.6, ls=":", zorder=1)
    cx.set_xlabel(r"inverse temperature $\beta$")
    cx.set_ylabel(r"$(E-E_{\mathrm{best}})/2|E_{\mathrm{best}}|$", color=SEQ[-1])
    cx.tick_params(axis="y", colors=SEQ[-1])
    cx.set_title(r"(c) quality vs.\ discarded weight", loc="left")
    cx.grid(alpha=0.25)
    dx = cx.twinx()
    dx.plot(betas, e, "s--", color=ACCENT, ms=3.2, label=r"$\textstyle\sum_i\varepsilon_i$")
    dx.set_yscale("log")
    dx.set_ylabel(r"$\textstyle\sum_i \varepsilon_i$", color=ACCENT, rotation=90, labelpad=4)
    dx.tick_params(axis="y", colors=ACCENT)
    h1, l1 = cx.get_legend_handles_labels()
    h2, l2 = dx.get_legend_handles_labels()
    cx.legend(h1 + h2, l1 + l2, loc="center left", handletextpad=0.3, borderpad=0.2)

    # (d) how far apart are the returned solutions, really?
    #
    # These instances carry no local fields, so E(s) = E(-s) and every state has a
    # degenerate mirror at Hamming distance N. The Fig. 3(c) count scores that mirror
    # as a second solution for free. Distances here are quotient distances,
    # min(d, N-d), which need no gauge choice; the space has diameter N/2.
    if ex is not None:
        for r in div:
            for k in ("dq50", "dq90", "dqmax", "beta"):
                r[k] = float(r[k])
        div.sort(key=lambda r: r["beta"])
        N = 2500
        dbetas = sorted({r["beta"] for r in div})
        med = lambda k: [st.median([r[k] for r in div if r["beta"] == b]) for b in dbetas]
        lo, mid, hi = med("dq50"), med("dq90"), med("dqmax")
        ex.fill_between(dbetas, lo, hi, color=SEQ[1], alpha=0.30, lw=0,
                        label=r"$d_{50}$--$d_{\max}$")
        ex.plot(dbetas, mid, "o-", color=SEQ[3], ms=3.6, label=r"$d_{90}$")
        # the one instance/beta that clears the threshold is a degraded solve, not a
        # discovery: flag it rather than let the across-instance median bury it
        out = [(r["beta"], r["dqmax"]) for r in div if float(r["dqmax"]) > N / 4]
        for b, d in out:
            ex.plot([b], [d], "x", color=ACCENT, ms=5, mew=1.2, zorder=6)
        if out:
            ex.annotate(r"degraded solve", (out[0][0], out[0][1]), fontsize=6,
                        color=ACCENT, textcoords="offset points", xytext=(-3, 6),
                        ha="right", va="bottom")
        ex.axhline(N / 4, color=ACCENT, lw=0.9, ls="--")
        ex.annotate(r"distinct-valley threshold $N/4$", (dbetas[0], N / 4),
                    textcoords="offset points", xytext=(2, 3), ha="left", va="bottom",
                    fontsize=6, color=ACCENT)
        ex.axhline(N / 2, color="0.45", lw=0.7, ls=":")
        ex.annotate(r"quotient diameter $N/2$", (dbetas[0], N / 2),
                    textcoords="offset points", xytext=(2, 3), ha="left", va="bottom",
                    fontsize=6, color="0.45")
        # The same question across contraction orders: one state from each of the
        # eight lattice transformations, at beta=4. Plotted on the same axis so the
        # contrast with the within-order band is direct.
        xt = load("xtransform.csv")
        if xt:
            dmed = st.median([float(r["d_med"]) for r in xt])
            dmin = st.median([float(r["d_min"]) for r in xt])
            dmax = st.median([float(r["d_max"]) for r in xt])
            ex.errorbar([4.0], [dmed], yerr=[[dmed - dmin], [dmax - dmed]], fmt="s",
                        color="#b8860b", ms=4.5, lw=1.1, capsize=2.5, zorder=7,
                        label=r"across transformations")
        ex.set_yscale("log")
        ex.set_ylim(top=N)
        ex.set_xlabel(r"inverse temperature $\beta$")
        ex.set_ylabel(r"quotient distance to best state")
        ex.set_title(r"(d) spread of returned solutions", loc="left")
        ex.grid(alpha=0.25, which="both")
        ex.legend(loc="lower right", handletextpad=0.4, labelspacing=0.2,
                  fontsize=6)

    fig.tight_layout(pad=0.4, w_pad=1.4, h_pad=1.0)
    save(fig, "quality")


# --------------------------------------------------------------------------
# Figure 2 -- where GPU execution starts to pay
# --------------------------------------------------------------------------
def figure_crossover():
    rows = load("crossover.csv")
    for r in rows:
        r["bond"] = int(r["bond"]); r["ratio"] = float(r["cpu_s"]) / float(r["gpu_s"])
        r["spins"] = int(r["spins"])
    fig, ax = plt.subplots(figsize=(3.4, 2.5))
    styles = {(36, "dense"): (SEQ[0], "o", "-"), (128, "dense"): (SEQ[2], "s", "-"),
              (2048, "dense"): (SEQ[3], "^", "-"), (2048, "sparse"): (ACCENT, "D", "--"),
              (128, "sparse"): (ACCENT, "v", ":")}
    for key, (col, mk, ls) in styles.items():
        s = sorted([r for r in rows if (r["spins"], r["sparsity"]) == key],
                   key=lambda r: r["bond"])
        if not s:
            continue
        lbl = rf"{key[0]} spins, {key[1]}"
        ax.plot([r["bond"] for r in s], [r["ratio"] for r in s], ls, marker=mk,
                ms=3.4, color=col, label=lbl)
    ax.axhline(1.0, color="0.35", lw=0.8, ls="-", zorder=1)
    ax.annotate(r"GPU faster $\uparrow$", (0.02, 1.0), xycoords=("axes fraction", "data"),
                xytext=(0, 3), textcoords="offset points", ha="left", va="bottom",
                fontsize=6, color="0.35")
    ax.annotate(r"CPU faster $\downarrow$", (0.02, 1.0), xycoords=("axes fraction", "data"),
                xytext=(0, -4), textcoords="offset points", ha="left", va="top",
                fontsize=6, color="0.35")
    ax.set_xscale("log", base=2); ax.set_yscale("log")
    ax.set_xticks([8, 16, 32, 64]); ax.set_xticklabels([8, 16, 32, 64])
    ax.set_xlabel(r"bond dimension $D$")
    ax.set_ylabel(r"CPU / GPU wall-clock ratio")
    ax.grid(alpha=0.25, which="both")
    ax.legend(loc="center right", handletextpad=0.4, labelspacing=0.25)
    fig.tight_layout(pad=0.4)
    save(fig, "crossover")


# --------------------------------------------------------------------------
# Figure 3 -- what the allocation changes bought
# --------------------------------------------------------------------------
def figure_alloc():
    # Bytes only: post-change allocated GiB was reproduced on both tested systems.
    # Wall/GC timings are machine-specific and not plotted.
    rows = load("alloc.csv")
    groups = [("branch_states", "GPU", r"states"),
              ("branch_states", "CPU", r"states"),
              ("temporaries", "CPU", r"temp.")]
    fig, ax = plt.subplots(1, 1, figsize=(3.4, 2.4))
    labels = [rf"{g[2]}" + "\n" + rf"{g[1]}" for g in groups]
    xs = range(len(groups))
    before, after = [], []
    for change, dev, _ in groups:
        r = next(x for x in rows if x["change"] == change and x["device"] == dev
                 and x["metric"] == "alloc_GiB")
        before.append(float(r["before"])); after.append(float(r["after"]))
    w = 0.36
    ax.bar([x - w / 2 for x in xs], before, w, color="0.72", label=r"before")
    ax.bar([x + w / 2 for x in xs], after, w, color=SEQ[3], label=r"after")
    for x, (b, a) in enumerate(zip(before, after)):
        ax.annotate(rf"$-{100*(b-a)/b:.0f}\%$", (x + w / 2, a), textcoords="offset points",
                    xytext=(0, 2), ha="center", fontsize=6, color=SEQ[3])
    ax.set_xticks(list(xs)); ax.set_xticklabels(labels, fontsize=7)
    ax.set_title(r"allocated [GiB]", loc="left")
    ax.grid(alpha=0.25, axis="y")
    ax.set_axisbelow(True)
    ax.legend(loc="upper right", handletextpad=0.4)
    fig.tight_layout(pad=0.4)
    save(fig, "allocation")


if __name__ == "__main__":
    figure_quality()
    figure_crossover()
    figure_alloc()
