# Indicators Table Implementation Plan

<!-- POINT-IN-TIME -->
> **Point-in-time record — 2026-04-17. Not current state.**
> This document describes what was true when it was written. The model, panel and
> calibration have changed since; several numbers here are known to be superseded.
> For current state see `README.md`, and for the 2026-08 fidelity review and its
> corrections log see `docs/reviews/2026-08-01-v2-intention-and-bug-review.md`.


> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a compact, sortable table below the cards in the Indicators section showing latest value, m/m raw change, m/m % change, last release date, and expected next release date for each of the 12 indicators.

**Architecture:** Extend `Indicator` type with two optional ISO date fields emitted by the R pipeline. Introduce a compact per-unit change formatter (TDD). Build a new `IndicatorsTable` component that shares selection state with the existing card grid. Patch the existing `data/indicators.json` with the new fields via a one-off Node script so the feature ships immediately; update `pipeline/04_emit_json.R` so future weekly runs emit the fields canonically.

**Tech Stack:** Next.js 15 / React 19, TypeScript, Tailwind, Vitest for unit tests, R for the data pipeline.

Design spec: [`docs/superpowers/specs/2026-04-17-indicators-table-design.md`](../specs/2026-04-17-indicators-table-design.md).

## File Structure

- `src/lib/types.ts` — extend `Indicator` interface with 2 optional fields.
- `src/lib/format.ts` — add `formatRawChange(delta, unit)` helper.
- `src/lib/format.test.ts` — unit tests for `formatRawChange`.
- `src/components/IndicatorsTable.tsx` — **new** table component.
- `src/components/IndicatorGrid.tsx` — render the table below the detail card; pass shared state.
- `scripts/fill-release-dates.mjs` — **new** one-off Node script to populate `last_release_date` and `next_release_estimate` on the existing `data/indicators.json`.
- `pipeline/04_emit_json.R` — emit the two new fields per indicator on future runs.

---

### Task 1: Extend `Indicator` type with release-date fields

**Files:**
- Modify: `src/lib/types.ts`

- [ ] **Step 1: Edit `Indicator` interface**

Open `src/lib/types.ts`. Find the `Indicator` interface (around line 60) and add the two optional ISO-date fields:

```ts
export interface Indicator {
  id: string;
  name: string;
  group: IndicatorGroup;
  unit: string;
  source: string;
  series: IndicatorPoint[];
  last_release_date?: string;       // ISO "YYYY-MM-DD" — when the latest point was released
  next_release_estimate?: string;   // ISO "YYYY-MM-DD" — when the next point is expected
}
```

- [ ] **Step 2: Typecheck**

Run: `npx tsc --noEmit`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add src/lib/types.ts
git commit -m "types: add optional release-date fields to Indicator"
```

---

### Task 2: Failing tests for `formatRawChange`

**Files:**
- Modify: `src/lib/format.test.ts`

- [ ] **Step 1: Inspect the existing test file**

Run: `cat src/lib/format.test.ts`

Note the existing imports and test style so new tests match.

- [ ] **Step 2: Add failing tests**

Append these tests to `src/lib/format.test.ts` (keep existing tests intact). If the file has no import for `formatRawChange` yet, add it to the existing import block at the top.

```ts
import { formatRawChange } from "./format";

