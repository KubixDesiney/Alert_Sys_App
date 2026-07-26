#!/usr/bin/env node
// =============================================================================
// Embeds the publishable legal documents into store_legal_content.js.
// =============================================================================
// Cloudflare Workers cannot read the filesystem at runtime, so the store
// worker's gated /legal routes serve copies embedded at build time. This tool
// regenerates store_legal_content.js from docs/legal/ (single source of
// truth); `npm run legal:lint` warns whenever the embedded copy drifts.
// Publishing is still gated: the routes 404 unless LEGAL_PUBLISH = "true".
//
// Usage: npm run legal:embed

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

// slug (route) -> source draft + public title
const PUBLISHED = {
  privacy: { sourceFile: 'PRIVACY.md', title: 'Privacy Policy' },
  terms: { sourceFile: 'EULA.md', title: 'Terms of Use (EULA)' },
};

const docs = {};
for (const [slug, meta] of Object.entries(PUBLISHED)) {
  const markdown = fs.readFileSync(path.join(root, 'docs', 'legal', meta.sourceFile), 'utf8');
  docs[slug] = { ...meta, markdown };
}

const out = `// GENERATED FILE — do not edit by hand.
// Source of truth: docs/legal/ (regenerate with \`npm run legal:embed\`).
// Served by the store worker's /legal routes ONLY when LEGAL_PUBLISH = "true";
// until counsel signs off, the routes 404 and nothing here is public.
// eslint-disable
export const LEGAL_DOCS = ${JSON.stringify(docs, null, 2)};
`;

fs.writeFileSync(path.join(root, 'store_legal_content.js'), out);
console.log(`✓ store_legal_content.js regenerated (${Object.keys(docs).length} documents: ${Object.keys(docs).join(', ')})`);
