# tests/test_extract_from_james.py
from datetime import date
import extract_from_james as ej


def test_add_months_forward_and_back():
    assert ej.add_months(date(2022, 11, 1), 1) == date(2022, 12, 1)
    assert ej.add_months(date(2022, 12, 1), 1) == date(2023, 1, 1)
    assert ej.add_months(date(2023, 1, 1), -1) == date(2022, 12, 1)
    assert ej.add_months(date(2023, 2, 1), -2) == date(2022, 12, 1)


def test_months_lookup():
    assert ej.MONTHS["Jan"] == 1
    assert ej.MONTHS["Dec"] == 12


def test_parse_rows_basic_and_paren():
    text = "Jun 03, 2026 (May) 00:00 -22.4 -27.5"
    rows = ej.parse_rows(text)
    assert len(rows) == 1
    r = rows[0]
    assert r.release == date(2026, 6, 3)
    assert r.ref_token == "May"
    assert r.actual == -22.4
    assert r.previous == -27.5
    assert r.is_pct is False


def test_parse_rows_three_numbers_takes_first_as_actual():
    rows = ej.parse_rows("Apr 05, 2023 (Mar) 00:00 5.6 -4.0 -6.4")
    assert rows[0].actual == 5.6
    assert rows[0].previous == -6.4  # last token


def test_parse_rows_no_paren():
    rows = ej.parse_rows("Jan 03, 2011 22:30 46.3 47.6")
    assert rows[0].ref_token is None
    assert rows[0].release == date(2011, 1, 3)
    assert rows[0].actual == 46.3


def test_parse_rows_percent():
    rows = ej.parse_rows("Jun 09, 2026 (Jun) 01:30 -2.9% 3.5%")
    assert rows[0].is_pct is True
    assert rows[0].actual == -2.9
    assert rows[0].previous == 3.5


def test_parse_rows_skips_summary_line_without_time():
    # No HH:MM -> not a data row
    assert ej.parse_rows("Jun 03, 2026 -22.4 -27.5") == []
    assert ej.parse_rows("Release date Time Actual Forecast Previous") == []


def _row(rel, token, actual, prev=None, is_pct=False):
    return ej.Row(rel, token, actual, prev, is_pct, "")


def test_explicit_ref_year_boundary():
    # Feb 2025 release labelled (Dec) -> Dec 2024
    assert ej.explicit_ref(_row(date(2025, 2, 4), "Dec", -22.7)) == date(2024, 12, 1)
    # Jun 2026 release labelled (May) -> May 2026
    assert ej.explicit_ref(_row(date(2026, 6, 3), "May", -22.4)) == date(2026, 5, 1)
    # Same month
    assert ej.explicit_ref(_row(date(2026, 3, 31), "Mar", -27.9)) == date(2026, 3, 1)


def test_assign_aig_infers_no_paren_via_day_rule():
    # Mix of explicit (to learn the rule) and no-paren rows (to infer).
    rows = [
        _row(date(2011, 1, 31), "Jan", 46.7),   # day 31 -> offset 0
        _row(date(2011, 1, 3), None, 46.3),       # day 3  -> infer offset 1 -> Dec 2010
        _row(date(2010, 11, 30), "Nov", 47.6),    # day 30 -> offset 0
        _row(date(2010, 10, 1), None, 47.3),      # day 1  -> infer offset 1 -> Sep 2010
        _row(date(2010, 9, 1), "Aug", 51.7),      # learns offset 1 for day 1
    ]
    points = ej.assign_ref_month(rows)
    got = {p.row.release: p.ref_month for p in points}
    assert got[date(2011, 1, 3)] == date(2010, 12, 1)
    assert got[date(2010, 10, 1)] == date(2010, 9, 1)
    assert got[date(2011, 1, 31)] == date(2011, 1, 1)


def test_assign_westpac_all_offset_zero():
    rows = [
        _row(date(2026, 6, 9), "Jun", -2.9, is_pct=True),  # learns offset 0
        _row(date(2026, 5, 19), None, 3.5, is_pct=True),    # infer offset 0 -> May 2026
    ]
    points = ej.assign_ref_month(rows)
    got = {p.row.release: p.ref_month for p in points}
    assert got[date(2026, 5, 19)] == date(2026, 5, 1)


def test_validate_dedupes_agreeing_and_flags_disagreeing():
    p = [
        ej.Point(date(2018, 9, 1), 59.0, _row(date(2018, 10, 1), "Sep", 59.0)),
        ej.Point(date(2018, 9, 1), 59.0, _row(date(2018, 9, 30), "Sep", 59.0)),
        ej.Point(date(2017, 1, 1), 51.2, _row(date(2017, 2, 1), "Jan", 51.2)),
        ej.Point(date(2017, 1, 1), 99.9, _row(date(2017, 1, 31), "Jan", 99.9)),
    ]
    deduped, anomalies = ej.validate_series(p)
    assert deduped[date(2018, 9, 1)].value == 59.0
    assert any(a[0] == "dup_disagree" and a[1] == date(2017, 1, 1) for a in anomalies)