describe("formatRawChange", () => {
  it("formats $ millions under 100 with 1 dp", () => {
    expect(formatRawChange(-8.5, "$ millions")).toBe("−$8.5M");
  });

  it("formats $ millions 100+ with no decimals", () => {
    expect(formatRawChange(150, "$ millions")).toBe("+$150M");
  });

  it("formats $ millions ≥1000 as $Nbn with 1 dp", () => {
    expect(formatRawChange(1234, "$ millions")).toBe("+$1.2bn");
  });

  it("formats persons (series is thousands) under 1000 as k", () => {
    expect(formatRawChange(12.3, "persons")).toBe("+12.3k");
  });

  it("formats persons 1000+ as m", () => {
    expect(formatRawChange(1234, "persons")).toBe("+1.2m");
  });

  it("formats hours (thousands) with hrs suffix", () => {
    expect(formatRawChange(210, "hours (thousands)")).toBe("+210k hrs");
  });

  it("formats count with thousands separator", () => {
    expect(formatRawChange(1204, "count")).toBe("+1,204");
  });

  it("formats percent deltas as percentage points", () => {
    expect(formatRawChange(0.1, "percent")).toBe("+0.1pp");
  });

  it("formats index deltas as points", () => {
    expect(formatRawChange(-2.3, "index")).toBe("−2.3 pts");
  });

  it("uses unicode minus for negatives", () => {
    expect(formatRawChange(-150, "$ millions")).toBe("−$150M");
  });

  it("renders zero without a sign", () => {
    expect(formatRawChange(0, "percent")).toBe("0.0pp");
  });

  it("falls back gracefully for an unknown unit", () => {
    expect(formatRawChange(5.5, "whatever")).toBe("+5.5");
  });
});
```

If the file does not yet use Vitest's `describe`/`it`/`expect`, leave those globals alone — the project already enables them via `vitest.config.ts` (check with `cat vitest.config.ts` if unsure). Import `{ describe, it, expect }` from `"vitest"` only if the existing tests in the file do so.

- [ ] **Step 3: Run tests — expect them to fail**

Run: `npx vitest run src/lib/format.test.ts`
Expected: FAIL with `formatRawChange is not exported from ./format` (or equivalent).

---

### Task 3: Implement `formatRawChange`

**Files:**
- Modify: `src/lib/format.ts`

- [ ] **Step 1: Implement the helper**

Append to `src/lib/format.ts`:

```ts
export function formatRawChange(delta: number, unit: string): string {
  const abs = Math.abs(delta);
  const sign = delta > 0 ? "+" : delta < 0 ? "−" : "";

  switch (unit) {
    case "$ millions": {
      if (abs >= 1000) return `${sign}$${(abs / 1000).toFixed(1)}bn`;
      if (abs >= 100) return `${sign}$${abs.toFixed(0)}M`;
      return `${sign}$${abs.toFixed(1)}M`;
    }
    case "persons": {
      // Source series is already thousands of persons despite the label.
      if (abs >= 1000) return `${sign}${(abs / 1000).toFixed(1)}m`;
      return `${sign}${abs.toFixed(1)}k`;
    }
    case "hours (thousands)":
      return `${sign}${abs.toFixed(0)}k hrs`;
    case "count":
      return `${sign}${Math.round(abs).toLocaleString("en-AU")}`;
    case "percent":
      return `${delta === 0 ? "" : sign}${abs.toFixed(1)}pp`;
    case "index":
      return `${delta === 0 ? "" : sign}${abs.toFixed(1)} pts`;
    default:
      return `${sign}${abs.toFixed(1)}`;
  }
}
```

- [ ] **Step 2: Run tests — expect all green**

Run: `npx vitest run src/lib/format.test.ts`
Expected: all tests pass.

- [ ] **Step 3: Typecheck + lint**

Run: `npx tsc --noEmit && npx eslint src/lib/format.ts src/lib/format.test.ts`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add src/lib/format.ts src/lib/format.test.ts
git commit -m "feat(format): add formatRawChange helper for per-unit delta display"
```

---

### Task 4: One-off script to backfill release-date fields on `data/indicators.json`

**Files:**
- Create: `scripts/fill-release-dates.mjs`
- Modify: `data/indicators.json` (via running the script)

**Why:** The R pipeline will emit these fields on its next weekly run, but we want the feature to work today. This script is a one-off backfill that mirrors the R logic using the same lag-days table. It stays in-tree so it can be rerun (e.g. if the data file is regenerated without the new fields).

- [ ] **Step 1: Create the script**

Write `scripts/fill-release-dates.mjs`:

