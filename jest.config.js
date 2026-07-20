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
  // Floor set a few points below the current baseline (statements/lines ~89%,
  // functions ~92%, branches ~71%) to block regressions with headroom for
  // normal test churn. Ratchet upward as the suite grows.
  coverageThreshold: {
    global: { statements: 84, branches: 65, functions: 86, lines: 84 },
  },
};
