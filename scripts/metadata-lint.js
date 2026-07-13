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
const files = walk('force-app');

// ---- pre-pass: index every custom field (required?, type, MD master) ----
// Keyed "Object.Field" — matches the <field> value in a permission set's fieldPermissions.
const fieldMeta = {};   // "VS_Slot__c.VS_Capacity__c" -> { required, type, refTo }
const masterOf = {};    // detailObject -> masterObject  (from MasterDetail fields)
for (const f of files) {
  const m = f.match(/objects[\/\\]([^\/\\]+)[\/\\]fields[\/\\](.+)\.field-meta\.xml$/);
  if (!m) continue;
  const [obj, fld] = [m[1], m[2]];
  const c = fs.readFileSync(f, 'utf8');
  const type = (c.match(/<type>([^<]+)<\/type>/) || [])[1] || '';
  const required = /<required>\s*true\s*<\/required>/.test(c);
  const refTo = (c.match(/<referenceTo>([^<]+)<\/referenceTo>/) || [])[1] || '';
  fieldMeta[obj + '.' + fld] = { required, type, refTo };
  if (type === 'MasterDetail' && refTo) masterOf[obj] = refTo;
}

for (const f of files) {
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

// ---- permission-set checks (each costs a deploy round when wrong) ----
for (const f of files.filter(f => /permissionsets[\/\\].*\.permissionset-meta\.xml$/.test(f))) {
  const c = fs.readFileSync(f, 'utf8');
  const ps = path.basename(f).replace(/\.permissionset-meta\.xml$/, '');

  // 4. fieldPermissions on a field that CANNOT carry FLS (required or Master-Detail).
  //    A <fieldPermissions> entry for such a field fails deploy ("field cannot have field-level security").
  for (const blk of c.match(/<fieldPermissions>[\s\S]*?<\/fieldPermissions>/g) || []) {
    const field = (blk.match(/<field>([^<]+)<\/field>/) || [])[1] || '';
    const info = fieldMeta[field];
    if (info && (info.required || info.type === 'MasterDetail')) {
      const why = info.required ? 'required' : 'Master-Detail';
      fail(`permset ${ps} sets FLS on ${why} field ${field} — such fields can't have field-level security; remove the <fieldPermissions> entry: ${f}`);
    }
  }

  // 5. object read on a Master-Detail *detail* without read on its *master*.
  //    Detail access is governed by the master; granting read on the detail alone deploys but
  //    leaves records invisible (and often fails validation) — the master read must accompany it.
  const readObjs = new Set();
  for (const blk of c.match(/<objectPermissions>[\s\S]*?<\/objectPermissions>/g) || []) {
    const obj = (blk.match(/<object>([^<]+)<\/object>/) || [])[1] || '';
    if (obj && /<allowRead>\s*true\s*<\/allowRead>/.test(blk)) readObjs.add(obj);
  }
  for (const obj of readObjs) {
    const master = masterOf[obj];
    if (master && !readObjs.has(master)) {
      fail(`permset ${ps} grants read on MD detail ${obj} but NOT on its master ${master} — detail access requires master read; add an objectPermissions read for ${master}: ${f}`);
    }
  }
}

console.log(fails ? `== ${fails} metadata-limit issue(s) ==` : '== clean ==');
process.exit(fails ? 1 : 0);
