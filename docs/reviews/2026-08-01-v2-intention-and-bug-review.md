# v2 intention & bug review — 2026-08-01

Two-track review of the Australian GDP nowcast repo.

- **Track 1 (intention):** does `nowcasting_v2` honour RBA RDP 2024-04? Bar agreed with the owner: **"the paper's engine, our own panel"** — the estimation method must match the paper; the panel and variable selection are deliberately ours. Divergences in how the engine is *driven* are findings; documented, evidence-backed panel choices are not.
- **Track 2 (bugs):** whole repo, v1 and v2, excluding the 3,648 lines of `nowcasting_v2/R/methods/` verified byte-identical to the paper's own replication code.

**Method.** 10 finder agents (5 intention on Claude Fable 5, 5 bug subsystems on Claude Opus 5) produced 190 raw findings. 3 adversarial verifiers were instructed to *refute* each one and to default to refuting when uncertain. **141 survived; 49 were refuted or deduplicated.**

| severity | count |
|---|---:|
| 🔴 critical | 3 |
| 🟠 high | 18 |
| 🟡 medium | 49 |
| ⚪ low | 71 |

*Caveat on the counts:* the verifiers were told to kill anything they couldn't confirm, so the appendix contains findings that may well be real but unproven. Conversely, "survived" means one verifier failed to refute it — not that it is certain. Treat medium/low as a backlog to triage, not a defect list.

---

> ## Corrections log
>
> **This document was amended on 2026-08-02.** Two claims in the original narrative were
> wrong and have been rewritten in place; both are recorded here rather than silently
> deleted, because each was stated confidently and acted on.
>
> 1. **"The MAI is 65.8% labour by DFM loading weight."** Retracted. That figure came from
>    treating `|loading|` share as a weight vector. `qmle_dfm` runs `id_opt = "DFM2"`, whose
>    q×q block C₀ is the identity — so the first column's loading is *pinned to 1.0* and every
>    other loading is expressed relative to it. It is a normalisation artefact, not a weight.
>    The review itself caught the underlying mechanism as a low-severity finding
>    ("named-factor identification anchors on panel_info column order"). Measured properly by
>    correlation, the MAI tracks the **yield spreads** (`scrigbag5` 0.957, `scrigbag10` 0.932,
>    `scrigbag3` 0.920) far more closely than labour (`ue` −0.278, `ft_emp` 0.239, `ud` −0.116),
>    and that holds in every subsample from 1969, 1978, 2000 and 2015.
> 2. **"Switching to `real_time_factor()` will damp single-release swings."** Falsified by
>    direct test: filtered +0.652pp vs smoothed +0.649pp on the 2026-07-27 labour update. It
>    remains a genuine fidelity divergence (paper fn.33) but has no effect on sensitivity.
>
> The **finding** that the model over-amplified single releases was correct and is unchanged —
> only the proposed mechanism and the proposed fix were wrong. See *The labour-sensitivity
> question* below for what actually resolved it.

---

## Status: what has been fixed since this review ran

| finding | status | commit |
|---|---|---|
| Target quarter follows the MAI edge, skipping a quarter | **fixed** + regression test | `ce14abb` |
| Backtest look-ahead (`force_selected` on the full sample) | **fixed** (`recursive_selection`) | `ce14abb` |
| CI bands calibrated at one information stage | **fixed** (weekly grid, per-stage params) | `ce14abb` |
| Bias correction applied when not significant | **fixed** (t-tested per stage) | `ce14abb` |
| `z` from the normal instead of `t(df)` | **fixed** | `ce14abb` |
| Sample starts 1969, paper hard-codes 1978 | **fixed** | `3b0ba8e` |
| DFM2 anchors on column order, not highest Wald | **fixed** | `3b0ba8e` |
| Standardisation divides by sd, paper uses RMS | **fixed** | `3b0ba8e` |
| GDP look-ahead in `build_mai`'s Wald selection | **fixed** | `3b0ba8e` |

Everything else in this document is still open.

## The target-quarter bug was already live

The original text predicted this would fire on the 2026-08-03 cron. That framing was too narrow: **it had already been firing since 2026-07-20, on the stress model.** At α=0.20 the selection includes `wmi_sent`, whose publication lag is *negative* (−15d, released ahead of its reference month), so its MAI reached Q3 while the headline sat on Q2 — and `latest_v2.json` presented both under a single top-level `target_quarter`.

The documented contract (`nowcast_midas.R:14`, `:93`) is "target quarter = first quarter that has MAI data but no released GDP". The implementation instead took the *last* MAI quarter whenever the MAI edge crossed into a new quarter, which happens ~4 weeks before the previous quarter's GDP is released. The skipped quarter was never nowcast again and never got a final vintage for the track record.

Now always targets `last_released_gdp_quarter + 1`, with a warning for the inverse failure (MAI more than one quarter past target ⇒ stale `rt_dgdp_qtr.csv`).

---

## The labour-sensitivity question

The review was triggered by this: on 2026-07-27 a **labour-only** data update (commit `1ed1c80` — only `emp`/`ft_emp`/`pt_emp`/`ue`/`ud`/`hours` changed) moved v2 from −0.03% to +0.62%, **+0.65pp**, while v1 moved −0.01pp on the same release. Same target quarter, same `data_through`.

### Labour was never specially weighted

The original narrative claimed the MAI was 65.8% labour by loading weight. **That was wrong** — see the corrections log above. Measured three ways, the picture is:

**Marginal sensitivity.** Shock each selected series by an identical +1 SD and watch the nowcast (pre-fix):

| series | block | Δ nowcast |
|---|---|---:|
| `ue` | labour | −0.789 pp |
| `scrigbag3` | yield spread | −0.641 pp |
| `scrigbag10` | yield spread | −0.635 pp |
| `scrigbag5` | yield spread | −0.635 pp |
| `ft_emp` | labour | +0.002 pp |
| `ud` | labour | −0.001 pp |
| all others | — | ~0.000 pp |

Mean sensitivity: **labour 0.264pp, non-labour 0.239pp** — statistically the same. Four series dominated the model: one unemployment series and three interest-rate spreads. Labour only *looked* special because labour was the only block that updated that week. Had the yield curve moved instead, the same jump would have appeared.

**Against the paper.** The RBA censored 15 of the paper's 30 selected series — and 12 of those 15 are surveys, so the surviving sample is biased against exactly the block in question. On the one measure available for both (correlation with the finished MAI):

| | labour share of co-movement | strongest single series |
|---|---:|---|
| paper's MAI | **43.7%** | `wmi_sent` (a consumer survey) 0.626 |
| our MAI | **13.9%** | `scrigbag5` (a yield spread) 0.957 |

We are **less** labour-driven than the paper, not more. The real divergence is that the paper built an activity index and v2 had built something closer to a yield-curve index — which sits awkwardly against the project's own documented decision to exclude a financial block from v1 on Atlanta Fed / NY Fed precedent.

**What the release actually did.** A news decomposition of the 2026-07-27 move (revert each series to its 07-20 vintage, re-run the full production chain) attributes the entire +0.649pp to the data, none to the as-of advance:

| | contribution |
|---|---:|
| as-of advance alone | +0.000 pp |
| new labour data | +0.649 pp |
| — `ft_emp` | +0.792 pp |
| — `ud` | +0.523 pp |
| — `ue` | −0.001 pp |
| — `emp`, `pt_emp`, `hours` | 0.000 (not selected) |

June full-time employment rose **+0.29%, a 0.34 SD move** — utterly ordinary against series extremes of −6.5 SD (Apr 2020) and −3.5 SD (1991). That routine print moved the quarterly GDP nowcast 0.79pp, more than twice the model's own error SD.

**One anomaly remains unexplained.** Removing `ft_emp`'s June observation moves the nowcast 0.79pp, but shocking that same observation by a full SD moves it 0.002pp — a series whose *presence* is worth 400× its *value*. `ft_emp` was the `DFM2` anchor, which is the obvious suspect, but this was never demonstrated.

### The real diagnosis: amplification, not weighting

The problem was never that labour carried too much weight. It was that an 11-series index had **four series each carrying ~0.7pp of quarterly GDP per standard deviation** — labour and yields alike.

Four fidelity divergences were found. Two are confirmed contributors; one was tested and exonerated.

**1. v2 emits the RTS-*smoothed* factor as the MAI. The paper uses the *filtered* one.** `build_mai.R:236` takes `dfm$factors[,1]`, which `qmle_dfm_methods.R:1103` populates from the RTS smoother. The paper's footnote 33 (p.9) is explicit: *"the filtered estimate ... is appropriate for conditional forecasting, while the smoothed estimate is appropriate for within-sample estimation."* Both `Modelling_GDP_MIDAS_TP.R:58` and `Recursive_Nowcast_GDP_UMIDAS_TP.R:58` read the `real_time_factor()` output. **`real_time_factor` is never called anywhere in v2.**

A smoothed factor is two-sided, so every new observation revises the entire MAI history rather than just its tip. The original narrative reasoned from that to "therefore this amplifies single-release swings, and switching to the filtered factor will damp them."

**Tested and false.** Patching `build_mai` to use `real_time_factor()` and re-running the same news decomposition gives **+0.652pp against the smoothed +0.649pp** — no effect. Per-series: `ft_emp` +0.839 filtered vs +0.792 smoothed, `ud` +0.546 vs +0.523.

It remains a real fidelity divergence and should still be fixed, on fidelity grounds. It is not the amplifier, and it is not "the single most important finding".

**2. The paper's spec-determination stage was dropped.** `Determine_TP_MAI_Estimation_Options.R` exists to derive the factor structure empirically. v2 hardcodes `dfm_q = 1L` with `s=2, p=1` as ported constants, never re-derived on our panel. The paper runs 30 predictors through one factor; v2 runs 11. Concentration is therefore an untested inheritance rather than a design choice — but note the "the factor *is* the labour cycle" reasoning in the original draft does not survive measurement (the factor tracked yield spreads at 0.92–0.96 and labour at 0.12–0.28). Still open.

**3. The soft block cannot compete on history.** Survey series are observed for 37–66 months against labour's ~580. Standardisation and loadings for the soft block are estimated on roughly three years of data, and `transform_panel`'s interior-NA fallback silently replaces 20-year rolling demeaning with a full-sample mean for at least `anz_sent`. Surveys carrying almost no influence is therefore partly an artefact of short samples and a silent fallback, not purely a statement that they don't inform GDP. Still open.

