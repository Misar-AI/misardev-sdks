import { defineConfig } from "tsup";

// @misardev/sdk and commander are dependencies, so tsup leaves them external:
// the CLI shares the SDK's error classes instead of bundling a second copy.
export default defineConfig({
  entry: { bin: "src/bin.ts", index: "src/index.ts" },
  format: ["esm"],
  target: "node18",
  platform: "node",
  dts: { entry: { index: "src/index.ts" } },
  sourcemap: true,
  clean: true,
});
