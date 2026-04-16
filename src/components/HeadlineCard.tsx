"use client";

import { LineChart, Line, ResponsiveContainer, Dot } from "recharts";
import type { LatestNowcast, GdpSeries } from "@/lib/types";
import { formatMillions, formatPct } from "@/lib/format";
import { chartColors } from "@/lib/chartTheme";

interface HeadlineCardProps {
  latest: LatestNowcast;
  gdp: GdpSeries;
}

export default function HeadlineCard({ latest, gdp }: HeadlineCardProps) {
  // Last 8 quarters of actuals + the nowcast point
  const last8 = gdp.series.slice(-8);
  const sparkData = [
    ...last8.map((q) => ({ quarter: q.quarter, value: q.value, isNowcast: false })),
    { quarter: latest.target_quarter, value: latest.nowcast.gdp_chain_volume_millions, isNowcast: true },
  ];

  return (
    <section className="mb-8 border border-border-heavy p-4">
      <p className="text-[10px] uppercase tracking-wider text-label mb-2">
        {latest.target_quarter} nowcast
      </p>
      <div className="flex flex-wrap items-baseline gap-x-6 gap-y-2">
        <span className="font-headline text-4xl text-teal">
          {formatPct(latest.nowcast.qoq_growth_pct)}
        </span>
        <span className="text-sm text-label">QoQ</span>
        <span className="font-headline text-2xl text-teal-500">
          {formatPct(latest.nowcast.yoy_growth_pct)}
        </span>
        <span className="text-sm text-label">YoY</span>
        <span className="ml-auto text-sm text-label">
          {formatMillions(latest.nowcast.gdp_chain_volume_millions)} chain volume
        </span>
      </div>
      <div className="mt-4 h-20">
        <ResponsiveContainer>
          <LineChart data={sparkData} margin={{ top: 5, right: 5, bottom: 5, left: 5 }}>
            <Line
              type="monotone"
              dataKey="value"
              stroke={chartColors.primary}
              strokeWidth={1.5}
              // eslint-disable-next-line @typescript-eslint/no-explicit-any
              dot={(props: any) => {
                const { cx, cy, payload, index } = props;
                if (payload.isNowcast) {
                  return <Dot key={`dot-${index}`} cx={cx} cy={cy} r={4} fill={chartColors.accent} stroke={chartColors.primary} strokeWidth={1.5} />;
                }
                return <Dot key={`dot-${index}`} cx={cx} cy={cy} r={0} fill="transparent" />;
              }}
            />
          </LineChart>
        </ResponsiveContainer>
      </div>
      <p className="mt-2 text-[10px] text-label-light">
        Last 8 quarters of GDP (dark teal) with current nowcast (green). Data through {latest.data_through}.
      </p>
    </section>
  );
}
