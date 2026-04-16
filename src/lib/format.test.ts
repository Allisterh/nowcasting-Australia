import { describe, it, expect } from "vitest";
import { formatMillions, formatPct, formatQuarter, formatMonth, formatDate } from "./format";

describe("formatMillions", () => {
  it("formats with dollar prefix and comma thousands", () => {
    expect(formatMillions(694649)).toBe("$694,649M");
  });
});

describe("formatPct", () => {
  it("formats with sign and 2dp", () => {
    expect(formatPct(0.13)).toBe("+0.13%");
    expect(formatPct(-0.42)).toBe("−0.42%");
    expect(formatPct(0)).toBe("0.00%");
  });
});

describe("formatQuarter", () => {
  it("passes through canonical form", () => {
    expect(formatQuarter("2026 Q1")).toBe("2026 Q1");
  });
});

describe("formatMonth", () => {
  it("converts YYYY-MM to short label", () => {
    expect(formatMonth("2026-04")).toBe("Apr 26");
  });
});

describe("formatDate", () => {
  it("formats ISO date to human-readable", () => {
    expect(formatDate("2026-04-15")).toBe("15 Apr 2026");
  });
});
