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

2. From the historical table on that page, read the most recent "Actual" value for NAB Business Confidence. Note the month the value corresponds to — the release is for the PREVIOUS calendar month. For example, a release dated 2026-05-13 reports April 2026 data.

3. Change directory to the nowcasting repo:
   cd C:/Users/wilso/Documents/Claude/Projects/nowcasting

4. Pull latest:
   git pull origin main

5. Append the new observation to pipeline/nab_business_confidence_raw.csv. Format:
   date,value
   YYYY-MM-01,<integer or decimal>

   Use the first day of the reported month as the date. Preserve chronological order; append at the bottom. Do not modify existing rows.

6. Commit and push:
   git add pipeline/nab_business_confidence_raw.csv
   git commit -m "data: NAB Business Confidence for <Month YYYY>"
   git push

7. Report: what value was recorded for what month, and the commit URL.

If the investing.com page is blocked, the table is missing the expected row, or the value cannot be read with confidence: STOP. Do NOT write a fabricated value. Report the failure so James can update manually.
```

## Notes

- The repo itself does not scrape NAB — the pipeline reads from `pipeline/nab_business_confidence_raw.csv` as the single source of truth.
- If this task ever fails silently, the weekly nowcast pipeline falls back to the last-known value and the site's headline won't break. James will notice a month-old NAB value on the dashboard.
- The alternative aggregators (`tradingeconomics.com`, NAB direct) can be swapped into Step 1 without any other changes — the contract is the CSV, not the source.
- To revise this task, edit this file and re-paste the prompt into Claude Desktop's scheduled-task UI.
