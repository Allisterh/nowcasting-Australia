"use client";

import { BarChart, Bar, Cell, ResponsiveContainer } from "recharts";
import type { V2Model, GdpSeries } from "@/lib/types";
import { formatPct } from "@/lib/format";
import { chartColors } from "@/lib/chartTheme";

interface Props {
  headline: V2Model;
  gdp: GdpSeries;
}

// We deliberately publish no interval. The band this used to show was the point
// estimate +/- one standard deviation of past errors, labelled "about a 2-in-3
// chance" -- but the model's errors are not centred on zero (it runs ~0.34pp
// high), so that range actually contained the eventual figure in 7 of 17
// quarters, not 2 in 3. Rather than shift the band off the published number, we
// disclose the track record, which is what the Atlanta Fed's GDPNow does: it
// publishes no confidence band, only its average error. RDP 2024-04 likewise
// evaluates on RMSE and publishes no interval.
//
// The ci_* fields remain in the payload for the record. Do not render them as a
// confidence level without re-measuring coverage first.

export default function NowcastHeadline({ headline, gdp }: Props) {
  const model = headline;

  const bars = [
    ...gdp.series.slice(-12).map((q) => ({ quarter: q.quarter, growth: q.qoq_pct, isNowcast: false })),
    { quarter: model.target_quarter, growth: model.qoq_growth_pct, isNowcast: true },
  ];

  return (
    <section className="mb-8 border border-border-heavy p-4">
      <div className="flex items-center justify-between flex-wrap gap-2 mb-3">
        <p className="text-[10px] uppercase tracking-wider text-label">
          {model.target_quarter} — our GDP estimate
        </p>
      </div>

      {/* Big number */}
      <div className="flex flex-wrap items-baseline gap-x-8 gap-y-2">
        <div className="flex items-baseline gap-x-2">
          <span className="font-headline text-5xl text-teal">{formatPct(model.qoq_growth_pct)}</span>
          <span className="text-xs text-label">growth this quarter</span>
        </div>
        <div className="flex items-baseline gap-x-2">
          <span className="font-headline text-2xl text-teal-500">{formatPct(model.yoy_growth_pct)}</span>
          <span className="text-xs text-label">vs a year ago</span>
        </div>
      </div>

      {/* Track record in place of an interval — see the note at the top of this file */}
      {model.err_mae_pp != null && model.err_bias_pp != null && (
        <div className="mt-3 text-xs text-label">
          Over the last {model.err_n} quarters this estimate has missed the eventual figure by{" "}
          {model.err_mae_pp.toFixed(2)}pp on average
          {model.err_bias_pp > 0.05 && `, and has tended to run ${model.err_bias_pp.toFixed(2)}pp high`}
          {model.err_bias_pp < -0.05 && `, and has tended to run ${Math.abs(model.err_bias_pp).toFixed(2)}pp low`}.
        </div>
      )}

      {/* Last 12 quarters + this quarter's estimate */}
      <div className="mt-4 h-20">
        <ResponsiveContainer>
          <BarChart data={bars} margin={{ top: 5, right: 5, bottom: 5, left: 5 }}>
            <Bar dataKey="growth" isAnimationActive={false}>
              {bars.map((row, i) => (
                <Cell key={i} fill={row.isNowcast ? chartColors.accent : chartColors.primary} />
              ))}
            </Bar>
          </BarChart>
        </ResponsiveContainer>
      </div>
      <p className="text-[10px] text-label-light">
        Quarterly growth over the last 12 quarters (dark teal); this quarter&rsquo;s estimate in green.
      </p>
    </section>
  );
}
