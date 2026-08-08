#!/usr/bin/env python3
"""Regenerate data/backcasts.json from a v2 backtest CSV.

WHY THIS EXISTS. data/backcasts.json is the simulated track record behind the
site's "Track record (simulated)" table, and until now nothing produced it --
it was written by hand at the 2026-06-11 v2 cutover. gen_performance_v2.py's own
header complains that this was "not reproducible". It also meant the track
record silently kept describing a model that had since changed: the 2026-08-02
fidelity work altered the sample start, the factor, the DFM anchor, the scaling
and the selection, and none of that reached these numbers.

WHAT A "BACKCAST" IS HERE. For each target quarter, the LAST as-of before that
quarter's GDP was released -- i.e. the most informed estimate the model would
have published, immediately before the actual landed. backtest_v2 advances its
target quarter only when GDP is released, so the last as_of row for a target
quarter is exactly that.

THESE ARE NOT LIVE NOWCASTS. Every value is a re-run over history using only the
data published at the time. The `note` field says so, and the site renders that
disclaimer -- keep both.

Usage (from repo root):
  python nowcasting_v2/gen_backcasts_v2.py [backtest.csv] [first_quarter]

Defaults to the CI-calibration backtest and 2022 Q1 -- the SAME window the CI
calibration uses (compute_ci_params_v2.R's CALIB_FROM). That alignment is the
point: the accuracy line under the headline is drawn from the calibration, so if
the table below it covered different quarters the two would disagree on the
page, which is exactly what happened until 2026-08-08 (table 0.31pp over 12
quarters vs headline 0.37pp over 17).

The window was 2023 Q2 -- inherited from the hand-built file this replaced, with
no reason behind it. Widening to 2022 Q1 adds the five 2022 quarters, which are
the model's worst (MAE 0.512), so this makes the published track record LOOK
WORSE. That is the honest direction and the reason it is safe: the warning that
used to sit here was about widening to flatter the numbers. Do not narrow it
casually, and if you change it, change CALIB_FROM to match or the page will
contradict itself again.
"""
import csv, json, os, sys, statistics as st

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def p(*a): return os.path.join(ROOT, *a)

SRC   = sys.argv[1] if len(sys.argv) > 1 else p("nowcasting_v2", "cache", "ci_recalib", "qa_a10_acc.csv")
FIRST = sys.argv[2] if len(sys.argv) > 2 else "2022 Q1"

def qkey(q):
    y, qq = q.split()
    return (int(y), int(qq[1]))

rows = [r for r in csv.DictReader(open(SRC)) if r.get("qoq_error") not in ("", "NA", None)]
if not rows:
    raise SystemExit(f"no usable rows in {SRC}")

by = {}
for r in rows:
    by.setdefault(r["target_quarter"], []).append(r)

quarters = sorted((q for q in by if qkey(q) >= qkey(FIRST)), key=qkey)
if not quarters:
    raise SystemExit(f"no target quarters at or after {FIRST} in {SRC}")

backcasts = []
for q in quarters:
    last = max(by[q], key=lambda r: r["as_of"])          # final as-of before release
    fc   = float(last["qoq_growth_forecast"])
    act  = float(last["qoq_actual"])
    backcasts.append({
        "target_quarter":    q,
        "qoq_forecast_pct":  round(fc, 2),
        "qoq_actual_pct":    round(act, 2),
        "error_pp":          round(fc - act, 2),
        # "direction" = did we get the sign of growth right
        "direction_correct": (fc >= 0) == (act >= 0),
        "is_backcast":       True,
    })

errs = [b["error_pp"] for b in backcasts]
out = {
    "model": f"v2 headline (MAI -> QA U-MIDAS, {os.path.basename(SRC).replace('_acc.csv','')})",
    "basis": "pseudo-out-of-sample backtest (hypothetical; not produced in real time)",
    "note":  ("These are BACKTESTED estimates, shown to give the model a track record. "
              "They are not live nowcasts. Each is the last as-of before that quarter's GDP "
              "release, re-run using only data published at the time."),
    "source": os.path.relpath(SRC, ROOT),
    "n": len(backcasts),
    "mae_pp": round(st.mean(abs(e) for e in errs), 3),
    "hit_rate_pct": round(100 * sum(b["direction_correct"] for b in backcasts) / len(backcasts), 1),
    "backcasts": backcasts,
}

with open(p("data", "backcasts.json"), "w") as f:
    json.dump(out, f, indent=2)
    f.write("\n")

print(f"wrote data/backcasts.json  n={out['n']}  {quarters[0]}..{quarters[-1]}  "
       f"MAE {out['mae_pp']}pp  hit rate {out['hit_rate_pct']}%")
