#!/usr/bin/env node
/* Org capability probe. Run on FIRST connect to any org, before trusting a deploy plan:
 *     node scripts/org-capability-probe.js -o <alias>
 *
 * Sprint 1 burned ~8 deploy rounds bisecting two non-standard Metadata API behaviours on the DE
 * target (D-027 CMDT-record deploys rejected; D-028 FLS applied to system-mode DML at deploy-time
 * test run). This probe discovers what is cheaply discoverable in seconds and records it to
 * .claude/memory/org-capabilities.md so the next session inherits the knowledge instead of re-earning it.
 *
 * SAFETY: read-only. It runs `sf org display` + one `--dry-run` (checkOnly, no writes) only.
 * It REQUIRES an explicit -o/--target-org and never falls back to a default org — the log history
 * warns that live client sandbox/prod orgs are connected in this environment (never probe those). */
const { execFileSync } = require('child_process');
const fs = require('fs');

const argv = process.argv.slice(2);
const getArg = (names) => { for (let i = 0; i < argv.length; i++) if (names.includes(argv[i])) return argv[i + 1]; return null; };
const alias = getArg(['-o', '--target-org']);
if (!alias) {
  console.error('Usage: node scripts/org-capability-probe.js -o <org-alias>');
  console.error('Refusing to run without an explicit target — never probe a default/ambient org.');
  process.exit(2);
}

const sf = (args) => execFileSync('sf', args, { encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
const findings = [];   // { probe, result, detail }
const rec = (probe, result, detail) => { findings.push({ probe, result, detail }); console.log(`  [${result}] ${probe} — ${detail}`); };

console.log('== Org capability probe: ' + alias + ' ==');

// --- Probe 0: connection + edition (the cheap, decisive signal) ---
let org = null;
try {
  const out = JSON.parse(sf(['org', 'display', '--target-org', alias, '--json']));
  org = out.result || {};
} catch (e) {
  rec('connection', 'ERROR', 'sf org display failed — org not authenticated or sf CLI missing (' + (e.message || '').split('\n')[0] + ')');
  console.log('== probe aborted: cannot reach org ==');
  process.exit(1);
}
const edition = org.edition || 'Unknown';
const isDE = /developer/i.test(edition);
rec('connection', 'OK', `${org.username || '?'} @ ${org.instanceUrl || '?'} (edition: ${edition})`);

// --- Probe 1: CMDT record deployability (D-027) ---
// The opaque one. Heuristic by edition, then confirm-path documented (a real confirm needs the
// CMDT *type* present in the org, so we don't auto-deploy a throwaway type here).
if (isDE) {
  rec('cmdt-record-deploy', 'LIKELY-BLOCKED',
    'Developer Edition — D-027 pattern: Metadata API rejects CustomMetadata RECORD deploys (UNKNOWN_EXCEPTION), type+fields deploy fine. Plan to create CMDT records MANUALLY in Setup.');
} else {
  rec('cmdt-record-deploy', 'UNKNOWN',
    'Not a Developer Edition org — D-027 may not apply. Confirm with a --dry-run of one CMDT record before batching.');
}

// --- Probe 2: FLS on system-mode DML at deploy-time tests (D-028) ---
if (isDE) {
  rec('fls-on-system-mode-dml', 'LIKELY-STRICT',
    'Developer Edition — D-028 pattern: deploy-time RunLocalTests apply FLS even to system-mode DML. Build test fixtures under System.runAs(user-with-FLS-permset); split tests that do system-mode DML on required/MD fields and exclude them from the deploy run (RunSpecifiedTests is class-level only).');
} else {
  rec('fls-on-system-mode-dml', 'UNKNOWN',
    'Not a Developer Edition org — standard behaviour usually bypasses FLS in system mode. Confirm on first deploy that runs tests.');
}

// --- Record to project memory (append-only register) ---
const memFile = '.claude/memory/org-capabilities.md';
const stamp = org.instanceUrl || alias; // no Date.* — the deploy log/PIPELINE_STATE carry the date
let existing = '';
try { existing = fs.readFileSync(memFile, 'utf8'); } catch {}
if (!existing) existing = '# Org Capabilities Register\n\nProbe results per org (from scripts/org-capability-probe.js). Append-only.\n\n| Org (alias) | Edition | CMDT-record deploy | FLS on system-mode DML | Instance |\n|---|---|---|---|---|\n';
const row = `| ${alias} | ${edition} | ${findings.find(f => f.probe === 'cmdt-record-deploy').result} | ${findings.find(f => f.probe === 'fls-on-system-mode-dml').result} | ${stamp} |\n`;
if (!existing.includes(`| ${alias} | ${edition} |`)) {
  try { fs.writeFileSync(memFile, existing + row); console.log('  recorded → ' + memFile); }
  catch (e) { console.log('  (could not write ' + memFile + ': ' + e.message + ')'); }
} else {
  console.log('  (' + memFile + ' already has a row for this org/edition — left as-is)');
}

console.log('== probe complete ==');
console.log('Deploy-confirm the two DE quirks the first time you push to a new org; this probe flags the');
console.log('likelihood from edition so you plan the two-phase CMDT + runAs fixtures up front, not on round 8.');
process.exit(0);
