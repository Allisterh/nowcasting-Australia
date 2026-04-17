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