def test_validate_flags_chain_break():
    # Previous of newer row should ~match Actual of next-older row.
    p = [
        ej.Point(date(2022, 3, 1), 55.7, _row(date(2022, 3, 31), "Mar", 55.7, prev=53.2)),
        ej.Point(date(2022, 2, 1), 53.2, _row(date(2022, 2, 28), "Feb", 53.2, prev=48.4)),
        ej.Point(date(2022, 1, 1), 99.0, _row(date(2022, 1, 31), "Jan", 99.0, prev=54.8)),
    ]
    # newer row prev=53.2 matches older actual 53.2 -> ok
    # 2022-02 prev=48.4 vs older actual 99.0 -> break
    _, anomalies = ej.validate_series(p)
    assert any(a[0] == "chain_break" for a in anomalies)


def test_transform_aig_old_era_converts():
    nf = ej.AIG_NEW_FROM["aig_pmi"]  # date(2023, 2, 1)
    assert ej.transform_aig(50.0, date(2020, 6, 1), nf) == 0.0
    assert ej.transform_aig(60.0, date(2020, 6, 1), nf) == 20.0
    assert ej.transform_aig(32.4, date(2013, 1, 1), nf) == -35.2


def test_transform_aig_new_era_passthrough():
    nf = ej.AIG_NEW_FROM["aig_pmi"]
    assert ej.transform_aig(-6.4, date(2023, 2, 1), nf) == -6.4
    assert ej.transform_aig(5.6, date(2023, 3, 1), nf) == 5.6


def test_transform_aig_services_all_old():
    nf = ej.AIG_NEW_FROM["aig_psi"]   # far future
    assert ej.transform_aig(45.6, date(2022, 11, 1), nf) == -8.8


def test_assert_clean_break_rejects_negative_in_old_era():
    # An old-era negative value means the break is misconfigured.
    pts = {date(2020, 6, 1): ej.Point(date(2020, 6, 1), -5.0, _row(date(2020, 7, 1), "Jun", -5.0))}
    import pytest
    with pytest.raises(ValueError):
        ej.assert_clean_aig_break(pts, ej.AIG_NEW_FROM["aig_pmi"])


def test_reconstruct_hits_anchors_and_fills_between():
    # pct[m] is the % change AT month m vs m-1.
    pct = {
        date(2020, 1, 1): 0.0,
        date(2020, 2, 1): 10.0,   # +10%
        date(2020, 3, 1): -50.0,  # will be overridden by anchor at Mar
    }
    anchors = {date(2020, 1, 1): 100.0, date(2020, 3, 1): 121.0}
    levels, drift, unanchored = ej.reconstruct_westpac_levels(pct, anchors)
    assert levels[date(2020, 1, 1)] == 100.0      # anchor
    assert levels[date(2020, 2, 1)] == 110.0      # 100 * 1.10
    assert levels[date(2020, 3, 1)] == 121.0      # anchor (reset)
    assert unanchored == []
    # drift recorded at the Mar anchor: arrived 110*0.5=55 vs true 121
    assert any(m == date(2020, 3, 1) for m, _ in drift)


def test_reconstruct_backfills_before_first_anchor():
    pct = {date(2020, 1, 1): 0.0, date(2020, 2, 1): 25.0}
    anchors = {date(2020, 2, 1): 125.0}
    levels, drift, unanchored = ej.reconstruct_westpac_levels(pct, anchors)
    assert levels[date(2020, 2, 1)] == 125.0
    assert levels[date(2020, 1, 1)] == 100.0      # 125 / 1.25
    assert unanchored == []


def test_reconstruct_gap_splits_segments_drops_unanchored():
    # A survey gap splits the series into segments. The pre-gap segment has no
    # anchor, so it is dropped (reported in `unanchored`); the post-gap segment
    # is anchored and reconstructed. Must not raise.
    pct = {
        date(2020, 1, 1): 5.0,
        # 2020-02 deliberately missing (gap) -> [2020-01] is its own segment
        date(2020, 3, 1): 10.0,
        date(2020, 4, 1): 2.0,
    }
    anchors = {date(2020, 3, 1): 121.0}
    levels, drift, unanchored = ej.reconstruct_westpac_levels(pct, anchors)
    assert levels[date(2020, 3, 1)] == 121.0
    assert levels[date(2020, 4, 1)] == round(121.0 * 1.02, 1)
    # The anchorless pre-gap segment is dropped and reported, not crashed/None.
    assert date(2020, 1, 1) not in levels
    assert (date(2020, 1, 1), date(2020, 1, 1)) in unanchored


