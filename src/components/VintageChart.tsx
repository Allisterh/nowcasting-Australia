"use client";

import {
  ComposedChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  ReferenceLine,
  ReferenceDot,
  Label,
} from "recharts";
import type { VintageSeries, LatestNowcast } from "@/lib/types";
import { formatPct, formatDate } from "@/lib/format";
import { chartColors, axisTick } from "@/lib/chartTheme";

interface VintageChartProps {
  nowcasts: VintageSeries;
  latest: LatestNowcast;
}

export default function VintageChart({ nowcasts, latest }: VintageChartProps) {
  const relevant = nowcasts.vintages.filter(
    (v) => v.target_quarter === latest.target_quarter,
  );
  const points = relevant
    .map((v) => ({
      x: v.days_until_release,
      y: v.qoq_growth_pct,
      runDate: v.run_date,
    }))
    .sort((a, b) => a.x - b.x);

  return (
    <section className="mb-10">
      <p className="font-headline text-3xl text-teal">GDP nowcast evolution</p>
      <p className="text-xs text-label mb-2 max-w-prose">
        Each green point is a weekly nowcast for {latest.target_quarter}. As new indicator data arrives through the quarter, the nowcast evolves — the line traces those revisions up to the ABS GDP release.
      </p>
      <div className="h-[320px]">
        <ResponsiveContainer>
          <ComposedChart
            data={points}
            margin={{ top: 20, right: 40, bottom: 20, left: 20 }}
          >
            <CartesianGrid strokeDasharray="3 3" stroke={chartColors.border} />
            <XAxis
              type="number"
              dataKey="x"
              domain={[-95, 5]}
              ticks={[-90, -75, -60, -45, -30, -15, 0]}
              tick={axisTick}
              label={{
                value: "Days until next GDP release",
                position: "insideBottom",
                offset: -10,
                style: { fontSize: 10, fill: chartColors.label },
              }}
            />
            <YAxis
              type="number"
              dataKey="y"
              domain={["auto", "auto"]}
              tickFormatter={(v) => `${v.toFixed(2)}%`}
              tick={axisTick}
              label={{
                value: "Quarter-on-quarter Growth (%)",
                angle: -90,
                position: "insideLeft",
                style: { fontSize: 10, fill: chartColors.label },
              }}
            />
            <Tooltip
              formatter={(v: unknown) => [
                typeof v === "number" ? `${v.toFixed(3)}%` : "",
                "",
              ]}
              labelFormatter={(_, payload) => {
                const runDate = payload?.[0]?.payload?.runDate;
                return runDate ? formatDate(runDate) : "";
              }}
              contentStyle={{ fontSize: 11 }}
            />
            <Line
              type="linear"
              dataKey="y"
              stroke={chartColors.primary}
              strokeWidth={1.5}
              dot={{
                r: 4,
                fill: chartColors.accent,
                stroke: chartColors.accent,
              }}
              isAnimationActive={false}
            />
            <ReferenceDot
              x={latest.latest_actual.released_days_before_next}
              y={latest.latest_actual.qoq_growth_pct}
              r={5}
              fill={chartColors.primary}
              stroke="none"
            >
              <Label
                position="top"
                offset={10}
                value={`Latest actual / ${latest.latest_actual.quarter} / ${formatPct(latest.latest_actual.qoq_growth_pct)}`}
                style={{ fontSize: 10, fill: chartColors.primary }}
              />
            </ReferenceDot>
            <ReferenceLine
              x={0}
              stroke={chartColors.label}
              strokeDasharray="4 3"
            >
              <Label
                position="insideTopRight"
                offset={10}
                value={`GDP Release / ${formatDate(latest.next_gdp_release_date)}`}
                style={{ fontSize: 10, fill: chartColors.label }}
              />
            </ReferenceLine>
          </ComposedChart>
        </ResponsiveContainer>
      </div>
    </section>
  );
}
