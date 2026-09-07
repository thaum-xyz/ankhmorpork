#!/usr/bin/env python3
"""Turn a run directory of fio JSON into a readable comparison.

Emits, into the run directory:
  summary.md   -- comparison tables across every measured target
  results.csv  -- every metric, one row per target/job

Usage: report.py results/<run-id>
"""
import csv
import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def pct(io, key):
    """Percentile in microseconds. Absent when the job ran with gtod_reduce.

    Read/write stats carry percentiles under clat_ns; the sync block reports its
    own under lat_ns instead, so fall through rather than returning nothing.
    """
    for block in ("clat_ns", "lat_ns"):
        p = (io.get(block) or {}).get("percentile") or {}
        v = p.get(key)
        if v:
            return v / 1000.0
    return None


def mean_us(io):
    v = (io.get("clat_ns") or {}).get("mean") or (io.get("lat_ns") or {}).get("mean")
    return v / 1000.0 if v else None


def mibs(io):
    # fio reports bw in KiB/s
    return (io.get("bw") or 0) / 1024.0


def _one(doc):
    """Per-job metrics from a single fio run."""
    jobs = {}
    for job in doc.get("jobs", []):
        r, w, sy = job.get("read", {}), job.get("write", {}), job.get("sync", {})
        jobs[job.get("jobname", "?")] = {
            "read_iops": r.get("iops", 0.0), "write_iops": w.get("iops", 0.0),
            "read_mibs": mibs(r), "write_mibs": mibs(w),
            "read_lat_us": mean_us(r), "write_lat_us": mean_us(w),
            "read_p99_us": pct(r, "99.000000"), "write_p99_us": pct(w, "99.000000"),
            "read_p999_us": pct(r, "99.900000"), "write_p999_us": pct(w, "99.900000"),
            "sync_lat_us": mean_us(sy), "sync_p99_us": pct(sy, "99.000000"),
            "sync_p999_us": pct(sy, "99.900000"),
        }
    return jobs


