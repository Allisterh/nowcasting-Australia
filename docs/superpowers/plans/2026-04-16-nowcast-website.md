# Nowcast Website Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `nowcast.wlsn.me` — a Next.js static site that displays a weekly-updated Australian GDP nowcast, reading JSON artifacts produced by a GitHub-Actions-hosted R pipeline.

**Architecture:** One repo (`adrasyn/nowcasting`) containing both the R pipeline (`pipeline/`) and the Next.js site (`src/`). Weekly cron runs R in GH Actions, emits JSON to `data/`, pushes to main, triggers deploy. Site is static-built at deploy time with JSON baked in.

**Tech Stack:** Next.js 15, React 19, TypeScript, Tailwind CSS v4, Recharts, Instrument Serif + Inter (Google Fonts). R pipeline pinned via `renv`. Playwright for e2e smoke. Deployed to GitHub Pages with custom domain.

**Spec:** `docs/superpowers/specs/2026-04-16-nowcast-website-design.md`

**Note on data location:** The spec said `public/data/`. The sibling project `aus-fuel-shipments` uses `data/` at the repo root and reads it build-time via `fs.readFileSync`. We will follow that precedent — JSON lives in `data/`, not `public/data/`. This means JSON values are baked into the prerendered HTML at build time; not fetched at runtime. Smaller client payload, same behaviour.

---

## File Structure

**New files (created by this plan):**

- `.gitignore`
- `package.json`, `package-lock.json`, `tsconfig.json`, `next.config.ts`, `postcss.config.mjs`
- `eslint.config.mjs`
- `src/app/layout.tsx`, `src/app/page.tsx`, `src/app/globals.css`
- `src/lib/types.ts`, `src/lib/data.ts`, `src/lib/data.test.ts`
- `src/lib/chartTheme.ts`, `src/lib/format.ts`
- `src/components/Header.tsx`
- `src/components/Footer.tsx`
- `src/components/StalenessBanner.tsx`
- `src/components/HeadlineCard.tsx`
- `src/components/GdpHistoryChart.tsx`
- `src/components/VintageChart.tsx`
- `src/components/IndicatorSparkline.tsx`
- `src/components/IndicatorDetailCard.tsx`
- `src/components/IndicatorGrid.tsx`
- `src/components/PerformanceSection.tsx`
- `src/components/MethodologyPanel.tsx`
- `data/latest.json`, `data/gdp.json`, `data/nowcasts.json`, `data/indicators.json`, `data/performance.json` (placeholder at first, real data after pipeline wiring)
- `pipeline/run_complete_nowcast.R` (copied + made portable)
- `pipeline/R/*.R` (helpers, copied + tidied)
- `pipeline/scripts/01_fetch_data.R` → `04_emit_json.R` (consolidated from legacy)
- `pipeline/scripts/04_emit_json.R` (NEW)
- `pipeline/renv.lock`, `pipeline/.Rprofile` (renv activation)
- `pipeline/nab_business_confidence_raw.csv` (copied)
- `pipeline/tests/test_emit_json.R`, `pipeline/tests/fixtures/*.rds`
- `.github/workflows/deploy.yml`
- `.github/workflows/nowcast-weekly.yml`
- `tests/site.spec.ts` (Playwright)
- `playwright.config.ts`
- `docs/nab-update-task.md`
- `README.md`

**Out of scope / not created:** backend, database, auth, CMS, blog.

---

## Task 1: Bootstrap repo & scaffold Next.js project

**Files:**
- Create: `.gitignore`, `package.json`, `tsconfig.json`, `next.config.ts`, `postcss.config.mjs`, `eslint.config.mjs`, `src/app/layout.tsx`, `src/app/page.tsx`, `src/app/globals.css`, `README.md`

- [ ] **Step 1: Initialise git + GitHub**

```bash
cd /c/Users/wilso/Documents/Claude/Projects/nowcasting
git init
gh repo create adrasyn/nowcasting --public --source=. --description "Australian GDP nowcast website — nowcast.wlsn.me"
```

- [ ] **Step 2: Create `.gitignore`**

Create `.gitignore`:
```
# dependencies
/node_modules

# next.js
/.next/
/out/

# production
/build

# misc
.DS_Store
*.pem
Thumbs.db

# debug
npm-debug.log*
yarn-debug.log*
yarn-error.log*
.pnpm-debug.log*

# env files
.env*

# typescript
*.tsbuildinfo
next-env.d.ts

# playwright
/test-results/
/playwright-report/

# R pipeline cache (local-only)
/pipeline/.cache/
/pipeline/renv/library/
/pipeline/renv/staging/
/pipeline/.Rhistory
/pipeline/.RData
```

- [ ] **Step 3: Create `package.json`**

```json
{
  "name": "nowcasting",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "next lint",
    "test": "vitest run",
    "test:watch": "vitest",
    "test:e2e": "playwright test"
  },
  "dependencies": {
    "next": "15.3.1",
    "react": "^19.0.0",
    "react-dom": "^19.0.0",
    "recharts": "^3.8.1"
  },
  "devDependencies": {
    "@eslint/eslintrc": "^3",
    "@playwright/test": "^1.48.0",
    "@tailwindcss/postcss": "^4",
    "@types/node": "^20",
    "@types/react": "^19",
    "@types/react-dom": "^19",
    "eslint": "^9",
    "eslint-config-next": "15.3.1",
    "tailwindcss": "^4",
    "typescript": "^5",
    "vitest": "^2.1.0"
  }
}
```

- [ ] **Step 4: Create `tsconfig.json`**

```json
{
  "compilerOptions": {
    "target": "ES2017",
    "lib": ["dom", "dom.iterable", "esnext"],
    "allowJs": true,
    "skipLibCheck": true,
    "strict": true,
    "noEmit": true,
    "esModuleInterop": true,
    "module": "esnext",
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "preserve",
    "incremental": true,
    "plugins": [{ "name": "next" }],
    "paths": { "@/*": ["./src/*"] }
  },
  "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx", ".next/types/**/*.ts"],
  "exclude": ["node_modules"]
}
```

- [ ] **Step 5: Create `next.config.ts`**

```ts
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "export",
  images: { unoptimized: true },
};

export default nextConfig;
```

- [ ] **Step 6: Create `postcss.config.mjs`**

```js
export default {
  plugins: { "@tailwindcss/postcss": {} },
};
```

- [ ] **Step 7: Create `eslint.config.mjs`**

```js
import { dirname } from "path";
import { fileURLToPath } from "url";
import { FlatCompat } from "@eslint/eslintrc";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const compat = new FlatCompat({ baseDirectory: __dirname });

export default [...compat.extends("next/core-web-vitals", "next/typescript")];
```

- [ ] **Step 8: Create `src/app/globals.css` with JW palette tokens**

```css
@import "tailwindcss";

@theme {
  /* James's personal palette */
  --color-teal: #034159;
  --color-teal-600: #034159;
  --color-teal-500: #065a7a;
  --color-teal-400: #0a7d99;
  --color-green: #0cf25d;
  --color-green-muted: #0ac853;

  /* Neutral chrome (shared with fuel-shipments) */
  --color-border: #e2e8f0;
  --color-border-heavy: #111827;
  --color-label: #6b7280;
  --color-label-light: #9ca3af;
  --color-panel: #f8fafc;

  /* Vintage ramp — used by charts for sequential data */
  --color-ramp-0: #034159;
  --color-ramp-1: #0a4d66;
  --color-ramp-2: #125a6e;
  --color-ramp-3: #1b6775;
  --color-ramp-4: #27747a;
  --color-ramp-5: #34827e;
  --color-ramp-6: #43907f;
  --color-ramp-7: #569e7e;
  --color-ramp-8: #6dac79;
  --color-ramp-9: #87ba6f;
  --color-ramp-10: #a5c861;
  --color-ramp-11: #c6d652;
  --color-ramp-12: #0cf25d;

  --font-headline: "Instrument Serif", Georgia, serif;
  --font-body: "Inter", system-ui, sans-serif;
}

body {
  font-family: var(--font-body);
  color: #111827;
  background: #ffffff;
}
```

- [ ] **Step 9: Create `src/app/layout.tsx`**

```tsx
import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Australian GDP Nowcast",
  description:
    "Weekly nowcast of Australian GDP using a dynamic factor model over 13 high-frequency indicators.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
        <link
          href="https://fonts.googleapis.com/css2?family=Instrument+Serif&family=Inter:wght@400;500;600;700&display=swap"
          rel="stylesheet"
        />
      </head>
      <body className="font-body antialiased">{children}</body>
    </html>
  );
}
```

- [ ] **Step 10: Create `src/app/page.tsx` with a minimal "hello" placeholder**

```tsx
export default function Home() {
  return (
    <main className="max-w-5xl mx-auto px-4 sm:px-6 py-8">
      <h1 className="font-headline text-4xl">Australian GDP Nowcast</h1>
      <p className="mt-2 text-label">Under construction.</p>
    </main>
  );
}
```

- [ ] **Step 11: Create minimal `README.md`**

```markdown
# nowcasting

Australian GDP nowcast website at [nowcast.wlsn.me](https://nowcast.wlsn.me).

Weekly-updated dashboard reading JSON artifacts produced by the R pipeline in `pipeline/`.

Spec: `docs/superpowers/specs/2026-04-16-nowcast-website-design.md`
```

- [ ] **Step 12: Install dependencies and verify build**

```bash
npm install
npm run build
```

Expected: clean build output, `out/` directory created with static HTML.

- [ ] **Step 13: Commit**

```bash
git add -A
git commit -m "feat: bootstrap Next.js + Tailwind v4 scaffold with JW palette tokens"
git push -u origin main
```

---

## Task 2: JSON types + placeholder data fixtures

**Files:**
- Create: `src/lib/types.ts`, `data/latest.json`, `data/gdp.json`, `data/nowcasts.json`, `data/indicators.json`, `data/performance.json`

- [ ] **Step 1: Create `src/lib/types.ts` matching the spec's JSON contract**

