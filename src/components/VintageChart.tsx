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
        Vintage evolution — how each quarter&apos;s nowcast moved over time
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
              formatter={(v) => {
                if (typeof v === "number") return [formatMillions(v), ""];
                return ["", ""];
              }}
              labelStyle={{ fontSize: 10 }}
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
