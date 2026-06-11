#!/usr/bin/env python3
"""Regenerate data/indicators_v2.json (the indicator-grid display) from data_raw.

WHY: the indicator grid reads data/indicators_v2.json, but nothing rebuilt it, so
its values went stale even though data_raw/*.csv was being refreshed weekly (the
emit only writes latest_v2.json). This generator refreshes every indicator's
`series` from data_raw and advances the release-date fields in step, preserving
all curated metadata (name/group/unit/source, display window, ordering).

Run from repo root:  python nowcasting_v2/gen_indicators_v2.py
Wired into the weekly cron after the v2 emit so the grid stays current.

Design:
  * Uses the EXISTING indicators_v2.json as the metadata template (which
    indicators, their names/groups/units/sources, and each series' start month).
  * For each indicator, reloads its series from data_raw/<id>.csv, keeping the
    same start month (preserves the curated chart window) and matching the
    existing value precision. data_raw is the source of truth, so revisions to
    historical months flow through too.
  * Advances last_release_date / next_release_estimate by however many months the
    data extended (preserves each source's day-of-month release pattern).
"""
import json, csv, os, calendar

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IND = os.path.join(ROOT, "data", "indicators_v2.json")
RAW = os.path.join(ROOT, "nowcasting_v2", "data_raw")


def ndec(v):
    s = str(v)
    return len(s.split(".")[1]) if "." in s else 0


def month_idx(yyyy_mm):
    y, m = int(yyyy_mm[:4]), int(yyyy_mm[5:7])
    return y * 12 + (m - 1)


def shift_iso_months(iso, n):
    """Shift a YYYY-MM-DD date by n months, clamping the day to month length."""
    y, m, d = (int(x) for x in iso.split("-"))
    idx = y * 12 + (m - 1) + n
    ny, nm = idx // 12, idx % 12 + 1
    return f"{ny:04d}-{nm:02d}-{min(d, calendar.monthrange(ny, nm)[1]):02d}"


def read_raw(series_id):
    p = os.path.join(RAW, f"{series_id}.csv")
    with open(p, newline="") as f:
        return [(r["date"][:7], r["value"]) for r in csv.DictReader(f)]


def main():
    doc = json.load(open(IND))
    advanced = []
    for ind in doc["indicators"]:
        sid = ind["id"]
        old = ind["series"]
        if not old:
            continue
        decimals = max(ndec(p["value"]) for p in old)
        start = old[0]["date"]            # preserve curated chart start
        old_latest = old[-1]["date"]
        raw = read_raw(sid)
        new = [{"date": ym, "value": round(float(v), decimals)}
               for ym, v in raw if ym >= start]
        if not new:
            print(f"  WARN {sid}: no data_raw rows >= {start}; leaving as-is")
            continue
        new_latest = new[-1]["date"]
        adv = month_idx(new_latest) - month_idx(old_latest)
        if adv > 0:
            for k in ("last_release_date", "next_release_estimate"):
                if ind.get(k):
                    ind[k] = shift_iso_months(ind[k], adv)
            advanced.append(f"{sid} {old_latest}->{new_latest}")
        ind["series"] = new

    json.dump(doc, open(IND, "w"), indent=2)
    print(f"indicators_v2.json regenerated ({len(doc['indicators'])} indicators).")
    if advanced:
        print("Advanced:", ", ".join(advanced))
    else:
        print("All indicators already current.")


if __name__ == "__main__":
    main()
