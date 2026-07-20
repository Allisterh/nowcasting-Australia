"""Regression test for the survey release-date schedule in gen_indicators_v2.py.

Guards the "Updated" / "Next release" columns of the indicator grid against the
bug where survey series rode a drifting month-shift heuristic and produced wrong
(and sometimes FUTURE) dates — e.g. ANZ-Roy Morgan showing a release in the next
month. Deterministic: `today` is injected, so it never depends on the wall clock.

Run: python3 nowcasting_v2/tests/test_release_schedule.py
"""
import sys, os, datetime, importlib.util

GEN = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "gen_indicators_v2.py")
spec = importlib.util.spec_from_file_location("gen_indicators_v2", GEN)
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)

TODAY = datetime.date(2026, 7, 20)  # a Monday
sched = gen.SURVEY_SCHEDULE
fails = []


def check(label, got, want):
    ok = str(got) == str(want)
    print(f"  {'PASS' if ok else 'FAIL'}  {label}: got={got} want={want}")
    if not ok:
        fails.append(label)


# NAB Monthly Business Survey: 2nd Tuesday of the month AFTER the reference month.
last, nxt = sched["nab_conf"](2026, 6, TODAY)
check("NAB Jun -> last_release", last, datetime.date(2026, 7, 14))
check("NAB Jun -> next_release", nxt, datetime.date(2026, 8, 11))

# Westpac-MI Consumer Sentiment: 2nd Tuesday of the SAME (data) month.
last, nxt = sched["wmi_sent"](2026, 7, TODAY)
check("Westpac Jul -> last_release", last, datetime.date(2026, 7, 14))
check("Westpac Jul -> next_release", nxt, datetime.date(2026, 8, 11))

# ANZ-Indeed Job Ads: ~1st Tuesday of the following month.
last, nxt = sched["anz_ads"](2026, 6, TODAY)
check("ANZ Job Ads Jun -> last_release", last, datetime.date(2026, 7, 7))
check("ANZ Job Ads Jun -> next_release", nxt, datetime.date(2026, 8, 4))

# ANZ-Roy Morgan Consumer Confidence: WEEKLY (every Tuesday). Stored monthly, but
# refreshed weekly -> last Tue <= today, next Tue > today, never in the future.
last, nxt = sched["anz_sent"](2026, 7, TODAY)
check("ANZ-RM -> last_release (last Tue <= today)", last, datetime.date(2026, 7, 14))
check("ANZ-RM -> next_release (next Tue)", nxt, datetime.date(2026, 7, 21))
check("ANZ-RM last_release not in future", last <= TODAY, True)

print("\nRESULT:", "ALL PASS" if not fails else f"{len(fails)} FAILURE(S): {fails}")
sys.exit(1 if fails else 0)
