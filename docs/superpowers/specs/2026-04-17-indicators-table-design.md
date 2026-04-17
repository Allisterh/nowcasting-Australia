# Indicators Table — Design

**Date:** 2026-04-17
**Status:** Approved by user, ready for implementation plan.

## Goal

Add a compact table to the Indicators section of the dashboard that summarises, for each of the 12 indicators, the latest reading, month-on-month change (raw + %), when it was last released, and when the next release is expected. The table complements the existing sparkline cards and detail chart; rows are clickable and share state with the card selection.

## User intent

Right now a user has to eyeball 12 sparklines to answer "what's new?" The table gives an at-a-glance summary sorted by most-recently-updated indicator, so the user can quickly see which series just refreshed and where the movement was. It also answers "when does the next print land?" without needing external knowledge.

## Placement

Rendered inside `IndicatorGrid`, **after the detail card** (so when the detail chart is open it still sits above the table). Order within the Indicators section:

1. Section heading "Indicators"
2. Group-by-group card grid (existing)
3. Detail card (existing, conditional on selection)
4. **New** — Indicators table

## Columns

| # | Column | Content | Format |
|---|---|---|---|
| 1 | Indicator | `indicator.name` | plain text |
| 2 | Latest value | most recent series value | localized number with compact unit suffix (e.g. `14,567.2k`, `$28,350M`, `5.9%`, `105.3`) |
| 3 | Δ m/m (raw) | `latest - previous` | compact signed, colored (see Compact formatter, Colours) |
| 4 | Δ m/m (%) | `(latest - previous) / previous × 100` | signed, 2 dp, coloured; `—` for rate/index indicators |
| 5 | Updated | release date of latest point | `formatDayMonth` → "4 June" |
| 6 | Next release | expected release date of the next point | `formatDayMonth` → "4 June" |

### Sort

By `last_release_date` descending. Indicators missing that field sort to the bottom. Ties broken by `indicator.name` ascending.

### % change semantics

For `percent` (`unemp_rate`, `part_rate`) and `index` (`cons_conf`, `bus_conf`) units, the % change of a rate or index is unhelpful (e.g. "unemployment rose 2% m/m" when the rate moved 4.00 → 4.08). Column 4 shows `—` for these four indicators. The raw-change column (which is in pp/pts for these units) carries the signal.

## Compact raw-change formatter

New helper in `src/lib/format.ts`: `formatRawChange(delta: number, unit: string): string`.

Rules per unit string (matching the `unit` field in `indicators.json`):

| Unit | Rule | Example |
|---|---|---|
| `$ millions` | `±$Nbn` if abs ≥ 1000, else `±$NM` (no decimals if \|N\| ≥ 100, else 1 dp) | `+$1.2bn`, `+$150M`, `-$8.5M` |
| `persons` | source values are in thousands of persons despite the label; format delta as `±N.Nk` if abs < 1000, else `±N.Nm` | `+12.3k`, `+1.2m` |
| `hours (thousands)` | `±Nk hrs` | `+210k hrs` |
| `count` | `±N,NNN` (thousands-separated integer) | `+1,204` |
| `percent` | `±N.Npp` | `+0.1pp` |
| `index` | `±N.N pts` | `+2.3 pts` |

Positive values get a leading `+`, negative a leading `−` (Unicode minus, matching `formatPct`). Zero → `0` with unit suffix. Rounding: 1 dp unless the table above specifies otherwise.

## Row interaction

The row is a full-width `<button>` (inside a `<tr>` cell wrapper, or the `<tr>` itself made keyboard-accessible). Clicking a row calls the same `setSelected` used by cards. When a row's indicator matches the selected indicator, the row gets the selected treatment (`border-border-heavy bg-panel`), matching the card style.

Hover: `hover:bg-panel` (faint background, similar to existing table styles).

## Colours

Mirrors `PerformanceSection`:

- Positive Δ → `text-teal`
- Negative Δ → `text-[#c0392b]`
- Zero → default (`text-black` via inheritance)

Applied to columns 3 and 4 only.

## Pipeline changes (R)

File: `pipeline/04_emit_json.R`.

For each indicator, compute and emit two new fields:

- `last_release_date`: ISO `"YYYY-MM-DD"` = month-end of the latest series point + `release_lag_days`.
- `next_release_estimate`: ISO `"YYYY-MM-DD"` = month-end of the **next** month after the latest series point + `release_lag_days`.

Example: latest data point is `"2026-03"`, lag is 15 days. Month-end of 2026-03 is 2026-03-31 → `last_release_date = 2026-04-15`. Next reference month is 2026-04, month-end 2026-04-30 → `next_release_estimate = 2026-05-15`.

### Indicator ID mapping

The release calendar in `pipeline/04_release_calendar.R` uses slightly different IDs than `indicators.json`. Mapping table (calendar → JSON):

| Calendar ID | JSON IDs |
|---|---|
| `employment` | `employment` |
| `unemp_rate` | `unemp_rate` |
| `participation` | `part_rate` |
| `hours_worked` | `hours_worked` |
| `retail` | `retail_trade` |
| `exports` | `goods_exp`, `services_exp` |
| `imports` | `goods_imp`, `services_imp` |
| `building_app` | `building_approvals` |
| `cons_conf` | `cons_conf` |
| `bus_conf` | `bus_conf` |

This mapping lives as a named list in `04_emit_json.R`. If a lookup fails, fall back to 30-day lag (matches existing default in `calculate_release_date`) and log a warning.

## Types

Extend `Indicator` in `src/lib/types.ts`:

```ts
export interface Indicator {
  id: string;
  name: string;
  group: IndicatorGroup;
  unit: string;
  source: string;
  series: IndicatorPoint[];
  last_release_date?: string;
  next_release_estimate?: string;
}
```

Fields are optional so existing JSON without them still parses; if missing, the table shows `—` in those columns.

## Testing

- `src/lib/format.test.ts` — unit tests for `formatRawChange`, one case per unit type (positive, negative, zero).
- `src/components/IndicatorsTable` — no dedicated unit test. Manual verification: row sort order, selected-state sync with cards, click-to-select.
- No Playwright changes required.

## Files to touch

- `pipeline/04_emit_json.R` — compute and emit `last_release_date`, `next_release_estimate` per indicator. Import/use the existing release schedule from `.cache/processed/release_schedule.rds` or inline the table.
- `src/lib/types.ts` — add optional fields to `Indicator`.
- `src/lib/format.ts` — add `formatRawChange`.
- `src/lib/format.test.ts` — test cases for `formatRawChange`.
- `src/components/IndicatorsTable.tsx` — **new** component. Receives `indicators`, `selected`, `onSelect` props.
- `src/components/IndicatorGrid.tsx` — render `<IndicatorsTable>` after the detail card; pass state.
- `data/indicators.json` — regenerated by the pipeline (optionally hand-edit for preview before the next weekly run).

## Out of scope

- Responsive/mobile redesign of the table (keep horizontal scroll for narrow viewports).
- Sorting by other columns.
- Filtering by group.
- Sparklines in the table (cards already cover that).
- Changing the cards themselves or the detail chart.
