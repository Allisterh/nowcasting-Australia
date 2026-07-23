"""Test the "updated this run" detection + data_updates record in gen_indicators_v2.py.

Verifies the data-visibility feature: a series that gained a newer reference month
than it carried in the previously-committed JSON is flagged updated_this_run=True
(with prev/latest periods), an unchanged series is False, and latest_v2.json gets a
data_updates block listing exactly the advanced series plus the nowcast move.

Deterministic: runs the real generator against temp fixtures (no wall-clock or
network dependence beyond survey release-date formatting, which is not asserted).

Run: python3 nowcasting_v2/tests/test_data_updates.py
"""
import sys, os, json, csv, tempfile, importlib.util

GEN = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "gen_indicators_v2.py")
spec = importlib.util.spec_from_file_location("gen_indicators_v2", GEN)
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)

fails = []


def check(label, got, want):
    ok = got == want
    print(f"  {'PASS' if ok else 'FAIL'}  {label}: got={got!r} want={want!r}")
    if not ok:
        fails.append(label)


def write_csv(path, rows):
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["date", "value"])
        w.writerows(rows)


with tempfile.TemporaryDirectory() as tmp:
    raw = os.path.join(tmp, "data_raw")
    data = os.path.join(tmp, "data")
    os.makedirs(raw)
    os.makedirs(data)

    # Template = the *previous* run's committed grid. nab_conf ends May; wmi_sent
    # ends Jun.
    template = {"indicators": [
        {"id": "nab_conf", "name": "NAB Business Confidence", "group": "Business surveys",
         "unit": "net balance", "source": "NAB",
         "series": [{"date": "2026-04", "value": -24.0}, {"date": "2026-05", "value": -14.0}],
         "last_release_date": "2026-06-10", "next_release_estimate": "2026-07-14"},
        {"id": "wmi_sent", "name": "Westpac-MI Consumer Sentiment", "group": "Households",
         "unit": "index", "source": "Westpac",
         "series": [{"date": "2026-05", "value": 80.6}, {"date": "2026-06", "value": 83.9}],
         "last_release_date": "2026-06-09", "next_release_estimate": "2026-07-14"},
    ]}
    ind_path = os.path.join(data, "indicators_v2.json")
    json.dump(template, open(ind_path, "w"))

    # Fresh data_raw: nab_conf gained June (advances May->Jun); wmi_sent unchanged.
    write_csv(os.path.join(raw, "nab_conf.csv"),
              [["2026-04-01", -24.0], ["2026-05-01", -14.0], ["2026-06-01", -5.0]])
    write_csv(os.path.join(raw, "wmi_sent.csv"),
              [["2026-05-01", 80.6], ["2026-06-01", 83.9]])

    # Prior-emitted latest_v2.json with two same-quarter vintages -> delta = -0.10.
    lv2_path = os.path.join(data, "latest_v2.json")
    json.dump({"as_of": "2026-07-20", "vintages": [
        {"run_date": "2026-07-13", "target_quarter": "2026 Q2", "qoq_growth_pct": 0.07},
        {"run_date": "2026-07-20", "target_quarter": "2026 Q2", "qoq_growth_pct": -0.03},
    ]}, open(lv2_path, "w"))

    # Point the generator at the fixtures and run it.
    gen.ROOT = tmp
    gen.IND = ind_path
    gen.RAW = raw
    gen.V1_IND = os.path.join(data, "indicators.json")  # absent -> ABS sync skipped
    gen.main()

    doc = {i["id"]: i for i in json.load(open(ind_path))["indicators"]}
    check("nab_conf updated_this_run", doc["nab_conf"]["updated_this_run"], True)
    check("nab_conf prev_period", doc["nab_conf"]["prev_period"], "2026-05")
    check("nab_conf latest_period", doc["nab_conf"]["latest_period"], "2026-06")
    check("wmi_sent updated_this_run", doc["wmi_sent"]["updated_this_run"], False)

    du = json.load(open(lv2_path)).get("data_updates")
    check("data_updates present", du is not None, True)
    if du:
        check("run_date", du["run_date"], "2026-07-20")
        check("nowcast_delta_pp", du["nowcast_delta_pp"], -0.1)
        check("series ids", [s["id"] for s in du["series"]], ["nab_conf"])
        if du["series"]:
            check("series prev->latest",
                  (du["series"][0]["prev_period"], du["series"][0]["latest_period"]),
                  ("2026-05", "2026-06"))

print()
if fails:
    print(f"RESULT: {len(fails)} FAILED -> {fails}")
    sys.exit(1)
print("RESULT: ALL PASS")
