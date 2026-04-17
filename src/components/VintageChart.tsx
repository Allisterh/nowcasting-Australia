"use client";

import {
  ComposedChart,
  Scatter,
  XAxis,
  YAxis,
  ZAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  ReferenceLine,
  Label,
} from "recharts";
import type { VintageSeries, LatestNowcast } from "@/lib/types";
import { formatDate, formatDayMonth } from "@/lib/format";
import { chartColors, axisTick } from "@/lib/chartTheme";

interface VintageChartProps {
  nowcasts: VintageSeries;
  latest: LatestNowcast;
}

type VintagePoint = { kind: "vintage"; x: number; y: number; runDate: string };
type ActualPoint = { kind: "actual"; x: number; y: number; actualQuarter: string };

export default function VintageChart({ nowcasts, latest }: VintageChartProps) {
  const relevant = nowcasts.vintages.filter(
    (v) => v.target_quarter === latest.target_quarter,
  );
  const vintagePoints: VintagePoint[] = relevant
    .map((v) => ({
      kind: "vintage" as const,
      x: v.days_until_release,
      y: v.qoq_growth_pct,
      runDate: v.run_date,
    }))
    .sort((a, b) => a.x - b.x);

  const actualPoint: ActualPoint = {
    kind: "actual",
    x: latest.latest_actual.released_days_before_next,
    y: latest.latest_actual.qoq_growth_pct,
    actualQuarter: latest.latest_actual.quarter,
  };

  return (
    <section className="mb-10">
      <p className="font-headline text-3xl text-black">Nowcast evolution</p>
      <p className="text-xs text-label mb-2">
        Each green point is a weekly nowcast for {latest.target_quarter}. As new indicator data arrives through the quarter, the nowcast evolves — the line traces those revisions up to the ABS GDP release. The dark-teal circle shows the previous quarter&rsquo;s actual GDP growth for context.
      </p>
      <div className="h-[320px]">
        <ResponsiveContainer>
          <ComposedChart
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
            <ZAxis range={[80, 80]} />
            <Tooltip
              cursor={false}
              shared={false}
              content={({ active, payload }) => {
                if (!active || !payload || payload.length === 0) return null;
                const p = payload.find((entry) => {
                  const data = entry?.payload as
                    | VintagePoint
                    | ActualPoint
                    | undefined;
                  return data?.kind === "vintage" || data?.kind === "actual";
                })?.payload as VintagePoint | ActualPoint | undefined;
                if (!p) return null;
                const isActual = p.kind === "actual";
                const heading = isActual ? p.actualQuarter : formatDate(p.runDate);
                const rowLabel = isActual ? "Latest actual" : "Nowcast";
                return (
                  <div
                    style={{
                      background: "#fff",
                      border: `1px solid ${chartColors.border}`,
                      padding: "6px 8px",
                      fontSize: 11,
                      lineHeight: 1.4,
                    }}
                  >
                    <div style={{ color: chartColors.label }}>{heading}</div>
                    <div>
                      {rowLabel}: {p.y.toFixed(2)}%
                    </div>
                  </div>
                );
              }}
            />
            <Scatter
              data={vintagePoints}
              dataKey="y"
              fill={chartColors.accent}
              line={{ stroke: chartColors.primary, strokeWidth: 1.5 }}
              lineType="joint"
              shape="circle"
              isAnimationActive={false}
            />
            <Scatter
              data={[actualPoint]}
              dataKey="y"
              fill={chartColors.primary}
              shape="circle"
              isAnimationActive={false}
            />
            <ReferenceLine
              x={0}
              stroke={chartColors.label}
              strokeDasharray="4 3"
            >
              <Label
                content={(props) => {
                  const vb = (props as { viewBox?: { x: number; y: number; height: number } }).viewBox;
                  if (!vb) return null;
                  const labelX = vb.x + 12;
                  const labelY = vb.y + vb.height / 2;
                  return (
                    <text
                      x={labelX}
                      y={labelY}
                      transform={`rotate(-90, ${labelX}, ${labelY})`}
                      fontSize={10}
                      fill={chartColors.label}
                      textAnchor="middle"
                    >
                      {`GDP release: ${formatDayMonth(latest.next_gdp_release_date)}`}
                    </text>
                  );
                }}
              />
            </ReferenceLine>
          </ComposedChart>
        </ResponsiveContainer>
      </div>
    </section>
  );
}
