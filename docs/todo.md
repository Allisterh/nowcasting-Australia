# TODO / backlog

Pending work the user has flagged for later.

## URGENT — first thing next session: make each series stationary

**Context.** We discovered two coupled bugs on 2026-04-17:
1. `generate_nowcast` was pulling `yfcst[, "in"]` (retrospective Kalman-smoothed fit for the latest OBSERVED quarter) and labelling it as the nowcast for the next quarter. Per the `nowcasting` package's R Journal paper (RJ-2019-020), the correct column is `yfcst[, "out"]` — the proper mixed-frequency nowcast. **Fix landed** in `pipeline/06_generate_nowcast.R`: now matches target_quarter against the ts time index and pulls `out` (falling back to `in` only if the target is already observed — useful for historical backtests).
2. With the fix, today's "correct" Q1 2026 nowcast comes out at **+3.02% QoQ / +5.66% YoY** — implausibly high vs RBA projections (~0.5% QoQ) and Australian recent actuals (~2% YoY). A controlled diagnostic (`pipeline/test_out_mixed_freq.R`, deleted after running; results in `.cache/mixfreq_test.txt`) showed that even stripping ALL Q1 2026 monthly data, the model still predicts +1.61% QoQ for Q1 — a pure factor-state projection that's already 2–3× too high.

**Root cause.** Model uses `trans = rep(0, ncol(ts_data))` in `Bpanel()` — i.e. *no stationarity transformation*, fit on raw levels. The DFM extracts the level trend as a common factor, then AR-projects it forward, producing persistent over-extrapolation. The earlier team decision to use `trans=0` was validated by a backtest showing "MAE ~$1–2K vs ~$100K with transforms" — **but that backtest was measuring `in`-column backcast residuals, not real nowcast errors**. The comparison was against the wrong quantity. With the corrected extraction, `trans=0` likely produces terrible POOS forecast errors.

**Plan for next session.**

1. **Audit each series' stationarity.** For every column in master_wide: run an Augmented Dickey-Fuller (ADF) test on the raw series, then on candidate transformations (1st difference, 2nd difference, log, log 1st diff, log 2nd diff, YoY diff) — pick the simplest transformation that passes ADF at the 5% level.
2. **Map those choices to `nowcasting`'s `trans` codes** in `Bpanel`. Confirm the exact semantics of each trans value from the package docs (the commented-out map we inherited — `gdp=7, household_spending=1, cons_conf=2, …` — is a candidate but needs verifying). Use `Rscript -e '?nowcasting::Bpanel'` as the source of truth.
3. **Refit with the stationarity-corrected panel.** Inspect today's Q1 2026 nowcast — it should land in a plausible range (roughly 0–1% QoQ for a healthy economy).
4. **Re-run the backtest sweep (r=2, r=3) with the corrected extraction + stationarity transforms.** The real POOS MAE will finally be measured. Replace `docs/backtest-recommendation-2026-04-17.md` with corrected numbers.
5. **Only after this** do we resume the Q1 2026 weekly reconstruction and push to the site (site has been pulled via DNS CNAME removal while we sort this).

**Helpful pointers.**
- `nowcasting::Bpanel` is where trans codes apply (currently in `pipeline/05_estimate_model.R:257`).
- Existing commented map (line 253): `gdp=7, household_spending=1, cons_conf=2, building_app=1, bus_conf=2, exports_goods=1, exports_servs=7, imports_goods=1, imports_servs=7, employment=1, unemp_rate=2, participation=2, hours_worked=1`.
- The diagnostic log from today is at `pipeline/.cache/mixfreq_test.txt` (kept — useful reference).
- Full master dataset post-SA-swap is at `pipeline/.cache/processed/master_dataset_complete.rds`.

**Where we stopped.** Was about to inspect `Bpanel()` source and documentation to confirm trans code semantics. Did not yet run any ADF tests or trial transformations.

---

## Post-hoc Q1 2026 weekly nowcast reconstruction

## Post-hoc Q1 2026 weekly nowcast reconstruction

**Goal.** Rebuild a complete weekly nowcast track record for Q1 2026 as if the pipeline had been running on its current weekly schedule from the start of the quarter — producing one vintage per calendar week, using only the data that was actually available at that week's release dates.

**Motivation.** The existing `vintage_tracking.csv` for Q1 2026 is sparse and includes the stale-retail era. To have a clean, dense track record for the first full quarter under the MHSI model, we want to simulate what the weekly pipeline *would have* produced each week.

**Approach.**

