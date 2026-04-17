# TODO / backlog

Pending work the user has flagged for later.

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
