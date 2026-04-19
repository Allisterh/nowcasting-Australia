"use client";

import {
  LineChart,
  Line,
  BarChart,
  Bar,
  YAxis,
  ResponsiveContainer,
} from "recharts";
import type { IndicatorPoint } from "@/lib/types";
import { chartColors } from "@/lib/chartTheme";

export type SparklineMode = "level" | "change" | "bar";

interface Props {
  series: IndicatorPoint[];
  mode?: SparklineMode;
}

const WINDOW_MONTHS = 60;

export default function IndicatorSparkline({ series, mode = "level" }: Props) {
  if (mode === "bar") {
    const deltas = series
      .slice(1)
      .map((p, i) => ({ date: p.date, value: p.value - series[i].value }))
      .slice(-WINDOW_MONTHS);

    return (
      <div className="h-10">
        <ResponsiveContainer>
          <BarChart data={deltas} margin={{ top: 1, right: 0, bottom: 1, left: 0 }}>
            {/* Hidden axis so deltas span the full chart height; otherwise
                recharts defaults to a domain that includes 0 + dataMax,
                compressing small fluctuations. */}
            <YAxis hide domain={["dataMin", "dataMax"]} />
            <Bar
              dataKey="value"
              fill={chartColors.primary}
              isAnimationActive={false}
            />
          </BarChart>
        </ResponsiveContainer>
      </div>
    );
  }

  const displaySeries =
    mode === "change"
      ? series
          .slice(1)
          .map((p, i) => ({ date: p.date, value: p.value - series[i].value }))
          .slice(-WINDOW_MONTHS)
      : series.slice(-WINDOW_MONTHS);

  return (
    <div className="h-10">
      <ResponsiveContainer>
        <LineChart data={displaySeries}>
          {/* Without an explicit YAxis, recharts picks a default domain
              that often includes 0, which flattens high-value / narrow-
              range series (participation 63-67%, hours_worked in
              millions). Force the domain to the data range. */}
          <YAxis hide domain={["dataMin", "dataMax"]} />
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