def test_reconstruct_anchor_must_be_in_series():
    # An anchor whose month is not in the pct series cannot anchor a segment
    # (levels propagate only along existing pct links). The pct segment is left
    # unanchored and dropped rather than silently mis-seeded. In real data every
    # anchor IS an in-series month, so this only guards the misconfigured case.
    pct = {
        date(2020, 1, 1): 10.0,
        date(2020, 2, 1): 0.0,
        date(2020, 3, 1): 5.0,
    }
    anchors = {date(2019, 12, 1): 200.0}  # anchor month NOT in pct
    levels, drift, unanchored = ej.reconstruct_westpac_levels(pct, anchors)
    assert levels == {}
    assert (date(2020, 1, 1), date(2020, 3, 1)) in unanchored


def test_validate_duplicate_no_spurious_chain_break():
    # Fix 3: an agreeing duplicate of a month must not create a false chain_break,
    # and a genuine break across a one-month gap is still flagged.
    p = [
        # 2022-03 duplicate listings (both agree at 55.7), prev=53.2 matches 2022-02
        ej.Point(date(2022, 3, 1), 55.7, _row(date(2022, 3, 31), "Mar", 55.7, prev=53.2)),
        ej.Point(date(2022, 3, 1), 55.7, _row(date(2022, 3, 30), "Mar", 55.7, prev=53.2)),
        ej.Point(date(2022, 2, 1), 53.2, _row(date(2022, 2, 28), "Feb", 53.2, prev=99.0)),
        # gap: no 2022-01; next older month is 2021-12 with actual 50.0
        ej.Point(date(2021, 12, 1), 50.0, _row(date(2021, 12, 31), "Dec", 50.0, prev=49.0)),
    ]
    _, anomalies = ej.validate_series(p)
    breaks = [a for a in anomalies if a[0] == "chain_break"]
    # The duplicate must NOT inject a chain_break for 2022-03.
    assert not any(a[1] == date(2022, 3, 1) for a in breaks)
    # 2022-02 prev=99.0 vs next-older (2021-12) actual 50.0 -> genuine break flagged.
    assert any(a[1] == date(2022, 2, 1) for a in breaks)


def test_load_anchors_reads_csv():
    anchors = ej.load_westpac_anchors("westpac_anchors.csv")
    assert anchors[date(2026, 6, 1)] == 80.6
    assert anchors[date(2012, 2, 1)] == 95.5


def test_write_series_sorts_ascending_and_formats(tmp_path):
    pts = {
        date(2022, 2, 1): ej.Point(date(2022, 2, 1), 53.2, _row(date(2022, 2, 28), "Feb", 53.2)),
        date(2021, 12, 1): ej.Point(date(2021, 12, 1), -1.0, _row(date(2022, 1, 31), "Dec", -1.0)),
    }
    out = tmp_path / "x.csv"
    ej.write_series(str(out), pts)
    lines = out.read_text().splitlines()
    assert lines[0] == "date,value"
    assert lines[1] == "2021-12-01,-1.0"   # earliest first
    assert lines[2] == "2022-02-01,53.2"


def test_backup_existing(tmp_path):
    src = tmp_path / "data"
    src.mkdir()
    (src / "aig_pmi.csv").write_text("date,value\n2020-01-01,1.0\n")
    backup = tmp_path / "data" / "_pre_james_backup"
    ej.backup_csvs(str(src), str(backup), ["aig_pmi"])
    assert (backup / "aig_pmi.csv").read_text().startswith("date,value")


def test_sources_config_complete():
    ids = {s[0] for s in ej.SOURCES}
    assert ids == {"aig_pmi", "aig_pci", "aig_psi", "nab_cond", "nab_conf", "wmi_sent"}
    # every AiG series has a configured break
    for sid, _, kind in ej.SOURCES:
        if kind == "aig":
            assert sid in ej.AIG_NEW_FROM


def test_process_source_nab_passthrough(tmp_path, monkeypatch):
    # Feed canned text instead of a real PDF.
    text = ("Jun 09, 2026 (May) 02:30 3.00 3.00\n"
            "May 12, 2026 (Apr) 02:30 3.00 6.00\n"
            "Apr 14, 2026 (Mar) 02:30 6.00 6.00\n")
    monkeypatch.setattr(ej, "pdf_text", lambda p: text)
    pts, anomalies, prov = ej.process_source(
        ("nab_cond", "fake.pdf", "nab"), data_dir=str(tmp_path), anchors={})
    assert pts[date(2026, 5, 1)].value == 3.00
    assert pts[date(2026, 3, 1)].value == 6.00