```js
// One-off: patch data/indicators.json with last_release_date and
// next_release_estimate per indicator. Idempotent — safe to rerun.
// Mirrors the lag-days table in pipeline/04_release_calendar.R.

import fs from "node:fs";
import path from "node:path";

const LAG_DAYS = {
  employment: 15,
  unemp_rate: 15,
  part_rate: 15,
  hours_worked: 15,
  retail_trade: 30,
  cons_conf: 5,
  building_approvals: 30,
  bus_conf: 5,
  goods_exp: 45,
  services_exp: 45,
  goods_imp: 45,
  services_imp: 45,
};

function monthEnd(yyyyMm) {
  const [y, m] = yyyyMm.split("-").map(Number);
  // Day 0 of the next month = last day of this month, in UTC.
  return new Date(Date.UTC(y, m, 0));
}

function nextMonthEnd(yyyyMm) {
  const [y, m] = yyyyMm.split("-").map(Number);
  // m is 1-indexed here; JS Date uses 0-indexed months.
  // Next month's month-end = day 0 of (next_month + 1).
  return new Date(Date.UTC(y, m + 1, 0));
}

function addDays(d, n) {
  const r = new Date(d);
  r.setUTCDate(r.getUTCDate() + n);
  return r;
}

function iso(d) {
  return d.toISOString().slice(0, 10);
}

const file = path.resolve("data/indicators.json");
const doc = JSON.parse(fs.readFileSync(file, "utf-8"));

for (const ind of doc.indicators) {
  const lag = LAG_DAYS[ind.id];
  if (lag == null) {
    console.warn(`no lag mapping for ${ind.id}, skipping`);
    continue;
  }
  const series = ind.series;
  if (!series?.length) continue;

  const latest = series[series.length - 1].date; // "YYYY-MM"
  ind.last_release_date = iso(addDays(monthEnd(latest), lag));
  ind.next_release_estimate = iso(addDays(nextMonthEnd(latest), lag));
}

fs.writeFileSync(file, JSON.stringify(doc, null, 2) + "\n");
console.log(`patched ${doc.indicators.length} indicators in ${file}`);
```

- [ ] **Step 2: Run the script**

Run: `node scripts/fill-release-dates.mjs`
Expected: `patched 12 indicators in .../data/indicators.json`.

- [ ] **Step 3: Spot-check the output**

Run: `grep -A 1 '"last_release_date"' data/indicators.json | head -8`
Expected: each indicator now has ISO date strings for both new fields. Sanity-check that `last_release_date` for the Labour series (15-day lag) is roughly 15 days after the latest data month's end.

- [ ] **Step 4: Typecheck (no type changes, but confirm the JSON still parses)**

Run: `npx tsc --noEmit`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add scripts/fill-release-dates.mjs data/indicators.json
git commit -m "data: backfill per-indicator release dates"
```

---

### Task 5: Create `IndicatorsTable` component

**Files:**
- Create: `src/components/IndicatorsTable.tsx`

- [ ] **Step 1: Write the component**

Create `src/components/IndicatorsTable.tsx`:

```tsx
"use client";

import type { Indicator } from "@/lib/types";
import { formatDayMonth, formatRawChange } from "@/lib/format";

interface Props {
  indicators: Indicator[];
  selectedId: string | null;
  onSelect: (ind: Indicator) => void;
}

const NO_PCT_UNITS = new Set(["percent", "index"]);

function formatLatestValue(value: number, unit: string): string {
  switch (unit) {
    case "$ millions":
      return `$${Math.round(value).toLocaleString("en-AU")}M`;
    case "persons":
      return `${value.toLocaleString("en-AU", { maximumFractionDigits: 1 })}k`;
    case "hours (thousands)":
      return `${Math.round(value).toLocaleString("en-AU")}k hrs`;
    case "count":
      return Math.round(value).toLocaleString("en-AU");
    case "percent":
      return `${value.toFixed(1)}%`;
    case "index":
      return value.toFixed(1);
    default:
      return value.toLocaleString("en-AU");
  }
}

function changeClass(delta: number): string {
  if (delta > 0) return "text-teal";
  if (delta < 0) return "text-[#c0392b]";
  return "";
}

