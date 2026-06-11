# Nowcast handoff — from_james survey/sentiment series

Self-contained package to port into the nowcast working directory.

**Start here:** read `NOWCAST_INTEGRATION_NOTES.md` first — it covers the scale/units traps
(AiG is now −100/+100, not 0–100), the reference-month-vs-release-date convention, coverage
gaps and confidence, and the NAB-inconsistency warning. Don't wire these in before reading it.

## Manifest

```
NOWCAST_INTEGRATION_NOTES.md          read first — integration guide + gotchas
from-james-pdf-ingestion-design.md    the design spec (rationale for every decision)
extract_from_james.py                 the regenerator (idempotent)
westpac_anchors.csv                   Westpac level anchors (add rows + re-run to tighten history)
tests/test_extract_from_james.py      33 tests guarding the pipeline
from_james/*.pdf                      source PDFs (re-export + re-run to refresh)
data/
  aig_pmi.csv  aig_pci.csv  aig_psi.csv   AiG Mfg/Constr/Services, −100..+100 (0=neutral)
  nab_cond.csv  nab_conf.csv              NAB Conditions/Confidence, net balance
  wmi_sent.csv                            Westpac consumer sentiment, index level (100=neutral)
  wmi_sent_pct.csv                        Westpac MoM % (alt representation)
  provenance_from_james.csv               every value → source PDF + release_date (use for vintage)
  *_review.csv                            flagged observations (advisory; values still in series)
```

## Refresh / re-run (from this folder, with the project venv)

```
.venv\Scripts\python.exe -m pytest tests/ -q       # expect 33 passed
.venv\Scripts\python.exe extract_from_james.py      # regenerates data/ + FROM_JAMES_REPORT.md
```

The script reads `from_james/` + `westpac_anchors.csv` and writes `data/` — all paths relative
to this folder, so it runs as-is once a Python env with `pdfplumber` is available.

## Not included (still open, see notes)

- S&P / Judo Manufacturing & Services PMI — never sourced.
- NAB sub-series (trade/profit/emp/forward/stocks/cu) — still on the old 2012+ scrape, not here.
- Westpac pre-1988 and Jan-2008 — unreconstructable from available data.
