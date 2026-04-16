import { test, expect } from "@playwright/test";

test("homepage renders the headline nowcast", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Australia GDP nowcast" })).toBeVisible();
  // Headline card shows a QoQ percentage label
  await expect(page.getByText(/QoQ/).first()).toBeVisible();
  // At least one SVG chart renders
  await expect(page.locator("svg").first()).toBeVisible();
});

test("indicator grid renders and detail card opens on click", async ({ page }) => {
  await page.goto("/");
  // The indicator buttons use the indicator display name. "Employment" is in the
  // Labour group and is guaranteed to be present.
  const empBtn = page.getByRole("button", { name: /Employment/ }).first();
  await empBtn.click();
  // Detail card shows a metadata line "{group} · {unit} · {source}"
  await expect(page.getByText(/Labour · persons/)).toBeVisible();
});

test("methodology panel toggles", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("button", { name: /^Methodology/ }).click();
  await expect(page.getByText(/Dynamic Factor Model/)).toBeVisible();
});
