# NAB Business Confidence — monthly Claude scheduled task

This is the prompt James pastes into Claude Desktop's scheduled-task UI. It runs once a month, post the 2nd Tuesday, and updates the NAB Business Confidence CSV in the nowcasting repo via Chrome MCP against the user's preferred aggregator (no server-side scrape needed).

## Schedule

| Field | Value |
|---|---|
| Cron | `0 2 15 * *` (02:00 local on the 15th of each month) |
| Frequency | monthly |
| Window | The 15th is always past the 2nd Tuesday, so the previous month's data will always be available by then. |

## Prompt (paste verbatim)

```
You are updating the NAB Business Confidence CSV in the nowcasting repository. Run these steps in order.

1. Open Chrome (via Chrome MCP) and navigate to:
   https://www.investing.com/economic-calendar/nab-business-confidence-217

2. From the historical table on that page, read the TWO most recent "Actual" values for NAB Business Confidence:
   a. The most recent row — this is the new observation for the PREVIOUS calendar month. (A release dated 2026-05-13 reports April 2026 data.)
   b. The row before that — this is the prior month's value. NAB frequently revises the previous month's figure on release day, so it may differ from what is currently in the CSV.

3. Change directory to the nowcasting repo:
   cd C:/Users/wilso/Documents/Claude/Projects/nowcasting

4. Pull latest:
   git pull origin main

5. Read the current contents of pipeline/nab_business_confidence_raw.csv and locate the row for the prior month (the one identified in step 2b). Compare its value to what investing.com now shows for that month.

   - If the values match: no revision needed.
   - If the values differ: UPDATE that row's value in place. Do NOT add a duplicate row and do NOT modify any row older than the prior month.

6. Append the new observation (from step 2a) to pipeline/nab_business_confidence_raw.csv. Format:
   date,value
   YYYY-MM-01,<integer or decimal>

   Use the first day of the reported month as the date. Preserve chronological order; append at the bottom.

7. Commit and push. The commit message depends on whether a revision happened in step 5:
   - New month only:
     git commit -m "data: NAB Business Confidence for <Month YYYY>"
   - New month + revision of prior month:
     git commit -m "data: NAB Business Confidence for <Month YYYY> (+ <Prior Month> revision)"

   git add pipeline/nab_business_confidence_raw.csv
   git push

8. Report: the new month's value, whether the prior month was revised (and if so, from → to), and the commit URL.

If the investing.com page is blocked, the table is missing the expected row, or the value cannot be read with confidence: STOP. Do NOT write a fabricated value. Report the failure so James can update manually.
```

## Notes

- The repo itself does not scrape NAB — **v1** reads `pipeline/nab_business_confidence_raw.csv`.
- **There are TWO NAB inputs, not one.** This task maintains v1's CSV. **v2** reads
  `nowcasting_v2/data_raw/nab_conf.csv` (plus seven sub-indices: `nab_cond`, `nab_trade`,
  `nab_profit`, `nab_emp`, `nab_forward`, `nab_stocks`, `nab_cu`), which are refreshed by the
  local Cowork survey routine — see `docs/cowork-weekly-refresh.md`. Updating one does **not**
  update the other. If the v2 headline stalls on a freshness guard, this task is not the fix.
- If this task ever fails silently, the weekly nowcast pipeline falls back to the last-known value and the site's headline won't break. James will notice a month-old NAB value on the dashboard.
- The alternative aggregators (`tradingeconomics.com`, NAB direct) can be swapped into Step 1 without any other changes — the contract is the CSV, not the source.
- To revise this task, edit this file and re-paste the prompt into Claude Desktop's scheduled-task UI.
