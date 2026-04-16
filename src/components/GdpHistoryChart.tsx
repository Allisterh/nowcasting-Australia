"use client";

import {
  Line, XAxis, YAxis, CartesianGrid, Tooltip,
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
              formatter={(v) => {
                if (typeof v === "number") return [formatMillions(v), ""];
                if (Array.isArray(v) && typeof v[0] === "number" && typeof v[1] === "number") {
                  return [`${formatMillions(v[0])} – ${formatMillions(v[1])}`, ""];
                }
                return ["", ""];
              }}
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
