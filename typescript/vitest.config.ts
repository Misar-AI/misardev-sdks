import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    // `node`, not `jsdom`: a fetch-based HTTP client with no DOM usage.
    environment: "node",
    include: ["tests/**/*.test.ts"],
    coverage: {
      provider: "v8",
      include: ["src/**/*.ts"],
      thresholds: { lines: 80, functions: 80, branches: 70, statements: 80 },
    },
  },
});
