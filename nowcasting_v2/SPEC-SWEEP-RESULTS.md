# Spec-lever sweep — α=0.10 and COVID-dummies-OFF (2026-06-13)

<!-- POINT-IN-TIME -->
> ## ⚠️ THE CONCLUSION OF THIS DOCUMENT WAS WRONG. α is now 0.10, the paper's value.
>
> **Re-run 2026-08-02 without the look-ahead. The result reverses.**
>
> This sweep concluded that α=0.05 was *"empirically justified, not a stylistic deviation
> to apologise for"*, and that matching the RBA's 0.10 *"would make the live nowcast
> materially worse."* Neither claim survives honest measurement.
>
> The RMSEs below were produced with the targeted-predictor selection fixed ONCE on the
> FULL sample and forced at every historical as-of — so the Wald gate saw the GDP outcomes
> of the very quarters it was about to "nowcast". That advantage scales with how many
> series are admitted, which is precisely why the looser threshold looked so much worse.
>
> | full-sample RMSE gap, α=0.05 vs 0.10 | |
> |---|---:|
> | claimed below (with look-ahead) | **+0.2340** |
> | re-measured (look-ahead removed) | **+0.0297** |
>
> 87% of the claimed advantage was the artefact. What remains is not statistically
> distinguishable — paired test on squared error, full sample n=49: **p = 0.43**;
> post-COVID n=17: **p = 0.63**. α=0.20 is likewise indistinguishable from 0.05.
>
> With no measurable cost, the tie breaks toward the paper. **Production moved to
> α = 0.10 on 2026-08-02** (`emit_v2_json.R`, model id `v2_qa_a10`).
>
> Everything below is retained as the record of what was believed in June, and of how a
> look-ahead in a backtest can invert a spec decision. Do not cite its numbers.
>
> The inputs had also all moved since June:
>
> | | this document | current |
> |---|---|---|
> | candidate panel | 29 series | 31 |
> | selected at α=0.05 | 9 | ~10 |
> | selected at α=0.10 | 14 | not re-measured |
> | MAI sample start | 1969 | 1978 (the paper's fixed start) |
> | factor published | RTS-smoothed | filtered (`real_time_factor`) |
> | DFM anchor series | panel_info column order | highest Wald statistic |
> | standardisation | divide by sd | divide by RMS (the paper's) |
> | selection in the backtest | fixed once on the FULL sample (look-ahead) | recursive at each as-of |
>
> Re-run with `backtest_v2(sel_alpha = ...)` at `as_of_freq = "quarter_end"`. Full results
> in the 2026-08-02 addendum of
> `docs/reviews/2026-08-01-v2-intention-and-bug-review.md`.

Two experiments James queued (2026-06-12). Both probe where **v2's spec deviates from the
RBA's published method** — not the data (the Bucket-B data expansion was already NO-GO at
production spec). Each config runs the production headline (29-set) + 9 Bucket-B marginals +
full-9, holding every other knob at production (model=qa, dfm_q=1, qa_lag=0:1, exclude=AIG+rt).

Harness: `R/spec_sweep.R` → `cache/specsweep/summary_specsweep.csv`. Toggle added:
`covid_dummies=TRUE` (default, no production change) in `build_mai()` + `backtest_v2()`.
Judging on **postCOVID(2022+) / OOS8** — full-sample is circular for the COVID-off lever
(it refits 2020). 0 failures; all 33 variants computed.

## Headline: both levers are decisive NO-GO

| Config | spec | n_sel | RMSE full | RMSE **pc** | RMSE **oos8** |
|---|---|---|---|---|---|
| **A — production** | α=0.05, COVID-on | 9 | **0.4535** | **0.3422** | **0.2409** |
| B — α=0.10 lever | α=0.10, COVID-on | 14 | 0.6875 (+0.234) | 0.3914 (+0.049) | 0.3788 (+0.138) |
| C — COVID-off lever | α=0.05, COVID-off | 17 | 0.5143 (+0.061) | 0.5195 (+0.177) | 0.4107 (+0.170) |

Both levers lose on **all three windows**, and badly on the honest ones. Production α=0.05 +
COVID-on is the best of the three by a wide margin.

## Lever 1 — α=0.10 (the RBA's actual value): NO-GO

- Looser cut admits **14 series vs 9**. Accuracy degrades sharply everywhere: full +0.234,
  postCOVID +0.049, OOS8 +0.138 (+57% OOS8 RMSE).
- Within-config marginals are near-null (±0.004 pc): most Bucket-B series still don't select
  even at α=0.10; the two that do (credit_personal, non_res_ba) move pc by <0.004.
- **Takeaway:** v2's stricter α=0.05 is *empirically justified*, not a stylistic deviation to
  apologise for. Matching the RBA's 0.10 would make the live nowcast materially worse. The
  extra 5 series at 0.10 are noise, not signal.

## Lever 2 — COVID-dummies-OFF: NO-GO (and the circular-full trap is visible)

- Removing the 2020-21 selection dummies inflates Wald stats broadly (the 2020Q2 co-crash
  re-enters every series), pulling selection **9 → 17** and *changing the composition*: drops
  credit_card, nab_conf, wmi_sent, fcmygbag10; adds pt_emp, hours, the NAB sub-indices,
  anz_ads. Selection gets contaminated by one leverage quarter.
- Honest windows blow out: **postCOVID 0.5195 (+52%)**, **OOS8 0.4107 (+70%)** vs production.
- The trap, made concrete: adding Bucket-B series on top of COVID-off *improves full-sample*
  (debit_card d_full −0.031, full_bucketb −0.029) while *worsening* pc/oos8 (debit_card
  d_pc +0.020; full_bucketb d_pc +0.034, d_oos +0.034). A full-sample "win" here is just
  re-fitting 2020 — exactly why we judged on pc/oos8.
- **Takeaway:** the COVID dummies are load-bearing IIS *outlier control* for selection, not a
  "shock test" that expires. 2020-21 are still in-sample, so "years past COVID" doesn't reduce
  the need. Dropping them corrupts the selection.

## Combined conclusion

Three independent confirmations of the **29-series production panel + production spec**:
1. Stricter α=0.05 beats the RBA's 0.10 on the live nowcast.
2. COVID dummies are necessary for clean selection.
3. Bucket-B series stay non-additive *even when the levers force them into selection* — when
   admitted (looser α or COVID-off) they make the honest windows worse, never better.

No production change. Keep v2 as-is. Toggle + driver retained on `bucket-b-panel-research`
for any future spec probe.