1. Generate a list of target weekly nowcast dates covering Q1 2026 (e.g. every Monday from ~2026-01-05 through 2026-04-27, bounded by the next scheduled release date).
2. For each date:
   - Take a snapshot of indicator data available as of that date, using the release calendar in `pipeline/04_release_calendar.R` (`get_available_data()`).
   - Re-estimate the DFM on that snapshot (same n_factors the model ships with — informed by the factor-count backtest).
   - Generate a nowcast for 2026 Q1.
   - Write a vintage row into `vintage_tracking.csv` with the simulated run timestamp.
3. Save the RDS per vintage under `.cache/model_output/vintages/2026Q1/` matching the existing naming convention.
4. Re-emit `data/nowcasts.json` via the normal emit step so the Nowcast Evolution chart on the site reflects the dense track record.

**Note.** This overlaps structurally with `pipeline/09_backtest_model.R` (POOS re-estimation) but at weekly rather than quarterly cadence, and targeting a single quarter. Consider extracting a shared helper `run_nowcast_at_asof_date(master, config, as_of_date, target_quarter)` once this lands.

**Watch-outs.**

- The simulated vintages must be clearly distinguishable from real weekly runs — suggest either a prefix (`vintage_sim_…`) or a boolean `simulated` column added to the CSV.
- Running this once and committing vintages as real-weekly artifacts could be misleading; label clearly in the commit message and consider a flag the frontend could use to denote "reconstructed" vs "live" vintages.
- Respect the ragged edge: `get_available_data()` already handles it — don't shortcut.

---

## Evolution chart: add a dimmed next-quarter line

**Motivation (user, 2026-08-02).** While we're still inside the current quarter waiting for its GDP to be released, the *next* quarter's nowcast has already begun to evolve. Show it on the Nowcast Evolution chart as a second, less bright line — visible, but not competing with the current-quarter series for attention.

**Context worth knowing before starting.** We already saw an accidental version of this. Before the 2026-08-02 target-quarter fix, `nowcast_midas()` took the *last* MAI quarter rather than the first unreleased one, so the stress model drifted onto 2026 Q3 while the headline sat on Q2 — and `latest_v2.json` presented the two side by side under a single top-level `target_quarter`, inviting readers to compare them as if they described the same quarter. That was a bug and is fixed. This TODO is the *deliberate* version of the same idea, and it needs to be built so a reader can never confuse the two lines.

**Approach.**

1. Emit a second nowcast per run targeting `target_q + 1`. `nowcast_midas()` now always targets the first quarter without released GDP, so this needs an explicit second call (or a `target_offset` argument) rather than falling out of the ragged edge by accident.
2. `data/vintages_v2.json` already carries `target_quarter` on every row, so the data model needs no schema change — append the next-quarter vintages alongside the current-quarter ones and let the frontend group by `target_quarter`.
3. Frontend: render the current-quarter series at full weight and the next-quarter series dimmed (lower opacity, and consider dashed). Legend must name both quarters explicitly — not "current"/"next", which goes stale the moment GDP releases.
4. Handle the promotion. When the current quarter's GDP is released, the next-quarter line becomes the current-quarter line. `vintages_v2.json` is deliberately append-only (see `emit_v2_json.R` — a from-scratch reconstruction lets revisions silently rewrite history), so the promotion must be purely a rendering decision driven by `target_quarter` vs released GDP, never a rewrite of past rows.

**Watch-outs.**

- The next-quarter nowcast will sit at `jt = 0` or `1` for most of its visible life — i.e. little or no target-quarter data. Since `840e636` those stages get the paper's own FC and M1 models rather than the old random-walk fallback, so the estimator is legitimate, but it is running on the thinnest information the paper contemplates and its bands are correspondingly wide. The dimmer line is therefore statistically honest as well as visually sensible; consider a tooltip saying so.
- **`jt = 0` and `jt = 1` have never been calibrated.** Every CI parameter is estimated from backtest as-ofs, and production only ever reaches `jt = 2` or `3`, so `ci_params_for_stage()` has no bucket for the stages a next-quarter line would spend most of its life in and will fall back to the pooled band. Before shipping that line, either calibrate those stages explicitly (the backtest can be driven to them by targeting the *following* quarter) or state on the chart that the early band is pooled, not stage-specific.
- It must draw its confidence band from its own information stage, not the current quarter's. The per-stage CI work (`compute_ci_params_v2.R`, `ci_params_for_stage()`) already supports this — pass the next-quarter nowcast's own `n_months_in_quarter`.
- Don't let the two lines share a `prev_level`. That was exactly the `emit_v2_json.R:123` bug: the stress model's level and YoY were computed off the quarter before the *headline's* target, understating its level by a whole quarter of growth. A next-quarter nowcast needs the current quarter's (still unreleased, hence nowcast) level as its anchor — which means its level is a compounding of two estimates and should be presented with that uncertainty, or presented as growth only.
