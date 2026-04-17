"use client";

import { useState } from "react";
import type { IndicatorData, Indicator, IndicatorGroup } from "@/lib/types";
import IndicatorSparkline, { type SparklineMode } from "./IndicatorSparkline";
import IndicatorDetailCard from "./IndicatorDetailCard";
import IndicatorsTable from "./IndicatorsTable";

const GROUP_ORDER: IndicatorGroup[] = ["Labour", "Consumer", "Business", "External"];

const SPARKLINE_MODE: Record<string, SparklineMode> = {
  employment: "bar",
  unemp_rate: "level",
  part_rate: "level",
  hours_worked: "level",
  household_spending: "bar",
  cons_conf: "level",
  building_approvals: "level",
  bus_conf: "level",
  goods_exp: "level",
  services_exp: "level",
  goods_imp: "level",
  services_imp: "level",
};

interface Props {
  indicators: IndicatorData;
}

export default function IndicatorGrid({ indicators }: Props) {
  const [selected, setSelected] = useState<Indicator | null>(null);

  const byGroup = GROUP_ORDER.map((group) => ({
    group,
    items: indicators.indicators.filter((i) => i.group === group),
  })).filter((g) => g.items.length > 0);

  return (
    <section className="mb-10">
      <p className="font-headline text-3xl text-black mb-2">
        Indicators
      </p>
      {byGroup.map((g) => (
        <div key={g.group} className="mb-4">
          <p className="text-xs text-label mb-2 border-b border-border pb-1">{g.group}</p>
          <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
            {g.items.map((ind) => (
              <button
                key={ind.id}
                onClick={() => setSelected(ind)}
                className={`text-left border p-2 hover:border-border-heavy ${
                  selected?.id === ind.id ? "border-border-heavy bg-panel" : "border-border"
                }`}
              >
                <p className="text-xs text-border-heavy">{ind.name}</p>
                <p className="text-[10px] text-label-light mb-1">{ind.unit}</p>
                <IndicatorSparkline
                  series={ind.series}
                  mode={SPARKLINE_MODE[ind.id] ?? "level"}
                />
              </button>
            ))}
          </div>
        </div>
      ))}
      {selected && <IndicatorDetailCard indicator={selected} onClose={() => setSelected(null)} />}
      <IndicatorsTable
        indicators={indicators.indicators}
        selectedId={selected?.id ?? null}
        onSelect={setSelected}
      />
    </section>
  );
}
