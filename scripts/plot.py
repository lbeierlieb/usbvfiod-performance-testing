"""plot.py CLONE RESULTS_CSV OUT_PNG

Sequential 1 MiB read throughput, median over the 3 repetitions, for every
merge to main in merge order. Failed revisions are marked at the bottom,
releases are drawn as vertical lines, the baseline (fio directly in the QEMU
VM, without passthrough) as a dashed line.
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

revs = []  # in merge order
dates = {}
failed = set()
values = {}  # rev -> [MB/s]
baseline = []  # MB/s directly in the QEMU VM
with open(results_csv) as f:
    for row in csv.DictReader(f):
        rev = row["rev"]
        if rev == "baseline":
            if row["status"] == "ok":
                baseline.append(float(row["bw_kib"]) * 1024 / 1e6)
            continue
        if rev not in dates:
            revs.append(rev)
            dates[rev] = row["date"]
        if row["status"] != "ok":
            failed.add(rev)
            continue
        values.setdefault(rev, []).append(float(row["bw_kib"]) * 1024 / 1e6)

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

fig, ax = plt.subplots(figsize=(12, 5))
xs = [i for i, rev in enumerate(revs) if rev in values]
ys = [statistics.median(values[revs[i]]) for i in xs]
ax.plot(xs, ys, color=LINE, linewidth=2, marker="o", markersize=4)
ref = [statistics.median(baseline)] if baseline else []
ax.set_ylim(bottom=0, top=max(ys + ref, default=1) * 1.15)
for b in ref:
    ax.axhline(b, color=INK, linewidth=1, linestyle="--")
    ax.annotate(f"QEMU VM without passthrough: {b:.0f} MB/s", (0, b), xycoords=("axes fraction", "data"),
                xytext=(4, 4), textcoords="offset points", color=INK, fontsize=9)
bad = [i for i, rev in enumerate(revs) if rev in failed]
if bad:
    ax.plot(bad, [0] * len(bad), "x", color=FAILED, markersize=8, clip_on=False, label="failed")
    ax.legend(loc="lower right", frameon=False)
for i, tag in releases:
    ax.axvline(i, color=INK, linewidth=0.8, linestyle=":")
    ax.annotate(tag, (i, 1), xycoords=("data", "axes fraction"), xytext=(3, -12),
                textcoords="offset points", color=INK, fontsize=9)
ax.set_ylabel("MB/s", color=INK)
ax.grid(axis="y", color="#e5e4e0", linewidth=0.8)
ax.spines[["top", "right"]].set_visible(False)

ticks = list(range(0, len(revs), max(1, len(revs) // 12)))
ax.set_xticks(ticks, [dates[revs[i]] for i in ticks], rotation=30, ha="right")
ax.set_xlabel(f"merges to main, {len(revs)} revisions", color=INK)
ax.set_title("usbvfiod: sequential 1 MiB reads from QEMU's emulated USB 3 stick in a Cloud Hypervisor guest",
             loc="left")
fig.tight_layout()
fig.savefig(out_png, dpi=150)
print(f"written {out_png}")
