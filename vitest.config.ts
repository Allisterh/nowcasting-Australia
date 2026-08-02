import { defineConfig } from "vitest/config";
import path from "path";

export default defineConfig({
  test: {
    environment: "node",
    // tests/site.spec.ts is a Playwright e2e spec (run by `npm run test:e2e`).
    // Vitest was collecting it, failing to execute a playwright TestType, and
    // reporting a permanent red — which trains everyone to ignore the suite.
    exclude: ["**/node_modules/**", "**/dist/**", "**/.next/**", "tests/**"],
  },
  resolve: {
    alias: { "@": path.resolve(__dirname, "./src") },
  },
});
