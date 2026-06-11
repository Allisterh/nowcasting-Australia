# RBA RDP 2024-04 panel vs our v2 coverage

The RBA's Monthly Activity Indicator uses **53 monthly predictors**
(`nowcasting_v2/rba_paper/content/Data/mai_info.csv`). v2 uses a **33-series
subset present in `data_raw/`** (of which **29 feed the model** — AiG ×3 and old
retail `rt` are present but excluded), plus **2 substitutes** of our own. This
maps every RBA series to its status.

## A. Already using (29 of the RBA's 53 feed the model)

| RBA series | Name | Source |
|---|---|---|
| emp, ft_emp, pt_emp, ue, ud, hours | Labour force (6) | ABS 6202.0 |
| anz_ads | ANZ job vacancies | ANZ-Indeed (also stands in for RBA's `doe_ads`) |
| nab_cond, nab_profit, nab_trade, nab_emp, nab_forward, nab_stocks, nab_conf, nab_cu | NAB business survey (8) | NAB monthly PDF |
| anz_sent | ANZ-Roy Morgan consumer confidence | Roy Morgan |
| wmi_sent | Westpac-MI consumer sentiment | Westpac IQ |
| export | Exports | ABS 5368.0 |
| credit, credit_housing, credit_business | Credit aggregates (3) | RBA D2 |
| firmmbab90 | BBSW | RBA F1.1 |
| fcmygbag3, fcmygbag5, fcmygbag10 | AGS yields (3) | RBA F2.1 |
| scrigbag3, scrigbag5, scrigbag10 | Yield-BBSW spreads (3) | RBA (derived) |
| credit_card | Credit card spending | RBA C1 |

**Present in `data_raw/` but excluded from the model:** `aig_pmi`, `aig_psi`,
`aig_pci` (AiG surveys, discontinued); `rt` (old ABS retail, superseded).

**Our substitutes (not in the RBA's 53 by name):** `household_spending` (real
MHSI, ABS 5682.0 — replaces RBA's `rt` for consumption) and `building_app`
(aggregate dwelling approvals, ABS 8731.0 — replaces RBA's disaggregated approvals).

## B. Not used, but easily accessible (free, automatable — good test candidates)

| RBA series | Name | Source / why easy |
|---|---|---|
| `debit_card` | Debit card spending | RBA retail-payments stats — same family as `credit_card`. **Strongest candidate; never tried.** |
| `import` | Imports | ABS 5368.0 — **same table we already fetch `export` from.** |
| `credit_personal` | Personal credit | RBA D2 — **same table as the other credit aggregates.** |
| `res_ba`, `hs_ba`, `nh_ba`, `alt_add`, `non_res_ba` | Approvals disaggregated (5) | ABS 8731.0 — **same release as our `building_app`.** |
| `arrivals` | Overseas arrivals / passengers | ABS 3401.0, free time series. |
| `twi` | AUD trade-weighted index | RBA exchange-rate stats (free CSV). Earlier sourced via FRED, which was unreachable from the host — RBA direct fixes that. |
| `icp` | RBA Index of Commodity Prices | RBA I2 (free CSV). Same FRED caveat as `twi`. |
| `doe_ads` | Dept of Employment job ads | now JSA Internet Vacancy Index (free XLSX) — but largely redundant with `anz_ads`. |

## C. Hard to get / no good free source

| RBA series | Name | Why hard |
|---|---|---|
| `asx200` | S&P/ASX 200 (equity prices) | Catalogued MISSING — "no free CSV". RBA stopped publishing the share-price table; Yahoo/Stooq need API keys or are unstable. |
| `house_prices` | House prices | Catalogued MISSING — ABS RPPI discontinued 2021; CoreLogic paywalled. |
| `acr` | Auction clearance rates | CoreLogic/Domain, paywalled / unstable. |
| `mt103s` | RTGS high-value payments | RBA payments data, not cleanly automatable. |
| `mv` | New vehicle sales | ABS 9314.0 discontinued; FCAI is the replacement but HTML-scrape only (messy). *Moderate.* |
| `new_reg` | New company registrations | ASIC data, no clean time-series feed. *Moderate.* |
| `anz_finance` | ANZ-RM financial situation | a sub-index of the Roy Morgan release we already scrape — extra parsing, doable. *Moderate.* |
| `wmi_finance` | Westpac-MI family finances | a sub-index of the Westpac release we already scrape — extra parsing, doable. *Moderate.* |

## Tested?
v1 (the 13-series DFM) backtested adding **commodity prices, AUD, inventories,
and arrivals** (2026-06-04) → none beat the baseline or fixed the Q1-2026 miss.
**That test was in the v1 framework, not v2** — none of the Bucket-B candidates
has been evaluated inside the v2 MAI + U-MIDAS model.
