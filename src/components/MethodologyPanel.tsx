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
            The MAI is a single monthly activity factor extracted by a dynamic factor model. It
            starts from a candidate panel of about 30 monthly series spanning labour, household
            spending, trade, credit, financial markets, and business and consumer surveys — but
            following the paper, a targeted-predictor step first tests each candidate against
            quarterly GDP growth and keeps only those that clear a significance threshold. In
            practice that leaves roughly a third of the panel, so the factor is built from around
            ten series rather than all thirty. The U-MIDAS step then regresses quarterly GDP growth
            on the mixed-frequency MAI, accommodating the ragged edge where the latest month of some
            series has not yet been published. Estimates are re-run weekly as new observations
            arrive, and the selection is re-run with them.
          </p>
          <p>
            Two specifications are shown. The <strong>Main</strong> estimate uses a stricter
            selection threshold and a quarter-average regression, tuned for precision in normal
            quarters. The <strong>Volatility model</strong> uses a looser threshold — so it draws on
            a wider set of series — and an unrestricted regression that weights individual months
            within the quarter, trading precision for faster response around shocks. They are
            therefore <em>not</em> the same model with different weights: they are fit on different
            selections of series and use different regressions, which is why they can disagree.
          </p>
          <p>
            The likely ranges are derived from the model&rsquo;s out-of-sample backtest errors: we
            take the distribution of past nowcast errors against final GDP and size the interval from
            that spread. A correction for systematic over- or under-prediction is applied only where
            that bias is statistically distinguishable from zero, so for some estimates the range sits
            centred on the published figure and for others it is deliberately offset. The
            calibration re-runs the model at every past Monday rather than only at quarter-ends, so
            the range reflects the amount of data actually available at each point in the quarter.
          </p>
          <p>
            These ranges widened in August 2026. That was a correction, not a deterioration: the
            earlier calibration let the model see GDP figures that had not been published at the
            time it was supposedly forecasting them, which made its historical accuracy look better
            than it was. The current ranges are calibrated on post-2020 quarters only, because the
            model&rsquo;s errors are measurably larger in that period than before it. They describe
            performance in ordinary quarters and do not price in another pandemic-scale shock. They
            remain estimated from a modest number of quarters, so treat them as approximate.
          </p>
        </div>
      )}
    </section>
  );
}