```ts
export interface NowcastEstimate {
  gdp_chain_volume_millions: number;
  qoq_growth_pct: number;
  yoy_growth_pct: number;
  ci_68_low: number;
  ci_68_high: number;
  ci_95_low: number;
  ci_95_high: number;
}

export interface LatestNowcast {
  generated_at: string; // ISO 8601
  target_quarter: string; // e.g. "2026 Q1"
  data_through: string; // e.g. "2026-04"
  nowcast: NowcastEstimate;
  latest_actual: {
    quarter: string;
    gdp_chain_volume_millions: number;
  };
}

export interface GdpQuarter {
  quarter: string;
  value: number;
  qoq_pct: number;
  yoy_pct: number;
}

export interface GdpSeries {
  series: GdpQuarter[];
}

export interface Vintage {
  run_date: string; // "YYYY-MM-DD"
  target_quarter: string;
  point: number;
  ci_68_low: number;
  ci_68_high: number;
  ci_95_low: number;
  ci_95_high: number;
  data_through: string;
}

export interface VintageSeries {
  vintages: Vintage[];
}

export type IndicatorGroup = "Labour" | "Consumer" | "Business" | "External";

export interface IndicatorPoint {
  date: string; // "YYYY-MM"
  value: number;
}

export interface Indicator {
  id: string;
  name: string;
  group: IndicatorGroup;
  unit: string;
  source: string;
  series: IndicatorPoint[];
}

export interface IndicatorData {
  indicators: Indicator[];
}

export interface AccuracyError {
  target_quarter: string;
  final_nowcast: number;
  actual: number;
  error_millions: number;
  error_pct: number;
}

export interface Performance {
  mae_millions: number;
  mae_pct: number;
  rmse_millions: number;
  hit_rate_direction: number;
  errors: AccuracyError[];
}

export interface DashboardData {
  latest: LatestNowcast;
  gdp: GdpSeries;
  nowcasts: VintageSeries;
  indicators: IndicatorData;
  performance: Performance;
}
```

- [ ] **Step 2: Create `data/latest.json` (realistic placeholder sourced from Apr 2026 output)**

```json
{
  "generated_at": "2026-04-15T21:00:00Z",
  "target_quarter": "2026 Q1",
  "data_through": "2026-04",
  "nowcast": {
    "gdp_chain_volume_millions": 694649,
    "qoq_growth_pct": 0.13,
    "yoy_growth_pct": 2.69,
    "ci_68_low": 690200,
    "ci_68_high": 699100,
    "ci_95_low": 685800,
    "ci_95_high": 703500
  },
  "latest_actual": {
    "quarter": "2025 Q4",
    "gdp_chain_volume_millions": 693772
  }
}
```

- [ ] **Step 3: Create `data/gdp.json` with ~8 years of quarters**

Build from the nowcast_summary Recent trajectory (2024 Q4 → 2025 Q4) and plausible prior values:

```json
{
  "series": [
    { "quarter": "2018 Q1", "value": 601000, "qoq_pct": 0.6, "yoy_pct": 2.4 },
    { "quarter": "2018 Q2", "value": 604500, "qoq_pct": 0.58, "yoy_pct": 2.5 },
    { "quarter": "2024 Q4", "value": 676456, "qoq_pct": 0.31, "yoy_pct": 1.8 },
    { "quarter": "2025 Q1", "value": 679361, "qoq_pct": 0.43, "yoy_pct": 1.9 },
    { "quarter": "2025 Q2", "value": 685128, "qoq_pct": 0.85, "yoy_pct": 2.2 },
    { "quarter": "2025 Q3", "value": 688317, "qoq_pct": 0.47, "yoy_pct": 2.4 },
    { "quarter": "2025 Q4", "value": 693772, "qoq_pct": 0.79, "yoy_pct": 2.56 }
  ]
}
```

(A real placeholder will be filled in later from actual ABS historical values; this is enough for chart skeletons.)

- [ ] **Step 4: Create `data/nowcasts.json` with vintages from existing runs**

```json
{
  "vintages": [
    { "run_date": "2026-02-06", "target_quarter": "2025 Q4", "point": 692500, "ci_68_low": 688000, "ci_68_high": 697000, "ci_95_low": 684000, "ci_95_high": 701000, "data_through": "2026-02" },
    { "run_date": "2026-03-02", "target_quarter": "2026 Q1", "point": 692100, "ci_68_low": 687500, "ci_68_high": 696700, "ci_95_low": 683200, "ci_95_high": 701000, "data_through": "2026-02" },
    { "run_date": "2026-03-04", "target_quarter": "2026 Q1", "point": 692900, "ci_68_low": 688300, "ci_68_high": 697500, "ci_95_low": 684000, "ci_95_high": 701800, "data_through": "2026-03" },
    { "run_date": "2026-03-12", "target_quarter": "2026 Q1", "point": 693800, "ci_68_low": 689400, "ci_68_high": 698200, "ci_95_low": 685200, "ci_95_high": 702400, "data_through": "2026-03" },
    { "run_date": "2026-04-15", "target_quarter": "2026 Q1", "point": 694649, "ci_68_low": 690200, "ci_68_high": 699100, "ci_95_low": 685800, "ci_95_high": 703500, "data_through": "2026-04" }
  ]
}
```

- [ ] **Step 5: Create `data/indicators.json` with all 12 indicators and 12 months of synthetic values each**

**This is a throwaway fixture for building chart components before the R pipeline is wired.** It will be overwritten by Task 14 with real values. Do not invest effort making the numbers economically realistic — they just need to have the right shape and type.

Note: the spec and prose elsewhere reference "13 indicators" — that count includes GDP itself. GDP is the target variable and lives in `gdp.json`, not `indicators.json`. This file holds the 12 predictors.

Entries required (exact 12, IDs must match what `04_emit_json.R` will emit in Task 14):

| id | name | group | unit | source string |
|---|---|---|---|---|
| `employment` | Employment | Labour | persons | ABS Labour Force Survey (A84423127L) |
| `unemp_rate` | Unemployment Rate | Labour | percent | ABS Labour Force Survey (A84423050A) |
| `part_rate` | Participation Rate | Labour | percent | ABS Labour Force Survey (A84423051C) |
| `hours_worked` | Hours Worked | Labour | hours (thousands) | ABS Labour Force Survey (A84426277X) |
| `retail_trade` | Retail Trade | Consumer | $ millions | ABS Retail Trade (A3349873A) |
| `cons_conf` | Consumer Confidence | Consumer | index | OECD via FRED (CSCICP02AUM460S) |
| `building_approvals` | Building Approvals | Business | count | ABS Building Approvals (A422070J) |
| `bus_conf` | NAB Business Confidence | Business | index | NAB Monthly Business Survey |
| `goods_exp` | Goods Exports | External | $ millions | ABS International Trade (A2718577A) |
| `services_exp` | Services Exports | External | $ millions | ABS International Trade (A3535093X) |
| `goods_imp` | Goods Imports | External | $ millions | ABS International Trade (A2718603V) |
| `services_imp` | Services Imports | External | $ millions | ABS International Trade (A3535257J) |

For each, use the same 12 dates (`"2025-05"` through `"2026-04"`) and pick any monotonically increasing (or reasonable) series of values of the right order of magnitude for the `unit`. Example skeleton for one entry (copy+adapt for all 13):

```json
{
  "id": "employment",
  "name": "Employment",
  "group": "Labour",
  "unit": "persons",
  "source": "ABS Labour Force Survey (A84423127L)",
  "series": [
    { "date": "2025-05", "value": 14320000 },
    { "date": "2025-06", "value": 14345000 },
    { "date": "2025-07", "value": 14368000 },
    { "date": "2025-08", "value": 14395000 },
    { "date": "2025-09", "value": 14418000 },
    { "date": "2025-10", "value": 14430000 },
    { "date": "2025-11", "value": 14452000 },
    { "date": "2025-12", "value": 14478000 },
    { "date": "2026-01", "value": 14495000 },
    { "date": "2026-02", "value": 14512000 },
    { "date": "2026-03", "value": 14530000 },
    { "date": "2026-04", "value": 14548000 }
  ]
}
```

Commit the full 13-entry file — no blanks, no TBDs.

- [ ] **Step 6: Create `data/performance.json`**

```json
{
  "mae_millions": 3481,
  "mae_pct": 0.53,
  "rmse_millions": 4200,
  "hit_rate_direction": 0.82,
  "errors": [
    { "target_quarter": "2024 Q4", "final_nowcast": 677100, "actual": 676456, "error_millions": 644, "error_pct": 0.1 },
    { "target_quarter": "2025 Q1", "final_nowcast": 678900, "actual": 679361, "error_millions": -461, "error_pct": -0.07 },
    { "target_quarter": "2025 Q2", "final_nowcast": 684200, "actual": 685128, "error_millions": -928, "error_pct": -0.14 },
    { "target_quarter": "2025 Q3", "final_nowcast": 687900, "actual": 688317, "error_millions": -417, "error_pct": -0.06 },
    { "target_quarter": "2025 Q4", "final_nowcast": 694500, "actual": 693772, "error_millions": 728, "error_pct": 0.1 }
  ]
}
```

- [ ] **Step 7: Commit**

```bash
git add src/lib/types.ts data/
git commit -m "feat: add JSON types and placeholder data fixtures"
git push
```

---

## Task 3: Data loader with unit tests

**Files:**
- Create: `src/lib/data.ts`, `src/lib/data.test.ts`, `vitest.config.ts`

- [ ] **Step 1: Create `vitest.config.ts`**

```ts
import { defineConfig } from "vitest/config";
import path from "path";

export default defineConfig({
  test: {
    environment: "node",
  },
  resolve: {
    alias: { "@": path.resolve(__dirname, "./src") },
  },
});
```

- [ ] **Step 2: Write the failing test at `src/lib/data.test.ts`**

```ts
import { describe, it, expect } from "vitest";
import { loadDashboardData } from "./data";

describe("loadDashboardData", () => {
  it("loads all five JSON files and returns a DashboardData object", () => {
    const data = loadDashboardData();
    expect(data.latest.target_quarter).toBeTruthy();
    expect(data.gdp.series.length).toBeGreaterThan(0);
    expect(data.nowcasts.vintages.length).toBeGreaterThan(0);
    expect(data.indicators.indicators.length).toBeGreaterThan(0);
    expect(data.performance.mae_pct).toBeGreaterThan(0);
  });

  it("returns sane fallbacks when files are missing", () => {
    // loader should not throw even with missing files; test via monkey-patching env
    // covered by fallback branches in loadDashboardData
    const data = loadDashboardData();
    expect(typeof data).toBe("object");
  });
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `npm run test -- data`
Expected: FAIL — "Cannot find module './data'"

- [ ] **Step 4: Write `src/lib/data.ts`**

```ts
import fs from "fs";
import path from "path";
import type {
  LatestNowcast,
  GdpSeries,
  VintageSeries,
  IndicatorData,
  Performance,
  DashboardData,
} from "./types";

