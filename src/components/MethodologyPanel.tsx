"use client";

import { useState } from "react";

export default function MethodologyPanel() {
  const [open, setOpen] = useState(false);

  return (
    <section id="methodology" className="mb-10">
      <button
        onClick={() => setOpen(!open)}
        className={`w-full text-left font-headline border border-border-heavy px-4 py-3 flex items-center justify-between hover:bg-panel ${open ? "border-b-0" : ""}`}
      >
        <span className="font-headline text-3xl text-black">Methodology</span>
        <span className="text-xs text-label font-body">{open ? "Hide" : "Show"}</span>
      </button>
      {open && (
        <div className="border border-t-0 border-border-heavy px-4 py-4 text-sm text-border-heavy space-y-3">
          <p>
            This dashboard nowcasts Australia&rsquo;s quarterly real GDP growth ahead of the ABS
            release using a Monthly Activity Indicator (MAI) and an unrestricted MIDAS (U-MIDAS)
            regression, following the Reserve Bank of Australia&rsquo;s approach in{" "}
            <a
              href="https://www.rba.gov.au/publications/rdp/2024/2024-04.html"
              target="_blank"
              rel="noopener noreferrer"
              className="underline hover:text-teal"
            >
              Research Discussion Paper 2024-04
            </a>
            .
          </p>
          <p>
            The MAI is a single monthly activity factor extracted by a dynamic factor model from
            roughly 30 monthly series spanning labour, household spending, trade, credit, financial
            markets, and business and consumer surveys. The U-MIDAS step regresses quarterly GDP
            growth on the mixed-frequency MAI, accommodating the ragged edge of the panel where the
            latest month of some series has not yet been published. Estimates are re-run weekly as new
            observations arrive.
          </p>
          <p>
            Two specifications are available. The <strong>Main</strong> estimate is tuned for
            precision in normal quarters. The <strong>Volatility model</strong> estimate places more
            weight on recent months, trading some precision for faster response around shocks. Both
            are fit on the same panel and differ only in that weighting.
          </p>
          <p>
            The confidence intervals are derived from the model&rsquo;s out-of-sample
            backtest errors: we take the distribution of past nowcast errors against final GDP, size
            the 68% interval from that spread, and bias-correct for any systematic over- or
            under-prediction. They are calibrated on a limited run of recent quarters, so treat them
            as approximate.
          </p>
        </div>
      )}
    </section>
  );
}
