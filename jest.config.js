// Jest config for the Cloudflare Worker test suite.
// Runs under `node --experimental-vm-modules` (see package.json) because the
// worker ships as ESM; `transform: {}` passes source straight to Node's ESM loader.
// Coverage uses the V8 provider (no Babel instrumentation needed for ESM).
export default {
  testEnvironment: 'node',
  testMatch: ['<rootDir>/worker_test/**/*.test.js'],
  transform: {},
  coverageProvider: 'v8',
  collectCoverage: false,
  collectCoverageFrom: ['worker/**/*.js'],
  coverageReporters: ['text-summary', 'lcov'],
  // Floor set just below the current baseline (lines ~64%) to block regressions
  // without flaking on small changes. Ratchet upward as the suite grows.
  coverageThreshold: {
    global: { statements: 60, branches: 54, functions: 62, lines: 60 },
  },
};
