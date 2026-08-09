import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["test/**/*.test.ts"],
    // Tests share one Postgres database; each file truncates state it touches.
    fileParallelism: false,
    testTimeout: 20000,
    hookTimeout: 20000,
  },
});
