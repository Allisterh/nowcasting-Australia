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
  * Sets last_release_date / next_release_estimate from each source's real release
    cadence: ABS series reuse v1's scraped dates; survey series (NAB/ANZ/Westpac)
    use SURVEY_SCHEDULE (computed release dates); other series keep the month-shift.
"""
import json, csv, os, calendar, datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IND = os.path.join(ROOT, "data", "indicators_v2.json")
V1_IND = os.path.join(ROOT, "data", "indicators.json")
RAW = os.path.join(ROOT, "nowcasting_v2", "data_raw")

# ABS-sourced v2 indicators -> v1 indicators.json ids. The v1 emit
# (04_emit_json.R) scrapes each ABS publication's real "Next Release" date every
# run, so reuse those authoritative dates instead of the fixed-day month-shift
# below, which drifts off the real ABS schedule (ABS moves dates around public
# holidays — e.g. the May-2026 Labour Force release is 25 Jun, not the heuristic
# 15 Jun). v1 runs before this generator in the weekly cron. RBA/survey series
# have no v1 ABS entry and keep the month-shift heuristic.
ABS_DATE_MAP = {
    "emp": "employment", "ft_emp": "employment", "pt_emp": "employment",
    "ue": "unemp_rate", "ud": "unemp_rate", "hours": "hours_worked",
    "household_spending": "household_spending",
    "building_app": "building_approvals", "export": "goods_exp",
}

# Survey series (NAB / ANZ / Westpac) have no v1 ABS entry, so the old code left
# them on the drifting month-shift heuristic — which produced dates that were wrong
# (NAB's real release is the 2nd Tuesday, not a fixed day) and, for the weekly
# ANZ-Roy Morgan series, dates in the FUTURE. Instead, compute each survey's real
# release date from its published cadence. TUE = Tuesday (Mon=0 .. Sun=6).
TUE = 1


def _nth_weekday(year, month, weekday, n):
    """Date of the n-th `weekday` of year-month (n starts at 1)."""
    first = datetime.date(year, month, 1)
    offset = (weekday - first.weekday()) % 7
    return first + datetime.timedelta(days=offset + 7 * (n - 1))


def _add_months(year, month, k):
    idx = year * 12 + (month - 1) + k
    return idx // 12, idx % 12 + 1


def _monthly_tuesday(offset_months, nth):
    """Schedule for a MONTHLY survey released on the nth Tuesday of
    (data month + offset_months). Returns (last_release, next_release), where next
    is the same rule applied to the following data month. last is clamped to <= today
    so a point that lands before its modelled release date never shows a future date.
    """
    def f(y, m, today):
        ry, rm = _add_months(y, m, offset_months)
        last = min(_nth_weekday(ry, rm, TUE, nth), today)
        ny, nm = _add_months(y, m, 1)
        nry, nrm = _add_months(ny, nm, offset_months)
        nxt = _nth_weekday(nry, nrm, TUE, nth)
        return last, nxt
    return f


def _weekly_tuesday(y, m, today):
    """Schedule for a WEEKLY survey (ANZ-Roy Morgan, published every Tuesday). The
    stored series is monthly, but it is refreshed weekly, so "last updated" is the
    most recent Tuesday on/before today and "next" is the following Tuesday."""
    last = today - datetime.timedelta(days=(today.weekday() - TUE) % 7)
    nxt = today + datetime.timedelta(days=((TUE - today.weekday()) % 7) or 7)
    return last, nxt


# id -> schedule function(data_year, data_month, today) -> (last_release, next_release)
SURVEY_SCHEDULE = {
    # NAB Monthly Business Survey: 2nd Tuesday of the month AFTER the reference month.
    **{sid: _monthly_tuesday(1, 2) for sid in (
        "nab_conf", "nab_cond", "nab_trade", "nab_profit",
        "nab_emp", "nab_forward", "nab_stocks", "nab_cu")},
    "wmi_sent": _monthly_tuesday(0, 2),   # Westpac-MI: 2nd Tuesday of the same month.
    "anz_ads":  _monthly_tuesday(1, 1),   # ANZ-Indeed Job Ads: ~1st Tuesday of the following month.
    "anz_sent": _weekly_tuesday,          # ANZ-Roy Morgan Consumer Confidence: weekly (every Tuesday).
}


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


def load_v1_abs_dates():
    """Real ABS release dates scraped by the v1 emit, keyed by v1 indicator id."""
    if not os.path.exists(V1_IND):
        print("  WARN: data/indicators.json (v1) not found; ABS dates stay on heuristic")
        return {}
    try:
        v1 = json.load(open(V1_IND))
        return {i["id"]: i for i in v1["indicators"]}
    except Exception as e:
        print(f"  WARN: could not read v1 indicators.json ({e}); ABS dates stay on heuristic")
        return {}


def main():
    doc = json.load(open(IND))
    v1_dates = load_v1_abs_dates()
    today = datetime.date.today()
    advanced = []
    abs_synced = []
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
        if sid in SURVEY_SCHEDULE:
            # Survey series: compute the real release date from each survey's
            # published cadence, replacing the drifting month-shift heuristic.
            sy, sm = int(new_latest[:4]), int(new_latest[5:7])
            last_d, next_d = SURVEY_SCHEDULE[sid](sy, sm, today)
            ind["last_release_date"] = last_d.isoformat()
            ind["next_release_estimate"] = next_d.isoformat()
            if adv > 0:
                advanced.append(f"{sid} {old_latest}->{new_latest}")
        else:
            if adv > 0:
                for k in ("last_release_date", "next_release_estimate"):
                    if ind.get(k):
                        ind[k] = shift_iso_months(ind[k], adv)
                advanced.append(f"{sid} {old_latest}->{new_latest}")
            # ABS series: override the month-shift heuristic with v1's scraped,
            # authoritative ABS release dates (falls back to the heuristic above
            # when v1 is missing or a field is null).
            src = ABS_DATE_MAP.get(sid)
            if src and src in v1_dates:
                for k in ("last_release_date", "next_release_estimate"):
                    v = v1_dates[src].get(k)
                    if v:
                        ind[k] = v
                abs_synced.append(sid)
        ind["series"] = new

    json.dump(doc, open(IND, "w"), indent=2)
    print(f"indicators_v2.json regenerated ({len(doc['indicators'])} indicators).")
    if advanced:
        print("Advanced:", ", ".join(advanced))
    else:
        print("All indicators already current.")
    if abs_synced:
        print(f"ABS dates synced from v1 ({len(abs_synced)}):", ", ".join(abs_synced))


if __name__ == "__main__":
    main()
