# extract_from_james.py
"""Ingest investing.com calendar PDFs in from_james/ and regenerate series."""
from __future__ import annotations
import csv
import os
import re
import shutil
from dataclasses import dataclass
from datetime import date, datetime

MONTHS = {m: i for i, m in enumerate(
    ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
     "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"], start=1)}


@dataclass
class Row:
    release: date
    ref_token: str | None
    actual: float
    previous: float | None
    is_pct: bool
    raw: str


@dataclass
class Point:
    ref_month: date
    value: float
    row: "Row"


def add_months(d: date, delta: int) -> date:
    idx = d.year * 12 + (d.month - 1) + delta
    return date(idx // 12, idx % 12 + 1, 1)


_ROW_RE = re.compile(
    r"^([A-Z][a-z]{2} \d{2}, \d{4})"      # release date
    r"(?:\s*\(([A-Z][a-z]{2})\))?"          # optional (RefMonth)
    r"\s+(\d{2}:\d{2})"                      # REQUIRED time
    r"\s+(.+)$"                              # tail: actual [forecast] [previous]
)
_NUM_RE = re.compile(r"-?\d+(?:\.\d+)?")


def parse_rows(text: str) -> list[Row]:
    rows: list[Row] = []
    for line in text.splitlines():
        line = line.strip()
        m = _ROW_RE.match(line)
        if not m:
            continue
        rel = datetime.strptime(m.group(1), "%b %d, %Y").date()
        tail = m.group(4)
        nums = [float(x) for x in _NUM_RE.findall(tail)]
        if not nums:
            continue
        rows.append(Row(
            release=rel,
            ref_token=m.group(2),
            actual=nums[0],
            previous=nums[-1] if len(nums) > 1 else None,
            is_pct="%" in tail,
            raw=line,
        ))
    return rows


def pdf_text(path: str) -> str:
    import warnings
    import pdfplumber
    out = []
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        with pdfplumber.open(path) as pdf:
            for page in pdf.pages:
                out.append(page.extract_text() or "")
    return "\n".join(out)


def explicit_ref(row: Row) -> date:
    rm = MONTHS[row.ref_token]
    year = row.release.year
    if rm > row.release.month:  # token month after release month -> previous year
        year -= 1
    return date(year, rm, 1)


def learn_offset_rule(rows: list[Row]):
    """Return f(day)->offset_months, learned from explicit rows (offsets 0/1 only)."""
    pairs = []
    for r in rows:
        if r.ref_token:
            ref = explicit_ref(r)
            off = (r.release.year * 12 + r.release.month) - (ref.year * 12 + ref.month)
            if off in (0, 1):
                pairs.append((r.release.day, off))
    offsets = {o for _, o in pairs}
    if offsets == {0} or not pairs:
        return lambda day: 0
    if offsets == {1}:
        return lambda day: 1
    days_off1 = [d for d, o in pairs if o == 1]
    days_off0 = [d for d, o in pairs if o == 0]
    thr = (max(days_off1) + min(days_off0)) / 2.0
    if not (max(days_off1) < min(days_off0)):  # overlap -> fall back to 15
        thr = 15
    return lambda day: 1 if day <= thr else 0


def assign_ref_month(rows: list[Row]) -> list[Point]:
    rule = learn_offset_rule(rows)
    points = []
    for r in rows:
        if r.ref_token:
            ref = explicit_ref(r)
        else:
            off = rule(r.release.day)
            ref = add_months(date(r.release.year, r.release.month, 1), -off)
        points.append(Point(ref, r.actual, r))
    return points


CHAIN_TOL = 1.0


def validate_series(points: list[Point]):
    anomalies = []
    by_month: dict[date, list[Point]] = {}
    for p in points:
        by_month.setdefault(p.ref_month, []).append(p)
    deduped = {}
    for m, ps in by_month.items():
        vals = {round(p.value, 4) for p in ps}
        if len(vals) > 1:
            anomalies.append(("dup_disagree", m, [p.value for p in ps]))
        deduped[m] = ps[0]
    # Previous-column chain built from the DEDUPED points (one per month),
    # ordered by ref_month descending (newest month first). Comparing each
    # month's "Previous" to the next-older *month* avoids spurious breaks from
    # duplicate listings of the same month and is also correct across genuine
    # survey gaps (investing.com "Previous" = the prior available month).
    ordered = sorted(deduped.values(), key=lambda p: p.ref_month, reverse=True)
    for i in range(len(ordered) - 1):
        prev = ordered[i].row.previous
        older = ordered[i + 1].value
        if prev is not None and prev != 0.0 and abs(prev - older) > CHAIN_TOL:
            anomalies.append(("chain_break", ordered[i].ref_month, prev, older))
    return deduped, anomalies


FAR_FUTURE = date(9999, 12, 1)

# Known/expected methodology-break ref months (informational + test fixtures).
# process_source does NOT trust these — it detects the break from the data via
# detect_new_from(), because the indices switched at slightly different months
# (Manufacturing Feb-2023, Construction Jan-2023) and Services never switched.
AIG_NEW_FROM = {
    "aig_pmi": date(2023, 2, 1),   # Manufacturing: last old Nov-2022, first new Feb-2023
    "aig_pci": date(2023, 1, 1),   # Construction: first new Jan-2023 (released Feb-28-2023)
    "aig_psi": FAR_FUTURE,         # Services: discontinued Nov-2022, all old-scale
}

NEW_SCALE_WINDOW_START = date(2022, 6, 1)  # excludes the 2020 COVID diffusion lows
NEW_SCALE_MAX = 25.0                        # old diffusion stays >25 in this window


def detect_new_from(deduped: dict[date, "Point"]) -> date:
    """First ref month (from mid-2022 on) whose RAW value is new-scale.

    The old diffusion scale (0..100, 50=neutral) never goes negative and, post-COVID,
    stays well above 25; the new net-balance scale's first reading is negative/small.
    So the earliest ref month >= 2022-06 with value <= 25 marks the switch. Returns
    FAR_FUTURE when the series never switched (e.g. Services, discontinued in 2022).
    """
    candidates = sorted(m for m, p in deduped.items()
                        if m >= NEW_SCALE_WINDOW_START and p.value <= NEW_SCALE_MAX)
    return candidates[0] if candidates else FAR_FUTURE


def transform_aig(value: float, ref_month: date, new_from: date) -> float:
    if ref_month < new_from:
        return round((value - 50.0) * 2.0, 1)
    return value


def assert_clean_aig_break(deduped: dict[date, Point], new_from: date) -> None:
    """Old-era diffusion values are 0..100; a negative there means a misconfigured break."""
    for m, p in deduped.items():
        if m < new_from and not (0.0 <= p.value <= 100.0):
            raise ValueError(f"old-era AiG value out of 0..100 at {m}: {p.value}")
        if m >= new_from and not (-100.0 <= p.value <= 100.0):
            raise ValueError(f"new-era AiG value out of -100..100 at {m}: {p.value}")


def load_westpac_anchors(path: str) -> dict[date, float]:
    anchors = {}
    with open(path, newline="") as fh:
        for row in csv.DictReader(fh):
            y, m, d = row["date"].split("-")
            anchors[date(int(y), int(m), int(d))] = float(row["level"])
    return anchors


def _contiguous_segments(months: list[date]) -> list[list[date]]:
    """Split a sorted month list into maximal runs of consecutive months.
    A survey gap (a missing month) ends a run, because the % chain links m-1 -> m
    only when pct[m] exists, so levels cannot propagate across a gap."""
    segments, seg = [], []
    for m in months:
        if seg and m != add_months(seg[-1], 1):
            segments.append(seg)
            seg = []
        seg.append(m)
    if seg:
        segments.append(seg)
    return segments


def reconstruct_westpac_levels(pct_by_month: dict[date, float],
                               anchors: dict[date, float]):
    """Reconstruct index levels from MoM %, segment by segment (gap-aware).

    Within each contiguous segment, propagate from the earliest in-segment anchor
    (forward, re-anchoring at later anchors; backward to the segment start). A
    segment with no anchor cannot be leveled and is reported in `unanchored`.
    Returns (levels, drift, unanchored) where drift is [(month, propagated-truth)]
    at each re-anchor and unanchored is [(start, end)] of dropped segments.
    """
    levels: dict[date, float] = {}
    drift = []
    unanchored = []
    for seg in _contiguous_segments(sorted(pct_by_month)):
        seg_anchor_months = [m for m in seg if m in anchors]
        if not seg_anchor_months:
            unanchored.append((seg[0], seg[-1]))
            continue
        first_a = seg_anchor_months[0]   # earliest anchor in this segment
        idx = seg.index(first_a)
        # forward from the first anchor, re-anchoring at any later anchors
        cur = anchors[first_a]
        levels[first_a] = cur
        for m in seg[idx + 1:]:
            cur = cur * (1 + pct_by_month[m] / 100.0)
            if m in anchors:
                drift.append((m, round(cur - anchors[m], 2)))
                cur = anchors[m]   # reset to ground truth
            levels[m] = cur
        # backward from the first anchor to the start of the segment
        cur = anchors[first_a]
        for m in reversed(seg[:idx]):
            nxt = add_months(m, 1)
            cur = cur / (1 + pct_by_month[nxt] / 100.0)
            levels[m] = cur
    return ({m: round(v, 1) for m, v in levels.items()}, drift, unanchored)


def write_series(path: str, points: dict[date, Point]) -> None:
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["date", "value"])
        for m in sorted(points):
            v = points[m].value
            w.writerow([m.isoformat(), f"{v:.1f}" if isinstance(v, float) else v])


