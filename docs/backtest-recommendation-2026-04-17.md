# Factor-count backtest — recommendation

<!-- POINT-IN-TIME -->
> **Point-in-time record — 2026-04-17. Not current state.**
> This document describes what was true when it was written. The model, panel and
> calibration have changed since; several numbers here are known to be superseded.
> For current state see `README.md`, and for the 2026-08 fidelity review and its
> corrections log see `docs/reviews/2026-08-01-v2-intention-and-bug-review.md`.


**Generated:** 2026-04-17 (post-MHSI swap)
**Backtest window:** 2020 Q1 – 2025 Q4 quarterly (24 forecasts per model)
**Configs compared:** `n_factors ∈ {2, 3, 4}`, `var_order = 1`
**Raw outputs:** `pipeline/.cache/backtest_output/` (per-r directories + `comparison.md` + `comparison.csv`)

## TL;DR

**Keep `n_factors = 3`** (current production config). `r = 4` is structurally infeasible with 13 indicators — every iteration failed with a rank-deficient covariance matrix. Between `r = 2` and `r = 3`:

- On **level MAE**, they're roughly tied (r = 2 slightly better).
- On **directional accuracy** — the metric that matters most for a public QoQ-growth dashboard — **r = 3 wins decisively**.

No code change required.

## Headline numbers

| Metric | r = 2 | r = 3 | Winner |
|---|---:|---:|---|
| **Full 2020–2025 (24 forecasts)** | | | |
| MAE ($M) | 7,235 | 7,485 | r = 2 (+3.3%) |
| RMSE ($M) | 10,895 | 10,813 | r = 3 (+0.8%) |
| MAPE | 1.15% | 1.18% | r = 2 |
| Mean bias ($M) | −3,833 | −5,525 | r = 2 |
| MAE QoQ (pp) | 1.16 | 1.15 | tied |
| RMSE QoQ (pp) | 1.74 | 1.84 | r = 2 |
| **Hit rate** | **66.7%** | **79.2%** | **r = 3 (+12.5pp)** |
| **Post-COVID 2022–2025 (16 forecasts)** | | | |
| MAE ($M) | 3,226 | 3,598 | r = 2 (+10%) |
| RMSE ($M) | 4,490 | 4,249 | r = 3 (+5%) |
| MAPE | 0.49% | 0.54% | r = 2 |
| Mean bias ($M) | −947 | −2,490 | r = 2 |
| MAE QoQ (pp) | 0.44 | 0.38 | **r = 3 (+13%)** |
| RMSE QoQ (pp) | 0.61 | 0.42 | **r = 3 (+31%)** |
| **Hit rate** | **81.2%** | **93.8%** | **r = 3 (+12.5pp)** |
| **COVID 2020–2021 (8 forecasts)** | | | |
| MAE ($M) | 15,252 | 15,258 | tied |
| Hit rate | 37.5% | 50.0% | r = 3 |

## Why `r = 3` wins despite losing on level MAE

The two models have essentially identical **level** accuracy in normal conditions — r = 2 is $372M tighter on MAE, r = 3 is $241M tighter on RMSE. That's within the noise for a $700B economy; neither is a clear level-accuracy winner.

But the **user-facing number on the site is QoQ growth percent**, not the level. And on QoQ:

- r = 3's MAE is **0.38 pp vs 0.44 pp** post-COVID — 13% tighter.
- r = 3's RMSE is **0.42 pp vs 0.61 pp** — 31% tighter. This says r = 3's *worst* QoQ calls are much closer to reality than r = 2's.
- r = 3's directional hit rate is **93.8% post-COVID vs 81.2%**. Translating: r = 2 calls the wrong direction roughly 1 quarter in 5; r = 3 does so roughly 1 quarter in 16.

For a dashboard whose headline is "GDP grew +0.3% this quarter", getting the sign right is the most visible dimension of quality. A model that shaves 10% off the level MAE but miscalls the direction 20% of the time vs 6% is a worse product.

## Why `r = 4` is off the table

Every r = 4 iteration failed with *"system is computationally singular: reciprocal condition number ≈ 1e-20"*. With only 13 indicators, asking the DFM to extract 4 orthogonal common factors makes the estimation problem under-identified — the state-covariance matrix collapses to rank deficiency. The error is definitional, not a tuning issue. 4 factors would require expanding the indicator panel first.

## Caveats worth noting

1. **Both models systematically under-forecast** (negative mean bias across all subsets). r = 3's bias is larger (−$2,490M vs −$947M post-COVID, ≈ 0.4pp). Likely an artifact of the EM algorithm absorbing negative COVID-era shocks into baseline factor dynamics. Worth revisiting if it persists over the next few quarters of live running.
2. **Both models badly missed the 2020 COVID rebound.** 2020 Q3/Q4 actual was +3.5% / +3.4%; both r = 2 and r = 3 predicted near-zero or negative. Structural break; expected failure mode for a linear DFM with `trans = 0`.
3. **r = 3 is ~12× slower to estimate than r = 2** (EM needs more iterations to converge on the larger factor space). In the sweep r = 3 took 145 min vs r = 2's 12 min. This is irrelevant for weekly production (still minutes, not hours) but worth knowing if you ever need to run a lot of backtests quickly.
4. **Empirical RMSE can replace the placeholder CI bands.** The post-COVID RMSE of **$4,249M** for r = 3 (≈ 0.6% of GDP) is the right empirical basis for the ±68% interval currently set as a hardcoded 0.7% of the point estimate. Queue this as a follow-up if you want better-founded CIs.

## Recommendation

**Ship: no config change.** Keep `configure_dfm(n_factors = 3, var_order = 1)` in `pipeline/05_estimate_model.R`. The post-MHSI r = 3 model has:

- Hit rate 93.8% on the post-COVID regime — genuinely good.
- QoQ RMSE 0.42 pp — in RBA/Treasury target range.
- Level MAPE 0.54% — classed as "good accuracy" in the report schema.

Revisit if:
- The systematic under-forecast persists over 4+ live quarters (may indicate the EM has baked in a COVID-era drift we should address).
- Indicator panel expands meaningfully (r = 4 might then become feasible).
- You switch away from the `nowcasting` package to one with cleaner stationarity back-transforms.

## Files

- `pipeline/.cache/backtest_output/r2/` — per-quarter results, charts, report for r = 2
- `pipeline/.cache/backtest_output/r3/` — same, r = 3
- `pipeline/.cache/backtest_output/r4/` — empty (all iterations failed); see `sweep.log` for error detail
- `pipeline/.cache/backtest_output/comparison.md` — auto-generated side-by-side table
- `pipeline/.cache/backtest_output/sweep.log` — full run log
- `pipeline/09_backtest_model.R` — portable harness (tidyverse + ggplot2 only, no james-mess deps)
- `pipeline/run_backtest_sweep.R` — runner (loops r, saves per-r outputs, writes comparison)
