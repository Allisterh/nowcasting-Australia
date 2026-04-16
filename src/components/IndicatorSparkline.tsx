"use client";

import { LineChart, Line, ResponsiveContainer } from "recharts";
import type { IndicatorPoint } from "@/lib/types";
import { chartColors } from "@/lib/chartTheme";

interface Props {
  series: IndicatorPoint[];
  mode?: "level" | "change";
}

export default function IndicatorSparkline({ series, mode = "level" }: Props) {
  const displaySeries =
    mode === "change"
      ? series.slice(1).map((p, i) => ({
          date: p.date,
          value: p.value - series[i].value,
        }))
      : series;

  return (
    <div className="h-10">
      <ResponsiveContainer>
        <LineChart data={displaySeries}>
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
