"""plot.py CLONE RESULTS_CSV OUT_PNG

One panel per fio job: median over the 3 repetitions for every merge to
main, in merge order. Failed revisions are marked at the bottom, releases
are drawn as vertical lines.
"""

import csv
import statistics
import subprocess
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

clone, results_csv, out_png = sys.argv[1:]

LINE = "#2a78d6"
FAILED = "#d03b3b"
INK = "#52514e"

# (job, title, metric, factor) with factor converting the CSV value.
PANELS = [
    ("seq1m", "Sequential read, 1 MiB blocks", "MB/s", "bw_kib", 1024 / 1e6),
    ("seq64k", "Sequential read, 64 KiB blocks", "MB/s", "bw_kib", 1024 / 1e6),
    ("rand4k", "Random read, 4 KiB blocks", "IOPS", "iops", 1),
]

revs = []  # in merge order
dates = {}
failed = set()
values = {}  # (rev, job, column) -> [values]
with open(results_csv) as f:
    for row in csv.DictReader(f):
        rev = row["rev"]
        if rev not in dates:
            revs.append(rev)
            dates[rev] = row["date"]
        if row["status"] != "ok":
            failed.add(rev)
            continue
        for column in ("bw_kib", "iops"):
            values.setdefault((rev, row["job"], column), []).append(float(row[column]))

# Position of each release: the first measured merge containing the tag.
releases = []
tags = subprocess.run(
    ["git", "-C", clone, "tag", "--sort=creatordate"], capture_output=True, text=True, check=True
).stdout.split()
for tag in tags:
    for i, rev in enumerate(revs):
        is_ancestor = subprocess.run(["git", "-C", clone, "merge-base", "--is-ancestor", tag, rev])
        if is_ancestor.returncode == 0:
            releases.append((i, tag))
            break

fig, axes = plt.subplots(len(PANELS), 1, figsize=(12, 9), sharex=True)
for ax, (job, title, unit, column, factor) in zip(axes, PANELS):
    xs, ys = [], []
    for i, rev in enumerate(revs):
        if (rev, job, column) in values:
            xs.append(i)
            ys.append(statistics.median(values[(rev, job, column)]) * factor)
    ax.plot(xs, ys, color=LINE, linewidth=2, marker="o", markersize=4)
    ax.set_ylim(bottom=0, top=max(ys, default=1) * 1.15)
    bad = [i for i, rev in enumerate(revs) if rev in failed]
    ax.plot(bad, [0] * len(bad), "x", color=FAILED, markersize=8, clip_on=False,
            label="failed" if bad else None)
    for i, tag in releases:
        ax.axvline(i, color=INK, linewidth=0.8, linestyle=":")
        ax.annotate(tag, (i, 1), xycoords=("data", "axes fraction"), xytext=(3, -12),
                    textcoords="offset points", color=INK, fontsize=9)
    ax.set_title(title, loc="left", fontsize=11)
    ax.set_ylabel(unit, color=INK)
    ax.grid(axis="y", color="#e5e4e0", linewidth=0.8)
    ax.spines[["top", "right"]].set_visible(False)
    if bad:
        ax.legend(loc="lower right", frameon=False)

ticks = list(range(0, len(revs), max(1, len(revs) // 12)))
axes[-1].set_xticks(ticks, [dates[revs[i]] for i in ticks], rotation=30, ha="right")
axes[-1].set_xlabel(f"merges to main, {len(revs)} revisions", color=INK)
fig.suptitle("usbvfiod: USB 3 stick read performance in a Cloud Hypervisor guest", x=0.01, ha="left")
fig.tight_layout()
fig.savefig(out_png, dpi=150)
print(f"written {out_png}")
