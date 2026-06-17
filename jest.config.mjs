// Jest coverage configuration.
//
// Test discovery is left at Jest defaults (matches worker_test/*.test.js), so
// plain `npm test` is unaffected. These options only take effect under
// `npm run test:coverage` (run by .github/workflows/quality.yml), turning that
// job into a real gate that fails if coverage of the Guardian self-heal modules
// regresses below the floor.
export default {
  collectCoverageFrom: [
    'tool/guardian_joint_fix.mjs',
    'tool/guardian_drill.mjs',
    'tool/guardian_preflight.mjs',
    'tool/guardian_providers.mjs',
  ],
  coveragePathIgnorePatterns: ['/node_modules/'],
  coverageThreshold: {
    global: { statements: 45, branches: 35, functions: 45, lines: 45 },
  },
};
