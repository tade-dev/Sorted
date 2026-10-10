import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['test/**/*.test.ts'],
    environment: 'node',
    // The emulator-backed suites clear their collections in beforeEach with
    // recursiveDelete, which slows down as a long-lived emulator accumulates
    // data across many runs. At the default 10s that surfaces as a confusing
    // "test failed" on an unrelated assertion. If hooks start timing out even
    // at 60s, restart the emulator (`npm run emulators`) rather than raising
    // this further: a clean emulator runs the same suite in about 7 seconds.
    hookTimeout: 60_000,
  },
});
