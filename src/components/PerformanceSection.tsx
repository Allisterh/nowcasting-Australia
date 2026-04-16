import type { Performance } from "@/lib/types";
import { formatMillions, formatPct } from "@/lib/format";

interface Props {
  performance: Performance;
}

export default function PerformanceSection({ performance }: Props) {
  return (
    <section className="mb-10">
      <p className="text-[10px] uppercase tracking-wider text-label mb-2">
        Track record
      </p>
      <div className="grid grid-cols-3 gap-3 mb-4">
        <Tile label="MAE" value={formatMillions(performance.mae_millions)} sub={`${performance.mae_pct.toFixed(2)}% of GDP`} />
        <Tile label="RMSE" value={formatMillions(performance.rmse_millions)} />
        <Tile
          label="Directional hit rate"
          value={`${(performance.hit_rate_direction * 100).toFixed(0)}%`}
          sub="Nowcast predicted the correct direction"
        />
      </div>
      <p className="text-xs text-label mb-3 max-w-prose">
        Each quarter, the final nowcast (latest vintage before the release) is compared against the actual GDP value. Directional hit rate is the share of quarters where the nowcast correctly predicted growth or contraction.
      </p>
      <table className="w-full text-xs border-collapse">
        <thead>
          <tr className="border-b border-border-heavy text-left text-[10px] uppercase text-label">
            <th className="py-2">Quarter</th>
            <th className="py-2">Final nowcast</th>
            <th className="py-2">Actual</th>
            <th className="py-2">Error ($M)</th>
            <th className="py-2">Error (%)</th>
          </tr>
        </thead>
        <tbody>
          {performance.errors.map((e) => (
            <tr key={e.target_quarter} className="border-b border-border">
              <td className="py-2">{e.target_quarter}</td>
              <td className="py-2">{formatMillions(e.final_nowcast)}</td>
              <td className="py-2">{formatMillions(e.actual)}</td>
              <td className={`py-2 ${e.error_millions > 0 ? "text-teal" : "text-[#c0392b]"}`}>
                {e.error_millions > 0 ? "+" : ""}{e.error_millions.toLocaleString()}
              </td>
              <td className={`py-2 ${e.error_pct > 0 ? "text-teal" : "text-[#c0392b]"}`}>
                {formatPct(e.error_pct)}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  );
}

function Tile({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div className="border border-border p-3">
      <p className="text-[10px] uppercase tracking-wider text-label">{label}</p>
      <p className="font-headline text-2xl text-teal mt-1">{value}</p>
      {sub && <p className="text-[10px] text-label-light mt-1">{sub}</p>}
    </div>
  );
}