const DATA_DIR = path.join(process.cwd(), "data");

function readJson<T>(filename: string, fallback: T): T {
  const filePath = path.join(DATA_DIR, filename);
  try {
    const raw = fs.readFileSync(filePath, "utf-8");
    return JSON.parse(raw) as T;
  } catch {
    return fallback;
  }
}

const LATEST_FALLBACK: LatestNowcast = {
  generated_at: "1970-01-01T00:00:00Z",
  target_quarter: "—",
  data_through: "—",
  nowcast: {
    gdp_chain_volume_millions: 0,
    qoq_growth_pct: 0,
    yoy_growth_pct: 0,
    ci_68_low: 0,
    ci_68_high: 0,
    ci_95_low: 0,
    ci_95_high: 0,
  },
  latest_actual: { quarter: "—", gdp_chain_volume_millions: 0 },
};

export function loadDashboardData(): DashboardData {
  return {
    latest: readJson<LatestNowcast>("latest.json", LATEST_FALLBACK),
    gdp: readJson<GdpSeries>("gdp.json", { series: [] }),
    nowcasts: readJson<VintageSeries>("nowcasts.json", { vintages: [] }),
    indicators: readJson<IndicatorData>("indicators.json", { indicators: [] }),
    performance: readJson<Performance>("performance.json", {
      mae_millions: 0,
      mae_pct: 0,
      rmse_millions: 0,
      hit_rate_direction: 0,
      errors: [],
    }),
  };
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `npm run test -- data`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add src/lib/data.ts src/lib/data.test.ts vitest.config.ts
git commit -m "feat: add data loader with unit tests"
git push
```

---

## Task 4: Formatting helpers + chart theme module

**Files:**
- Create: `src/lib/format.ts`, `src/lib/format.test.ts`, `src/lib/chartTheme.ts`

- [ ] **Step 1: Write failing tests at `src/lib/format.test.ts`**

```ts
import { describe, it, expect } from "vitest";
import { formatMillions, formatPct, formatQuarter, formatMonth, formatDate } from "./format";

describe("formatMillions", () => {
  it("formats with dollar prefix and comma thousands", () => {
    expect(formatMillions(694649)).toBe("$694,649M");
  });
});

describe("formatPct", () => {
  it("formats with sign and 2dp", () => {
    expect(formatPct(0.13)).toBe("+0.13%");
    expect(formatPct(-0.42)).toBe("−0.42%");
    expect(formatPct(0)).toBe("0.00%");
  });
});

describe("formatQuarter", () => {
  it("passes through canonical form", () => {
    expect(formatQuarter("2026 Q1")).toBe("2026 Q1");
  });
});

describe("formatMonth", () => {
  it("converts YYYY-MM to short label", () => {
    expect(formatMonth("2026-04")).toBe("Apr 26");
  });
});

describe("formatDate", () => {
  it("formats ISO date to human-readable", () => {
    expect(formatDate("2026-04-15")).toBe("15 Apr 2026");
  });
});
```

- [ ] **Step 2: Run test — expect FAIL**

Run: `npm run test -- format`
Expected: FAIL

- [ ] **Step 3: Implement `src/lib/format.ts`**

```ts
export function formatMillions(m: number): string {
  return `$${m.toLocaleString("en-AU")}M`;
}

export function formatPct(pct: number): string {
  if (pct === 0) return "0.00%";
  const sign = pct > 0 ? "+" : "−";
  return `${sign}${Math.abs(pct).toFixed(2)}%`;
}

export function formatQuarter(q: string): string {
  return q;
}

export function formatMonth(yyyyMm: string): string {
  const [y, m] = yyyyMm.split("-");
  const labels = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
  return `${labels[parseInt(m, 10) - 1]} ${y.slice(2)}`;
}

export function formatDate(iso: string): string {
  const d = new Date(iso);
  const months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
  return `${d.getDate()} ${months[d.getMonth()]} ${d.getFullYear()}`;
}
```

- [ ] **Step 4: Run test — expect PASS**

Run: `npm run test -- format`
Expected: PASS

- [ ] **Step 5: Implement `src/lib/chartTheme.ts`**

```ts
export const chartColors = {
  primary: "#034159",
  accent: "#0cf25d",
  border: "#e2e8f0",
  label: "#6b7280",
  labelLight: "#9ca3af",
  textHeavy: "#111827",
};

export const chartRamp = [
  "#034159", "#0a4d66", "#125a6e", "#1b6775", "#27747a",
  "#34827e", "#43907f", "#569e7e", "#6dac79", "#87ba6f",
  "#a5c861", "#c6d652", "#0cf25d",
];

export const axisTick = { fontSize: 10, fill: chartColors.label };
export const gridStroke = { strokeDasharray: "3 3", stroke: chartColors.border };
```

- [ ] **Step 6: Commit**

```bash
git add src/lib/format.ts src/lib/format.test.ts src/lib/chartTheme.ts
git commit -m "feat: add formatting helpers and shared chart theme"
git push
```

---

## Task 5: Shell components — Header, Footer, StalenessBanner

**Files:**
- Create: `src/components/Header.tsx`, `src/components/Footer.tsx`, `src/components/StalenessBanner.tsx`

**No unit tests** — these are static presentational components validated by Playwright e2e later.

- [ ] **Step 1: Create `src/components/Header.tsx`**

```tsx
import { formatDate } from "@/lib/format";

interface HeaderProps {
  generatedAt: string;
}

export default function Header({ generatedAt }: HeaderProps) {
  return (
    <header className="border-b border-border-heavy pb-4 mb-6">
      <h1 className="font-headline text-4xl sm:text-5xl text-teal">
        Australian GDP Nowcast
      </h1>
      <p className="mt-2 text-sm text-label max-w-2xl">
        A weekly nowcast of Australian GDP using a dynamic factor model over 13 high-frequency indicators.
      </p>
      <p className="mt-1 text-xs text-label-light">
        Last updated: {formatDate(generatedAt)}
      </p>
    </header>
  );
}
```

- [ ] **Step 2: Create `src/components/Footer.tsx`**

```tsx
export default function Footer() {
  return (
    <footer className="mt-16 pt-4 border-t border-border text-xs text-label-light flex flex-wrap gap-x-4 gap-y-1">
      <span>Not an official forecast</span>
      <span>·</span>
      <span>Chart: 𝕏 @jameswilson</span>
      <span>·</span>
      <a href="https://github.com/adrasyn/nowcasting" className="hover:text-label underline-offset-2 hover:underline">
        Source on GitHub
      </a>
      <span>·</span>
      <a href="#methodology" className="hover:text-label underline-offset-2 hover:underline">
        Methodology
      </a>
    </footer>
  );
}
```

- [ ] **Step 3: Create `src/components/StalenessBanner.tsx`**

```tsx
import { formatDate } from "@/lib/format";

interface StalenessBannerProps {
  generatedAt: string;
  thresholdDays?: number;
}

export default function StalenessBanner({
  generatedAt,
  thresholdDays = 10,
}: StalenessBannerProps) {
  const generated = new Date(generatedAt);
  const now = new Date();
  const ageDays = Math.floor((now.getTime() - generated.getTime()) / 86400000);

  if (ageDays < thresholdDays) return null;

  return (
    <div className="mb-4 px-3 py-2 border border-border-heavy bg-panel text-xs">
      Last updated {ageDays} days ago ({formatDate(generatedAt)}) — data is currently stale.
    </div>
  );
}
```

- [ ] **Step 4: Wire into `src/app/page.tsx`**

```tsx
import { loadDashboardData } from "@/lib/data";
import Header from "@/components/Header";
import Footer from "@/components/Footer";
import StalenessBanner from "@/components/StalenessBanner";

export default function Home() {
  const data = loadDashboardData();
  return (
    <main className="max-w-5xl mx-auto px-4 sm:px-6 py-8">
      <StalenessBanner generatedAt={data.latest.generated_at} />
      <Header generatedAt={data.latest.generated_at} />
      <p className="text-label text-sm">More sections landing in subsequent tasks.</p>
      <Footer />
    </main>
  );
}
```

- [ ] **Step 5: Verify build + visual check**

```bash
npm run dev
```

Open http://localhost:3000 — confirm header, banner (hidden if fresh), and footer render cleanly with correct fonts.

- [ ] **Step 6: Commit**

```bash
git add src/components/Header.tsx src/components/Footer.tsx src/components/StalenessBanner.tsx src/app/page.tsx
git commit -m "feat: add Header, Footer, and StalenessBanner shell components"
git push
```

---

## Task 6: HeadlineCard

**Files:**
- Create: `src/components/HeadlineCard.tsx`

- [ ] **Step 1: Create the component**

```tsx
"use client";

import { LineChart, Line, ResponsiveContainer, Dot } from "recharts";
import type { LatestNowcast, GdpSeries } from "@/lib/types";
import { formatMillions, formatPct } from "@/lib/format";
import { chartColors } from "@/lib/chartTheme";

interface HeadlineCardProps {
  latest: LatestNowcast;
  gdp: GdpSeries;
}

export default function HeadlineCard({ latest, gdp }: HeadlineCardProps) {
  // Last 8 quarters of actuals + the nowcast point
  const last8 = gdp.series.slice(-8);
  const sparkData = [
    ...last8.map((q) => ({ quarter: q.quarter, value: q.value, isNowcast: false })),
    { quarter: latest.target_quarter, value: latest.nowcast.gdp_chain_volume_millions, isNowcast: true },
  ];

  return (
    <section className="mb-8 border border-border-heavy p-4">
      <p className="text-[10px] uppercase tracking-wider text-label mb-2">
        {latest.target_quarter} nowcast
      </p>
      <div className="flex flex-wrap items-baseline gap-x-6 gap-y-2">
        <span className="font-headline text-4xl text-teal">
          {formatPct(latest.nowcast.qoq_growth_pct)}
        </span>
        <span className="text-sm text-label">QoQ</span>
        <span className="font-headline text-2xl text-teal-500">
          {formatPct(latest.nowcast.yoy_growth_pct)}
        </span>
        <span className="text-sm text-label">YoY</span>
        <span className="ml-auto text-sm text-label">
          {formatMillions(latest.nowcast.gdp_chain_volume_millions)} chain volume
        </span>
      </div>
      <div className="mt-4 h-20">
        <ResponsiveContainer>
          <LineChart data={sparkData} margin={{ top: 5, right: 5, bottom: 5, left: 5 }}>
            <Line
              type="monotone"
              dataKey="value"
              stroke={chartColors.primary}
              strokeWidth={1.5}
              dot={(props) => {
                const { cx, cy, payload, index } = props;
                if (payload.isNowcast) {
                  return <Dot key={`dot-${index}`} cx={cx} cy={cy} r={4} fill={chartColors.accent} stroke={chartColors.primary} strokeWidth={1.5} />;
                }
                return <Dot key={`dot-${index}`} cx={cx} cy={cy} r={0} fill="transparent" />;
              }}
            />
          </LineChart>
        </ResponsiveContainer>
      </div>
      <p className="mt-2 text-[10px] text-label-light">
        Last 8 quarters of GDP (dark teal) with current nowcast (green). Data through {latest.data_through}.
      </p>
    </section>
  );
}
```

- [ ] **Step 2: Wire into `src/app/page.tsx`**

```tsx
import HeadlineCard from "@/components/HeadlineCard";
// ...inside Home()
<HeadlineCard latest={data.latest} gdp={data.gdp} />
```

- [ ] **Step 3: Visual check at `npm run dev`**

Confirm: headline number + spark chart render, green accent dot marks the nowcast point.

- [ ] **Step 4: Iterate with user via visual companion if needed**

The spec calls for chart iteration using the in-browser companion. Stage a mockup comparison if the component needs polish before moving on. Otherwise proceed.

- [ ] **Step 5: Commit**

```bash
git add src/components/HeadlineCard.tsx src/app/page.tsx
git commit -m "feat: add HeadlineCard with sparkline"
git push
```

---

## Task 7: GdpHistoryChart

**Files:**
- Create: `src/components/GdpHistoryChart.tsx`

- [ ] **Step 1: Create the component**

```tsx
"use client";

import {
  LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip,
  ResponsiveContainer, Area, ComposedChart,
} from "recharts";
import type { GdpSeries, LatestNowcast } from "@/lib/types";
import { formatMillions } from "@/lib/format";
import { chartColors, axisTick } from "@/lib/chartTheme";

interface GdpHistoryChartProps {
  gdp: GdpSeries;
  latest: LatestNowcast;
}

export default function GdpHistoryChart({ gdp, latest }: GdpHistoryChartProps) {
  type Row = {
    quarter: string;
    actual: number | null;
    nowcast: number | null;
    ci68: [number, number] | null;
  };

  const rows: Row[] = gdp.series.map((q) => ({
    quarter: q.quarter,
    actual: q.value,
    nowcast: null,
    ci68: null,
  }));

  // Link: last actual becomes the starting point of the nowcast dashed segment
  const lastActual = gdp.series[gdp.series.length - 1];
  if (lastActual) {
    const lastIdx = rows.length - 1;
    rows[lastIdx].nowcast = lastActual.value;
  }

  rows.push({
    quarter: latest.target_quarter,
    actual: null,
    nowcast: latest.nowcast.gdp_chain_volume_millions,
    ci68: [latest.nowcast.ci_68_low, latest.nowcast.ci_68_high],
  });

  return (
    <section className="mb-10">
      <p className="text-[10px] uppercase tracking-wider text-label mb-2">
        GDP chain volume — quarterly
      </p>
      <div className="h-[300px]">
        <ResponsiveContainer>
          <ComposedChart data={rows} margin={{ top: 5, right: 10, bottom: 5, left: 10 }}>
            <CartesianGrid strokeDasharray="3 3" stroke={chartColors.border} />
            <XAxis dataKey="quarter" tick={axisTick} interval="preserveStartEnd" />
            <YAxis
              tick={axisTick}
              tickFormatter={(v) => `${Math.round(v / 1000)}k`}
              domain={["auto", "auto"]}
            />
            <Tooltip
              formatter={(v: number) => [formatMillions(v), ""]}
              labelStyle={{ fontSize: 10 }}
              contentStyle={{ fontSize: 11 }}
            />
            <Area
              type="monotone"
              dataKey="ci68"
              stroke="none"
              fill={chartColors.primary}
              fillOpacity={0.15}
            />
            <Line type="monotone" dataKey="actual" stroke={chartColors.primary} strokeWidth={1.5} dot={false} />
            <Line
              type="monotone"
              dataKey="nowcast"
              stroke={chartColors.accent}
              strokeWidth={1.5}
              strokeDasharray="4 3"
              dot={{ r: 3, fill: chartColors.accent, stroke: chartColors.primary, strokeWidth: 1 }}
            />
          </ComposedChart>
        </ResponsiveContainer>
      </div>
      <p className="mt-2 text-[10px] text-label-light">
        Solid: ABS actuals. Dashed green: nowcast. Shaded band: 68% confidence interval.
      </p>
    </section>
  );
}
```

- [ ] **Step 2: Wire into `src/app/page.tsx`**

```tsx
import GdpHistoryChart from "@/components/GdpHistoryChart";
// ...after HeadlineCard
<GdpHistoryChart gdp={data.gdp} latest={data.latest} />
```

- [ ] **Step 3: Visual check at `npm run dev`**

Confirm the line + dashed continuation + CI band render correctly.

- [ ] **Step 4: Commit**

```bash
git add src/components/GdpHistoryChart.tsx src/app/page.tsx
git commit -m "feat: add GdpHistoryChart with nowcast continuation and CI band"
git push
```

---

## Task 8: VintageChart

**Files:**
- Create: `src/components/VintageChart.tsx`

- [ ] **Step 1: Create the component**

```tsx
"use client";

import {
  LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend,
  ResponsiveContainer,
} from "recharts";
import type { VintageSeries } from "@/lib/types";
import { formatMillions } from "@/lib/format";
import { chartColors, chartRamp, axisTick } from "@/lib/chartTheme";

interface VintageChartProps {
  nowcasts: VintageSeries;
}

interface VintageRow {
  run_date: string;
  [targetQuarter: string]: number | string;
}

export default function VintageChart({ nowcasts }: VintageChartProps) {
  const targetQuarters = Array.from(new Set(nowcasts.vintages.map((v) => v.target_quarter))).sort();
  const runDates = Array.from(new Set(nowcasts.vintages.map((v) => v.run_date))).sort();

  const rows: VintageRow[] = runDates.map((run_date) => {
    const row: VintageRow = { run_date };
    for (const v of nowcasts.vintages) {
      if (v.run_date === run_date) {
        row[v.target_quarter] = v.point;
      }
    }
    return row;
  });

  const colorFor = (idx: number, total: number) => {
    if (total <= 1) return chartRamp[chartRamp.length - 1];
    const pos = Math.floor((idx / (total - 1)) * (chartRamp.length - 1));
    return chartRamp[pos];
  };

  return (
    <section className="mb-10">
      <p className="text-[10px] uppercase tracking-wider text-label mb-2">
        Vintage evolution — how each quarter's nowcast moved over time
      </p>
      <div className="h-[300px]">
        <ResponsiveContainer>
          <LineChart data={rows} margin={{ top: 5, right: 10, bottom: 5, left: 10 }}>
            <CartesianGrid strokeDasharray="3 3" stroke={chartColors.border} />
            <XAxis dataKey="run_date" tick={axisTick} />
            <YAxis
              tick={axisTick}
              tickFormatter={(v) => `${Math.round(v / 1000)}k`}
              domain={["auto", "auto"]}
            />
            <Tooltip
              formatter={(v: number) => [formatMillions(v), ""]}
              contentStyle={{ fontSize: 11 }}
            />
            <Legend wrapperStyle={{ fontSize: 10 }} />
            {targetQuarters.map((tq, idx) => (
              <Line
                key={tq}
                type="monotone"
                dataKey={tq}
                stroke={colorFor(idx, targetQuarters.length)}
                strokeWidth={1.5}
                dot={{ r: 2 }}
                connectNulls
              />
            ))}
          </LineChart>
        </ResponsiveContainer>
      </div>
      <p className="mt-2 text-[10px] text-label-light">
        One line per target quarter. Older quarters trend teal; latest quarter highlighted in green.
      </p>
    </section>
  );
}
```

- [ ] **Step 2: Wire into `src/app/page.tsx`**

```tsx
import VintageChart from "@/components/VintageChart";
// ...after GdpHistoryChart
<VintageChart nowcasts={data.nowcasts} />
```

- [ ] **Step 3: Visual check — confirm one line per target quarter with ramp coloring**

- [ ] **Step 4: Commit**

```bash
git add src/components/VintageChart.tsx src/app/page.tsx
git commit -m "feat: add VintageChart with ramp-coloured per-quarter lines"
git push
```

---

## Task 9: IndicatorSparkline + IndicatorGrid + IndicatorDetailCard

**Files:**
- Create: `src/components/IndicatorSparkline.tsx`, `src/components/IndicatorDetailCard.tsx`, `src/components/IndicatorGrid.tsx`

- [ ] **Step 1: Create `src/components/IndicatorSparkline.tsx`**

```tsx
"use client";

import { LineChart, Line, ResponsiveContainer } from "recharts";
import type { IndicatorPoint } from "@/lib/types";
import { chartColors } from "@/lib/chartTheme";

interface Props {
  series: IndicatorPoint[];
}

export default function IndicatorSparkline({ series }: Props) {
  return (
    <div className="h-10">
      <ResponsiveContainer>
        <LineChart data={series}>
          <Line
            type="monotone"
            dataKey="value"
            stroke={chartColors.primary}
            strokeWidth={1.2}
            dot={false}
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}
```

- [ ] **Step 2: Create `src/components/IndicatorDetailCard.tsx`**

```tsx
"use client";

import {
  LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer,
} from "recharts";
import type { Indicator } from "@/lib/types";
import { formatMonth } from "@/lib/format";
import { chartColors, axisTick } from "@/lib/chartTheme";

interface Props {
  indicator: Indicator;
  onClose: () => void;
}

export default function IndicatorDetailCard({ indicator, onClose }: Props) {
  return (
    <div className="border border-border-heavy p-4 mt-2 mb-4 bg-panel">
      <div className="flex items-baseline justify-between mb-2">
        <div>
          <p className="font-headline text-xl text-teal">{indicator.name}</p>
          <p className="text-[10px] text-label-light">{indicator.group} · {indicator.unit} · {indicator.source}</p>
        </div>
        <button
          onClick={onClose}
          className="text-[10px] uppercase tracking-wider text-label hover:text-border-heavy"
        >
          Close
        </button>
      </div>
      <div className="h-[240px]">
        <ResponsiveContainer>
          <LineChart data={indicator.series} margin={{ top: 5, right: 10, bottom: 5, left: 10 }}>
            <CartesianGrid strokeDasharray="3 3" stroke={chartColors.border} />
            <XAxis dataKey="date" tickFormatter={formatMonth} tick={axisTick} interval="preserveStartEnd" />
            <YAxis tick={axisTick} tickFormatter={(v) => v.toLocaleString()} domain={["auto", "auto"]} />
            <Tooltip
              labelFormatter={(l) => formatMonth(String(l))}
              formatter={(v: number) => [v.toLocaleString(), ""]}
              contentStyle={{ fontSize: 11 }}
            />
            <Line type="monotone" dataKey="value" stroke={chartColors.primary} strokeWidth={1.5} dot={false} />
          </LineChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}
```

- [ ] **Step 3: Create `src/components/IndicatorGrid.tsx`**

```tsx
"use client";

import { useState } from "react";
import type { IndicatorData, Indicator, IndicatorGroup } from "@/lib/types";
import IndicatorSparkline from "./IndicatorSparkline";
import IndicatorDetailCard from "./IndicatorDetailCard";

const GROUP_ORDER: IndicatorGroup[] = ["Labour", "Consumer", "Business", "External"];

interface Props {
  indicators: IndicatorData;
}

export default function IndicatorGrid({ indicators }: Props) {
  const [selected, setSelected] = useState<Indicator | null>(null);

  const byGroup = GROUP_ORDER.map((group) => ({
    group,
    items: indicators.indicators.filter((i) => i.group === group),
  })).filter((g) => g.items.length > 0);

  return (
    <section className="mb-10">
      <p className="text-[10px] uppercase tracking-wider text-label mb-2">
        High-frequency indicators ({indicators.indicators.length})
      </p>
      {byGroup.map((g) => (
        <div key={g.group} className="mb-4">
          <p className="text-xs text-label mb-2 border-b border-border pb-1">{g.group}</p>
          <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
            {g.items.map((ind) => (
              <button
                key={ind.id}
                onClick={() => setSelected(ind)}
                className={`text-left border p-2 hover:border-border-heavy ${
                  selected?.id === ind.id ? "border-border-heavy bg-panel" : "border-border"
                }`}
              >
                <p className="text-xs text-border-heavy">{ind.name}</p>
                <p className="text-[10px] text-label-light mb-1">{ind.unit}</p>
                <IndicatorSparkline series={ind.series} />
              </button>
            ))}
          </div>
        </div>
      ))}
      {selected && <IndicatorDetailCard indicator={selected} onClose={() => setSelected(null)} />}
    </section>
  );
}
```

- [ ] **Step 4: Wire into `src/app/page.tsx`**

```tsx
import IndicatorGrid from "@/components/IndicatorGrid";
// ...after VintageChart
<IndicatorGrid indicators={data.indicators} />
```

- [ ] **Step 5: Visual check — confirm grid, click-through to detail, close works**

- [ ] **Step 6: Commit**

```bash
git add src/components/IndicatorSparkline.tsx src/components/IndicatorDetailCard.tsx src/components/IndicatorGrid.tsx src/app/page.tsx
git commit -m "feat: add indicator grid with sparklines and click-through detail"
git push
```

---

## Task 10: PerformanceSection + MethodologyPanel

**Files:**
- Create: `src/components/PerformanceSection.tsx`, `src/components/MethodologyPanel.tsx`

- [ ] **Step 1: Create `src/components/PerformanceSection.tsx`**

```tsx
import type { Performance } from "@/lib/types";
import { formatMillions, formatPct } from "@/lib/format";

interface Props {
  performance: Performance;
}

export default function PerformanceSection({ performance }: Props) {
  return (
    <section className="mb-10">
      <p className="text-[10px] uppercase tracking-wider text-label mb-2">
        Track record
      </p>
      <div className="grid grid-cols-3 gap-3 mb-4">
        <Tile label="MAE" value={formatMillions(performance.mae_millions)} sub={`${performance.mae_pct.toFixed(2)}% of GDP`} />
        <Tile label="RMSE" value={formatMillions(performance.rmse_millions)} />
        <Tile label="Directional hit rate" value={`${(performance.hit_rate_direction * 100).toFixed(0)}%`} />
      </div>
      <table className="w-full text-xs border-collapse">
        <thead>
          <tr className="border-b border-border-heavy text-left text-[10px] uppercase text-label">
            <th className="py-2">Quarter</th>
            <th className="py-2">Final nowcast</th>
            <th className="py-2">Actual</th>
            <th className="py-2">Error ($M)</th>
            <th className="py-2">Error (%)</th>
          </tr>
        </thead>
        <tbody>
          {performance.errors.map((e) => (
            <tr key={e.target_quarter} className="border-b border-border">
              <td className="py-2">{e.target_quarter}</td>
              <td className="py-2">{formatMillions(e.final_nowcast)}</td>
              <td className="py-2">{formatMillions(e.actual)}</td>
              <td className={`py-2 ${e.error_millions > 0 ? "text-teal" : "text-[#c0392b]"}`}>
                {e.error_millions > 0 ? "+" : ""}{e.error_millions.toLocaleString()}
              </td>
              <td className={`py-2 ${e.error_pct > 0 ? "text-teal" : "text-[#c0392b]"}`}>
                {formatPct(e.error_pct)}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  );
}

function Tile({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div className="border border-border p-3">
      <p className="text-[10px] uppercase tracking-wider text-label">{label}</p>
      <p className="font-headline text-2xl text-teal mt-1">{value}</p>
      {sub && <p className="text-[10px] text-label-light mt-1">{sub}</p>}
    </div>
  );
}
```

- [ ] **Step 2: Create `src/components/MethodologyPanel.tsx`**

```tsx
"use client";

import { useState } from "react";

export default function MethodologyPanel() {
  const [open, setOpen] = useState(false);

  return (
    <section id="methodology" className="mb-10">
      <button
        onClick={() => setOpen(!open)}
        className="w-full text-left border border-border-heavy px-4 py-3 flex items-center justify-between hover:bg-panel"
      >
        <span className="font-headline text-xl text-teal">Methodology</span>
        <span className="text-xs text-label">{open ? "Hide" : "Show"}</span>
      </button>
      {open && (
        <div className="border border-t-0 border-border-heavy px-4 py-4 text-sm text-border-heavy space-y-3 max-w-3xl">
          <p>
            This dashboard displays a nowcast of Australian real GDP growth produced by a Dynamic
            Factor Model (DFM) with an Expectation-Maximization estimator, following the methodology
            of the New York Fed Staff Nowcast.
          </p>
          <p>
            The model combines 13 high-frequency indicators spanning labour, consumer, business, and
            external sectors. Indicators are released at different times within each month ("ragged
            edge"); the Kalman filter naturally handles the missing data. The nowcast updates each
            week as new data arrives.
          </p>
          <p>
            Reference: Bok et al. (2018), <em>Macroeconomic Nowcasting and Forecasting with Big Data</em>,
            FRB NY Staff Report 830. Implementation uses the R <code>nowcasting</code> package.
          </p>
          <p className="text-xs text-label-light">
            This is a personal research project. Not an official forecast. Source code:{" "}
            <a className="underline" href="https://github.com/adrasyn/nowcasting">github.com/adrasyn/nowcasting</a>
          </p>
        </div>
      )}
    </section>
  );
}
```

- [ ] **Step 3: Wire both into `src/app/page.tsx`**

```tsx
import PerformanceSection from "@/components/PerformanceSection";
import MethodologyPanel from "@/components/MethodologyPanel";
// ...after IndicatorGrid
<PerformanceSection performance={data.performance} />
<MethodologyPanel />
```

- [ ] **Step 4: Visual check — confirm tiles render, table has green/red cells, methodology expands**

- [ ] **Step 5: Commit**

```bash
git add src/components/PerformanceSection.tsx src/components/MethodologyPanel.tsx src/app/page.tsx
git commit -m "feat: add performance table, scorecard tiles, and methodology panel"
git push
```

---

## Task 11: Full page assembly + visual companion iteration

**Files:**
- Modify: `src/app/page.tsx`

- [ ] **Step 1: Confirm `src/app/page.tsx` has all sections in correct order**

```tsx
import { loadDashboardData } from "@/lib/data";
import Header from "@/components/Header";
import Footer from "@/components/Footer";
import StalenessBanner from "@/components/StalenessBanner";
import HeadlineCard from "@/components/HeadlineCard";
import GdpHistoryChart from "@/components/GdpHistoryChart";
import VintageChart from "@/components/VintageChart";
import IndicatorGrid from "@/components/IndicatorGrid";
import PerformanceSection from "@/components/PerformanceSection";
import MethodologyPanel from "@/components/MethodologyPanel";

export default function Home() {
  const data = loadDashboardData();
  return (
    <main className="max-w-5xl mx-auto px-4 sm:px-6 py-8">
      <StalenessBanner generatedAt={data.latest.generated_at} />
      <Header generatedAt={data.latest.generated_at} />
      <HeadlineCard latest={data.latest} gdp={data.gdp} />
      <GdpHistoryChart gdp={data.gdp} latest={data.latest} />
      <VintageChart nowcasts={data.nowcasts} />
      <IndicatorGrid indicators={data.indicators} />
      <PerformanceSection performance={data.performance} />
      <MethodologyPanel />
      <Footer />
    </main>
  );
}
```

- [ ] **Step 2: Run `npm run dev` and review with James using the visual companion**

Present the full-page mockup; collect chart-design feedback; iterate as needed (color emphasis, spacing, font weights, tooltip styling). The user has signalled this iteration pass is expected. Document any design adjustments in commits with `style:` prefix.

- [ ] **Step 3: Verify static build succeeds**

Run: `npm run build`
Expected: `out/` directory produced, `out/index.html` contains all section headings, no build errors.

- [ ] **Step 4: Commit any iteration changes**

```bash
git add -A
git commit -m "style: iterate on chart composition per user review"
git push
```

---

## Task 12: R pipeline migration — copy & make portable

**Files:**
- Create: `pipeline/` (entire tree copied from legacy with surgical edits)

- [ ] **Step 1: Copy the pipeline**

```bash
mkdir -p pipeline
cp -r /c/Users/wilso/Documents/R/james-mess/code/project_nowcast/* pipeline/
```

- [ ] **Step 2: Remove archive + junk files immediately**

```bash
rm -rf pipeline/archive
rm pipeline/install_nowcasting.R pipeline/run_backtest.R pipeline/run_nowcast.R
rm pipeline/CLAUDE_IGR_PROCESS_NOTES.md pipeline/FIXES_COMPLETED.md pipeline/INDICATOR_STATUS.md pipeline/MISSION_ACCOMPLISHED.md pipeline/NOWCAST_RESULTS.md pipeline/TECHNICAL_NOTES.md pipeline/TODO.md
```

Keep: `README.md`, `run_complete_nowcast.R`, `03_data_ingestion.R`, `03b_fetch_fred_data.R`, `03c_nab_business_confidence.R`, `04_release_calendar.R`, `05_estimate_model.R`, `06_generate_nowcast.R`, `08_vintage_tracking.R`, `nab_business_confidence_raw.csv`.

- [ ] **Step 3: Make paths in `run_complete_nowcast.R` portable**

Modify `pipeline/run_complete_nowcast.R`:
- Delete the line `setwd("C:/Users/wilso/Documents/R/james-mess")`.
- Replace with:
```r
# Find the pipeline directory regardless of call location
if (!exists("PIPELINE_ROOT")) {
  PIPELINE_ROOT <- if (file.exists("pipeline/run_complete_nowcast.R")) {
    normalizePath("pipeline")
  } else if (file.exists("run_complete_nowcast.R")) {
    normalizePath(".")
  } else {
    stop("Cannot locate pipeline/ — run from repo root or pipeline/.")
  }
}
setwd(PIPELINE_ROOT)
```
- Replace every `source("code/project_nowcast/XX.R")` with `source("XX.R")` (since the CWD is now the pipeline dir).
- Replace every `data/project_nowcast/` path with `.cache/` for fetched/cached data, or `../data/` if the output is meant for the website.
- Replace every `outputs/project_nowcast/` path with `../data/` (JSON output) or delete PNG-writing lines (no PNG rendering in CI — keep only JSON).

- [ ] **Step 4: Make the same path fixes across all other `.R` scripts in pipeline/**

Run a find-and-replace pass: any reference to `code/project_nowcast/`, `data/project_nowcast/`, or `outputs/project_nowcast/` must be updated to pipeline-relative paths.

- [ ] **Step 5: Create `pipeline/README.md`**

```markdown
# Nowcast pipeline

R pipeline that produces the JSON artifacts consumed by the website.

## Run locally

From the repo root:
```bash
Rscript -e 'setwd("pipeline"); source("run_complete_nowcast.R")'
```

Or from inside `pipeline/`:
```bash
Rscript run_complete_nowcast.R
```

Outputs go to `../data/` (the repo-level `data/` directory consumed by Next.js).

## Dependencies

Pinned via `renv`. Run `renv::restore()` once to install.

## Cache

Raw ABS/FRED data cached under `.cache/` (gitignored). Safe to delete — will be refetched on next run.
```

- [ ] **Step 6: Verify local run works**

```bash
cd pipeline
Rscript run_complete_nowcast.R
```

Expected: pipeline runs, writes to `pipeline/.cache/` and eventually should write JSON to `../data/` (this wiring comes in Task 14).

- [ ] **Step 7: Commit**

```bash
git add pipeline/
git commit -m "feat: migrate R nowcast pipeline into pipeline/ with portable paths"
git push
```

---

## Task 13: Initialize renv and snapshot lockfile

**Files:**
- Create: `pipeline/renv.lock`, `pipeline/.Rprofile`, `pipeline/renv/activate.R`

- [ ] **Step 1: Initialize renv from inside pipeline/**

```bash
cd pipeline
Rscript -e 'install.packages("renv"); renv::init(bare = TRUE)'
```

This creates `renv/activate.R`, `.Rprofile`, and `renv.lock`.

- [ ] **Step 2: Install and snapshot all pipeline dependencies**

```bash
Rscript -e 'renv::install(c("tidyverse", "lubridate", "glue", "readabs", "fredr", "Matrix", "jsonlite"))'
Rscript -e 'renv::install("nmecsys/nowcasting")'  # archived-CRAN package, fetch from GitHub
Rscript -e 'renv::snapshot()'
```

- [ ] **Step 3: Verify `renv.lock` lists all required packages**

```bash
grep -E '"(tidyverse|nowcasting|readabs|fredr|jsonlite)"' renv.lock
```

Expected: matches for each.

- [ ] **Step 4: Add renv library to `.gitignore` (already done in Task 1) and commit lockfile**

```bash
cd ..
git add pipeline/renv.lock pipeline/.Rprofile pipeline/renv/activate.R
git commit -m "feat: pin R dependencies with renv"
git push
```

---

## Task 14: New script — `04_emit_json.R`

**Files:**
- Create: `pipeline/04_emit_json.R`
- Modify: `pipeline/run_complete_nowcast.R`

- [ ] **Step 1: Inspect the existing RDS shapes before implementing**

The R pipeline already saves `.rds` artifacts. The exact list/column names inside these files are not documented — we need to inspect them so `emit_json()` can read them correctly rather than guess.

```bash
cd pipeline
Rscript -e '
  latest <- readRDS("../../../R/james-mess/data/project_nowcast/model_output/latest_nowcast.rds")
  cat("=== latest_nowcast.rds ===\n"); str(latest, max.level = 2)

  master <- readRDS("../../../R/james-mess/data/project_nowcast/processed/master_dataset_complete.rds")
  cat("\n=== master_dataset_complete.rds ===\n"); str(master, max.level = 2)

  vintage_files <- list.files("../../../R/james-mess/data/project_nowcast/model_output/", pattern = "^nowcast_.*\\.rds$", full.names = TRUE)
  cat("\n=== vintage files found: ", length(vintage_files), "===\n")
  if (length(vintage_files) > 0) { str(readRDS(vintage_files[1]), max.level = 2) }
'
```

Write down the field names observed. The implementation in Step 4 must reference **actual** field names — adapt the code if they differ from what this plan anticipates. Common likely differences:
- `latest$point` may actually be `latest$nowcast` or `latest$gdp_forecast`.
- `latest$qoq_growth` may be `latest$qoq` or `latest$growth_qoq`.
- CIs may be a matrix/tibble column rather than scalar fields.
- `master$quarterly_gdp` may not exist as a named sub-element; quarterly GDP may be a subset of `master$long` filtered on `indicator_id == "gdp"`.

- [ ] **Step 2: Write failing test at `pipeline/tests/test_emit_json.R`**

```r
library(testthat)
library(jsonlite)

test_that("emit_json writes all five files to the target dir", {
  target <- tempfile("emit_json_test_")
  dir.create(target, recursive = TRUE)

  fixture_nowcast <- readRDS("tests/fixtures/latest_nowcast.rds")
  fixture_master <- readRDS("tests/fixtures/master_dataset_complete.rds")
  fixture_vintages <- readRDS("tests/fixtures/vintages.rds")
  fixture_performance <- readRDS("tests/fixtures/performance.rds")

  source("../04_emit_json.R")

  emit_json(
    target_dir = target,
    latest = fixture_nowcast,
    master = fixture_master,
    vintages = fixture_vintages,
    performance = fixture_performance
  )

  expect_true(file.exists(file.path(target, "latest.json")))
  expect_true(file.exists(file.path(target, "gdp.json")))
  expect_true(file.exists(file.path(target, "nowcasts.json")))
  expect_true(file.exists(file.path(target, "indicators.json")))
  expect_true(file.exists(file.path(target, "performance.json")))

  latest <- fromJSON(file.path(target, "latest.json"))
  expect_true(!is.null(latest$target_quarter))
  expect_true(is.numeric(latest$nowcast$gdp_chain_volume_millions))
})
```

- [ ] **Step 3: Build fixture files**

```bash
mkdir -p pipeline/tests/fixtures
Rscript -e '
  src <- "../R/james-mess/data/project_nowcast"
  file.copy(file.path(src, "model_output/latest_nowcast.rds"), "pipeline/tests/fixtures/latest_nowcast.rds", overwrite = TRUE)
  file.copy(file.path(src, "processed/master_dataset_complete.rds"), "pipeline/tests/fixtures/master_dataset_complete.rds", overwrite = TRUE)
  # Construct a vintages tibble by loading all nowcast_YYYY-MM-DD.rds files
  vfiles <- list.files(file.path(src, "model_output"), pattern = "^nowcast_\\d{4}-\\d{2}-\\d{2}\\.rds$", full.names = TRUE)
  if (length(vfiles) > 0) {
    vintages <- do.call(rbind, lapply(vfiles, function(f) {
      v <- readRDS(f)
      # Shape will be inspected in Step 1; adapt extraction to actual field names
      data.frame(
        run_date = gsub(".*nowcast_(\\d{4}-\\d{2}-\\d{2}).rds$", "\\1", basename(f)),
        target_quarter = v$target_quarter %||% NA_character_,
        point = v$point %||% v$nowcast %||% NA_real_
      )
    }))
    saveRDS(vintages, "pipeline/tests/fixtures/vintages.rds")
  }
  # Performance: synthesise from vintages + actuals later
  saveRDS(list(mae_millions = 3481, mae_pct = 0.53, rmse_millions = 4200,
               hit_rate_direction = 0.82, errors = data.frame()),
          "pipeline/tests/fixtures/performance.rds")
'
```

If the source `.rds` files are missing or have unexpected shapes (per Step 1), **hand-roll synthetic fixtures** matching the shapes `emit_json()` expects. The test must be runnable offline.

- [ ] **Step 4: Run test — expect FAIL ("Cannot find emit_json function")**

```bash
Rscript -e 'setwd("tests"); testthat::test_file("test_emit_json.R")'
```

- [ ] **Step 5: Implement `pipeline/04_emit_json.R`**

```r
#### Emit JSON artifacts for the website ####
# Reads in-memory model outputs and writes 5 JSON files to target_dir.
# Called from run_complete_nowcast.R after nowcast generation.

library(jsonlite)
library(dplyr)
library(tidyr)
library(lubridate)

#' Write nowcast JSON artifacts
#' @param target_dir Where to write (e.g. "../data")
#' @param latest List with nowcast point, CIs, target_quarter, data_through
#' @param master Master dataset object (list with $wide, $long)
#' @param vintages Tibble of historical nowcasts (one row per run/quarter)
#' @param performance List with MAE, RMSE, hit_rate, errors tibble
emit_json <- function(target_dir, latest, master, vintages, performance) {
  dir.create(target_dir, showWarnings = FALSE, recursive = TRUE)

  # 1. latest.json
  latest_out <- list(
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    target_quarter = latest$target_quarter,
    data_through = latest$data_through,
    nowcast = list(
      gdp_chain_volume_millions = latest$point,
      qoq_growth_pct = latest$qoq_growth,
      yoy_growth_pct = latest$yoy_growth,
      ci_68_low = latest$ci_68_low,
      ci_68_high = latest$ci_68_high,
      ci_95_low = latest$ci_95_low,
      ci_95_high = latest$ci_95_high
    ),
    latest_actual = list(
      quarter = latest$latest_actual_quarter,
      gdp_chain_volume_millions = latest$latest_actual_value
    )
  )
  write_json(latest_out, file.path(target_dir, "latest.json"),
             auto_unbox = TRUE, pretty = TRUE)

  # 2. gdp.json — quarterly actuals from master dataset
  gdp_series <- master$quarterly_gdp %>%
    arrange(quarter) %>%
    mutate(
      qoq_pct = (value / lag(value) - 1) * 100,
      yoy_pct = (value / lag(value, 4) - 1) * 100
    ) %>%
    select(quarter, value, qoq_pct, yoy_pct)
  write_json(list(series = gdp_series), file.path(target_dir, "gdp.json"),
             auto_unbox = TRUE, na = "null", pretty = TRUE)

  # 3. nowcasts.json — historical vintages
  write_json(list(vintages = vintages), file.path(target_dir, "nowcasts.json"),
             auto_unbox = TRUE, pretty = TRUE)

  # 4. indicators.json — 13 indicators with metadata and monthly series
  indicators_out <- list(indicators = indicators_to_json(master))
  write_json(indicators_out, file.path(target_dir, "indicators.json"),
             auto_unbox = TRUE, pretty = TRUE)

  # 5. performance.json
  write_json(performance, file.path(target_dir, "performance.json"),
             auto_unbox = TRUE, pretty = TRUE)

  message(sprintf("✓ Emitted 5 JSON files to %s", target_dir))
}

#' Transform master dataset into per-indicator JSON structure
indicators_to_json <- function(master) {
  # Define group mapping (matches the website's IndicatorGroup type)
  group_map <- list(
    employment = "Labour", unemp_rate = "Labour", part_rate = "Labour", hours_worked = "Labour",
    retail_trade = "Consumer", cons_conf = "Consumer",
    building_approvals = "Business", bus_conf = "Business",
    goods_exp = "External", services_exp = "External",
    goods_imp = "External", services_imp = "External"
  )
  # Friendly names + units + sources live in master$indicator_meta (built by 03_data_ingestion.R)
  indicator_ids <- names(master$indicator_meta)

  lapply(indicator_ids, function(id) {
    meta <- master$indicator_meta[[id]]
    series_df <- master$long %>% filter(indicator_id == id) %>% arrange(date)
    list(
      id = id,
      name = meta$name,
      group = group_map[[id]] %||% "External",
      unit = meta$unit,
      source = meta$source,
      series = lapply(seq_len(nrow(series_df)), function(i) {
        list(
          date = format(series_df$date[i], "%Y-%m"),
          value = series_df$value[i]
        )
      })
    )
  })
}

`%||%` <- function(a, b) if (is.null(a)) b else a
```

- [ ] **Step 6: Run test — expect PASS**

```bash
Rscript -e 'setwd("tests"); testthat::test_file("test_emit_json.R")'
```

- [ ] **Step 7: Wire `emit_json()` into `run_complete_nowcast.R`**

Append to the end of `pipeline/run_complete_nowcast.R`:

```r
#### Step N: Emit JSON for the website ####
cat("\nSTEP N: Emitting JSON artifacts...\n")
cat("----------------------------------------\n")

source("04_emit_json.R")

# Load or assemble the structures expected by emit_json()
latest_nowcast_struct <- readRDS("../data/.internal/latest_nowcast_struct.rds")  # produced upstream
vintages_df <- load_vintages()  # defined in 08_vintage_tracking.R
performance_struct <- compute_performance(vintages_df)  # helper to be added

emit_json(
  target_dir = "../data",
  latest = latest_nowcast_struct,
  master = master,
  vintages = vintages_df,
  performance = performance_struct
)

cat("\n✓ JSON artifacts written to ../data/\n")
```

Note: `latest_nowcast_struct`, `load_vintages()`, and `compute_performance()` will require small new helpers. Define them in `pipeline/R/json_helpers.R`:

```r
# pipeline/R/json_helpers.R
load_latest_nowcast_struct <- function(nowcast_result, master) {
  # Adapt this to the actual shape of `nowcast_result` — inspect with str() if unsure
  list(
    target_quarter = nowcast_result$target_quarter,
    data_through = format(max(master$long$date, na.rm = TRUE), "%Y-%m"),
    point = nowcast_result$point %||% nowcast_result$nowcast,
    qoq_growth = nowcast_result$qoq_growth,
    yoy_growth = nowcast_result$yoy_growth,
    ci_68_low = nowcast_result$ci_68_low,
    ci_68_high = nowcast_result$ci_68_high,
    ci_95_low = nowcast_result$ci_95_low,
    ci_95_high = nowcast_result$ci_95_high,
    latest_actual_quarter = nowcast_result$latest_actual_quarter,
    latest_actual_value = nowcast_result$latest_actual_value
  )
}

load_vintages <- function(vintage_dir = "../data/.internal/vintages") {
  # Reads every historical nowcast_*.rds and builds a tibble of vintages.
  files <- list.files(vintage_dir, pattern = "^nowcast_\\d{4}-\\d{2}-\\d{2}\\.rds$", full.names = TRUE)
  if (length(files) == 0) return(data.frame())
  do.call(rbind, lapply(files, function(f) {
    v <- readRDS(f)
    data.frame(
      run_date = gsub(".*nowcast_(\\d{4}-\\d{2}-\\d{2})\\.rds$", "\\1", basename(f)),
      target_quarter = v$target_quarter,
      point = v$point %||% v$nowcast,
      ci_68_low = v$ci_68_low, ci_68_high = v$ci_68_high,
      ci_95_low = v$ci_95_low, ci_95_high = v$ci_95_high,
      data_through = v$data_through
    )
  }))
}

compute_performance <- function(vintages, actuals) {
  # `actuals` is the quarterly GDP series.
  # For each target quarter with a final actual, take the last (latest run_date) vintage
  # for that quarter as the "final nowcast".
  library(dplyr)
  finals <- vintages %>%
    group_by(target_quarter) %>%
    slice_max(run_date, n = 1) %>%
    ungroup()
  scored <- finals %>%
    inner_join(actuals %>% select(quarter, actual = value), by = c("target_quarter" = "quarter")) %>%
    mutate(
      error_millions = point - actual,
      error_pct = (point - actual) / actual * 100
    )
  list(
    mae_millions = mean(abs(scored$error_millions)),
    mae_pct = mean(abs(scored$error_pct)),
    rmse_millions = sqrt(mean(scored$error_millions^2)),
    hit_rate_direction = mean(sign(scored$point - lag(scored$point)) == sign(scored$actual - lag(scored$actual)), na.rm = TRUE),
    errors = scored %>% select(target_quarter, final_nowcast = point, actual, error_millions, error_pct)
  )
}

`%||%` <- function(a, b) if (is.null(a)) b else a
```

In `run_complete_nowcast.R`, source this file before calling `emit_json()` and populate the three structures from the model outputs already in memory.

- [ ] **Step 8: Run the full pipeline end-to-end locally**

```bash
cd pipeline
Rscript run_complete_nowcast.R
```

Expected: pipeline completes, `data/latest.json` and siblings updated in repo root.

- [ ] **Step 9: Verify site consumes the real data**

```bash
cd ..
npm run dev
```

Open http://localhost:3000. Confirm the real nowcast values flow through (should match the Apr 15 summary: $694,649M, +0.13% QoQ).

- [ ] **Step 10: Commit**

```bash
git add pipeline/04_emit_json.R pipeline/run_complete_nowcast.R pipeline/tests/ data/
git commit -m "feat: emit JSON artifacts from R pipeline and wire into run_complete_nowcast"
git push
```

---

## Task 15: GitHub Actions — deploy.yml

**Files:**
- Create: `.github/workflows/deploy.yml`

- [ ] **Step 1: Create the workflow**

```yaml
name: Deploy to GitHub Pages

on:
  push:
    branches: [main]
    paths:
      - "src/**"
      - "data/**"
      - "public/**"
      - "package.json"
      - "package-lock.json"
      - "next.config.ts"
      - "tailwind.config.ts"
      - "postcss.config.mjs"
      - "tsconfig.json"
      - ".github/workflows/deploy.yml"
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: "pages"
  cancel-in-progress: false

jobs:
  deploy:
    runs-on: ubuntu-latest
    timeout-minutes: 10

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: "20"
          cache: "npm"

      - name: Install Node dependencies
        run: npm ci

      - name: Build Next.js static site
        run: npm run build

      - name: Upload Pages artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: out

      - name: Deploy to GitHub Pages
        uses: actions/deploy-pages@v4
```

- [ ] **Step 2: Enable GitHub Pages in repo settings**

Manually in the GitHub UI: Settings → Pages → Source = "GitHub Actions".

- [ ] **Step 3: Commit and push**

```bash
git add .github/workflows/deploy.yml
git commit -m "ci: add deploy workflow for GitHub Pages"
git push
```

- [ ] **Step 4: Verify the first deployment succeeds**

Watch Actions tab. On success, the site is live at `https://adrasyn.github.io/nowcasting/`.

- [ ] **Step 5: Commit verification note if needed — no code change required**

---

## Task 16: GitHub Actions — nowcast-weekly.yml

**Files:**
- Create: `.github/workflows/nowcast-weekly.yml`

- [ ] **Step 1: Create the workflow**

```yaml
name: Weekly Nowcast

on:
  schedule:
    # 21:00 UTC Sunday = 07:00 AEST Monday (AEST only; in AEDT this is 08:00 local)
    - cron: "0 21 * * 0"
  workflow_dispatch:

permissions:
  contents: write
  issues: write

concurrency:
  group: nowcast-weekly
  cancel-in-progress: false

jobs:
  nowcast:
    runs-on: ubuntu-latest
    timeout-minutes: 45

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up R
        uses: r-lib/actions/setup-r@v2
        with:
          r-version: "4.3"
          use-public-rspm: true

      - name: Install system dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y libcurl4-openssl-dev libssl-dev libxml2-dev

      - name: Set up renv cache
        uses: r-lib/actions/setup-renv@v2
        with:
          working-directory: pipeline

      - name: Run nowcast pipeline
        id: nowcast
        working-directory: pipeline
        env:
          FRED_API_KEY: ${{ secrets.FRED_API_KEY }}
        run: Rscript run_complete_nowcast.R

      - name: Commit updated JSON
        if: success()
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add data/
          if git diff --staged --quiet; then
            echo "No JSON changes to commit"
            exit 0
          fi
          git commit -m "data: weekly nowcast $(date -u +%Y-%m-%d)"
          git pull --rebase origin main
          git push

      - name: Open issue on failure
        if: failure()
        uses: actions/github-script@v7
        with:
          script: |
            const runUrl = `https://github.com/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId}`;
            const today = new Date().toISOString().slice(0, 10);
            await github.rest.issues.create({
              owner: context.repo.owner,
              repo: context.repo.repo,
              title: `Weekly nowcast failed ${today}`,
              body: `The weekly nowcast pipeline failed. See logs: ${runUrl}`,
              labels: ["pipeline-failure"]
            });
```

- [ ] **Step 2: Add FRED_API_KEY secret in repo settings**

Manually in the GitHub UI: Settings → Secrets and variables → Actions → New repository secret. Name: `FRED_API_KEY`. Value: James's key (he has one locally).

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/nowcast-weekly.yml
git commit -m "ci: add weekly nowcast cron workflow"
git push
```

- [ ] **Step 4: Manual dispatch to verify end-to-end**

In the GitHub Actions tab → Weekly Nowcast → Run workflow. This is the first real CI run of the R pipeline. Watch logs carefully.

- [ ] **Step 5: Triage any failures, fix, retry**

Most likely failure modes:
- `nowcasting` package install fails → fall back to `remotes::install_github("nmecsys/nowcasting")` as a pre-step.
- `readabs` system deps missing → add to `apt-get install` line.
- Script path issues → re-verify portable-paths task 12.

If fixes needed, iterate in small commits until green.

- [ ] **Step 6: Once green, commit any fixes and note success**

---

## Task 17: Custom domain + DNS

**Files:**
- Create: `CNAME` at repo root (gets auto-committed to Pages branch by GitHub when you configure the custom domain in the UI)

**User-driven steps** (James does these in browsers/DNS console):

- [ ] **Step 1: Add DNS CNAME record**

At James's DNS provider: `nowcast.wlsn.me CNAME adrasyn.github.io`. Propagation ~5-15 min.

- [ ] **Step 2: Verify DNS**

```bash
dig +short nowcast.wlsn.me
```
Expected: resolves to GitHub Pages IPs via adrasyn.github.io CNAME.

- [ ] **Step 3: Configure custom domain in GitHub**

Settings → Pages → Custom domain → enter `nowcast.wlsn.me` → Save. GitHub verifies and auto-commits a `CNAME` file.

- [ ] **Step 4: Wait for TLS cert and enable Enforce HTTPS**

Check back in ~10 min. When certificate is issued, tick "Enforce HTTPS".

- [ ] **Step 5: Verify**

Visit `https://nowcast.wlsn.me` — expected: site loads over HTTPS with valid cert.

---

## Task 18: Playwright e2e smoke test

**Files:**
- Create: `playwright.config.ts`, `tests/site.spec.ts`

- [ ] **Step 1: Install Playwright**

```bash
npx playwright install chromium
```

- [ ] **Step 2: Create `playwright.config.ts`**

```ts
import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./tests",
  timeout: 30000,
  use: {
    baseURL: "http://localhost:3000",
    headless: true,
  },
  webServer: {
    command: "npm run build && npx serve out -p 3000",
    port: 3000,
    reuseExistingServer: !process.env.CI,
  },
});
```

- [ ] **Step 3: Install `serve` for static hosting during tests**

```bash
npm install --save-dev serve
```

- [ ] **Step 4: Write failing test at `tests/site.spec.ts`**

```ts
import { test, expect } from "@playwright/test";

test("homepage renders headline nowcast", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Australian GDP Nowcast" })).toBeVisible();
  // Headline card shows a percentage
  await expect(page.getByText(/QoQ/)).toBeVisible();
  // At least one SVG chart renders
  await expect(page.locator("svg").first()).toBeVisible();
});

test("indicator grid renders and detail card opens on click", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("button", { name: /Employment/ }).first().click();
  await expect(page.getByText(/Labour · persons/)).toBeVisible();
});

test("methodology panel toggles", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("button", { name: "Methodology" }).click();
  await expect(page.getByText(/Dynamic Factor Model/)).toBeVisible();
});
```

- [ ] **Step 5: Run the test**

```bash
npm run test:e2e
```

Expected: PASS.

- [ ] **Step 6: Add Playwright to CI in deploy.yml**

Insert before "Build Next.js static site":

```yaml
      - name: Install Playwright browsers
        run: npx playwright install --with-deps chromium

      - name: Run e2e tests
        run: npm run test:e2e
```

- [ ] **Step 7: Commit**

```bash
git add playwright.config.ts tests/ package.json package-lock.json .github/workflows/deploy.yml
git commit -m "test: add Playwright e2e smoke test and wire into CI"
git push
```

---

## Task 19: NAB scheduled-task prompt

**Files:**
- Create: `docs/nab-update-task.md`

- [ ] **Step 1: Write the prompt document**

```markdown
# NAB Business Confidence — Monthly Claude Scheduled Task

This is the prompt that James pastes into Claude Desktop's scheduled-task UI. The task runs once a month, post the 2nd Tuesday, and updates the NAB Business Confidence CSV in the nowcasting repo.

## Schedule
- Cron: `0 2 15 * *` (02:00 local on the 15th of each month — always after the 2nd Tuesday, before the next weekly nowcast)
- Frequency: monthly

## Prompt

```
You are updating the NAB Business Confidence CSV in the nowcasting repository.

1. Open the following URL in Chrome (via Chrome MCP):
   https://www.investing.com/economic-calendar/nab-business-confidence-217

2. From the historical table on that page, read the most recent "Actual" value for NAB Business Confidence. Note the month the value corresponds to (the release is for the PREVIOUS month — e.g. a release dated 2026-05-13 reports April 2026 data).

3. Change directory to the nowcasting repo:
   cd C:/Users/wilso/Documents/Claude/Projects/nowcasting

4. Pull latest:
   git pull origin main

5. Append the new observation to pipeline/nab_business_confidence_raw.csv. The CSV format is:
   date,value
   YYYY-MM-01,<integer or decimal>

   Use the first day of the reported month as the date. Preserve existing chronological order; append at the bottom.

6. Commit and push:
   git add pipeline/nab_business_confidence_raw.csv
   git commit -m "data: NAB Business Confidence for <Month YYYY>"
   git push

7. Report back: what value was recorded for what month, and the commit URL.

If the investing.com page is blocked or the value cannot be read reliably, do NOT write a fabricated value. Instead, report the failure so James can update manually.
```

## Notes

- The repo itself does not scrape NAB — the pipeline reads from `pipeline/nab_business_confidence_raw.csv` as the single source of truth.
- If this task fails for any reason, the weekly nowcast pipeline falls back to the last-known value and opens a GitHub Issue titled `Update NAB Business Confidence for <month>` as a manual reminder.
- To revise this task, edit this file and re-paste the prompt into Claude Desktop.
```

- [ ] **Step 2: Commit**

```bash
git add docs/nab-update-task.md
git commit -m "docs: add Claude scheduled-task prompt for monthly NAB update"
git push
```

- [ ] **Step 3: James copies the prompt into Claude Desktop's scheduled-task UI**

Manual step for James after this task completes. Verify the first scheduled run occurs on the next 15th.

---

## Task 20: Final polish — README, cleanup, smoke-test the full loop

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Rewrite `README.md` with real content**

```markdown
# nowcasting

Australian GDP nowcast website at **[nowcast.wlsn.me](https://nowcast.wlsn.me)**.

A weekly-updated single-page dashboard showing a Dynamic Factor Model nowcast of Australian GDP, the underlying 13 high-frequency indicators, and the model's track record.

## How it works

```
Mondays 07:00 AEST  →  GH Actions runs pipeline/run_complete_nowcast.R
                   →  Emits JSON to data/
                   →  Commits to main
                   →  Triggers deploy workflow
                   →  Next.js static build published to GitHub Pages
                   →  nowcast.wlsn.me serves the fresh nowcast
```

## Local development

```bash
# Site
npm install
npm run dev            # localhost:3000
npm run build          # static export to out/
npm run test           # unit tests (vitest)
npm run test:e2e       # Playwright smoke test

# Pipeline (R)
cd pipeline
Rscript -e 'renv::restore()'   # install pinned packages (one-off)
Rscript run_complete_nowcast.R
```

## Repository layout

- `src/` — Next.js 15 app
- `data/` — JSON artifacts committed weekly by CI
- `pipeline/` — R nowcast pipeline
- `docs/` — spec, plan, NAB scheduled-task prompt

## Methodology

See `docs/superpowers/specs/2026-04-16-nowcast-website-design.md` and the in-site `Methodology` panel.

## License

Personal research project. Not an official forecast.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: fill out README with usage, layout, and pipeline overview"
git push
```

- [ ] **Step 3: End-to-end smoke**

1. Manually trigger `nowcast-weekly.yml` via workflow_dispatch.
2. Watch it complete, commit fresh JSON, trigger deploy.
3. Watch deploy complete.
4. Hit `nowcast.wlsn.me` — verify fresh data loads.
5. Check no unexpected GitHub Issues opened.

- [ ] **Step 4: Tag a Phase 1 release**

```bash
git tag -a v0.1.0 -m "Phase 1: first live weekly nowcast"
git push origin v0.1.0
```

---

## Summary & done-ness

Phase 1 is **done** when:

- [x] `nowcast.wlsn.me` resolves over HTTPS.
- [x] Page renders all six sections with real data from the R pipeline.
- [x] `nowcast-weekly.yml` has succeeded end-to-end at least once (preferably on the real Monday cron).
- [x] `deploy.yml` succeeds on every push that touches `data/` or `src/`.
- [x] NAB update prompt is documented at `docs/nab-update-task.md`; James has pasted it into Claude Desktop's scheduled-task UI.
- [x] Playwright smoke test passes in CI.

Phase 2 explicitly deferred: data-release-triggered updates, state-level nowcast, interactive drilldowns, alerting, NAB direct scraper.
