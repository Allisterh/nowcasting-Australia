"use client";

import { BarChart, Bar, Cell, ResponsiveContainer } from "recharts";
import type { LatestNowcast, GdpSeries } from "@/lib/types";
import { formatPct } from "@/lib/format";
import { chartColors } from "@/lib/chartTheme";

interface HeadlineCardProps {
  latest: LatestNowcast;
  gdp: GdpSeries;
}

export default function HeadlineCard({ latest, gdp }: HeadlineCardProps) {
  // Last 12 quarters of QoQ growth + the current nowcast's QoQ growth
  const data = [
    ...gdp.series.slice(-12).map((q) => ({
      quarter: q.quarter,
      growth: q.qoq_pct,
      isNowcast: false,
    })),
    {
      quarter: latest.target_quarter,
      growth: latest.nowcast.qoq_growth_pct,
      isNowcast: true,
    },
  ];

  return (
    <section className="mb-8 border border-border-heavy p-4">
      <p className="text-[10px] uppercase tracking-wider text-label mb-2">
        {latest.target_quarter} nowcast
      </p>
      <div className="flex flex-wrap items-baseline gap-x-8 gap-y-2">
        <div className="flex items-baseline gap-x-2">
          <span className="font-headline text-4xl text-teal">
            {formatPct(latest.nowcast.qoq_growth_pct)}
          </span>
          <span className="text-[10px] uppercase tracking-wider text-label">QoQ</span>
        </div>
        <div className="flex items-baseline gap-x-2">
          <span className="font-headline text-2xl text-teal-500">
            {formatPct(latest.nowcast.yoy_growth_pct)}
          </span>
          <span className="text-[10px] uppercase tracking-wider text-label">YoY</span>
        </div>
      </div>
      <div className="mt-4 h-20">
        <ResponsiveContainer>
          <BarChart data={data} margin={{ top: 5, right: 5, bottom: 5, left: 5 }}>
            <Bar dataKey="growth">
              {data.map((row, i) => (
                <Cell
                  key={i}
                  fill={row.isNowcast ? chartColors.accent : chartColors.primary}
                />
              ))}
            </Bar>
          </BarChart>
        </ResponsiveContainer>
      </div>
      <p className="mt-2 text-[10px] text-label-light">
        QoQ growth over the last 12 quarters (dark teal) with current nowcast (green). Data through {latest.data_through}.
      </p>
    </section>
  );
}
