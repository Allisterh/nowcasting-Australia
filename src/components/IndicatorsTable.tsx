"use client";

import type { Indicator } from "@/lib/types";
import { formatDayMonth, formatMonth, formatRawChange } from "@/lib/format";

interface Props {
  indicators: Indicator[];
  selectedId: string | null;
  onSelect: (ind: Indicator) => void;
}

// % change is meaningless for rates, diffusion indices and index levels.
const NO_PCT_UNITS = new Set(["percent", "index", "%", "net balance"]);

function formatLatestValue(value: number, unit: string): string {
  switch (unit) {
    case "$ millions":
    case "$m":
      return `$${Math.round(value).toLocaleString("en-AU")}M`;
    case "$bn":
      return `$${value.toLocaleString("en-AU", { maximumFractionDigits: 1 })}bn`;
    case "persons":
    case "000s persons":
      return `${value.toLocaleString("en-AU", { maximumFractionDigits: 1 })}k`;
    // Thousands of hours — see the note in lib/format.ts. Scale for display so
    // the number carries a unit a reader can parse.
    case "hours (thousands)": {
      if (value >= 1_000_000) return `${(value / 1_000_000).toFixed(2)}bn hrs`;
      if (value >= 1000) return `${(value / 1000).toFixed(1)}m hrs`;
      return `${Math.round(value).toLocaleString("en-AU")}k hrs`;
    }
    case "dwellings":
    case "count":
      return Math.round(value).toLocaleString("en-AU");
    case "percent":
    case "%":
      return `${value.toFixed(1)}%`;
    case "net balance":
      return value.toFixed(0);
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
                  {ind.updated_this_run ? (
                    <span
                      className="inline-flex items-center gap-1 text-teal"
                      title={
                        ind.prev_period && ind.latest_period
                          ? `New this week: ${formatMonth(ind.prev_period)} → ${formatMonth(ind.latest_period)}`
                          : "New this week"
                      }
                    >
                      <span className="w-1.5 h-1.5 rounded-full bg-teal" aria-hidden />
                      {ind.last_release_date ? formatDayMonth(ind.last_release_date) : "New"}
                    </span>
                  ) : ind.last_release_date ? (
                    formatDayMonth(ind.last_release_date)
                  ) : (
                    "—"
                  )}
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
