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
