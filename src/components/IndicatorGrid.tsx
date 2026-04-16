"use client";

import { useState } from "react";
import type { IndicatorData, Indicator, IndicatorGroup } from "@/lib/types";
import IndicatorSparkline from "./IndicatorSparkline";
import IndicatorDetailCard from "./IndicatorDetailCard";

const GROUP_ORDER: IndicatorGroup[] = ["Labour", "Consumer", "Business", "External"];

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
      <p className="text-[10px] uppercase tracking-wider text-label mb-2">
        High-frequency indicators ({indicators.indicators.length})
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
                <IndicatorSparkline series={ind.series} />
              </button>
            ))}
          </div>
        </div>
      ))}
      {selected && <IndicatorDetailCard indicator={selected} onClose={() => setSelected(null)} />}
    </section>
  );
}