def backup_csvs(data_dir: str, backup_dir: str, series_ids: list[str]) -> None:
    """Snapshot the pre-existing CSVs ONCE. Never overwrite an existing backup, so
    re-running the ingestion can't clobber the original snapshot with regenerated data."""
    os.makedirs(backup_dir, exist_ok=True)
    for sid in series_ids:
        src = os.path.join(data_dir, f"{sid}.csv")
        dst = os.path.join(backup_dir, f"{sid}.csv")
        if os.path.exists(src) and not os.path.exists(dst):
            shutil.copy2(src, dst)


def write_provenance(path: str, records: list[tuple]) -> None:
    # records: (series_id, ref_month_iso, value, source_pdf, release_iso)
    with open(path, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["series", "ref_month", "value", "source_pdf", "release_date"])
        w.writerows(records)


SOURCES = [
    ("aig_pmi", "Australian Industry Group (AIG) Manufacturing Index.pdf", "aig"),
    ("aig_pci", "Australian Industry Group (AIG) Construction Index.pdf", "aig"),
    ("aig_psi", "Australian Industry Group (AIG) Services Index.pdf", "aig"),
    ("nab_cond", "National Australia Bank (NAB) Business Conditions.pdf", "nab"),
    ("nab_conf", "National Australia Bank (NAB) Business Confidence.pdf", "nab"),
    ("wmi_sent", "Australia Westpac Consumer Sentiment.pdf", "westpac"),
]
FROM_DIR = "from_james"