**4. Selection targets revised GDP, not first-release.** The paper follows Koenig, Dolmas & Piger (2003) and uses **first-release** GDP growth as the target of both the Wald selection and the MIDAS models (p.5; Figure A3 note). `fetch_rt_gdp.R:5` uses the current vintage and says so in a comment. Overlapping values differ materially (2021 Q1: 2.162 vs the paper's 1.787). Revised GDP embeds later labour-account information, which plausibly tilts the Wald ranking toward labour predictors relative to the target the paper specifies.

**What actually resolved it.** Four fidelity fixes landed in `3b0ba8e` — the 1978 sample floor, Wald-ordered `DFM2` anchor, RMS standardisation, and closing the GDP look-ahead in the Wald selection. Measured at the same 2026-07-27 as-of:

| | pre-fix | post-fix |
|---|---:|---:|
| Q2 nowcast | +0.615% | **+0.619%** |
| max single-series sensitivity | 0.789 pp (`ue`) | **0.148 pp** (`scrigbag5`) |
| mean labour sensitivity | 0.264 pp | **0.002 pp** |
| selected series | 11 | 10 |

The point estimate barely moved; the sensitivity collapsed by a factor of five. A 1 SD move in any single series now shifts the nowcast by at most 0.15pp — inside the model's own error SD rather than more than double it.

**Attribution is incomplete and should not be overstated.** With the 1978 floor disabled but the other three fixes applied, max sensitivity is still 0.140pp — so the sample window is *not* what damped it. The 1978 floor instead moves the *level*: 1969 start gives −0.021%, 1978 gives +0.619%, a 0.64pp swing from including nine years in which no labour data existed at all. Which of the remaining three (anchor order, RMS, GDP truncation) did the damping was never isolated. The anchor reorder is the natural suspect given the `ft_emp` presence-vs-value anomaly, but that is a hypothesis, not a result.

---

## Recommended actions

Ranked. Nothing here proposes a rewrite.

### Done (2026-08-02)
| # | Action | Outcome |
|---|---|---|
| 1 | Target-quarter rule corrected to its documented contract | `ce14abb`; regression test added. Was already live on the stress model since 2026-07-20 |
| 11 | CI calibration re-run without full-sample-fixed selection | `ce14abb`. Bands were ~53% too narrow like-for-like (sd 0.3528 → 0.5398) |
| 12 | Sample-start control at the paper's 1978 | `3b0ba8e`. Moves the level 0.64pp; does **not** affect sensitivity |
| — | `DFM2` anchor ordered by Wald, not column order | `3b0ba8e` |
| — | Standardisation by RMS, matching `scale(center=FALSE, scale=TRUE)` | `3b0ba8e` |
| — | GDP look-ahead closed in `build_mai`'s Wald selection | `3b0ba8e` |

### Fix now
| # | Action | Why | Where |
|---|---|---|---|
| 2 | Derive `prev_level` and the YoY chain from each model's *own* target quarter | Latent: currently masked because both models target the same quarter again after #1, but nothing asserts it | `emit_v2_json.R:83,123` |
| 3 | Assert the two models share a target quarter, or label the difference | Same latency as #2 | `emit_v2_json.R:152`, `NowcastHeadline.tsx:27` |
| 4 | Correct the Methodology copy | Says "~30 series" and "both fit on the same panel"; actually 10 and 16 series, different panels *and* different MIDAS specs. Also needs updating for the wider bands | `MethodologyPanel.tsx:45` |
| 5 | Label the track record as backtested | `backcasts.json` carries the disclaimer; the page drops it and heads the column "Final nowcast". Compounded by the leak — the advertised accuracy was ~38% better than real | `PerformanceSection.tsx:23` |
| 6 | Add a length-regression guard to the NAB fetchers | `scrape_nab_full.R:304` overwrites 348 months of history with a ~40-month stub; only `nab_conf` has a tripwire | `scrape_nab_full.R:311` |
| 7 | Guard the ABS indicator count | A URL change silently drops a series and v1 nowcasts on 12 | `03_data_ingestion.R:218` |

### Investigate — these change the model
| # | Action | Why |
|---|---|---|
| 8 | Switch the MAI to `real_time_factor()` | Genuine fidelity divergence (paper fn.33). **Do not expect it to damp sensitivity** — tested, +0.652 vs +0.649pp, no effect. Fix it because the paper prescribes it, not for stability |
| 9 | **Re-derive `q`, `s`, `p` on our panel** via the paper's own spec-determination stage | The highest-value open fidelity item. Tests whether one factor suits a 31-series panel, or whether a second would give the soft block somewhere to live |
| 10 | Move the selection/MIDAS target to first-release GDP | Paper-specified (Koenig–Dolmas–Piger). May be blocked on ABS vintage availability 2022–2026 — the paper's own file stops at 2022 |
| 13 | Re-run the α sweep on the current panel | `SPEC-SWEEP-RESULTS.md` records 29→9; production is now 31→10 under the fixed spec |
| 14 | Isolate which of anchor-order / RMS / GDP-truncation damped the sensitivity | Currently unattributed; matters for knowing what to preserve |
| 15 | Explain the `ft_emp` presence-vs-value anomaly | Removing its June observation moves the nowcast 0.79pp; shocking it 1 SD moves it 0.002pp |

### Accept and document
- α=0.05 over the paper's 0.10 — evidence-backed, though the sweep needs re-running (#13).
- Panel substitutions (`ivi` for `doe_ads`, `household_spending` for `rt`) — sensible adaptations to the censored panel.
- **The point/band centring split is resolved.** Bias is now t-tested per information stage and applied only where significant. The headline's is not (t=1.24) so its band is centred on the published point; the stress model's is (t=3.31) so its band is deliberately offset. Note the earlier draft's "the bias is fitting noise, drop it" was an artefact of n=17 — on the weekly grid it is real for one of the two models.
- **Per-stage CI calibration is built but does not currently change the band.** `jt=2` vs `jt=3`: sd 0.5377 vs 0.5398, F=0.89, p=0.697. And `jt=0` cannot occur — GDP releases ~60 days after quarter-end, so a target quarter always has ≥2 months of data. The `jt=0` random-walk fallback is dead code in production.
- **The post-COVID calibration window is justified**, tested rather than inherited: pre-2020 sd 0.3382 (n=85) vs post-2021 sd 0.5824 (n=38), F=2.97, p<0.0001.


## Track 1 — fidelity to RBA RDP 2024-04

### W4 — Real-time discipline  (7 findings)

#### 🟠 high · CI params calibrated under full-sample-fixed selection; production re-selects every Monday

`nowcasting_v2/R/backtest_v2.R:163` · real-time-leak · finder confidence: high  · **bears on labour concentration**

**Claim.** The CI-calibration backtests (recalib_ci_v2.R:15-22) run backtest_v2(), which fixes the targeted-predictor selection ONCE on the full current panel ('Fixing full-sample targeted-predictor selection...', backtest_v2.R:161-174) and forces it at every historical as-of via force_selected. Production (emit_v2_json.R mk(), line 120) calls build_mai() with NO force_selected, so the live Wald selection is recomputed each Monday on truncated data. The calibration therefore (i) lets the Wald gate see the GDP outcomes of the very quarters the backtest then 'nowcasts' (look-ahead: selection is supervised on the evaluation sample), and (ii) calibrates a process that is not the production process (fixed selection vs weekly re-selection, whose regime switches add forecast variance the bands never see). The paper makes the same one-time simplification but explicitly flags it as a limitation (p. 25) and never uses those errors to publish calibrated intervals.

**Evidence.** backtest_v2.R:163-168: full_sel_res <- build_mai(tfs = tfs_full, ...) on wide_full = readRDS(panel_rds) (full latest vintage); :168 fixed_selection <- full_sel_res$diagnostics$selected; :229 force_selected = sel_t. recalib_ci_v2.R:15-17: backtest_v2(out_csv="cache/ci_recalib/qa_a05_acc.csv", model="qa", sel_alpha=0.05, ..., lag_fn=.lag_acc) — no force_full_selection override, so the full-sample gate is used. emit_v2_json.R:120-122: build_mai(tfs=tfs_m, sel_alpha=sel_alpha, dfm_q=1L, exclude_ids=...) — no force_selected. ci_params_v2.json: source "cache/ci_recalib/qa_a05_acc.csv", qoq_sd_pp 0.3528, n=17. Paper p.25: "we do not redo the pre-selection step... the ranking is done only once and using the full sample. This could bring some issues with our results".

**Failure scenario.** A quarter (e.g. 2020 Q2) whose extreme GDP outcome drove several series over the Wald threshold is backtested with exactly those series in the MAI, producing an error smaller than any real-time analyst could have achieved; the post-COVID error sd (0.3528pp, n=17) computed from such errors is shipped as ci_params_v2.json and applied to Monday nowcasts made by a model whose selection (11 series at 2026-07-27) was chosen live and can differ from the calibration's fixed set — published 68/95 bands are systematically too tight and describe a different model.

**Survived refutation because.** Verified all three legs. backtest_v2.R:161-174 computes fixed_selection once on the full-latest-vintage panel and forces it at every as-of via force_selected (line 229). recalib_ci_v2.R:15-22 calls backtest_v2 with no force_full_selection override, so that full-sample gate is what produced cache/ci_recalib/qa_a05_acc.csv, and ci_params_v2.json names that file as its source (n=17, qoq_sd_pp 0.3528). emit_v2_json.R:120-122 calls build_mai with sel_alpha/dfm_q/exclude_ids but NO force_selected, so production re-runs the Wald gate every Monday. Could not refute. The paper makes the same one-time simplification but flags it and does not publish calibrated intervals from it; v2 does, so the calibration-vs-production mismatch is a real defect in how the engine is driven.


#### 🟠 high · CI bands calibrated only at quarter-end information stage but applied at every Monday stage

`nowcasting_v2/R/backtest_v2.R:186` · fidelity · finder confidence: high

**Claim.** backtest_v2 evaluates only at quarter-end as-of dates (as_of_dates <- ceiling_date(q_starts,"quarter")-1), where the headline MAI uniformly reaches month 2 of the target quarter (labour/financial through M2 under .lag_acc), i.e. one fixed within-quarter stage. Production applies the resulting single bias/sd pair to every Monday of the cadence, where jt varies 0..3 (latest_v2.json shows headline jt=3; early-cadence Mondays have jt=0-1). The paper's own evaluation (Table 3, pp. 20-21; Figure 4 timeline) shows accuracy differs materially by stage (separate FC/M1/M2/M3/QA models with different RMSEs), which is precisely why it distinguishes them; v2 collapses the stages into one interval.

**Evidence.** backtest_v2.R:182-188 quarter-end as_of construction; ci_params_v2.json n=17 (2022Q1..2026Q1 quarter-ends), single qoq_sd_pp=0.3528; emit_v2_json.R:126-127 applies it to whichever jt the Monday produces; vintages cadence spans the whole quarter (vintages_v2.json Mondays from 2026-06-01). Paper Table 3: full-sample RMSE varies FC 0.87 / M1 0.70 / M2 0.78 / M3 0.88.

**Failure scenario.** On the first cadence Monday after a GDP release (jt=0, QA random-walk extrapolation of the MAI) the published 68% band has half-width 0.35pp — calibrated on errors made with 2 months of target-quarter data — so early-quarter intervals are materially overconfident; the vintage evolution chart then shows early points 'jumping outside' their own initial bands as data arrives.

**Survived refutation because.** Verified and strengthened. backtest_v2.R:182-188 builds as_of_dates as quarter-ends only. I worked the ragged edge at a quarter-end as-of with .lag_acc: labour (lag 15) has month-2 data but not month-3 (M3 ref_end + 15 > quarter-end), so the calibration sample is a jt=2 stage. Production's live headline is jt=3 (latest_v2.json n_months_in_quarter=3), and I traced the first cadence Monday (.mondays_to_date starts at last_q_end+60, e.g. 2026-06-01 for a Q2 target) to jt=1. So a single sd=0.3528/bias=0.2006 pair calibrated at one stage is applied across jt=1..3 — bands too tight early, too loose late. The paper's Table 3 distinguishes FC/M1/M2/M3/QA precisely because accuracy differs by stage. Could not refute.


<details>
<summary>5 medium/low findings</summary>

| sev | finding | location | category | labour |
|---|---|---|---|---|
| 🟡 medium | GDP_LAG=60 understates true ~64-day ABS lag; 2026-06-01 vintage embeds GDP released 2026-06-03 | `nowcasting_v2/R/emit_v2_json.R:33` | real-time-leak |  |
| 🟡 medium | Shipped CI params (2026-06-11) predate the current 31-candidate panel and 11-series selection | `pipeline/seed/ci_params_v2.json:1` | stale-doc | yes |
| ⚪ low | Emit's per-Monday Wald selection reads the full GDP file, not the truncated gdp_m | `nowcasting_v2/R/emit_v2_json.R:120` | real-time-leak | yes |
| ⚪ low | Future-dated vintage possible: .mondays_to_date can return a Monday after today | `nowcasting_v2/R/emit_v2_json.R:78` | ci-reliability |  |
| ⚪ low | CI half-widths use normal z with n=17 errors instead of t(16) | `pipeline/compute_ci_params.R:40` | correctness |  |

</details>

### W2 — TP selection & MAI  (4 findings)

#### 🟠 high · v2 emits the RTS-smoothed factor as the MAI; the paper's nowcast engine uses the filtered real-time factor

`nowcasting_v2/R/build_mai.R:236` · fidelity · finder confidence: high  · **bears on labour concentration**

**Claim.** build_mai.R takes `fac <- dfm$factors[, 1L]`, and qmle_dfm's `factors` is the RTS-smoothed state (`factors <- t(fs$xs[...])`, qmle_dfm_methods.R:1103). The paper explicitly uses the FILTERED estimate for conditional forecasting (footnote 33, p.9: 'we will only focus on the filtered estimate of the MAI ... the filtered estimate (based on the full sample parameter estimates) is appropriate for conditional forecasting, while the smoothed estimate is appropriate for within-sample estimation'), computed via `real_time_factor()` (Kalman filter only, `kf$xf`, qmle_dfm_methods.R:1193-1198), and both Modelling_GDP_MIDAS_TP.R:58 and Recursive_Nowcast_GDP_UMIDAS_TP.R:58 read `rt_mai_q_1_s_2_p_1_rdp.csv`, the real_time_factor output written by Estimate_and_Analyse_TP_MAI.R:150,268. grep shows `real_time_factor` is never called anywhere in v2's R/ or pipeline/.

**Evidence.** v2: build_mai.R:231-236 `dfm <- qmle_dfm(...); fac <- dfm$factors[, 1L]`; qmle_dfm_methods.R:1103 `factors <- t(fs$xs[seq_len(r), , drop = FALSE])` (xs = rts_smoother output). Paper: Recursive_Nowcast_GDP_UMIDAS_TP.R:58 `mth_infile <- sprintf("rt_%s_q_%d_s_%d_p_%d_rdp.csv", ...) # real-time mai`; Estimate_and_Analyse_TP_MAI.R:150 `rt_dfm <- real_time_factor(...)`; qmle_dfm_methods.R:1198 `factors <- t(kf$xf[...]) # Estimated real-time factors (i.e. x_t|t)`; RDP 2024-04 footnote 33.

**Failure scenario.** Every weekly run: the MIDAS regression is fit on a two-sided smoothed MAI history instead of the one-sided filtered history the paper prescribes, so (a) MIDAS coefficients differ from the paper's engine, (b) any new data release (e.g. the 2026-07-27 labour-only update, fact 6) revises the ENTIRE smoothed MAI history, not just the edge, amplifying single-release swings in the published nowcast (+0.65pp), and (c) backtest RMSEs are flattered because interior smoothed states embed future information relative to each pseudo-real-time as-of.

**Survived refutation because.** Verified in the byte-identical methods file: qmle_dfm_methods.R:1103 sets `factors <- t(fs$xs[...])` where fs comes from run_fs_recursions (xs = RTS-smoothed states), while real_time_factor at line 1177-1198 returns `t(kf$xf[...])` labelled '# Estimated real-time factors (i.e. x_t|t)'. grep confirms real_time_factor is called ONLY from rba_paper/content/Code/Estimate_and_Analyse_TP_MAI.R:150 and MAI_COVID_Robustness_Analysis.R:112 — never from any v2 R/ or pipeline/ file. The paper's nowcast driver Recursive_Nowcast_GDP_UMIDAS_TP.R:58 reads `rt_mai_..._rdp.csv` with the comment '# real-time mai', i.e. the real_time_factor output. build_mai.R:236 takes dfm$factors[,1]. This is the clearest engine-fidelity divergence in the batch and I could not refute it. Downgraded from critical to high only because the model is re-estimated consistently each run, so the harm is estimation/prediction mismatch and whole-history revision rather than a directly computable wrong number.


#### 🟠 high · Selection and MIDAS target GDP is latest-vintage growth, not the paper's first-release GDP

`nowcasting_v2/R/fetch_rt_gdp.R:5` · fidelity · finder confidence: high  · **bears on labour concentration**

**Claim.** The paper explicitly follows Koenig, Dolmas and Piger (2003) and uses FIRST-RELEASE quarterly GDP growth as the target of the Wald selection regressions and the MIDAS models (p.5: 'Instead of using the current release version of GDP ... we follow Koenig, Dolmas and Piger (2003)'s recommendation and use the first-release version of GDP'; Figure A3 note: 'GDP is first release'). v2's fetch_rt_gdp.R computes QoQ growth from the CURRENT vintage of ABS A2304402X and admits it in a comment: '"rt" = real-time in the RBA naming; here we use the latest vintage (a real-time vintage substitution is a later refinement)'. Overlapping values differ materially from the paper's rt_dgdp_qtr.csv (2021Q1: v2 2.162 vs paper 1.787; 2021Q3: v2 -1.713 vs paper -1.922).

**Evidence.** fetch_rt_gdp.R:5-7 (comment quoted above), :24 `read_abs_series(series_id)` with series_id A2304402X, :37 growth from lag of latest-vintage levels; RDP 2024-04 p.5; nowcasting_v2/data_raw/rt_dgdp_qtr.csv 2021-03-01 = 2.16207 vs rba_paper/content/Data/rt_dgdp_qtr.csv 1/03/2021 = 1.786828.

**Failure scenario.** Wald statistics and hence the selected predictor set are computed against a revised target: heavily revised quarters (COVID era, 2021Q1 revised up 0.38pp) shift the ranking, and revised GDP embeds later labour-account information, plausibly favouring labour predictors over timely soft indicators relative to a first-release target. The MIDAS coefficient fit and the reported backtest errors also measure the wrong (revised) target relative to the paper's engine. The in-code note frames it as a known stopgap ('later refinement'), so it is documented but unresolved.

**Survived refutation because.** Verified on all three legs. (1) fetch_rt_gdp.R:5-6 states 'here we use the latest vintage (a real-time vintage substitution is a later refinement)'; :24 read_abs_series("A2304402X"); :36 growth from the lag of latest-vintage levels. (2) The paper's Recursive_Nowcast_GDP_UMIDAS_TP.R:64-66 reads its own rt_dgdp_qtr.csv, which is the Lee et al first-release series. (3) The numeric divergence is real: paper Data/rt_dgdp_qtr.csv 1/03/2021 = 1.786828 and 1/09/2021 = -1.922074; v2 data_raw/rt_dgdp_qtr.csv 2021-03-01 = 2.16207 and 2021-09-01 = -1.71278. This is the regressand of the Wald selection and the MIDAS fit — squarely 'how the engine is driven', not a panel choice — and the in-code note frames it as unresolved. Could not refute.


<details>
<summary>2 medium/low findings</summary>

| sev | finding | location | category | labour |
|---|---|---|---|---|
| 🟡 medium | The paper's DFM spec-determination stage (q, s, p) was dropped; q=1,s=2,p=1 are ported constants never re-derived on v2's panel | `nowcasting_v2/R/build_mai.R:54` | fidelity | yes |
| 🟡 medium | Production alpha=0.05 deviates from the paper's alpha=0.10 and its written justification is stale | `nowcasting_v2/SPEC-SWEEP-RESULTS.md:1` | stale-doc |  |

</details>

### W1 — Panel & transforms  (8 findings)

#### 🟠 high · No sample-start control: panel/MAI/selection/MIDAS all start 1969, paper hard-codes 1978

`nowcasting_v2/R/build_mai.R:84` · fidelity · finder confidence: high

**Claim.** The paper explicitly windows everything to a 1978 start (panel 1978:M2; selection/MIDAS estimation m_begin_str='1978-04-01', q_begin_str='1978-06-01' at Targeted_Predictor_MAI_Dataset.R:94-95). v2 has no sample-start control anywhere: build_panel.R:64 builds the spine from min(all series dates), and build_mai.R:84 sets m_start = min(quarter-start months of the spine). Because firmmbab90 starts 1969-06 (data_raw/firmmbab90.csv) and credit starts 1976-09, the emitted MAI runs from 1969-07 (confirmed: data_raw/mai.csv row 1 = 1969-07-01), the Wald/IIS selection regressions use quarters from 1969Q3 (per-series complete.cases only), and nowcast_midas.R:127 fits the MIDAS regression from 1969Q3 because rt_dgdp_qtr.csv covers 1959-12 onward with no gaps.

**Evidence.** Paper: Targeted_Predictor_MAI_Dataset.R:94 `m_begin_str <- "1978-04-01"`, :95 `q_begin_str <- "1978-06-01"`; paper p.4: dataset 'covers the sample period 1978:M2 to 2022:M9 and was influenced by the number of series available in the early part of the sample' (footnote 17: LFS began Feb 1978). v2: build_panel.R:64 `spine <- data.frame(date = seq(min(all_dates), max(all_dates), by = "month"))`; build_mai.R:84 `m_start <- min(ms)`; nowcast_midas.R:127 `m_start <- min(fm)`; data_raw/mai.csv first data row `1969-07-01,-0.036`; data_raw/rt_dgdp_qtr.csv first row `1959-12-01` (267 rows, contiguous).

**Failure scenario.** For 1969-07..1978-01 (~34 quarters) the only selected series observed is firmmbab90, so the 'activity indicator' over that span is just standardised monthly BBSW changes; those quarters enter the MIDAS estimation sample and pull the MAI slope coefficients toward the 1970s interest-rate/GDP relationship the paper deliberately excluded. Additionally, firmmbab90's full-sample unit-variance scaling now includes the high-volatility 1970s-80s rates era (paper: 1978+), compressing its modern z-scores; and firmmbab90/credit Wald statistics are computed over pre-1978 samples the paper's selection never sees, so the selected set itself can differ from what the paper's procedure would select on the same data.

**Survived refutation because.** Verified every link. build_panel.R:64 builds the spine from min(all_dates); build_mai.R:84 sets m_start = min(quarter-start months of the spine), and only the TRAILING edge is trimmed (lines 208-213). data_raw/firmmbab90.csv starts 1969-06-01, so data_raw/mai.csv's first row is 1969-07-01 with 683 monthly values. nowcast_midas.R:126-127 then sets its own m_start from the MAI, so the U-MIDAS sample begins 1969 Q3 — 227 quarters, which matches NIGHT-LOG.md's reported '226-qtr fit'. The paper's rba_paper/content/Data/mai_panel.csv begins 1/02/1978 and Targeted_Predictor_MAI_Dataset.R:94-95 hard-codes 1978-04-01/1978-06-01. Tried to refute via na_opt='exclude' — that only affects the PC initialisation (remove_na_values on yna); the DFM itself is handed the ragged Ysel and the Kalman recursions mask missing rows, so the 1969-1978 span really does enter the sample with essentially one observed selected series. Could not refute; this is a windowing/glue divergence in how the engine is driven.


<details>
<summary>7 medium/low findings</summary>

| sev | finding | location | category | labour |
|---|---|---|---|---|
| 🟡 medium | Interior-NA fallback silently replaces 20-year rolling demeaning with full-sample mean (hits anz_sent) | `nowcasting_v2/R/transform_panel.R:96` | fidelity | yes |
| 🟡 medium | Soft block observed 37-66 months vs labour's ~580; standardisation and loadings estimated on 3 years of data | `nowcasting_v2/seed/panel_info.csv:23` | data-contract | yes |
| ⚪ low | Named-factor identification anchors on panel_info column order (ft_emp), not the paper's highest-Wald series | `nowcasting_v2/R/build_mai.R:221` | fidelity |  |
| ⚪ low | build_panel silently keeps the last value for duplicate months | `nowcasting_v2/R/build_panel.R:56` | data-contract |  |
| ⚪ low | household_spending deflation interpolates quarterly CPI using next quarter's value (pseudo-real-time leak) | `nowcasting_v2/R/fetch/fetch_abs_panel.R:147` | real-time-leak |  |
| ⚪ low | run_nowcast_v2.R is a stale entrypoint: builds a different model spec than production and overwrites data_raw/mai.csv | `nowcasting_v2/R/run_nowcast_v2.R:93` | ci-reliability |  |
| ⚪ low | Unit-variance step divides by sd, paper divides by root-mean-square | `nowcasting_v2/R/transform_panel.R:102` | fidelity |  |

</details>

### W3 — MIDAS specification  (10 findings)

#### 🟠 high · Headline and stress are emitted as parallel 'models' but target DIFFERENT quarters (Q2 vs Q3)

`nowcasting_v2/R/emit_v2_json.R:152` · data-contract · finder confidence: high  · **bears on labour concentration**

**Claim.** data/latest_v2.json presents models.headline (v2_qa_a05, 2026 Q2, qoq +0.62, jt=3) and models.stress (v2_umidas_a20, 2026 Q3, qoq +0.35, jt=1) side by side under one top-level target_quarter (= headline's Q2) and one as_of. The quarter split is not a design decision: it is an artifact of selection-dependent ragged edges. At alpha=0.20 the stress selection includes wmi_sent (publication lag -15d, the only series with July data at as_of 2026-07-27), so build_mai's trailing-trim (build_mai.R:198-213 keeps months with >=1 SELECTED obs) extends the a20 MAI to 2026-07 and nowcast_midas targets Q3 with 1 month; the a05 headline's labour/financial-only selection ends at 2026-06 so it targets Q2 with 3 months. Nothing in the JSON or the emit code flags that the two numbers answer different questions.

**Evidence.** Verified in /Users/James/Documents/Claude/Projects/nowcasting/data/latest_v2.json: headline target '2026 Q2' jt=3, stress target '2026 Q3' jt=1, top-level target_quarter '2026 Q2'. emit_v2_json.R:152-154 builds both from the same tfs_m/gdp_m with only sel_alpha/model differing; nowcast_midas.R:93-104 derives target purely from MAI reach; .LAG_ACC (emit_v2_json.R:46-53) shows wmi_sent=-15 is the only series available for July at 2026-07-27.

**Failure scenario.** A reader compares headline +0.62 vs stress +0.35 as two views of the same quarter and infers 'the stress model sees weaker Q2 growth', when the stress number is a 1-month M1-style nowcast of a quarter that has barely begun. Worse, the paper's own Table 3 shows M1-timing nowcasts of a fresh quarter and complete-quarter QA nowcasts have very different error profiles, so even the qualitative comparison is invalid. The split also flips silently: any week wmi_sent's edge advances, the stress jumps a quarter while the headline stays put.

**Survived refutation because.** Verified directly in data/latest_v2.json: headline v2_qa_a05 target '2026 Q2' jt=3, stress v2_umidas_a20 target '2026 Q3' jt=1, both at as_of 2026-07-27, under one top-level target_quarter='2026 Q2'. Confirmed the mechanism arithmetically: .LAG_ACC gives wmi_sent lag -15, so July (ref_end Jul-31 minus 15 = Jul-16) is the ONLY series observable at Jul-27 — data_raw/wmi_sent.csv indeed ends 2026-07-01 while anz_sent (lag +10) is masked — and build_mai's trailing trim (lines 208-213) keeps a month with >=1 SELECTED observation, so the a20 MAI reaches July and nowcast_midas.R:96-104 takes the target from the MAI edge. NowcastHeadline.tsx presents both behind a Main/Volatility toggle with the same 'growth this quarter' framing. Could not refute.


#### 🟠 high · Stress yoy_growth_pct chains the WRONG quarters when stress targets Q3 (skips Q2-2026)

`nowcasting_v2/R/emit_v2_json.R:83` · correctness · finder confidence: high

**Claim.** .compute_yoy takes the last 3 released QoQ growths plus the nowcast. Released GDP at as_of 2026-07-27 ends 2026 Q1, so last3 = (2025Q3, 2025Q4, 2026Q1). For the headline (target 2026 Q2) the chain is correct. For the stress (target 2026 Q3) the published yoy 1.89 = chain of 2025Q3, 2025Q4, 2026Q1, 2026Q3-nowcast — it omits 2026 Q2 entirely and wrongly includes 2025 Q3, so it is not the year-ended growth of any quarter.

**Evidence.** emit_v2_json.R:83-87 '.compute_yoy <- function(gdp, nowcast_qoq) { ... last3 <- tail(g$value, 3L); (prod(1 + c(last3, nowcast_qoq)/100) - 1)*100 }' called at line 130 with gdpt (truncated to Q1 2026) for BOTH models; latest_v2.json stress yoy_growth_pct = 1.89 with target_quarter '2026 Q3'.

**Failure scenario.** Published stress yoy for 2026 Q3 is mechanically wrong whenever the two models' target quarters diverge (the current production state): correct Q3 yoy needs growths Q4-25..Q3-26 including a Q2 estimate; the emitted 1.89 chains Q3-25..Q1-26 + Q3-26 and would remain wrong even if every input were perfect.

**Survived refutation because.** Verified: emit_v2_json.R:83-87 takes tail(g$value, 3) unconditionally and line 130 applies it to both models with the same gdpt (truncated to 2026 Q1). With the stress targeting 2026 Q3, the published 1.89 chains 2025Q3+2025Q4+2026Q1+Q3-nowcast, omitting 2026 Q2 and wrongly including 2025 Q3. NowcastHeadline.tsx renders yoy_growth_pct as 'vs a year ago', so it is on the page in Volatility mode. Could not refute.


#### 🟠 high · Stress level nowcast and CI level-bands anchor on Q1's level though the quarter before its Q3 target is Q2

`nowcasting_v2/R/emit_v2_json.R:123` · correctness · finder confidence: high

**Claim.** nowcast_midas documents prev_level as 'the released GDP chain-volume LEVEL of the quarter immediately BEFORE the target quarter' (nowcast_midas.R:63-65) and computes nowcast_level = prev_level*(1+g/100) (lines 226-230). emit_v2_json passes the SAME prev_level (2026 Q1 realized, 695945) to both mk() calls (line 123), but the stress targets 2026 Q3, whose preceding quarter is the unreleased Q2. The emitted stress gdp_chain_volume_millions = 698386 = Q1_level x (1+Q3 growth), skipping Q2 growth compounding entirely; ci_level_band (line 126-127) inherits the same wrong anchor for the stress 68/95 level bands.

**Evidence.** latest_v2.json: prev_level {value 695945, date '2026 Q1'}; stress level 698386 = 695945*1.0035 (matches qoq 0.35 exactly, no Q2 term); headline 700225 = 695945*1.00615. emit_v2_json.R:108-113 resolves prev_level once from latest.json latest_actual; mk() at 117-134 applies it regardless of nc$target_quarter.

**Failure scenario.** With headline Q2 growth +0.62, a consistent Q3 stress level would be about 695945*1.0062*1.0035 ~ 702700, i.e. the published stress level is ~4300 $m too low (about 0.6%), and its CI band is shifted by the same amount — the stress box understates the level by the whole missing quarter of growth every time the targets diverge.

**Survived refutation because.** Verified arithmetically against the live artifact: prev_level = 695945 ('2026 Q1'), stress gdp_chain_volume_millions = 698386 = 695945 x 1.0035, i.e. Q1 level x Q3 growth with no Q2 compounding. emit_v2_json.R resolves prev_level once (lines 107-113) and passes it to both mk() calls (line 123) regardless of nc$target_quarter, and lines 126-127 feed the same anchor to ci_level_band. nowcast_midas.R:63-65 documents prev_level as the quarter immediately BEFORE the target. Partial refutation: the level is not rendered on the page (NowcastHeadline's growthRange divides ci_68 by the same prevLevel, so the displayed growth band is self-consistent) — but the JSON field and the CI level bands are wrong. Upheld.


#### 🟠 high · Headline QA nowcast feeds PARTIAL-quarter MAI means; paper's QA model is full-quarter only

`nowcasting_v2/R/nowcast_midas.R:181` · fidelity · finder confidence: high

**Claim.** In the paper, the QA model's nowcast regressor is always the COMPLETE 3-month quarter average: in Recursive_Nowcast_GDP_UMIDAS_TP.R the QA block (lines 226-233) runs after the jt loop ends at jt=3, so nxm <- mean(x_new) averages all three target-quarter months; the paper (p.19) describes QA as 'a temporal aggregated value of the MAI for the current quarter ... making it similar to M3'. Partial within-quarter information is handled in the paper only via the U-MIDAS M1/M2 lag-shift (k=(3-jt):5), never via a partial mean. v2's headline QA instead sets nxm <- mean(target_months$value) over whatever 1-3 months exist at that Monday, feeding a 1- or 2-month average into a regression estimated exclusively on full 3-month averages (xm_est <- rowMeans(mls(x_est, k=0:2, m=3))).

**Evidence.** nowcast_midas.R:181-182 'if (jt >= 1L) { nxm <- mean(target_months$value, na.rm = TRUE) }' vs paper Recursive_Nowcast_GDP_UMIDAS_TP.R:229 'nxm <- mean(x_new, na.rm = TRUE)' where x_new at that point is the jt=3 vector (loop 207-223 finished). data/vintages_v2.json confirms partial-quarter headlines were published: 2026-06-01 (Q2 target, MAI through April => jt=1, qoq +0.38) and 2026-06-08 vintages predate any complete Q2 month-set.

**Failure scenario.** Whenever the MAI trends within the quarter, the partial mean is a biased proxy for the full-quarter average the coefficients expect. E.g. a 2020Q2-style profile (April -4, May -2, June 0): at jt=1 the QA regressor is -4 versus the true quarter average -2, so the published nowcast overshoots by roughly beta1*2pp. The paper never evaluated this estimator; v2's own RMSE/CI evidence doesn't cover it either (the quarter-end backtest always sees jt=2, see separate CI finding), yet it is the published headline for the first half of every quarter.

**Survived refutation because.** Verified against the paper's source, which is the strongest form of this claim. In Recursive_Nowcast_GDP_UMIDAS_TP.R the QA block ('Quarter-average MAI model') sits AFTER the `for (jt in 0L:mt)` U-MIDAS loop closes, so when it executes `nxm <- mean(x_new, na.rm = TRUE)`, x_new is the vector left over from the final iteration jt = mt = 3 — the complete 3-month quarter. Partial within-quarter information is handled solely by the U-MIDAS lag shift k = (k1-jt):k2. v2's nowcast_midas.R:181-182 instead sets `nxm <- mean(target_months$value, na.rm = TRUE)` over whatever 1-3 months exist, while the coefficients come from `xm_est <- rowMeans(mls(x_est, k = 0:2, m = 3))`, i.e. full 3-month averages only. data/latest_v2.json confirms partial-quarter headlines were published (2026-06-01 vintage, Q2 target, qoq +0.38). This is a divergence in how the engine is driven, not a panel choice. Could not refute. High stands.


<details>
<summary>6 medium/low findings</summary>

| sev | finding | location | category | labour |
|---|---|---|---|---|
| 🟡 medium | data_through in latest_v2.json/vintages overstates what fed the headline model | `nowcasting_v2/R/emit_v2_json.R:148` | data-contract | yes |
| 🟡 medium | MIDAS estimation window floats with panel/selection instead of the paper's fixed sample start | `nowcasting_v2/R/nowcast_midas.R:121` | fidelity | yes |
| 🟡 medium | CI bands calibrated only at quarter-end as-ofs (fixed jt) but applied to every Monday with jt 0..3 | `nowcasting_v2/R/recalib_ci_v2.R:15` | ci-reliability |  |
| ⚪ low | jt=0 QA fallback (random-walk quarter-average substitution) is an unbacktested spec the paper never uses | `nowcasting_v2/R/nowcast_midas.R:184` | fidelity |  |
| ⚪ low | Misleading comment in U-MIDAS jt=0 branch claims RW extrapolation that the code (correctly) does not do | `nowcasting_v2/R/nowcast_midas.R:205` | stale-doc |  |
| ⚪ low | nowcast_midas as_of trims GDP by label date, not release date — latent look-ahead for direct callers | `nowcasting_v2/R/nowcast_midas.R:87` | real-time-leak |  |

</details>

### W5 — Evaluation & uncertainty  (8 findings)

<details>
<summary>8 medium/low findings</summary>

| sev | finding | location | category | labour |
|---|---|---|---|---|
| 🟡 medium | Point/band split: published point is the biased element by the model's own calibration (extends known finding) | `pipeline/ci_bands.R:18` | correctness | yes |
| 🟡 medium | CI bands calibrated on the same post-2022 window the model spec was selected on | `pipeline/compute_ci_params.R:17` | ci-reliability | yes |
| 🟡 medium | Stress-model bias correction (0.11pp, n=17) is statistically indistinguishable from zero | `pipeline/seed/ci_params_v2_umidas.json:1` | ci-reliability |  |
| ⚪ low | Backtest GDP release lag fixed at 60d vs actual ABS ~63-70d schedule | `nowcasting_v2/R/backtest_v2.R:112` | real-time-leak |  |
| ⚪ low | bias_correction_analysis.R header contradicts its own code on which errors are usable | `nowcasting_v2/R/bias_correction_analysis.R:11` | stale-doc |  |
| ⚪ low | Dead constant REALISED_Q1_QOQ and hardcoded '2026 Q1' will silently go stale | `nowcasting_v2/R/bias_correction_analysis.R:26` | stale-doc |  |
| ⚪ low | Parity gate gates nothing: results gitignored, never run in CI, no failure exit code | `nowcasting_v2/R/check_replication_parity.R:177` | ci-reliability |  |
| ⚪ low | ci_bands.R documents sd = sqrt(rmse^2 - bias^2) but code uses sample sd(n-1) | `pipeline/ci_bands.R:8` | stale-doc |  |

</details>

## Track 2 — bugs

### CI & data contract  (13 findings)

#### 🔴 critical · Stress model nowcasts a DIFFERENT quarter than the headline but is anchored to the headline's prev_level

`nowcasting_v2/R/emit_v2_json.R:123` · correctness · finder confidence: high

**Claim.** mk() passes the same `prev_level` (the level of the quarter before the HEADLINE target) and the same `.compute_yoy(gdpt, qoq)` base to both models, but nowcast_midas independently derives each model's target quarter from its own MAI end month. Since 2026-07-20 the alpha=0.20 stress panel's MAI reaches one month further than the alpha=0.05 headline panel, so the stress model targets 2026 Q3 while the headline targets 2026 Q2. Its published level and YoY are therefore computed off the wrong base quarter. Nothing asserts prev_level.date == target_quarter - 1.

**Evidence.** emit_v2_json.R:112-123 `prev_level <- pl$level` (single value, from latest.json latest_actual = 2026 Q1) then `nc <- nowcast_midas(mai, gdpt, prev_level = prev_level, ...)`; nowcast_midas.R:225 `nowcast_level <- prev_level * (1 + qoq_growth/100)`. emit_v2_json.R:130 `yoy_growth_pct = round(.compute_yoy(gdpt, qoq), 2)` where .compute_yoy (l.83-87) uses `tail(g$value, 3)` — the last 3 released QoQ growths, i.e. through 2026 Q1. data/latest_v2.json: prev_level = {value: 695945, date: "2026 Q1"}; models.headline.target_quarter = "2026 Q2"; models.stress.target_quarter = "2026 Q3", gdp_chain_volume_millions = 698386 = 695945*(1+0.003507), yoy_growth_pct = 1.89 = (1.00382*1.00873*1.00274*1.003507-1)*100 — the 4-quarter growth ending 2026 Q2. Git history confirms the divergence began at commit 7066b4d (as_of 2026-07-20) and persists at 1ed1c80 (2026-07-27); before that both models shared a target.

**Failure scenario.** Today's live site: clicking the "Volatility model" toggle shows a card labelled 2026 Q3 whose level is $698,386m (the 2026 Q1 level grown ONE quarter, not two — understated by roughly a full quarter of growth, ~$4bn) and whose "vs a year ago" figure of +1.89% is the year-ended growth to Q2, not Q3. The 68%/95% level bands (ci_level_band(qoq, prev_level, ...), l.126-127) are built on the same wrong base, so every dollar figure on that card is off by one quarter. No guard fires; the run exits 0 and commits.

**Survived refutation because.** Confirmed in the live artifact, not just in code. data/latest_v2.json: prev_level = {value: 695945, date: "2026 Q1"}; models.headline.target_quarter = "2026 Q2" (n_months_in_quarter 3); models.stress.target_quarter = "2026 Q3" (n_months_in_quarter 1); stress gdp_chain_volume_millions = 698386 = 695945 * (1+0.0035). emit_v2_json.R:113 binds a single prev_level before mk(); mk() passes it to both models and nowcast_midas.R:225 applies it as prev_level*(1+qoq/100) regardless of which quarter nowcast_midas independently selected. .compute_yoy(gdpt, qoq) at emit_v2_json.R:130 uses tail(g$value,3) — the last three RELEASED QoQ growths (through 2026 Q1) — so the stress card's 1.89% is the year-ended growth to Q2, not Q3. ci_level_band is built on the same prev_level. Nothing asserts prev_level.date == target_quarter - 1. I could not refute any step. Critical stands.


#### 🟠 high · Methodology text on the live site misdescribes the panel: '~30 series' and 'both fit on the same panel'

`src/components/MethodologyPanel.tsx:45` · stale-doc · finder confidence: high  · **bears on labour concentration**

**Claim.** The reader-facing methodology claims the MAI factor is extracted from ~30 series spanning labour, spending, trade, credit, financial markets and surveys, and that the Main and Volatility estimates are fit on the same panel differing only in weighting. Both are false for what the pipeline actually runs: targeted-predictor selection reduces 31 candidates to 11 for the headline and 18 for the stress model, the two use different MIDAS specifications (qa vs umidas), and the resulting factor's loadings are 65.8% on three labour series with 0.3% on the entire survey block.

**Evidence.** MethodologyPanel.tsx:33-38 "a single monthly activity factor extracted by a dynamic factor model from roughly 30 monthly series spanning labour, household spending, trade, credit, financial markets, and business and consumer surveys"; l.42-46 "Both are fit on the same panel and differ only in that weighting." Against emit_v2_json.R:152-154: `qa <- mk(tfs_m, gdp_m, "v2_qa_a05", ..., 0.05, "qa", CI_QA)` and `stress <- mk(tfs_m, gdp_m, "v2_umidas_a20", ..., 0.20, "umidas", CI_UMIDAS)` — different sel_alpha (so different selected panels) and different model. emit_v2_json.R:120 `build_mai(tfs = tfs, sel_alpha = sel_alpha, dfm_q = 1L, exclude_ids = c(AIG, "rt"), ...)` — the DFM is fitted on the SELECTED subset, not the 31-series pool.

**Failure scenario.** A reader opens Methodology on the live dashboard today. They are told the +0.62% figure comes from a factor over ~30 series across six domains, and that the +0.35% 'Volatility model' figure differs only in time weighting. In fact the headline factor is built from 11 series with 65.8% of its loading weight on ft_emp/ud/ue and 0.3% on all surveys combined, and the volatility figure comes from a different selection (18 series), a different regression, and — currently — a different target quarter. The stated provenance of the published number is wrong.

> **Editor's note (2026-08-02).** This finding is upheld — the Methodology copy is wrong and
> still needs correcting. But two of the numbers it cites in support are not reliable. The
> "65.8% of loading weight" figure is a `DFM2` normalisation artefact and is retracted (see
> the corrections log at the top of this document). The series counts have also moved under
> the fidelity fixes: the headline now selects **10** and the stress model **16**, not 11 and
> 18. The *substance* — "~30 series" and "both fit on the same panel" are both false — is
> unaffected, and the two models no longer differ in target quarter.

**Survived refutation because.** Verified both claims against the code. build_mai.R:215-231 fits qmle_dfm on Ysel = Xm_full[, selected], i.e. the DFM is estimated on the SELECTED subset, not the ~31-series pool — so 'extracted by a dynamic factor model from roughly 30 monthly series' (MethodologyPanel.tsx:34-39) describes the candidate pool as if it were the estimated model. emit_v2_json.R:152 and :154 pass sel_alpha 0.05/model 'qa' vs sel_alpha 0.20/model 'umidas', so the two published estimates use different selected panels AND different regressions, falsifying 'Both are fit on the same panel and differ only in that weighting' (:44-45). Confirmed the panel ships (grep 'Monthly Activity Indicator' out/index.html = 1). Raised to high: this is the reader-facing provenance of the published headline number and it is false in two independent respects.


<details>
<summary>11 medium/low findings</summary>

| sev | finding | location | category | labour |
|---|---|---|---|---|
| 🟡 medium | No recency guard on the v2 survey inputs; the only NAB check tests history length, not freshness | `nowcasting_v2/R/emit_v2_json.R:98` | correctness | yes |
| 🟡 medium | GDP release date is a hardcoded first-Wednesday rule, duplicated in the workflow gate and never reconciled with the scraped ABS calendar | `pipeline/04_emit_json.R:128` | correctness |  |
| 🟡 medium | latest.json pairs latest_actual.quarter/qoq from one source with the level from another, and v2 consumes that level as its anchor | `pipeline/04_emit_json.R:291` | data-contract |  |
| 🟡 medium | StalenessBanner is evaluated at build time on a statically exported site, so it can never fire when the pipeline stops | `src/components/StalenessBanner.tsx:13` | correctness |  |
| 🟡 medium | Nowcast-evolution chart is filtered on the v2 target quarter but captioned with the v1 one | `src/components/VintageChart.tsx:112` | correctness |  |
| 🟡 medium | Every v2 artifact silently falls back to a v1 artifact when its JSON is unreadable | `src/lib/data.ts:31` | data-contract |  |
| ⚪ low | deploy.yml never runs the vitest suite, so the data-contract unit tests are dead in CI | `.github/workflows/deploy.yml:48` | ci-reliability |  |
| ⚪ low | Pre-GDP-release gate cron cannot fire when the first Wednesday of the release month is the 1st | `.github/workflows/nowcast-weekly.yml:11` | ci-reliability |  |
| ⚪ low | The pre-GDP-release run produces no new v2 number: as_of snaps back to the preceding Monday | `nowcasting_v2/R/emit_v2_json.R:79` | correctness |  |
| ⚪ low | data_through is computed over the full 35-series panel including model-excluded series, and is a single value for two models with different MAI end months | `nowcasting_v2/R/emit_v2_json.R:149` | data-contract |  |
| ⚪ low | VintageChart's fixed x-domain silently drops vintages outside [-95, 5] days | `src/components/VintageChart.tsx:123` | correctness |  |

</details>

### v2 R code  (16 findings)

#### 🔴 critical · Target quarter is the LAST MAI quarter, not the first unreleased one - skips a whole quarter

`nowcasting_v2/R/nowcast_midas.R:98` · correctness · finder confidence: high

**Claim.** The stated contract (line 14, line 93) is "target quarter = first quarter that has MAI data but no released GDP". The implementation instead sets target_q <- last_mai_q whenever the MAI reaches beyond the last released GDP quarter. Once the MAI edge crosses into a new quarter while the previous quarter's GDP is still unreleased, the model abandons the completed-but-unreleased quarter and jumps forward, publishing a nowcast for a quarter that has only 1 month of data.

**Evidence.** nowcast_midas.R:94-104:
  last_gdp_q <- max(y$date)
  last_mai_q <- .quarter_label(max(m$date))
  if (last_mai_q <= last_gdp_q) { target_q <- seq(last_gdp_q, by="3 months", length.out=2L)[2L] } else { target_q <- last_mai_q }
.quarter_label (line 41-46) maps 2026-07-01 -> 2026-09-01 (Q3).
Production state (data/latest_v2.json): as_of 2026-07-27, target "2026 Q2", n_months_in_quarter 3, gdp_full max = 2026-03-01 (data_raw/rt_dgdp_qtr.csv tail). Q2 2026 GDP releases ~2026-09-02.
emit_v2_json.R:46-54 gives scrigbag3/5/10 and firmmbab90 a 2-day publication lag; .truncate_acc (line 57-67) therefore admits the July RBA yields on any as_of >= 2026-08-02. build_mai.R:208-213 only trims trailing months where NO selected series is observed, so one observed selected series keeps July.

**Failure scenario.** On the Monday cron of 2026-08-03 (or 2026-08-10 at the latest, once the RBA publishes July F1.1/F2.1): MAI extends to 2026-07 -> last_mai_q = 2026-09-01 (Q3) > last_gdp_q = 2026-03-01 (Q1) -> target_q = 2026 Q3 with jt = 1. The live site's headline flips from "2026 Q2" to "2026 Q3" roughly four weeks BEFORE Q2's actual release, Q2 is never nowcast again, and the final-vintage Q2 backcast used for track-record scoring never exists.

**Survived refutation because.** Verified in code AND confirmed already occurring in production. nowcast_midas.R:94-104: `if (last_mai_q <= last_gdp_q) { target_q <- last_gdp_q + 3 months } else { target_q <- last_mai_q }` — the else branch jumps to the MAI's own quarter, contradicting the stated contract at :14 and :93. Live proof: at as_of 2026-07-27, gdp_full max is 2026-03-01 (Q1) and Q1 clears .truncate_gdp (03-31 + 60 = 05-30 <= 07-27), so last_gdp_q = Q1; the alpha=0.20 stress MAI reaches 2026-07, .quarter_label maps that to 2026-09-01 = Q3 > Q1, and data/latest_v2.json duly shows models.stress.target_quarter = "2026 Q3" with n_months_in_quarter = 1 — Q2 skipped entirely, ~5 weeks before Q2's release. The headline will follow as soon as one selected series carries July (RBA yields/spreads have .LAG_ACC = 2, so any as_of >= 2026-08-02), and build_mai.R:208-213 only trims trailing months where NO selected series is observed. Could not refute. Critical stands. Related to but distinct from the prev_level finding: fixing prev_level per model would not stop Q2 from being abandoned.


#### 🟠 high · D2 credit series spliced across the 2019-07 definitional break with no level adjustment - 5 to 7 sigma artificial outliers

`nowcasting_v2/R/fetch/fetch_rba_panel.R:148` · fidelity · finder confidence: high  · **bears on labour concentration**

**Claim.** .splice_d2() stitches the 'excluding financial businesses' column (ends 2019-06) directly onto the 'including select financial businesses' column (starts 2019-07) without any level or ratio adjustment. credit_housing is not spliced at all but the underlying DLCACOHN/DLCACIHN columns are internally reclassified at the same date. All three series are tcode=t2 + tlog=TRUE, so the definitional level step becomes a single enormous log-difference.

**Evidence.** fetch_rba_panel.R:148-152:
  .splice_d2 <- function(p, old_id, new_id, break_date = as.Date("2019-07-01")) { old <- parse_rba_csv(p, old_id) |> filter(date < break_date); new <- parse_rba_csv(p, new_id) |> filter(date >= break_date); bind_rows(old, new) ... }
fetch_credit_housing (line 159-167) has no splice at all.
From tests/fixtures/rba_d2.csv: DLCACN ends 30/06/2019 = 2944.3; DLCACSFN starts 31/07/2019 = 2870.0. DLCACBN 961.5 -> DLCACSFBN 909.4. DLCACOHN 1240.6 -> 1122.7 and DLCACIHN 595.8 -> 667.7 (sum 1836.4 -> 1790.4).
Measured log-differences at 2019-07 vs each series' own full-sample distribution:
  credit          -0.02556  (z = -5.42)
  credit_business -0.05571  (z = -5.83)
  credit_housing  -0.02537  (z = -6.70)
Full-sample sd inflation from this single point: 2.5% / 2.9% / 5.5%.

**Failure scenario.** transform_panel.R:70 applies transform_series(tcode="t2", take_log=TRUE) and line 104 divides by the full-sample sd. The 2019-07 observation of credit_housing (a production-selected series, 1.1% of index weight) enters the DFM as a -6.7 sigma common shock, producing a spurious MAI trough in 2019-07; the same point enters the 2019 Q3 row of the build_mai.R:162 lm_hac Wald regression, distorting the selection statistic for credit, credit_business and credit_housing; and the inflated sd shrinks every other month of those series, systematically understating their true signal relative to the unbroken labour series.

**Survived refutation because.** Verified and strengthened. fetch_rba_panel.R:148-152 .splice_d2 does a raw bind_rows of the pre-break and post-break columns with no level or ratio adjustment; fetch_credit_housing (:159-167) sums DLCACOHN + DLCACIHN with no splice at all but those columns are reclassified at the same date. I recomputed from the committed CSVs: credit 2019-06 = 2944.3 -> 2019-07 = 2870.0 (log-diff -0.02556, z = -5.42 against the full-sample mean 0.00802 / sd 0.00619); credit_business 961.5 -> 909.4 (-0.05571, z = -5.83); credit_housing 1836.4 -> 1790.4 (-0.02537, z = -6.70). Decisive check against the paper: rba_paper/content/Data/mai_panel.csv shows credit 1/06/2019 = 2921.36 -> 1/07/2019 = 2928.52 and credit_housing 1784.47 -> 1788.33 — completely smooth. So the RBA's own input has no such break; this is v2's splice, and all three series are t2+tlog per mai_info.csv, so the break becomes one enormous log-difference feeding transform_panel's sd, the Wald regression and the DFM. Could not refute. High stands.


#### 🟠 high · fetch_nab_full overwrites the 348-month NAB history with a ~40-month fixture-derived stub

`nowcasting_v2/R/fetch/scrape_nab_full.R:304` · data-contract · finder confidence: medium  · **bears on labour concentration**

**Claim.** fetch_nab_full() rebuilds each nab_*.csv purely from the PDFs it can parse this run and write_csv's the result over the committed file. It never merges with the existing CSV and never checks for a length regression. data_raw/nab_conf.csv currently carries 348 monthly obs from 1997-03; the PDF sources documented in seed/panel_info.csv yield '39 obs 2023-02..2026-04'.

**Evidence.** scrape_nab_full.R:311-316:
  for (id in names(res$series)) { df <- res$series[[id]]; if (!is.null(df) && nrow(df) > 0) write_csv(df, file.path(dest_dir, paste0(id, ".csv"))) }
assemble_nab_full() (line 216-301) builds `series` only from monthly_paths/quarterly_paths parsed this run; there is no read of the existing CSV.
Actual: `head -2 data_raw/nab_conf.csv` -> 1997-03-01,9.0 ; 348 data rows.
seed/panel_info.csv nab_conf note: "39 obs 2023-02..2026-04, no gaps."
Only nab_conf has a downstream tripwire (emit_v2_json.R:97-99, nab_n < 120L). nab_cond/nab_trade/nab_profit/nab_emp/nab_forward/nab_stocks/nab_cu have none.

**Failure scenario.** Running Rscript R/fetch/scrape_nab_full.R (or the local Cowork refresh invoking it) truncates all eight nab_*.csv to the fixture span and the CI's `git add nowcasting_v2/data_raw/` commits the loss. emit_v2_json halts on the nab_conf guard - but only after the other seven series are already destroyed in the repo, and if the guard is ever relaxed the panel silently loses 25 years of survey history, changing transform_panel's standardisation and the Wald selection for the entire survey block.

**Survived refutation because.** Verified. scrape_nab_full.R fetch_nab_full builds `res$series` purely from assemble_nab_full() over the fixture/live PDFs parsed this run — I read assemble_nab_full end to end and there is no read of the existing CSV, no merge, and no length-regression check — then writes each non-empty tibble straight over data_raw/<id>.csv. The script auto-runs under `if (sys.nframe() == 0 && !interactive())`. Current state confirms the loss would be real: data_raw/nab_conf.csv has 348 rows spanning 1997-03..2026-06, while seed/panel_info.csv records the PDF-derived span as '39 obs 2023-02..2026-04'. Only nab_conf has a downstream tripwire (emit_v2_json.R:97-99, nab_n < 120L); nab_cond/nab_trade/nab_profit/nab_emp/nab_forward/nab_stocks/nab_cu have none, and CI's `git add nowcasting_v2/data_raw/` would commit the truncation. Could not refute. High stands.


<details>
<summary>13 medium/low findings</summary>

| sev | finding | location | category | labour |
|---|---|---|---|---|
| 🟡 medium | backtest_v2_monthly computes its fixed selection from the hardcoded default panel, not panel_rds | `nowcasting_v2/R/backtest_v2_monthly.R:142` | correctness |  |
| 🟡 medium | ANZ/Roy Morgan scrapers never signal failure - a blocked scrape silently reuses last week's CSV | `nowcasting_v2/R/fetch/scrape_anz_ivi.R:315` | ci-reliability |  |
| ⚪ low | _setup.R silently no-ops when no candidate library path exists | `nowcasting_v2/R/_setup.R:6` | ci-reliability |  |
| ⚪ low | Bias-correction 'real-time' errors are computed against latest-vintage GDP | `nowcasting_v2/R/bias_correction_analysis.R:51` | fidelity |  |
| ⚪ low | MAI factor sign is flipped but the loadings saved alongside it are not | `nowcasting_v2/R/build_mai.R:236` | correctness |  |
| ⚪ low | Series that fail the Wald regression are silently dropped from candidacy | `nowcasting_v2/R/build_mai.R:160` | correctness | yes |
| ⚪ low | build_panel has no staleness or length-regression guard - only an all-NA check | `nowcasting_v2/R/build_panel.R:73` | data-contract | yes |
| ⚪ low | .mondays_to_date can return a Monday in the future, stamping the JSON with a future vintage | `nowcasting_v2/R/emit_v2_json.R:72` | correctness |  |
| ⚪ low | Roy Morgan month columns read by position with no header validation | `nowcasting_v2/R/fetch/scrape_anz_ivi.R:194` | fidelity |  |
| ⚪ low | anz_ads month-on-month cross-check compares across gaps and drops valid rows | `nowcasting_v2/R/fetch/scrape_anz_ivi.R:99` | correctness |  |
| ⚪ low | parse_ivi is a stub that always returns zero rows; panel_info records the wrong reason | `nowcasting_v2/R/fetch/scrape_anz_ivi.R:275` | stale-doc |  |
| ⚪ low | tier1_coverage_report computes recency but only hard-fails on empty CSVs | `nowcasting_v2/R/fetch/tier1_coverage_report.R:74` | ci-reliability | yes |
| ⚪ low | spec_sweep hardcodes a production reference RMSE that no longer regenerates | `nowcasting_v2/R/spec_sweep.R:39` | stale-doc |  |

</details>

### Python  (24 findings)

#### 🔴 critical · NAB Tier-1 parse appends a value with ZERO overlap months — self-check silently skipped

`nowcasting_v2/scrapers/nab_monthly.py:216` · correctness · finder confidence: high

**Claim.** `_validate_and_append` blocks a series only when `gross` (a mismatch on an OVERLAP month) is non-empty. If a series parses only the newest column — which happens in practice when the older columns' glyphs bleed into the label band — `overlaps` is empty, so `mism`/`gross` are empty, the block is skipped, and the un-validated value is appended. The module docstring's 'PRIME DIRECTIVE / never guess' guarantee ('the columns that overlap the existing CSV must match') does not hold in exactly the case that matters: a brand-new month on a partially-parsed row. Note `verify()` (Tier 2) DOES enforce an overlap requirement (lines 311-318); Tier 1 `parse` does not.

**Evidence.** nab_monthly.py:216-231: `overlaps = sorted([d for d in parsed_months if d in have])` / `mism = [...for d in overlaps...]` / `gross = [...]` / `if gross: ... continue` / `new = sorted([d for d in parsed_months if d > last_date])`. No `if not overlaps:` guard. Proven partial-parse mode, run 2026-08-01 against the repo's own fixture: `parse_table1('tests/fixtures/nab/nab_monthly_2023_07.pdf')` returns `nab_conf {'2023-07-01': 40}` (ONE column only; sibling rows returned all three), `nab_trade {'2023-07-01': 20}`, `nab_forward {'2023-07-01': 0}`. Truth in data_raw: nab_conf.csv `2023-07-01,2.0`; nab_trade.csv `2023-07-01,18`; nab_forward.csv `2023-07-01,-1`. Range check NETBAL_RANGE=(-70,70) passes 40.

**Failure scenario.** NAB publishes the Aug-2026 monthly PDF with the same rotated-glyph layout as tests/fixtures/nab/nab_monthly_2023_07.pdf. data_raw/nab_conf.csv ends 2026-07-01. Operator runs `python scrapers/nab_monthly.py parse <url> --data-raw data_raw --write` (the default subcommand). parse_table1 returns {'nab_conf': {'2026-08-01': 40}} — newest column only. In _validate_and_append: parsed_months={'2026-08-01':40} passes the -70..70 range check; overlaps=[] so mism=[] and gross=[]; new=['2026-08-01'] -> the row `2026-08-01,40` is appended to nab_conf.csv. True value ~2. The report prints 'Appended: nab_conf [(2026-08-01, 40)]' with an empty self-check and NO block. The v2 panel then ingests NAB Business Confidence = +40 (a 38-point fabricated swing) for Aug 2026, feeding the live nowcast.

**Survived refutation because.** Verified, including reproducing the partial-parse mode myself. nab_monthly.py _validate_and_append: `overlaps = sorted([d for d in parsed_months if d in have])`, `mism` and `gross` are derived only from overlaps, `if gross: ... continue` is the only block, then `new = sorted([d for d in parsed_months if d > last_date])` appends. There is no `if not overlaps:` guard — and verify() DOES have one ('require an overlap month so the read can be validated, not blindly trusted'), which proves the omission in the Tier-1 path is an inconsistency, not a design. I ran parse_table1('tests/fixtures/nab/nab_monthly_2023_07.pdf') read-only: columns are May-23/Jun-23/Jul-23, but nab_conf returns only {'2023-07-01': 40}, nab_trade only {'2023-07-01': 20}, nab_forward only {'2023-07-01': 0}, while sibling rows return all three columns. Truth in data_raw: nab_conf 2023-07-01 = 2.0, nab_trade = 18, nab_forward = -1. On that fixture the wrong value is caught only because 2023-07 is already in the CSV; on a genuinely new month it would be appended unchecked, and 40 passes NETBAL_RANGE (-70, 70). Could not refute. Critical stands.


#### 🟠 high · v2 step is continue-on-error but the commit/deploy step is if: success() — partial v2 output ships

`.github/workflows/nowcast-weekly.yml:179` · ci-reliability · finder confidence: high

**Claim.** The v2 step (line 123-146) chains emit_v2_json.R -> gen_indicators_v2.py -> gen_performance_v2.py under `continue-on-error: true`. A failure partway through aborts the remaining commands (bash -eo pipefail) but leaves `success()` true for later steps, so the 'Commit updated JSON' step (line 179, `if: success()`) commits and deploys whatever mixture of new and stale files exists.

**Evidence.** .github/workflows/nowcast-weekly.yml:123-125 (`id: v2` / `if: success()` / `continue-on-error: true`), :137 `Rscript R/emit_v2_json.R`, :141 `python gen_indicators_v2.py`, :146 `python gen_performance_v2.py`, :177-179 `- name: Commit updated JSON and vintage index` / `if: success()`, :197 deploy `if: success() && steps.commit.outputs.changed == 'true'`. `continue-on-error: true` sets the step's outcome to failure but its conclusion to success, so `success()` remains true for downstream steps.

**Failure scenario.** On a Monday, emit_v2_json.R succeeds and writes data/latest_v2.json with the new headline (say 2026 Q2 = +0.62%) and a new vintage. gen_indicators_v2.py then raises — e.g. `read_raw` hits an empty value cell and `float('')` throws ValueError, or a data_raw CSV is absent so `open()` raises FileNotFoundError. The step aborts; gen_performance_v2.py never runs. The 'Alert on v2 failure' issue is opened, but the commit step still runs, stages `data/`, sees a diff (latest_v2.json changed), commits, pushes and triggers deploy.yml. The live site then renders a NEW headline nowcast next to LAST week's indicator grid — still carrying last week's `updated_this_run: true` teal dots labelled 'updated this week' and last week's values — plus a stale performance_v2.json. Nothing on the page indicates the mismatch.

**Survived refutation because.** Verified in .github/workflows/nowcast-weekly.yml: the v2 step (id: v2) carries `continue-on-error: true`, which sets outcome=failure but conclusion=success, so `success()` at the commit step remains true. The step body is a six-command bash script under the job default shell (bash -eo pipefail), so it aborts at the first failure with everything already written to data/ still on disk. emit_v2_json.R writes data/latest_v2.json and data/vintages_v2.json before gen_indicators_v2.py runs, and the commit step does `git add data/` unconditionally. I could find no guard: the only failure-aware step is 'Alert on v2 failure', which opens an issue but does not block the commit. Mechanism holds.


<details>
<summary>22 medium/low findings</summary>

| sev | finding | location | category | labour |
|---|---|---|---|---|
| 🟡 medium | Hours worked is labelled 'mn hours' but the value is in THOUSANDS of hours — a 1000x display error | `data/indicators_v2.json:1077` | data-contract | yes |
| 🟡 medium | next_release_estimate is computed from the stale data month and is in the past on the live site now | `nowcasting_v2/gen_indicators_v2.py:76` | correctness |  |
| 🟡 medium | _weekly_tuesday ignores the data month, so anz_sent always advertises fresh data from the wall clock | `nowcasting_v2/gen_indicators_v2.py:85` | correctness |  |
| 🟡 medium | A second run on the same day wipes every 'updated this week' marker and empties data_updates.series | `nowcasting_v2/gen_indicators_v2.py:205` | correctness |  |
| 🟡 medium | gen_performance_v2.py drops backcasts.json's 'not live nowcasts' disclosure and labels backtests 'final_nowcast' | `nowcasting_v2/gen_performance_v2.py:44` | fidelity | yes |
| 🟡 medium | NAB net-balance rows are mapped by position; a row that parses no numbers shifts every later series by one | `nowcasting_v2/scrapers/nab_monthly.py:166` | correctness |  |
| 🟡 medium | _num matches only ASCII hyphen; a typographic minus or parenthesised negative flips the sign | `nowcasting_v2/scrapers/nab_monthly.py:71` | correctness |  |
| 🟡 medium | test_nab_monthly.py passes with 0 series parsed — 6/10 fixtures already fail and it exits 0 | `nowcasting_v2/scrapers/test_nab_monthly.py:79` | test-coverage |  |
| 🟡 medium | test_nab_monthly.py validates against the live data_raw CSVs, so a bad appended value becomes its own expectation | `nowcasting_v2/scrapers/test_nab_monthly.py:14` | test-coverage |  |
| ⚪ low | No Python test runs in CI — all three test files are referenced only in a doc | `.github/workflows/nowcast-weekly.yml:141` | ci-reliability |  |
| ⚪ low | NAB capacity utilisation is labelled 'net balance' and rendered as an integer diffusion reading | `data/indicators_v2.json:5558` | data-contract |  |
| ⚪ low | latest_v2.json days_until_release is negative for future releases — sign inverted vs the field name | `data/latest_v2.json:1` | data-contract |  |
| ⚪ low | ABS release dates are copied from v1 without checking the two series are on the same reference month | `nowcasting_v2/gen_indicators_v2.py:229` | data-contract | yes |
| ⚪ low | Non-survey release dates only move when the data moves, so a stalled series freezes both dates in the past | `nowcasting_v2/gen_indicators_v2.py:221` | correctness |  |
| ⚪ low | latest_v2.json is truncated before the patch is written and any I/O error is swallowed with exit 0 | `nowcasting_v2/gen_indicators_v2.py:265` | correctness |  |
| ⚪ low | Regenerating indicators_v2.json converts integer values to floats and ratchets the stored precision | `nowcasting_v2/gen_indicators_v2.py:190` | data-contract |  |
| ⚪ low | Generator assumes data_raw CSVs are sorted ascending; an out-of-order row silently mislabels the latest period | `nowcasting_v2/gen_indicators_v2.py:199` | correctness |  |
| ⚪ low | gen_performance_v2.py assumes gdp.json is sorted, contiguous and duplicate-free with no assertion | `nowcasting_v2/gen_performance_v2.py:39` | correctness |  |
| ⚪ low | verify() accepts arbitrary date-key strings and can append a malformed date that later crashes the generator | `nowcasting_v2/scrapers/nab_monthly.py:307` | data-contract |  |
| ⚪ low | NAB _fetch downloads to a fixed /tmp path and `parse` with no subcommand raises AttributeError | `nowcasting_v2/scrapers/nab_monthly.py:344` | correctness |  |
| ⚪ low | _validate_and_append's docstring claims leftmost-column-only tolerance; the code applies one tolerance to all overlaps | `nowcasting_v2/scrapers/nab_monthly.py:193` | stale-doc |  |
| ⚪ low | scripts/fill-release-dates.mjs is superseded and its lag table has drifted from the R source it claims to mirror | `scripts/fill-release-dates.mjs:8` | stale-doc |  |

</details>

### v1 R pipeline  (26 findings)

#### 🟠 high · ABS fetch failures silently drop indicators; no count guard before the model runs

`pipeline/03_data_ingestion.R:218` · silent-failure · finder confidence: high  · **bears on labour concentration**

**Claim.** fetch_abs_indicator() swallows any fetch error into a warning and returns NULL (lines 81-85); fetch_all_abs_indicators() then just skips that indicator (`if (!is.null(data))` at line 218) with no assertion on the final count. run_complete_nowcast.R only prints the count (line 68) and never checks it equals 13. The FRED fetcher has exactly this guard (03b_fetch_fred_data.R:173-179) — the ABS path does not.

**Evidence.** 03_data_ingestion.R:81-85 `error = function(e) { warning(glue("Error fetching series {series_id}: {e$message}")); return(NULL) }`; :218 `if (!is.null(data)) {` ... `indicator_data[[ind$indicator_id]] <- data }` with no else; run_complete_nowcast.R:58 `abs_data <- fetch_all_abs_indicators(use_cache = FALSE)`; :68 `cat(sprintf("  Total indicators: %d\n", length(all_indicators)))`. Contrast 03b_fetch_fred_data.R:174 `if (length(fred_data) != expected) { stop(...) }`.

**Failure scenario.** ABS changes the time-series-directory URL for A84423043C (employment). read_abs_series() errors; fetch_abs_indicator returns NULL; employment is dropped. build_master_dataset produces a 12-column panel, estimate_dfm builds blocks/freq vectors from `ncol(ts_data_balanced)` so it estimates happily on 12 series, generate_nowcast returns a number, save_vintage writes n_indicators=12, and emit_json writes latest.json with a new headline QoQ. The site publishes a nowcast estimated without the single highest-weight input block, and nothing in the run exits non-zero, so the GitHub 'Alert on failure' step never fires. Only prepare_data_for_dfm's check on `gdp_quarterly` (05:28-30) would halt, and only if GDP itself were the series that failed.

**Survived refutation because.** Verified. 03_data_ingestion.R:81-85 swallows any fetch error into warning() + return(NULL); :218 is `if (!is.null(data)) { ... indicator_data[[ind$indicator_id]] <- data }` with no else and no post-loop assertion. I grepped run_complete_nowcast.R for any count check: line 68 only cat()s `length(all_indicators)`, and the only '13' in the file is a comment on line 7. The contrast is real — 03b_fetch_fred_data.R:173-179 does `expected <- nrow(fred_series); if (length(fred_data) != expected) stop(...)`. And 05_estimate_model.R sizes blocks/freq_vector from `ncol(ts_data_balanced)` at runtime, so a 12-series panel estimates without complaint. Severity lowered critical -> high: it needs an ABS-side failure to trigger, but when it does the run publishes a headline and exits 0 with no alert.


#### 🟠 high · latest.json / nowcasts.json `data_through` reports the run month, not the data reference month

`pipeline/04_emit_json.R:266` · data-contract · finder confidence: high

**Claim.** `data_through` is derived from `latest_vintage$data_as_of_date`, which save_vintage sets to `Sys.Date()` (the run date), not from the reference date of the newest observation. The fallback branch (line 273) correctly uses `max(master$wide$date)`, so the two branches disagree. Every vintage row in nowcasts.json has the same defect (line 428).

**Evidence.** 04_emit_json.R:266 `data_through_date <- as.Date(latest_vintage$data_as_of_date)`; :273 (fallback) `data_through_date <- max(master$wide$date, na.rm = TRUE)`; :368 `data_through = format(data_through_date, "%Y-%m")`; :428 `data_through = format(as.Date(data_as_of_date), "%Y-%m")`. 08_vintage_tracking.R:389 `data_as_of_date = as.Date(Sys.Date())`. Measured: data/latest.json says `"data_through": "2026-07"` for the 2026-07-27 run, but `max(master$wide$date)` in .cache/processed/master_dataset_wide.rds is 2026-06-01 and every series in data/indicators.json ends 2026-06 or earlier (services_exp/imp end 2026-03).

**Failure scenario.** A run on 2026-08-03 (first Monday) has newest data of June 2026 for labour and May 2026 for MHSI/trade. latest.json publishes `data_through: "2026-08"` — a month that has barely started and for which no series exists. nowcasts.json publishes `data_through: "2026-08"` on that vintage. Any consumer (the v2 page already renders this field for latest_v2) reads the model as two months more current than it is.

**Survived refutation because.** Verified against live data. 04_emit_json.R:266 sets `data_through_date <- as.Date(latest_vintage$data_as_of_date)` and 08_vintage_tracking.R writes `data_as_of_date = as.Date(Sys.Date())` — the run date. The fallback branch at :273 uses max(master$wide$date), so the two branches genuinely disagree, and :428 repeats the defect for every nowcasts.json row. Confirmed in the artifacts: data/latest.json reports data_through = "2026-07" for the 2026-07-27 run, while every series in data/indicators.json ends 2026-06 or earlier (household_spending 2026-05, services 2026-03). So it is wrong on the live site right now, not hypothetically. High stands.


#### 🟠 high · COVID mask is applied after Bpanel transformation, removing the 2020 collapse but keeping the rebound

`pipeline/05_estimate_model.R:277` · fidelity · finder confidence: medium  · **bears on labour concentration**

**Claim.** The Mar-Jul 2020 mask is applied to `ts_data_balanced` — the Bpanel OUTPUT, i.e. already-transformed data. With GDP on trans=7 (3-month % change) the quarterly growth observations land on Mar/Jun/Sep/Dec. Masking Mar-Jul removes Q1 2020 (-0.3%) and Q2 2020 (-7.0%) but leaves Q3 2020 (+3.4%) and Q4 2020 (+3.2%) in the estimation sample. The same asymmetry applies to the trans=1 monthly indicators: Apr-Jul employment collapse is masked, Aug/Sep rebound is not.

**Evidence.** 05:260-266 `ts_data_balanced <- Bpanel(base = ts_data, trans = trans_vec, ...)`; :276-280 `tt <- time(ts_data_balanced); covid_mask <- (floor(tt) == 2020) & (round((tt - 2020) * 12) + 1) %in% 3:7; ts_data_balanced[covid_mask, ] <- NA`. trans_vec from update_trans_codes.R:30 `"gdp_quarterly", 7, "3-mo %: quarterly level on monthly grid → QoQ % (target)"` and :26 `"employment", 1, "MoM %"`. The code comment at 05:270-272 claims the mask covers 'reopening rebound (Jun)' — under trans=7 the Jun 2020 GDP observation IS Q2's -7.0%, not the rebound; the rebound is the unmasked Sep observation.

**Failure scenario.** The DFM's GDP equation is fitted on a 2020 sample containing +3.4% and +3.2% quarters with no offsetting -7.0% quarter, paired with moderate positive Aug/Sep monthly indicator readings. This inflates the estimated GDP sensitivity to positive movements in the monthly panel — most sharply in the labour block, where the 2020 asymmetry is largest. It is a plausible mechanism for the measured +0.2174pp hot bias recorded in pipeline/seed/ci_params.json, which is then subtracted from the CI centre but not from the published point.

**Survived refutation because.** Verified. 05_estimate_model.R applies `ts_data_balanced[covid_mask, ] <- NA` for months 3:7 of 2020 AFTER Bpanel has transformed the panel, and I confirmed update_trans_codes.R assigns gdp_quarterly trans = 7 ('3-mo %: quarterly level on monthly grid -> QoQ % (target)') and employment trans = 1 ('MoM %'). With GDP's transformed observations landing on Mar/Jun/Sep/Dec, the mask removes exactly Q1 2020 and Q2 2020 and retains Q3 and Q4 2020 — so the collapse is dropped and the rebound kept, on both the target and the monthly indicators. The in-code comment's claim that Jun is the 'reopening rebound' is true for the trans=1 monthlies but false for the trans=7 GDP row, which corroborates that the asymmetry was not intended. I could not refute the mechanism; the causal link to the +0.2174pp bias in ci_params.json remains inference rather than proof. High stands.


<details>
<summary>23 medium/low findings</summary>

| sev | finding | location | category | labour |
|---|---|---|---|---|
| 🟡 medium | FRED fallback CSV is 4 months stale and is used silently with no freshness check | `pipeline/03b_fetch_fred_data.R:79` | stale-data |  |
| 🟡 medium | A second pipeline run on the same day silently wipes the data_updates audit trail and zeroes the nowcast delta | `pipeline/04_emit_json.R:315` | correctness | yes |
| 🟡 medium | nowcasts.json publishes back-fitted simulated vintages with no flag distinguishing them from live runs | `pipeline/04_emit_json.R:419` | fidelity |  |
| 🟡 medium | Two mutually inconsistent GDP release-date rules; the 64-day rule releases GDP up to 2 days before ABS does | `pipeline/04_release_calendar.R:57` | real-time-leak |  |
| 🟡 medium | generate_nowcast levels the point estimate off the wrong base quarter when target is >1 quarter ahead | `pipeline/06_generate_nowcast.R:131` | correctness |  |
| 🟡 medium | No convergence check reaches the production path; log_likelihood is NA in every vintage row | `pipeline/08_vintage_tracking.R:466` | silent-failure |  |
| 🟡 medium | CI bands are calibrated at a single as-of horizon (quarter end) but applied to every vintage regardless of horizon | `pipeline/09_backtest_model.R:74` | calibration |  |
| 🟡 medium | Backtest and vintage reconstruction use fully-revised data, so published CI params are revision-optimistic | `pipeline/09_backtest_model.R:108` | real-time-leak |  |
| 🟡 medium | NAB source CSV has three duplicated months; duplicates reach indicators.json and are silently averaged into the model | `pipeline/nab_business_confidence_raw.csv:140` | data-quality |  |
| ⚪ low | Any readr parse warning on the FRED response is treated as a fetch failure, triggering retries then the stale fallback | `pipeline/03b_fetch_fred_data.R:63` | error-handling |  |
| ⚪ low | indicators.json can pair a scraped last_release_date with a series that stops at an earlier reference month | `pipeline/04_emit_json.R:220` | data-contract | yes |
| ⚪ low | emit_json's performance aggregates omit na.rm, so one NA error nulls the whole public scorecard | `pipeline/04_emit_json.R:622` | correctness |  |
| ⚪ low | emit_json reaches for vraw_all via exists() with lexical fallthrough to the global environment | `pipeline/04_emit_json.R:407` | correctness |  |
| ⚪ low | configure_dfm's em_max_iter / em_tolerance / method are never passed to nowcast() and have no effect | `pipeline/05_estimate_model.R:302` | dead-config |  |
| ⚪ low | track_nowcast_evolution re-uses one full-sample model for every as-of date, so its 'evolution' is not a vintage series | `pipeline/06_generate_nowcast.R:300` | real-time-leak |  |
| ⚪ low | calculate_confidence_intervals silently substitutes a hardcoded prediction_sd of 1.0 in GDP level units | `pipeline/06_generate_nowcast.R:212` | hardcoded-value |  |
| ⚪ low | n_indicators_updated in the committed vintage index is permanently 0 because the vintage RDS files are gitignored | `pipeline/08_vintage_tracking.R:57` | ci-reliability |  |
| ⚪ low | get_vintage_history filters on a `quarter` column that master$wide never has, so actuals are always silently dropped | `pipeline/08_vintage_tracking.R:232` | correctness |  |
| ⚪ low | accuracy_log.csv is gitignored, so evaluate_accuracy re-reports every historical quarter as newly evaluated on each CI run | `pipeline/08_vintage_tracking.R:573` | ci-reliability |  |
| ⚪ low | load_ci_params uses a hardcoded relative seed/ path with no repo-root fallback, unlike every other path in emit_json | `pipeline/ci_bands.R:34` | path-fragility |  |
| ⚪ low | deploy_nowcast.R passes all_indicators = NULL, writing n_indicators = 0 into the committed vintage index | `pipeline/deploy_nowcast.R:46` | data-quality |  |
| ⚪ low | ci_params.json cites a source file that is gitignored and absent, so the published bands are not reproducible | `pipeline/seed/ci_params.json:11` | stale-doc |  |
| ⚪ low | test_emit_json.R cannot run in CI: it depends on an out-of-repo absolute path and gitignored fixtures | `pipeline/tests/test_emit_json.R:25` | ci-reliability |  |

</details>

### Next.js site  (25 findings)

#### 🟠 high · Main/Volatility toggle switches target quarter (Q2 vs Q3) while presenting both as "growth this quarter"

`src/components/NowcastHeadline.tsx:27` · correctness · finder confidence: high

**Claim.** `latest_v2.json` currently has `models.headline.target_quarter = "2026 Q2"` and `models.stress.target_quarter = "2026 Q3"`. NowcastHeadline swaps `model` on toggle but uses a single `prevLevel` (the 2026 Q1 level) for both, has no guard for the mismatch, and labels both "growth this quarter". The methodology copy asserts they differ only in weighting.

**Evidence.** data/latest_v2.json: headline `"target_quarter": "2026 Q2", "qoq_growth_pct": 0.62, "n_months_in_quarter": 3`; stress `"target_quarter": "2026 Q3", "qoq_growth_pct": 0.35, "n_months_in_quarter": 1`. `prev_level.value = 695945` with `"date": "2026 Q1"`. NowcastHeadline.tsx:27-28 `const model = mode === "main" ? headline : stress; const range = growthRange(model, prevLevel);` — one prevLevel for both. Line 61-63 renders `formatPct(model.qoq_growth_pct)` next to the fixed caption "growth this quarter". MethodologyPanel.tsx:44-45 "Both are fit on the same panel and differ only in that weighting." Upstream: nowcasting_v2/R/emit_v2_json.R:126-127 passes the same `prev_level` into `ci_level_band` for both models while line 128 takes `target_quarter = nc$target_quarter` per model.

**Failure scenario.** Visitor clicks "Volatility model". The heading becomes "2026 Q3 — our GDP estimate", the big number reads "+0.35% growth this quarter", and `growthRange(stress, 695945)` computes a likely range of −0.07% to +0.55% by dividing a Q3 level band by the Q1 level — a two-quarter growth rate rendered as a one-quarter rate. Meanwhile the vintage chart, indicator grid and backcast table on the same page are all about Q2. The reader compares +0.35% against +0.62% as two estimates of the same quarter; they are not.

**Survived refutation because.** Verified in the shipped data: latest_v2.json models.headline.target_quarter = '2026 Q2' (n_months_in_quarter 3) and models.stress.target_quarter = '2026 Q3' (n_months_in_quarter 1), with prev_level 695945 dated '2026 Q1'. NowcastHeadline.tsx:27-28 swaps `model` but passes the single prevLevel to growthRange for both, :39 renders '{model.target_quarter} — our GDP estimate', :61-62 renders the number beside the fixed caption 'growth this quarter'. Worse than stated: emit_v2_json.R:126-128 also anchors the stress model's own level and bands on the Q1 prev_level (698386 = 695945 * 1.0035), so the Q3 estimate is a Q3-over-Q1 level published as a QoQ. No guard anywhere. Could not refute. High confirmed.


#### 🟠 high · Homepage presents pseudo-out-of-sample backtest results as a live "Track record" and drops the explicit disclaimer

`src/components/PerformanceSection.tsx:23` · fidelity · finder confidence: high

**Claim.** page.tsx feeds `performance_v2.json` (backcast errors) into PerformanceSection under the heading "Track record" with a column headed "Final nowcast". data/backcasts.json carries the authoritative disclaimer, data.ts loads it into `DashboardData.backcasts`, and page.tsx never uses it. The `isBacktest` prose branch (lines 40-47) never contains the words "backtest", "backcast", "simulated" or "hypothetical".

**Evidence.** page.tsx:36-39 `<PerformanceSection performance={data.performanceV2 ?? data.performance} isBacktest={!!data.performanceV2} />`. PerformanceSection.tsx:23-25 `Track record`; line 58 `<th>Final nowcast</th>`. data/backcasts.json: `"basis": "pseudo-out-of-sample backtest (hypothetical; not produced in real time)"`, `"note": "These are BACKTESTED estimates, shown to give the new model a track record at launch. They are not live nowcasts."`. data.ts:74 loads it; grep over src/ shows `backcasts` is referenced only in src/app/v2/page.tsx (the unlinked preview route). Built output confirms: `grep -c "not live nowcasts" out/index.html` -> 0, `grep -c "BACKTESTED" out/index.html` -> 0.

**Failure scenario.** A visitor reads "Track record — MAE 0.25% of GDP · Bias +0.10% · 12 quarters, hit rate implied" and concludes the model has twelve quarters of live out-of-sample performance. None of those twelve numbers was ever produced in real time; every one is a re-estimated hindcast. The /v2 preview page labels each row "(backtest)" (v2/page.tsx:94) — the public page does not.

**Survived refutation because.** Verified end to end. page.tsx:36-39 passes performanceV2 with isBacktest true; PerformanceSection.tsx:23-25 heads it 'Track record' and :57 heads the column 'Final nowcast'; the isBacktest prose at :40-47 contains none of backtest/backcast/simulated/hypothetical. data/backcasts.json does carry basis 'pseudo-out-of-sample backtest (hypothetical; not produced in real time)' and the note 'They are not live nowcasts.', data.ts:74 loads it, and grep over src/ shows `backcasts` is referenced only in src/app/v2/page.tsx. Confirmed against the built artefact: grep -c 'not live nowcasts' out/index.html = 0 and grep -c 'BACKTESTED' out/index.html = 0, while v2/page.tsx:94 does label each row '(backtest)'. Could not refute. High confirmed.


<details>
<summary>23 medium/low findings</summary>

| sev | finding | location | category | labour |
|---|---|---|---|---|
| 🟡 medium | --color-label-light (#9ca3af) at 10px fails WCAG AA and carries the MAE and RBA-comparison figures | `src/app/globals.css:16` | accessibility |  |
| 🟡 medium | The /v2 staging preview is publicly deployed and marked index,follow with internal approval language | `src/app/v2/page.tsx:48` | fidelity |  |
| 🟡 medium | "Next release" column prints dates already in the past with no guard | `src/components/IndicatorsTable.tsx:123` | stale-data-indicator |  |
| 🟡 medium | Indicator table rows are click-only — keyboard and screen-reader users cannot open a detail chart from the table | `src/components/IndicatorsTable.tsx:85` | accessibility |  |
| 🟡 medium | Volatility-model bar is appended to the actuals series skipping 2026 Q2, with no x labels to reveal the hole | `src/components/NowcastHeadline.tsx:30` | correctness |  |
| 🟡 medium | Main/Volatility toggle buttons expose no pressed state to assistive technology | `src/components/NowcastHeadline.tsx:43` | accessibility |  |
| 🟡 medium | Track-record table colours the error column by sign, so the largest overshoot renders green | `src/components/PerformanceSection.tsx:74` | fidelity |  |
| 🟡 medium | No chart has a text alternative — the nowcast evolution and headline charts are opaque to assistive tech | `src/components/VintageChart.tsx:115` | accessibility |  |
| 🟡 medium | Silent JSON fallbacks publish zeroed placeholder numbers as if they were the nowcast | `src/lib/data.ts:21` | missing-error-state |  |
| 🟡 medium | formatDate/formatDayMonth read UTC-parsed dates in local time — every date shifts a day for western-hemisphere viewers | `src/lib/format.ts:21` | correctness |  |
| 🟡 medium | The only deploy gate is an e2e suite that asserts no numeric value or range | `tests/site.spec.ts:3` | ci-reliability |  |
| ⚪ low | README describes the site as a Dynamic Factor Model dashboard over 12 series; the live page runs the v2 MAI over 31 | `README.md:48` | stale-doc |  |
| ⚪ low | /v2 preview formats dollars with the build machine's default locale | `src/app/v2/page.tsx:12` | correctness |  |
| ⚪ low | Indicator grid displays all 31 candidates as identical tiles; 20 of them never enter the nowcast | `src/components/IndicatorGrid.tsx:66` | fidelity | yes |
| ⚪ low | Bar-mode sparkline baselines at dataMin, so the smallest positive month renders as zero change | `src/components/IndicatorSparkline.tsx:37` | correctness |  |
| ⚪ low | Percent-unit indicators are rounded to 1dp, collapsing yield spreads to "-0.0%" | `src/components/IndicatorsTable.tsx:33` | correctness |  |
| ⚪ low | Series with month gaps are drawn on a category axis and their gap change is labelled "Δ m/m" | `src/components/IndicatorsTable.tsx:54` | correctness |  |
| ⚪ low | Vintage chart has no empty state — a target-quarter mismatch renders a near-blank chart with the same caption | `src/components/VintageChart.tsx:45` | missing-empty-state |  |
| ⚪ low | Duplicate vintage records are plotted twice; no dedupe on run_date | `src/components/VintageChart.tsx:45` | data-contract |  |
| ⚪ low | data.test.ts's "returns sane fallbacks when files are missing" test never exercises a missing file | `src/lib/data.test.ts:16` | test-coverage |  |
| ⚪ low | formatPct prints a signed zero for sub-0.005% values, so a contraction can render as "−0.00%" | `src/lib/format.ts:5` | correctness |  |
| ⚪ low | formatMonth returns "undefined YY" for any input that is not exactly YYYY-MM | `src/lib/format.ts:18` | correctness |  |
| ⚪ low | `nowcast_delta_pp` and the run-level data_updates record are loaded and typed but never rendered | `src/lib/types.ts:24` | data-contract | yes |

</details>

## Appendix — refuted or deduplicated

49 of 190 raw findings did not survive adversarial verification. Verifiers were instructed to default to refuting when uncertain, so this list includes some findings that may be real but unproven.

| finding | why it was dropped |
|---|---|
| MIDAS is driven by the SMOOTHED MAI; paper explicitly uses the filtered real-time MAI | duplicate of: v2 emits the RTS-smoothed factor as the MAI; the paper's nowcast engine uses the filtered real-time factor |
| Dependent variable is latest-vintage GDP growth, not the paper's first-release GDP | duplicate of: Selection and MIDAS target GDP is latest-vintage growth, not the paper's first-release GDP |
| SPEC-SWEEP-RESULTS.md justification for the production MIDAS spec is stale (29->9 vs production 31->11) | duplicate of: Production alpha=0.05 deviates from the paper's alpha=0.10 and its written justification is stale |
| Named-factor identification is anchored to ft_emp by accident of panel column order, not the top-Wald series | duplicate of: Named-factor identification anchors on panel_info column order (ft_emp), not the paper's highest-Wald series |
| v2's soft block is structurally unable to load: 3-year survey histories inside a 48-year factor | duplicate of: Soft block observed 37-66 months vs labour's ~580; standardisation and loadings estimated on 3 years of data |
| Short-series clamping of the rolling demean departs from the paper's uniform 20-year window, and it hits exactly the soft block | REFUTED by the mechanism its sibling finding sets out and which I independently checked. With roll_len = n-1 on n observations, rolling_scale demeans row 1 by mean(obs 1..n-1) and rows 2..n by mean(obs 2..n). The paper's own code on the same short series insid |
| Dev driver writes data_raw/mai.csv under a different spec (alpha=0.10, AiG and rt included) than the production headline MAI | duplicate of: run_nowcast_v2.R is a stale entrypoint: builds a different model spec than production and overwrites data_raw/mai.csv |
| Ad hoc sign flip by correlation with the selected-panel mean replaces the paper's named-factor sign convention | REFUTED. Two independent reasons. (1) The flip cannot alter the nowcast: the MIDAS regression is re-estimated each run on the SAME MAI series, so a global sign flip of the whole history flips the fitted coefficient too and leaves the forecast identical. (2) Th |
| Informational: v2's IIS follows the replication code (alpha=0.01, 8 candidate dummies), which itself contradicts the paper text (5 per cent, seven indicators) | REFUTED — this is a non-finding by its own admission ('No action needed in v2'). Verified build_mai.R:35 and :50 do match Targeted_Predictor_MAI_Dataset.R:141 exactly, i.e. v2 is faithful to the paper's CODE, which is the standard the review bar sets ('the pap |
| Wald regression alignment (k=0:2, mf_lag, HAC options) verified faithful — no divergence found in the selection regression itself | REFUTED as a finding: it is explicitly a NEGATIVE result ('failure_scenario: None'). I independently confirmed the substance by reading build_mai.R:129-174 — k1=0L/k2=2L with mf_lag, int/QS/EH/dbw=FALSE/dft=TRUE, rmat = cbind(0, diag(3), 0), threshold = qchisq |
| Stress model silently targets a different quarter than headline; level/yoy/CI anchored on wrong quarter | duplicate of: Headline and stress are emitted as parallel 'models' but target DIFFERENT quarters (Q2 vs Q3) |
| GDP target is latest-vintage, not first-release, despite paper protocol and rt_ filename | duplicate of: Selection and MIDAS target GDP is latest-vintage growth, not the paper's first-release GDP |
| days_until_release sign inverted: as_of - release_date is negative before release | duplicate of: latest_v2.json days_until_release is negative for future releases — sign inverted vs the field name |
| data_through label overstates headline information set when wmi_sent defines the panel frontier | duplicate of: data_through in latest_v2.json/vintages overstates what fed the headline model |
| MAI fed to MIDAS is two-sided smoothed factor; paper's protocol uses one-sided Kalman-filter MAI | duplicate of: v2 emits the RTS-smoothed factor as the MAI; the paper's nowcast engine uses the filtered real-time factor |
| jt=0 QA random-walk extrapolation replaces paper's FC-stage model with same CI band | duplicate of: jt=0 QA fallback (random-walk quarter-average substitution) is an unbacktested spec the paper never uses |
| Roll-window clamp itself is faithful-in-effect; degenerates to full-span demeaning as paper's code would | REFUTED — and it refutes itself. Its own failure_scenario field says 'None material through this mechanism alone'. I verified the analysis is correct: transform_panel.R:79 `rl <- min(roll_months, n_tx - 1L)` leaves rolling_scale with a single loop iteration, a |
| rolling_scale demeans history with forward-looking windows, contradicting the paper's 'backward-looking' description | REFUTED on scope, and the finding refutes itself on impact. misc_methods.R is one of the six files established as BYTE-IDENTICAL to rba_paper/content/Code/methods/, and the session's standing instruction is explicit: 'The estimation math is upstream. Do not re |
| tcode/tlog assignments verified consistent with the paper for all shared series (no divergence) | REFUTED — self-declared non-finding. Its own failure_scenario reads 'None — recorded so the downstream verification stage knows the checks were performed and passed'. I spot-checked the underlying claim against rba_paper/content/Data/mai_info.csv and it holds  |
| Backtest estimates and scores on latest-vintage GDP; paper mandates first-release GDP | duplicate of: Selection and MIDAS target GDP is latest-vintage growth, not the paper's first-release GDP |
| Public v2 track record scores backtest reconstructions, not the published nowcasts | REFUTED on its central factual claim. The finding asserts v2's real-time 2026 Q1 nowcast was +0.77 vs a +0.30 print, so performance_v2's +0.07pp backtest error hides a real miss. But nowcasting_v2/NIGHT-LOG.md:46 states explicitly: 'First v2 nowcast: 2026 Q2 + |
| CI params calibrated only at quarter-end (jt=2) but applied at every within-quarter state | duplicate of: CI bands are calibrated at a single as-of horizon (quarter end) but applied to every vintage regardless of horizon |
| 95% band uses z=1.96 with parameters estimated from 17 observations | duplicate of: CI half-widths use normal z with n=17 errors instead of t(16) |
| Two conflicting 'post-COVID' definitions across evaluation scripts (2020Q4 vs 2022Q1) | REFUTED. Both values are verified present (backtest_v2_monthly.R:257 post_covid_from='2020-10-01'; pipeline/compute_ci_params.R:17 and bias_correction_analysis.R:25 POSTCOVID_FROM=2022-01-01), but the 2020-10-01 choice is documented in-code with an explicit ra |
| compute_ci_params accepts as few as 8 errors for calibrating public 95% bands | Refuted as a live finding. compute_ci_params.R:26-27 is a floor, not a setting: the guard has never been the binding constraint (both shipped params files carry n=17, the v1 file n=16), so no published band has ever been calibrated near n=8. The stated failure |
| compute_ci_params computes sd() while ci_bands.R documents sqrt(rmse^2 - bias^2) as the dispersion measure | duplicate of: ci_bands.R documents sd = sqrt(rmse^2 - bias^2) but code uses sample sd(n-1) |
| yoy_growth_pct multiplies non-consecutive quarters when the target skips a quarter | duplicate of: Stress yoy_growth_pct chains the WRONG quarters when stress targets Q3 (skips Q2-2026) |
| prev_level is never checked to be the quarter immediately before the target quarter | duplicate of: Stress level nowcast and CI level-bands anchor on Q1's level though the quarter before its Q3 target is Q2 |
| days_until_release has the wrong sign (as_of - release_date instead of release_date - as_of) | duplicate of: latest_v2.json days_until_release is negative for future releases — sign inverted vs the field name |
| DFM estimation window starts 1969 because one series does - RBA censors its panel to 1978 | duplicate of: No sample-start control: panel/MAI/selection/MIDAS all start 1969, paper hard-codes 1978 |
| DFM weight tracks series COVERAGE LENGTH, which the 1969 window maximises for labour | duplicate of: No sample-start control: panel/MAI/selection/MIDAS all start 1969, paper hard-codes 1978 |
| data_through overstates the model's information set by up to a month | duplicate of: data_through in latest_v2.json/vintages overstates what fed the headline model |
| Shipped CI bands are calibrated on a backtest with full-sample selection look-ahead | duplicate of: CI params calibrated under full-sample-fixed selection; production re-selects every Monday |
| Unit-variance scaling uses sd() where the RBA uses root-mean-square | duplicate of: Unit-variance step divides by sd, paper divides by root-mean-square |
| run_nowcast_v2 driver runs a different specification from production and overwrites data_raw/mai.csv | duplicate of: run_nowcast_v2.R is a stale entrypoint: builds a different model spec than production and overwrites data_raw/mai.csv |
| nowcast_midas's as_of GDP trim uses the quarter label, not the release date | duplicate of: nowcast_midas as_of trims GDP by label date, not release date — latent look-ahead for direct callers |
| _monthly_tuesday clamps last_release_date to `today`, publishing a date that is not a release date | REFUTED as a defect. The clamp is a deliberate, documented guard (the docstring at lines 69-73 states its purpose explicitly: prevent a point that lands before its modelled release date from showing a FUTURE date). The alternative behaviour the finding implici |
| gen_indicators_v2.py can leave data/latest_v2.json truncated and still exit 0 | duplicate of: latest_v2.json is truncated before the patch is written and any I/O error is swallowed with exit 0 |
| A same-day re-run wipes the data_updates / 'updated this week' audit trail | duplicate of: A second run on the same day wipes every 'updated this week' marker and empties data_updates.series |
| Commit step ships partial v2 output when the v2 step fails mid-script, and the failure alert states the opposite | duplicate of: v2 step is continue-on-error but the commit/deploy step is if: success() — partial v2 output ships |
| .mondays_to_date can return a Monday in the FUTURE, producing a future as_of and generated_at | duplicate of: .mondays_to_date can return a Monday in the future, stamping the JSON with a future vintage |
| StalenessBanner is evaluated at build time on a static export, so it can never fire | duplicate of: StalenessBanner is evaluated at build time on a statically exported site, so it can never fire when the pipeline stops |
| Methodology panel tells the public the MAI is built from ~30 series; production selects 11 | duplicate of: Methodology text on the live site misdescribes the panel: '~30 series' and 'both fit on the same panel' |
| Hours worked is labelled "mn hours" but the values are thousands of hours — a 1000x unit error on the live page | duplicate of: Hours worked is labelled 'mn hours' but the value is in THOUSANDS of hours — a 1000x display error |
| Vintage chart x-axis is hardcoded to [-95, 5], silently dropping earlier vintages | duplicate of: VintageChart's fixed x-domain silently drops vintages outside [-95, 5] days |
| Vintage chart caption names `latest.target_quarter` (v1) while plotting `targetQuarter` (v2) | duplicate of: Nowcast-evolution chart is filtered on the v2 target quarter but captioned with the v1 one |
| Confidence band in the vintage chart rides visibly below the point line every week, with no explanation | duplicate of: Point/band split: published point is the biased element by the model's own calibration (extends known finding) |
| Vintage band reconstructs the prior-quarter level from two rounded fields, introducing avoidable error | Refuted on magnitude. The reconstruction error is bounded by the rounding of qoq to 2dp — at most ~0.005% of the level — so the band edges shift by at most ~0.005pp on a ~0.35pp-wide band, which is not renderable at any plausible chart height. The finder's own |
| performance_v2.json failing to parse silently swaps in v1's single-quarter track record and different prose | duplicate of: Every v2 artifact silently falls back to a v1 artifact when its JSON is unreadable |
