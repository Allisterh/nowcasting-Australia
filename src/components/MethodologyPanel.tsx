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
            This dashboard displays a nowcast of Australian real GDP growth produced by a Dynamic
            Factor Model (DFM) with an Expectation-Maximization estimator, following the methodology
            of the New York Fed Staff Nowcast.
          </p>
          <p>
            The model combines 13 high-frequency indicators spanning labour, consumer, business, and
            external sectors. Indicators are released at different times within each month (&ldquo;ragged
            edge&rdquo;); the Kalman filter naturally handles the missing data. The nowcast updates each
            week as new data arrives.
          </p>
          <p>
            Reference: Bok et al. (2018), <em>Macroeconomic Nowcasting and Forecasting with Big Data</em>,
            FRB NY Staff Report 830. Implementation uses the R <code>nowcasting</code> package.
          </p>
        </div>
      )}
    </section>
  );
}
