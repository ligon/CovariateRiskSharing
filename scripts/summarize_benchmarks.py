#!/usr/bin/env python3
"""Summarize raw benchmark log entries."""
import argparse
import collections
from datetime import datetime

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--input", required=True)
parser.add_argument("--output", required=True)
args = parser.parse_args()

records = []
with open(args.input) as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = [p.strip() for p in line.split("|")]
        if len(parts) != 3:
            continue
        ts, label, dur = parts
        try:
            datetime.strptime(ts, "%Y-%m-%d %H:%M:%S")
        except ValueError:
            continue
        dur = dur.rstrip("s")
        try:
            seconds = int(dur)
        except ValueError:
            continue
        records.append((label, seconds))

summary_lines = []
summary_lines.append(f"## Benchmark summary generated {datetime.now():%Y-%m-%d %H:%M:%S}")
summary_lines.append(f"Raw log: {args.input}")
summary_lines.append("")
summary_lines.append(f"{'Target':30} {'Count':>5} {'Median':>8} {'Max':>8} {'Total':>10}")
summary_lines.append("-" * 70)

if records:
    grouped = collections.defaultdict(list)
    for label, seconds in records:
        grouped[label].append(seconds)
    for label in sorted(grouped):
        vals = sorted(grouped[label])
        count = len(vals)
        median = vals[count // 2] if count % 2 == 1 else sum(vals[count//2-1:count//2+1]) // 2
        total = sum(vals)
        summary_lines.append(f"{label:30} {count:5d} {median:8d}s {max(vals):8d}s {total:10d}s")
else:
    summary_lines.append("(no benchmark data yet)")

with open(args.output, "w") as fh:
    fh.write("\n".join(summary_lines) + "\n")