def _agg(samples):
    """Median plus spread across cycles.

    Median rather than mean because a single cycle caught by a load spike on a
    live cluster should not drag the number. `spread` is (max-min)/median, and
    report it: a metric that swings 50%+ between identical cycles has not been
    measured, it has been sampled once with extra steps.
    """
    out = {}
    keys = set()
    for s_ in samples:
        keys |= set(s_.keys())
    for k in keys:
        vals = [s_[k] for s_ in samples if s_.get(k) is not None]
        if not vals:
            out[k] = None; out[k + "_spread"] = None; out[k + "_range"] = None; continue
        vals.sort()
        n = len(vals)
        med = vals[n // 2] if n % 2 else (vals[n // 2 - 1] + vals[n // 2]) / 2
        out[k] = med
        # Coefficient of variation, not (max-min)/median. The range grows with
        # sample count by construction -- more cycles catch more outliers -- so a
        # range-based figure says variance got worse as evidence improved, which
        # is backwards. CV is stable in n and comparable between runs.
        if med and n > 1:
            mean = sum(vals) / n
            var = sum((v - mean) ** 2 for v in vals) / (n - 1)
            out[k + "_spread"] = (var ** 0.5) / abs(med)
        else:
            out[k + "_spread"] = None
        out[k + "_range"] = ((vals[-1] - vals[0]) / med) if med else None
    out["_n"] = len(samples)
    return out


def load(run_dir):
    """{target_id: {jobs, notes, n_cycles}} aggregated over measurement cycles."""
    targets = {}
    for name in sorted(os.listdir(run_dir)):
        tdir = os.path.join(run_dir, name)
        if not os.path.isdir(tdir):
            continue
        # cycle-N/fio.json is the current layout; a bare fio.json is a run from
        # before interleaving existed and is treated as a single cycle.
        paths = sorted(glob.glob(os.path.join(tdir, "cycle-*", "fio.json")))
        if not paths and os.path.isfile(os.path.join(tdir, "fio.json")):
            paths = [os.path.join(tdir, "fio.json")]
        runs = []
        for fp in paths:
            try:
                with open(fp) as fh:
                    runs.append(_one(json.load(fh)))
            except (json.JSONDecodeError, OSError) as exc:
                print(f"  skipping {fp}: {exc}", file=sys.stderr)
        if not runs:
            continue
        jobnames = set()
        for r in runs:
            jobnames |= set(r.keys())
        targets[name] = {
            "jobs": {jn: _agg([r[jn] for r in runs if jn in r]) for jn in jobnames},
            "cycles": len(runs),
            "notes": target_notes(tdir),
        }
    return targets


def target_notes(tdir):
    """Placement facts worth carrying into the report."""
    notes = []
    lh = os.path.join(tdir, "longhorn-volume.yaml")
    if os.path.isfile(lh):
        with open(lh) as fh:
            for line in fh:
                s = line.strip()
                if s.startswith("robustness:"):
                    notes.append(f"longhorn {s}")
                elif s.startswith("numberOfReplicas:"):
                    notes.append(f"longhorn {s}")
    return notes


def f(v, dp=1):
    return "-" if v is None else f"{v:,.{dp}f}"


def k(v):
    if v is None:
        return "-"
    return f"{v/1000:.1f}k" if v >= 10000 else f"{v:,.0f}"


def table(rows, headers):
    out = ["| " + " | ".join(headers) + " |",
           "| " + " | ".join("---" for _ in headers) + " |"]
    out += ["| " + " | ".join(r) + " |" for r in rows]
    return "\n".join(out)


def confidence(targets):
    """Flag metrics that did not reproduce across cycles.

    Exists because read IOPS once measured 157.9k and 363.6k on two identical
    nodes, and a single-sample harness reports that as a finding rather than as
    noise. A metric whose cycles disagree by more than 25% has not been measured.
    """
    ncyc = max((d["cycles"] for d in targets.values()), default=1)
    if ncyc < 2:
        return ("\n### Measurement confidence\n\nSingle cycle, so nothing here has "
                "been reproduced. Re-run with `--cycles 3` before trusting any "
                "difference smaller than the gaps between classes.\n")
    watch = [("randread_4k_qd64", "read_iops"), ("randwrite_4k_qd64", "write_iops"),
             ("commit_fsync_4k_qd1", "sync_lat_us"), ("randread_4k_qd1", "read_lat_us"),
             ("seqwrite_1m_qd8", "write_mibs")]
    rows = []
    for t in sorted(targets):
        for job, metric in watch:
            sp = targets[t]["jobs"].get(job, {}).get(metric + "_spread")
            rg = targets[t]["jobs"].get(job, {}).get(metric + "_range")
            if sp is not None and sp > 0.20:
                rows.append([f"`{t}`", f"`{job}`", metric.replace("_", " "),
                             f"{sp*100:.0f}%", f"{rg*100:.0f}%" if rg else "-"])
    s2 = [f"\n### Measurement confidence\n",
          f"Each target measured {ncyc}×, interleaved across the whole matrix rather "
          "than back to back, so a load spike on this live cluster hits every target "
          "rather than poisoning one. Tables above report the median.\n"]
    if rows:
        s2.append("Coefficient of variation above 20% across cycles. These are not "
                  "settled measurements and should not carry an argument; the range "
                  "column is max-min for context.\n")
        s2.append(table(rows, ["target", "job", "metric", "CV", "range"]))
    else:
        s2.append("No metric exceeded 20% coefficient of variation across cycles.\n")
    return "\n".join(s2)


def durability_audit(targets):
    """Compare each class's flush against the flush cost of its own device.

    A stack cannot persist to media faster than the device beneath it can flush.
    Where it appears to, it is acknowledging rather than persisting -- which is
    exactly what Longhorn was found doing on 2026-09-04, and what a single
    commits/s leaderboard silently rewards.

    The reference is the hostpath-* target on the same node, which measures the
    bare filesystem on that device with no CSI driver in the path.
    """
    refs = {}
    for t, d in targets.items():
        if t.startswith("hostpath-"):
            node = t.rsplit("-", 1)[-1]
            v = d["jobs"].get("commit_fsync_4k_qd1", {}).get("sync_lat_us")
            if v:
                refs[node] = v
    if not refs:
        return ("\n### Durability tier\n\nNo `hostpath-*` baseline in this run, so "
                "flush behaviour could not be audited. Add one per node: without it "
                "there is no way to tell a fast class from a class that skips the "
                "work.\n")

    rows, suspect = [], []
    for t in sorted(targets):
        if t.startswith("hostpath-"):
            continue
        node = t.rsplit("-", 1)[-1]
        ref = refs.get(node)
        got = targets[t]["jobs"].get("commit_fsync_4k_qd1", {}).get("sync_lat_us")
        if not ref or not got:
            continue
        ratio = got / ref
        # Below ~0.5x the device's own flush, the flush is not reaching media.
        # Above that, the class is at least paying something the device charges.
        if ratio < 0.5:
            tier, note = "**not durable**", f"{1/ratio:.0f}× faster than its device"
            suspect.append(t)
        elif ratio < 0.9:
            tier, note = "suspect", f"{1/ratio:.1f}× faster than its device"
        else:
            tier, note = "durable", f"{ratio:.1f}× the device's flush"
        rows.append([f"`{t}`", f(got), f(ref), tier, note])

    s2 = ["\n### Durability tier — is the flush real?\n",
          "Every class is compared against the `hostpath-*` baseline on its own "
          "node: the same filesystem and device with no CSI driver in the path. "
          "Nothing can persist to media faster than that.\n",
          table(rows, ["target", "fsync µs", "device µs", "tier", "note"])]
    if suspect:
        s2.append("\n> **Do not compare commit rates across tiers.** " +
                  ", ".join(f"`{x}`" for x in suspect) +
                  " acknowledge flushes without persisting them, so their commit "
                  "rates measure a weaker promise and rank above classes that do "
                  "the work. Compare within a tier, or not at all.\n")
    return "\n".join(s2)


def modern_report(targets):
    s = []
    order = sorted(targets)

    s.append("### QD1 latency — one request at a time\n")
    s.append("The number an interactive workload feels. Replication and network "
             "overhead cannot hide behind queue depth here.\n")
    rows = []
    for t in order:
        rd = targets[t]["jobs"].get("randread_4k_qd1", {})
        wr = targets[t]["jobs"].get("randwrite_4k_qd1", {})
        rows.append([f"`{t}`",
                     f(rd.get("read_lat_us")), f(rd.get("read_p99_us")), f(rd.get("read_p999_us")),
                     f(wr.get("write_lat_us")), f(wr.get("write_p99_us")), f(wr.get("write_p999_us"))])
    s.append(table(rows, ["target", "read avg µs", "read p99", "read p99.9",
                          "write avg µs", "write p99", "write p99.9"]))

    s.append(durability_audit(targets))

    s.append("\n### Durable commit — 4k write + fsync\n")
    s.append("The database question. Postgres, etcd and SQLite all pay this on "
             "every commit; this cluster runs eleven CNPG databases. `sync` "
             "columns time the flush call itself.\n")
    rows = []
    for t in order:
        j = targets[t]["jobs"].get("commit_fsync_4k_qd1", {})
        rows.append([f"`{t}`", k(j.get("write_iops")),
                     f(j.get("write_lat_us")), f(j.get("write_p99_us")),
                     f(j.get("sync_lat_us")), f(j.get("sync_p99_us"))])
    s.append(table(rows, ["target", "commits/s", "write avg µs", "write p99",
                          "sync avg µs", "sync p99"]))

    s.append("\n### Flush semantics — three ways to ask for durability\n")
    s.append("A stack that pushes to stable media cannot beat the bare device's "
             "flush, and the three primitives should land close together. Wide "
             "gaps, or a class faster than the raw volume beneath it, mean an "
             "acknowledgement rather than a flush.\n")
    rows = []
    for t in order:
        jf = targets[t]["jobs"].get("commit_fsync_4k_qd1", {})
        jd = targets[t]["jobs"].get("commit_fdatasync_4k_qd1", {})
        jo = targets[t]["jobs"].get("commit_osync_4k_qd1", {})
        rows.append([f"`{t}`",
                     f(jf.get("sync_lat_us")), k(jf.get("write_iops")),
                     f(jd.get("sync_lat_us")), k(jd.get("write_iops")),
                     f(jo.get("write_lat_us")), k(jo.get("write_iops"))])
    s.append(table(rows, ["target", "fsync µs", "fsync/s", "fdatasync µs",
                          "fdatasync/s", "O_SYNC write µs", "O_SYNC/s"]))

    s.append("\n### IOPS ceiling — 4k random, QD64\n")
    rows = []
    for t in order:
        rd = targets[t]["jobs"].get("randread_4k_qd64", {})
        wr = targets[t]["jobs"].get("randwrite_4k_qd64", {})
        mx = targets[t]["jobs"].get("randrw_4k_qd16_70r", {})
        rows.append([f"`{t}`",
                     k(rd.get("read_iops")), f(rd.get("read_mibs"), 0),
                     k(wr.get("write_iops")), f(wr.get("write_mibs"), 0),
                     k(mx.get("read_iops")), k(mx.get("write_iops"))])
    s.append(table(rows, ["target", "read IOPS", "read MiB/s", "write IOPS",
                          "write MiB/s", "mixed read", "mixed write"]))

    s.append("\n### Sequential throughput — 1 MiB, QD8\n")
    rows = []
    for t in order:
        rd = targets[t]["jobs"].get("seqread_1m_qd8", {})
        wr = targets[t]["jobs"].get("seqwrite_1m_qd8", {})
        rows.append([f"`{t}`", f(rd.get("read_mibs"), 0), f(wr.get("write_mibs"), 0)])
    s.append(table(rows, ["target", "read MiB/s", "write MiB/s"]))
    return "\n".join(s)


def write_csv(run_dir, targets):
    fp = os.path.join(run_dir, "results.csv")
    cols = ["target", "storageclass", "node", "job", "read_iops", "write_iops",
            "read_mibs", "write_mibs", "read_lat_us", "write_lat_us",
            "read_p99_us", "write_p99_us", "read_p999_us", "write_p999_us",
            "sync_lat_us", "sync_p99_us", "sync_p999_us"]
    with open(fp, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(cols)
        for t in sorted(targets):
            # target ids are "<class>-<node>"; node is the last dash-segment
            sc, _, node = t.rpartition("-")
            for job, m in targets[t]["jobs"].items():
                w.writerow([t, sc, node, job] + [m.get(c) for c in cols[4:]])
    return fp


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    run_dir = sys.argv[1]
    if not os.path.isdir(run_dir):
        print(f"not a directory: {run_dir}", file=sys.stderr)
        return 1

    meta_path = os.path.join(run_dir, "run-metadata.yaml")
    targets = load(run_dir)
    if not targets:
        print(f"no fio results found under {run_dir}", file=sys.stderr)
        return 1

    meta = ""
    if os.path.isfile(meta_path):
        with open(meta_path) as fh:
            meta = fh.read().strip()

    doc = [f"# StorageClass performance — {os.path.basename(run_dir.rstrip('/'))}\n",
           "Cluster: ankhmorpork. One target measured at a time; `lvm-thin`, "
           "`piraeus-r2` and `longhorn` share a volume group on each node, so "
           "concurrent runs would measure each other.\n",
           "```yaml", meta, f"targets_measured: {len(targets)}", "```\n",
           "## Results\n",
           modern_report(targets),
           confidence(targets),
           "\n## Caveats\n",
           "- On `beelink01` all three local classes live on `ubuntu-vg`; on "
           "`master02` on `secondary-vg`. Same physical device per node, so "
           "class-to-class differences on one node are stack overhead, not disk.\n"
           "- `piraeus-r2` provisions from the `temporary-topolvm` pool, which "
           "*is* `thin-pool0` — the same pool `lvm-thin` uses. `piraeus-r2` vs "
           "`lvm-thin` on the same node therefore isolates DRBD replication cost.\n"
           "- `longhorn` here is 3 replicas, `piraeus-r2` is 2, `lvm-thin` is 1 "
           "and unreplicated. These are not equivalent durability, and the "
           "faster classes are faster partly because they promise less.\n"
           "- `unifi-nas` is NFSv3 with `nolock` over the node network to "
           "192.168.40.10. Expect a hard throughput ceiling from the link, and "
           "note that `nolock` means no NFS byte-range locking.\n"
           "- `master01` is cordoned and so is not in the matrix.\n"]

    out = os.path.join(run_dir, "summary.md")
    with open(out, "w") as fh:
        fh.write("\n".join(doc) + "\n")
    csv_fp = write_csv(run_dir, targets)
    print(f"  wrote {out}")
    print(f"  wrote {csv_fp}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
