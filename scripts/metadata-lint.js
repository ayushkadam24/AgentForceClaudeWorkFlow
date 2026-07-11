#!/usr/bin/env node
/* Metadata deploy-limit linter. Run: node scripts/metadata-lint.js  (from project root)
 * Catches the defect classes that broke F-001 Sprint 1 BEFORE they reach a dry-run. */
const fs = require('fs'), path = require('path');
let fails = 0;
const fail = (m) => { fails++; console.log('  FAIL ' + m); };
const CAPS = [
  [/customPermissions[\/\\].*\.customPermission-meta\.xml$/, 255, 'CustomPermission'],
  [/permissionsets[\/\\].*\.permissionset-meta\.xml$/, 255, 'PermissionSet'],
  [/objects[\/\\][^\/\\]+[\/\\][^\/\\]+\.object-meta\.xml$/, 1000, 'CustomObject'],
  [/fields[\/\\].*\.field-meta\.xml$/, 1000, 'CustomField'],
];
const walk = (d, out = []) => {
  let e; try { e = fs.readdirSync(d, { withFileTypes: true }); } catch { return out; }
  e.forEach(x => { const p = path.join(d, x.name);
    x.isDirectory() ? walk(p, out) : (p.endsWith('-meta.xml') && out.push(p)); });
  return out;
};
console.log('== Metadata lint ==');
for (const f of walk('force-app')) {
  const c = fs.readFileSync(f, 'utf8');
  // 1. description caps
  const descs = [...c.matchAll(/<description>([\s\S]*?)<\/description>/g)];
  for (const [re, cap, label] of CAPS) {
    if (re.test(f)) descs.forEach(d => {
      if (d[1].length > cap) fail(`${label} description ${d[1].length} > ${cap}: ${f}`);
    });
  }
  // 2. illegal elements on __mdt
  if (/__mdt[\/\\].*\.object-meta\.xml$/.test(f) || (/objects[\/\\][^\/\\]*__mdt[\/\\]/.test(f) && f.endsWith('.object-meta.xml'))) {
    if (c.includes('<deploymentStatus>')) fail(`__mdt has illegal <deploymentStatus>: ${f}`);
    if (c.includes('<sharingModel>')) fail(`__mdt has illegal <sharingModel>: ${f}`);
  }
  // 3. formulas reading $CustomMetadata (deploy-mode coupling — warn as FAIL so it's decided, not discovered)
  if (f.includes('fields') && c.includes('$CustomMetadata')) {
    fail(`formula reads $CustomMetadata (checkOnly cannot validate w/ same-transaction CMDT — needs two-phase deploy or Apex read): ${f}`);
  }
}
console.log(fails ? `== ${fails} metadata-limit issue(s) ==` : '== clean ==');
process.exit(fails ? 1 : 0);
