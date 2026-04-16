export function formatMillions(m: number): string {
  return `$${m.toLocaleString("en-AU")}M`;
}

export function formatPct(pct: number): string {
  if (pct === 0) return "0.00%";
  const sign = pct > 0 ? "+" : "−";
  return `${sign}${Math.abs(pct).toFixed(2)}%`;
}

export function formatQuarter(q: string): string {
  return q;
}

export function formatMonth(yyyyMm: string): string {
  const [y, m] = yyyyMm.split("-");
  const labels = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
  return `${labels[parseInt(m, 10) - 1]} ${y.slice(2)}`;
}

export function formatDate(iso: string): string {
  const d = new Date(iso);
  const months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
  return `${d.getDate()} ${months[d.getMonth()]} ${d.getFullYear()}`;
}