export default function IndicatorsTable({ indicators, selectedId, onSelect }: Props) {
  const rows = indicators
    .map((ind) => {
      const n = ind.series.length;
      const latest = n > 0 ? ind.series[n - 1] : null;
      const prev = n > 1 ? ind.series[n - 2] : null;
      const delta = latest && prev ? latest.value - prev.value : null;
      const pct = latest && prev && prev.value !== 0 ? ((latest.value - prev.value) / prev.value) * 100 : null;
      return { ind, latest, prev, delta, pct };
    })
    .sort((a, b) => {
      const ad = a.ind.last_release_date ?? "";
      const bd = b.ind.last_release_date ?? "";
      if (ad !== bd) return bd.localeCompare(ad);
      return a.ind.name.localeCompare(b.ind.name);
    });

  return (
    <div className="mt-4 overflow-x-auto">
      <table className="w-full text-xs border-collapse">
        <thead>
          <tr className="border-b border-border-heavy text-left text-[10px] uppercase text-label">
            <th className="py-2 pr-3">Indicator</th>
            <th className="py-2 pr-3">Latest</th>
            <th className="py-2 pr-3">Δ m/m</th>
            <th className="py-2 pr-3">Δ m/m (%)</th>
            <th className="py-2 pr-3">Updated</th>
            <th className="py-2 pr-3">Next release</th>
          </tr>
        </thead>
        <tbody>
          {rows.map(({ ind, latest, delta, pct }) => {
            const isSelected = selectedId === ind.id;
            const pctSuppressed = NO_PCT_UNITS.has(ind.unit);
            return (
              <tr
                key={ind.id}
                onClick={() => onSelect(ind)}
                className={`cursor-pointer border-b border-border hover:bg-panel ${
                  isSelected ? "bg-panel" : ""
                }`}
              >
                <td className="py-2 pr-3">{ind.name}</td>
                <td className="py-2 pr-3">
                  {latest ? formatLatestValue(latest.value, ind.unit) : "—"}
                </td>
                <td className={`py-2 pr-3 ${delta != null ? changeClass(delta) : ""}`}>
                  {delta != null ? formatRawChange(delta, ind.unit) : "—"}
                </td>
                <td className={`py-2 pr-3 ${pct != null && !pctSuppressed ? changeClass(pct) : ""}`}>
                  {pctSuppressed || pct == null
                    ? "—"
                    : `${pct > 0 ? "+" : pct < 0 ? "−" : ""}${Math.abs(pct).toFixed(2)}%`}
                </td>
                <td className="py-2 pr-3">
                  {ind.last_release_date ? formatDayMonth(ind.last_release_date) : "—"}
                </td>
                <td className="py-2 pr-3">
                  {ind.next_release_estimate ? formatDayMonth(ind.next_release_estimate) : "—"}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
```

- [ ] **Step 2: Typecheck + lint**

Run: `npx tsc --noEmit && npx eslint src/components/IndicatorsTable.tsx`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add src/components/IndicatorsTable.tsx
git commit -m "feat(indicators): add IndicatorsTable component"
```

---

### Task 6: Wire `IndicatorsTable` into `IndicatorGrid`

**Files:**
- Modify: `src/components/IndicatorGrid.tsx`

- [ ] **Step 1: Add the import**

Open `src/components/IndicatorGrid.tsx`. Under the existing `import IndicatorDetailCard` line, add:

```tsx
import IndicatorsTable from "./IndicatorsTable";
```

- [ ] **Step 2: Render the table below the detail card**

Replace the current line:

```tsx
      {selected && <IndicatorDetailCard indicator={selected} onClose={() => setSelected(null)} />}
    </section>
```

with:

```tsx
      {selected && <IndicatorDetailCard indicator={selected} onClose={() => setSelected(null)} />}
      <IndicatorsTable
        indicators={indicators.indicators}
        selectedId={selected?.id ?? null}
        onSelect={setSelected}
      />
    </section>
```

- [ ] **Step 3: Typecheck + lint**

Run: `npx tsc --noEmit && npx eslint src/components/IndicatorGrid.tsx`
Expected: no errors.

- [ ] **Step 4: Build + start dev server for manual verification**

Run: `npm run dev`

Open the site, scroll to the Indicators section, and verify:
- Table appears below the cards (and below the detail chart when a card is selected).
- Rows are sorted by most recently released first.
- Clicking a row highlights it AND opens/updates the detail chart — same as clicking a card.
- Clicking the currently-selected card or row keeps selection.
- Δ m/m column shows `+` in teal for positive, `−` in red for negative.
- Δ m/m (%) shows `—` for the 4 rate/index indicators (`unemp_rate`, `part_rate`, `cons_conf`, `bus_conf`).
- "Updated" and "Next release" columns show dates like `15 April`.

Stop the dev server.

- [ ] **Step 5: Commit**

```bash
git add src/components/IndicatorGrid.tsx
git commit -m "feat(indicators): render table below detail card"
```

---

### Task 7: Emit release-date fields from the R pipeline

**Files:**
- Modify: `pipeline/04_emit_json.R`

- [ ] **Step 1: Add the lag table**

Open `pipeline/04_emit_json.R`. After the `INDICATOR_META` list (ends around line 57), insert the release-lag table keyed by JSON id:

```r
# Release lag (days) from reference-month-end to the actual ABS release.
# Mirrors pipeline/04_release_calendar.R — keep in sync.
INDICATOR_RELEASE_LAG_DAYS <- c(
  employment         = 15,
  unemp_rate         = 15,
  part_rate          = 15,
  hours_worked       = 15,
  retail_trade       = 30,
  cons_conf          = 5,
  building_approvals = 30,
  bus_conf           = 5,
  goods_exp          = 45,
  services_exp       = 45,
  goods_imp          = 45,
  services_imp       = 45
)
```

- [ ] **Step 2: Compute and emit the two new fields**

In the `# --- 4. indicators.json ---` block (around line 234), extend the per-indicator `list(...)` to include the new fields. Replace the existing `list(id = ..., series = series_df)` with:

```r
    last_ref_month <- if (nrow(series_df) > 0) tail(series_df$date, 1) else NA_character_
    lag_days <- INDICATOR_RELEASE_LAG_DAYS[[json_id]]
    if (is.null(lag_days) || !is.finite(lag_days)) {
      warning(sprintf("no release lag for %s — defaulting to 30 days", json_id))
      lag_days <- 30
    }

    release_dates <- if (!is.na(last_ref_month)) {
      parts <- strsplit(last_ref_month, "-", fixed = TRUE)[[1]]
      y <- as.integer(parts[1]); m <- as.integer(parts[2])
      month_start <- as.Date(sprintf("%d-%02d-01", y, m))
      this_end <- ceiling_date(month_start, "month") - days(1)
      next_end <- ceiling_date(month_start + months(1), "month") - days(1)
      list(
        last = format(this_end + days(lag_days), "%Y-%m-%d"),
        next_ = format(next_end + days(lag_days), "%Y-%m-%d")
      )
    } else {
      list(last = NA_character_, next_ = NA_character_)
    }

    list(
      id                    = json_id,
      name                  = meta$name,
      group                 = group,
      unit                  = meta$unit,
      source                = meta$source,
      series                = series_df,
      last_release_date     = release_dates$last,
      next_release_estimate = release_dates$next_
    )
```

`ceiling_date`, `days`, and `months` come from the already-imported `lubridate` package.

- [ ] **Step 3: Run the existing R tests**

Run: `Rscript pipeline/tests/test_emit_json.R`
Expected: tests pass. If the test file makes assertions about indicator field names and fails, update assertions in the same commit to include the two new fields.

If R is not available in your environment, note this in the commit message and skip to Step 4.

- [ ] **Step 4: Commit**

```bash
git add pipeline/04_emit_json.R pipeline/tests/test_emit_json.R
git commit -m "pipeline: emit last_release_date and next_release_estimate per indicator"
```

---

### Task 8: Final verification and push

- [ ] **Step 1: Run the full test suite**

Run: `npx vitest run`
Expected: all tests pass.

- [ ] **Step 2: Full typecheck + lint**

Run: `npx tsc --noEmit && npx eslint src/`
Expected: no errors.

- [ ] **Step 3: Production build**

Run: `npm run build`
Expected: build succeeds.

- [ ] **Step 4: Push**

```bash
git push origin main
```

Confirm GH Actions deploys successfully. Manually smoke-test the live site at nowcast.wlsn.me after deploy.
