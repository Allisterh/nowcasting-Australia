# Data-visibility feature — handoff notes

<!-- POINT-IN-TIME -->
> **Point-in-time record — 2026-07-23. Not current state.**
> This document describes what was true when it was written. The model, panel and
> calibration have changed since; several numbers here are known to be superseded.
> For current state see `README.md`, and for the 2026-08 fidelity review and its
> corrections log see `docs/reviews/2026-08-01-v2-intention-and-bug-review.md`.


**Branch:** `claude/nowcast-model-data-visibility-ienvde`
**Status:** DONE — verified end-to-end locally (CLI, 23 Jul 2026) and merged.

Local verification results (23 Jul):
- Full v1 pipeline ran clean; `data_updates` flagged exactly the 4 labour series
  that advanced May→Jun (Jun LFS, released 23 Jul), delta −0.01pp (0.66→0.65).
- Fixed one real bug found in the process: unflagged indicators emitted
  `"prev_period": {}` (jsonlite serialises a named `NULL` as `{}`), violating the
  frontend's `prev_period?: string` contract. Fields are now omitted entirely
  when a series didn't advance; `test_emit_json.R` asserts this.
- `test_emit_json.R` passes (fixtures regenerable from any run live in the
  gitignored `pipeline/tests/fixtures/`); Python suites + vitest + build green.
- Go-live: waited for the Monday cron — pushing mid-week couldn't light the main
  page anyway ("/" reads `indicators_v2.json`, and `data_raw/` only refreshes with
  the Sunday cloud routine, so a local v2 regen finds zero advances).

---

## Why this exists

James asked: *"I can't see what new data updated that fed each week's model run —
e.g. I don't know what data was updated last week that saw the Monday run drop the
nowcast to −0.03%."*

The pipeline **already computed** that attribution every run and then **threw it
away** (it lived only in gitignored `.cache/` vintage RDS files, or was `print()`ed
and discarded in `gen_indicators_v2.py`). This change captures it and surfaces it.

Reconstructed cause of the 20 Jul 2026 −0.03% (v2 headline `v2_qa_a05`, target
2026 Q2): 10 survey series advanced that run — the NAB business block + ANZ Job Ads
(May→Jun) and both consumer-sentiment reads (ANZ-RM, Westpac-MI, Jun→Jul); the
nowcast moved −0.10pp (from +0.07%). Confidence/sentiment actually *rose*, yet the
number fell — which is exactly why "what updated" needs surfacing and why the real
*attribution* (Level 2, see below) is worth doing later.

## Scope delivered (James approved)

- **Level 1** — capture "what data fed this run + how far the nowcast moved" as a
  durable record. Mechanism chosen: **"updated this run"** = a series carries a
  newer reference month than it did in the *previously-committed* JSON.
- **Level 3** — highlight the updated series *in the indicator grid* (no separate
  panel). Teal "updated this week" dot + legend on the cards; badge + "May → Jun"
  tooltip on the table's Updated column.
- **Level 1 record lives quietly** in `latest.json` / `latest_v2.json` as a
  `data_updates` block (no visible headline line — James's call).

## Files changed

| File | What |
|---|---|
| `src/lib/types.ts` | `updated_this_run`/`prev_period`/`latest_period` on `Indicator`; `DataUpdates` record on `LatestNowcast` + `LatestV2`. |
| `pipeline/04_emit_json.R` | **(v1, UNRUN)** diff fresh series vs previously-committed `indicators.json` → per-indicator flags; emit `data_updates` on `latest.json` (delta = qoq vs prior same-quarter run). |
| `nowcasting_v2/gen_indicators_v2.py` | **(v2, verified)** write flags from the advance it already computes; patch `latest_v2.json` with `data_updates` (delta from vintage log). |
| `src/components/IndicatorGrid.tsx` | teal dot + "updated this week" legend. |
| `src/components/IndicatorsTable.tsx` | teal badge + tooltip on the Updated cell. |
| `nowcasting_v2/tests/test_data_updates.py` | **new**, passing — covers advance-detection + `data_updates`. |
| `pipeline/tests/test_emit_json.R` | **(UNRUN)** asserts the fields exist + empty-baseline case. |

## Verified in the remote env

- `npm run build` typechecks clean; `npm test` → 19 vitest pass (the one failing
  file is `tests/site.spec.ts`, a Playwright spec vitest picks up by mistake —
  pre-existing, unrelated).
- `python3 nowcasting_v2/tests/test_data_updates.py` → ALL PASS.
- `python3 nowcasting_v2/tests/test_release_schedule.py` → ALL PASS (unbroken).
- Rendered the highlight live against the real 20 Jul advances — looks right.

## NOT verified (do this here)

The v1 R path (`04_emit_json.R`, `pipeline/tests/test_emit_json.R`) — no R in the
remote env. It's straightforward plumbing and was reviewed carefully, but unrun.

```bash
# from repo root, with the pipeline renv set up
cd pipeline
Rscript run_complete_nowcast.R      # full v1 run (fetches ABS/NAB/FRED, emits JSON)
Rscript tests/test_emit_json.R      # emit smoke test (now asserts the new fields)
```

Then check the output:

```bash
# latest.json should have a data_updates block:
#   { "run_date": "...", "nowcast_delta_pp": <num|null>, "series": [ {id,name,prev_period,latest_period}, ... ] }
python3 -c "import json; print(json.load(open('data/latest.json')).get('data_updates'))"

# indicators.json entries should each have updated_this_run (+ prev/latest_period when true):
python3 -c "import json; [print(i['id'], i.get('updated_this_run'), i.get('prev_period'), '->', i.get('latest_period')) for i in json.load(open('data/indicators.json'))['indicators']]"
```

Expected: only series whose reference month advanced vs the currently-committed
`indicators.json` are flagged. On a run where nothing advanced, `series` is `[]`
and all flags are `false` — that's correct, not a bug.

## Making the highlight go live now (optional)

It will activate on its own on the next Monday cron. To show it *this week* without
waiting: run the pipeline locally (above) so `data/*.json` regenerate with the
flags, sanity-check, then `git add data/ && git commit && git push`. The static
site rebuilds from those JSONs. (The main page grid reads `indicators_v2.json` via
`data.indicatorsV2 ?? data.indicators`, so the v2 Python generator — already
verified — is what lights up "/". `gen_indicators_v2.py` runs in the weekly cron
after `emit_v2_json.R`.)

## Gotcha found along the way

v1's old `indicators_updated_since_last` (in `08_vintage_tracking.R`) was already
**effectively dead in CI**: it compares against the previous vintage's `.rds`
snapshot, but those snapshots are gitignored and absent on a fresh CI checkout, so
`previous_vintage` is always `NULL` there. That's why this feature diffs the
committed JSON instead — cache-independent and works for both models. Left the
vintage code untouched; just didn't rely on it.

## Deferred (not built — James's call)

- **Level 2 — Kalman news decomposition.** "What updated" ≠ "what moved the number"
  (see the −0.03% story above: surveys improved, nowcast fell). The rigorous answer
  is a Bańbura–Modugno "news" decomposition attributing each week's revision to
  each release's surprise × weight — the NY-Fed-style method this model already
  follows. Lives in `06_generate_nowcast.R` (v1) / the MIDAS path (v2) when wanted.
- A visible "what changed this week" caption near the headline (James chose the
  quiet record + grid highlight instead).
