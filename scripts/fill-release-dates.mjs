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
  household_spending: 30,
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
  // Next month's month-end = day 0 of (this month's 0-indexed m + 2).
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
