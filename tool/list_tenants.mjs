#!/usr/bin/env node
// Prints the tenant registry (deploy/tenants/registry.json) as a table.
// Usage: node tool/list_tenants.mjs   (npm run tenants)
import { loadRegistry, renderTenantTable } from './tenant_registry.mjs';

console.log(renderTenantTable(loadRegistry()));
