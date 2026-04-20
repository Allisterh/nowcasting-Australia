export interface NowcastEstimate {
  gdp_chain_volume_millions: number;
  qoq_growth_pct: number;
  yoy_growth_pct: number;
  ci_68_low: number;
  ci_68_high: number;
  ci_95_low: number;
  ci_95_high: number;
}

export interface LatestNowcast {
  generated_at: string; // ISO 8601
  target_quarter: string; // e.g. "2026 Q1"
  data_through: string; // e.g. "2026-04"
  next_gdp_release_date: string; // ISO date, e.g. "2026-06-04"
  nowcast: NowcastEstimate;
  latest_actual: {
    quarter: string;
    gdp_chain_volume_millions: number;
    qoq_growth_pct: number;
    released_days_before_next: number; // e.g. -92
  };
}

export interface GdpQuarter {
  quarter: string;
  value: number;
  qoq_pct: number;
  yoy_pct: number;
}

export interface GdpSeries {
  series: GdpQuarter[];
}

export interface Vintage {
  run_date: string; // "YYYY-MM-DD"
  target_quarter: string;
  point: number;
  qoq_growth_pct: number;
  days_until_release: number; // negative = before release
  ci_68_low: number;
  ci_68_high: number;
  ci_95_low: number;
  ci_95_high: number;
  data_through: string;
}

export interface VintageSeries {
  vintages: Vintage[];
}

export type IndicatorGroup = "Labour" | "Consumer" | "Business" | "External";

export interface IndicatorPoint {
  date: string; // "YYYY-MM"
  value: number;
}

export interface Indicator {
  id: string;
  name: string;
  group: IndicatorGroup;
  unit: string;
  source: string;
  series: IndicatorPoint[];
  last_release_date?: string;       // ISO "YYYY-MM-DD" — when the latest point was released
  next_release_estimate?: string;   // ISO "YYYY-MM-DD" — when the next point is expected
}

export interface IndicatorData {
  indicators: Indicator[];
}

export interface AccuracyError {
  target_quarter: string;
  final_nowcast: number;
  actual: number;
  error_millions: number;
  error_pct: number;
  yoy_nowcast: number | null;
  yoy_actual: number | null;
  yoy_rba: number | null;
  somp_release: string | null;
  edge_pp: number | null;
}

export interface RbaComparison {
  n: number;
  avg_edge_pp: number | null;
}

export interface Performance {
  mae_millions: number;
  mae_pct: number;
  bias_millions: number;
  bias_pct: number;
  rba_comparison: RbaComparison;
  errors: AccuracyError[];
}

export interface DashboardData {
  latest: LatestNowcast;
  gdp: GdpSeries;
  nowcasts: VintageSeries;
  indicators: IndicatorData;
  performance: Performance;
}