def process_source(source, data_dir, anchors):
    sid, fname, kind = source
    text = pdf_text(os.path.join(FROM_DIR, fname))
    rows = parse_rows(text)
    points = assign_ref_month(rows)
    deduped, anomalies = validate_series(points)

    if kind == "aig":
        nf = detect_new_from(deduped)  # per-series break, detected from the data
        # Verify the break on RAW values (old-era diffusion 0..100, new-era
        # net-balance -100..100) BEFORE converting; afterwards every value is
        # on the new scale and the old-era 0..100 check would no longer hold.
        assert_clean_aig_break(deduped, nf)
        for m, p in deduped.items():
            p.value = transform_aig(p.value, m, nf)
    elif kind == "westpac":
        pct = {m: p.value for m, p in deduped.items()}
        levels, drift, unanchored = reconstruct_westpac_levels(pct, anchors)
        # also persist the raw % series
        write_series(os.path.join(data_dir, "wmi_sent_pct.csv"), deduped)
        deduped = {m: Point(m, lvl, deduped[m].row) for m, lvl in levels.items()}
        anomalies.append(("westpac_drift", drift))
        anomalies.append(("westpac_unanchored", unanchored))
    # nab: pass-through

    prov = [(sid, m.isoformat(), deduped[m].value, fname,
             deduped[m].row.release.isoformat()) for m in sorted(deduped)]
    return deduped, anomalies, prov


def main():
    data_dir = "data"
    ids = [s[0] for s in SOURCES]
    backup_csvs(data_dir, os.path.join(data_dir, "_pre_james_backup"), ids)
    anchors = load_westpac_anchors("westpac_anchors.csv")
    all_prov = []
    report_lines = ["# from_james ingestion report", ""]
    for source in SOURCES:
        sid = source[0]
        deduped, anomalies, prov = process_source(source, data_dir, anchors)
        write_series(os.path.join(data_dir, f"{sid}.csv"), deduped)
        # review file for non-drift anomalies
        review = [a for a in anomalies if a[0] in ("dup_disagree", "chain_break")]
        if review:
            with open(os.path.join(data_dir, f"{sid}_review.csv"), "w", newline="") as fh:
                w = csv.writer(fh)
                w.writerow(["kind", "detail"])
                for a in review:
                    w.writerow([a[0], "|".join(str(x) for x in a[1:])])
        all_prov.extend(prov)
        months = sorted(deduped)
        if months:
            report_lines.append(
                f"- **{sid}**: {len(deduped)} months, "
                f"{months[0].isoformat()} -> {months[-1].isoformat()}, "
                f"{len(review)} flagged")
        else:
            report_lines.append(f"- **{sid}**: 0 months, {len(review)} flagged")
        # Surface Westpac reconstruction diagnostics
        for a in anomalies:
            if a[0] == "westpac_drift" and a[1]:
                worst = max(a[1], key=lambda d: abs(d[1]))
                report_lines.append(
                    f"    - re-anchor points: {len(a[1])}; "
                    f"largest pre-reset drift: {worst[1]:+.2f} at {worst[0].isoformat()}")
            if a[0] == "westpac_unanchored" and a[1]:
                spans = ", ".join(f"{s.isoformat()}..{e.isoformat()}" for s, e in a[1])
                report_lines.append(
                    f"    - dropped (no anchor in segment): {spans}")
    write_provenance(os.path.join(data_dir, "provenance_from_james.csv"), all_prov)
    with open("FROM_JAMES_REPORT.md", "w", encoding="utf-8") as fh:
        fh.write("\n".join(report_lines) + "\n")


if __name__ == "__main__":
    main()
