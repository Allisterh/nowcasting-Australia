# Handoff — per-stage model dispatch (in progress, 2026-08-02)

Working state for the last open deviation from RDP 2024-04. Written because the
session that started this is running out of context; everything needed to finish
or abandon the change is here.

Branch: `spec/per-stage-model-dispatch` (off `main` @ `4350f4a`).

## The deviation

The paper builds **five separate models**, one per within-quarter information
stage (`Recursive_Nowcast_GDP_UMIDAS_TP.R:206-233`):

| stage | months of the target quarter available | paper's model |
|---|---|---|
| FC | 0 | U-MIDAS, `k = k1:k2` |
| M1 | 1 | U-MIDAS, `k = (k1-1):k2` |
| M2 | 2 | U-MIDAS, `k = (k1-2):k2` |
| M3 | 3 | U-MIDAS, `k = (k1-3):k2` |
| QA | 3 | quarter-average, flat weights — "similar to M3" |

Its QA block runs **after** the `jt` loop, so `x_new` is the jt=3 vector: QA is
only ever evaluated on a **complete** quarter.

v2 uses QA at **every** stage (`nowcast_midas.R`, the `qa` branch), feeding
`mean(target_months$value)` over whatever 1-3 months exist into coefficients
estimated exclusively on 3-month means (`xm_est <- rowMeans(mls(x_est, k=0:2, m=3))`).
At `jt=2` the regressor is not the same object the model was fitted on.

## Why it matters

Production only ever sees `jt = 2` or `3` (ABS releases GDP ~60 days after
quarter-end, i.e. two months into the next quarter). So roughly the first five
Mondays after each release — about half of what gets published — use the
mismatched estimator. Suggestive but not conclusive: measured bias is **+0.45pp at
jt=2** against **+0.34pp at jt=3**.

## The test (run this first — the change is conditional on it)

`cache/stagecmp/umidas_a10.csv` — weekly backtest, `model = "umidas"`,
`sel_alpha = 0.10`, same panel/lags as production. Compare its **jt=2 rows**
against the same rows of `cache/ci_recalib/qa_a10_acc.csv` (the shipped all-QA
run). Same as-ofs, same panel, different estimator at that stage.

- If M2 has lower error/bias at jt=2 → adopt per-stage dispatch, sequence below.
- If not → **abandon the change** and document the partial mean in
  `nowcast_midas.R` as a deliberate simplification, plus a note in the review
  report. Do not adopt it on fidelity grounds alone if it demonstrably forecasts
  worse; the owner's standard is fidelity *where it does not cost accuracy we can
  measure*.

## Sequence, if adopted

1. **Route by stage** in `nowcast_midas.R`: QA at `jt = 3`; the existing `umidas`
   branch (already the paper's `k = (k1 - jtf):k2`) at `jt < 3`. Both estimators
   are already implemented — this is routing, not new modelling.
2. **Recalibrate** (`R/recalib_ci_v2.R`, ~30 min). Required: the `jt=2` band
   (sd 0.4094, bias +0.4509) was measured on partial-QA errors and would
   otherwise describe an estimator no longer in use.
3. **Regenerate params** — `R/compute_ci_params_v2.R cache/ci_recalib/qa_a10_acc.csv pipeline/seed/ci_params_v2.json "qa_a10 (dfm_q=1)"`.
4. **Rebuild the evolution chart** — `emit_v2_json(rebuild_vintages = TRUE)`.
   Most of the 9 vintages are jt=2 (`data_through` 2026-05/06 against a Q2
   target), so most points move.
5. **Delete the `jt=0` random-walk fallback** in `nowcast_midas.R`. It is not the
   paper's method and has never been backtested; it only survived because there
   was nothing to replace it with. Per-stage dispatch gives it the paper's FC
   model. Keep the `jt=0`-cannot-occur note.
6. **Track record needs nothing.** All 12 backcasts sit at `jt=3` by construction
   — a backcast is the last estimate before release, by which point the quarter is
   complete. Verified. `backcasts.json` and `performance_v2.json` are unaffected.

## Then

Commit, merge to `main`, push, and trigger `nowcast-weekly.yml` manually to
confirm CI is green (that has been the pattern all session).

## Context this depends on

- Bias is **measured and reported but never applied** — the paper does not
  bias-correct and its MIDAS regression already fits an intercept. Do not
  reintroduce a correction. See `pipeline/ci_bands.R` header.
- α is **0.10**, the paper's value, as of `185ee3e`.
- The volatility/stress model was removed front and back; the `umidas`
  *estimator* deliberately remains available and is what step 1 uses.
- Full review and corrections log: `docs/reviews/2026-08-01-v2-intention-and-bug-review.md`.
