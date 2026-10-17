import { defineConfig } from "vitest/config";

export default defineConfig({
  // An inline postcss config stops Vite searching upward for one and tripping
  // over the Next.js app's config at the repo root. The CLI ships no CSS.
  css: { postcss: { plugins: [] } },
  test: {
    environment: "node",
    include: ["tests/**/*.test.ts"],
    coverage: {
      provider: "v8",
      include: ["src/**/*.ts"],
      exclude: ["src/bin.ts"],
      thresholds: { lines: 80, functions: 80, branches: 70, statements: 80 },
    },
  },
});