def _pt(y, m, v):
    return ej.Point(date(y, m, 1), v, _row(date(y, m, 28), None, v))


def test_detect_new_from_construction_jan2023():
    # Construction: old positive through Nov-2022, first negative (new scale) Jan-2023.
    deduped = {p.ref_month: p for p in [
        _pt(2020, 5, 21.6),   # COVID diffusion low (old, <25) must NOT trigger
        _pt(2022, 10, 43.3),
        _pt(2022, 11, 48.2),
        _pt(2023, 1, -5.0),   # first new-scale reading
        _pt(2023, 3, -5.8),
    ]}
    assert ej.detect_new_from(deduped) == date(2023, 1, 1)


def test_detect_new_from_manufacturing_feb2023():
    deduped = {p.ref_month: p for p in [
        _pt(2022, 11, 44.7),
        _pt(2023, 2, -6.4),
    ]}
    assert ej.detect_new_from(deduped) == date(2023, 2, 1)


def test_detect_new_from_services_never_switches():
    deduped = {p.ref_month: p for p in [
        _pt(2021, 6, 56.8),
        _pt(2022, 11, 45.6),
    ]}
    assert ej.detect_new_from(deduped) == ej.FAR_FUTURE


def test_backup_does_not_clobber_existing(tmp_path):
    src = tmp_path / "data"
    src.mkdir()
    (src / "aig_pmi.csv").write_text("date,value\nORIGINAL\n")
    backup = tmp_path / "data" / "_pre_james_backup"
    ej.backup_csvs(str(src), str(backup), ["aig_pmi"])
    # simulate a regenerated source file, then re-run backup
    (src / "aig_pmi.csv").write_text("date,value\nREGENERATED\n")
    ej.backup_csvs(str(src), str(backup), ["aig_pmi"])
    # backup must still hold the ORIGINAL, not the regenerated content
    assert "ORIGINAL" in (backup / "aig_pmi.csv").read_text()


def test_process_source_aig_asserts_then_converts(tmp_path, monkeypatch):
    # Old-era (pre-break) diffusion + new-era net balance. process_source must
    # verify the break on RAW values BEFORE converting, then splice old->new.
    text = ("Mar 31, 2023 (Mar) 00:00 5.6 -4.0\n"   # new era, ref Mar-2023, passthrough
            "Feb 28, 2023 (Feb) 00:00 -6.4 -17.1\n"  # new era, first new
            "Nov 30, 2022 (Nov) 00:00 44.7 49.6\n")   # old era, ref Nov-2022 -> (44.7-50)*2
    monkeypatch.setattr(ej, "pdf_text", lambda p: text)
    pts, anomalies, prov = ej.process_source(
        ("aig_pmi", "fake.pdf", "aig"), data_dir=str(tmp_path), anchors={})
    assert pts[date(2022, 11, 1)].value == -10.6   # old converted to new scale
    assert pts[date(2023, 2, 1)].value == -6.4      # new-era passthrough
    assert pts[date(2023, 3, 1)].value == 5.6       # new-era passthrough


def test_process_source_westpac_writes_pct_and_levels(tmp_path, monkeypatch):
    text = ("Mar 09, 2020 (Mar) 00:00 -50.0% 10.0%\n"
            "Feb 09, 2020 (Feb) 00:00 10.0% 0.0%\n"
            "Jan 09, 2020 (Jan) 00:00 0.0% 1.0%\n")
    monkeypatch.setattr(ej, "pdf_text", lambda p: text)
    anchors = {date(2020, 1, 1): 100.0, date(2020, 3, 1): 121.0}
    pts, anomalies, prov = ej.process_source(
        ("wmi_sent", "fake.pdf", "westpac"), data_dir=str(tmp_path), anchors=anchors)
    # levels wired through (not the raw %), anchors hit exactly
    assert pts[date(2020, 1, 1)].value == 100.0
    assert pts[date(2020, 2, 1)].value == 110.0
    assert pts[date(2020, 3, 1)].value == 121.0
    # raw % series persisted
    assert (tmp_path / "wmi_sent_pct.csv").exists()


def test_assert_clean_aig_break_rejects_new_era_out_of_range():
    import pytest
    pts = {date(2023, 6, 1): ej.Point(date(2023, 6, 1), 150.0,
           _row(date(2023, 7, 1), None, 150.0))}  # >100 on new scale
    with pytest.raises(ValueError):
        ej.assert_clean_aig_break(pts, date(2023, 2, 1))
