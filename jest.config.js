// Jest config for the Cloudflare Worker test suite.
//
// The worker file (`cloudflare_worker.js`) ships as ESM (uses
// `export default`). Jest still defaults to CommonJS, so we run it under
// `node --experimental-vm-modules` (see package.json scripts) and tell it
// not to transform our source — the `transform: {}` block makes Jest pass
// the file straight through to Node's ESM loader.
export default {
  testEnvironment: 'node',
  testMatch: ['<rootDir>/worker_test/**/*.test.js'],
  transform: {},
  // No coverage gates yet — add when the suite is broader.
  collectCoverage: false,
};
