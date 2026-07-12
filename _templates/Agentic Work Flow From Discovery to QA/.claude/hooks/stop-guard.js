#!/usr/bin/env node
/* Stop/SubagentStop guard: an agent may not finish while bookkeeping is stale.
 * Rule: if work artifacts (01-discovery, 02-build, 03-qa, 04-confirmations, force-app)
 * are newer than the last append to .claude/logs/agent-runs.log by >90s, block the stop
 * and tell the agent exactly what to append. Exit 0 = allow, exit 2 = block. */
const fs = require('fs'), path = require('path');

let raw = '';
process.stdin.on('data', d => raw += d);
process.stdin.on('end', () => {
  let input = {};
  try { input = JSON.parse(raw); } catch {}
  if (input.stop_hook_active) process.exit(0); // already continued once — don't loop

  const MON = ['01-discovery', '02-build', '03-qa', '04-confirmations', 'force-app'];
  let newest = { file: null, m: 0 };
  const walk = (dir) => {
    let entries; try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
    for (const e of entries) {
      if (e.name === 'node_modules' || e.name === '.git' || e.name === '.gitkeep') continue;
      const p = path.join(dir, e.name);
      if (e.isDirectory()) walk(p);
      else {
        try { const m = fs.statSync(p).mtimeMs; if (m > newest.m) newest = { file: p, m }; } catch {}
      }
    }
  };
  MON.forEach(d => walk(d));

  let logM = 0;
  try { logM = fs.statSync('.claude/logs/agent-runs.log').mtimeMs; } catch {}

  if (newest.m > logM + 90_000) {
    console.error(
      'GUARDRAIL: bookkeeping is stale. "' + newest.file + '" is newer than the last entry in ' +
      '.claude/logs/agent-runs.log. Before finishing: (1) append your run line to ' +
      '.claude/logs/agent-runs.log per rules/30 §4; (2) append a PIPELINE_STATE.md log line if a ' +
      'work item completed or phase changed; (3) append a jira-log.md status line for any ticket ' +
      'whose status changed; (4) ensure every D-###/A-### you cited exists in .claude/memory/. ' +
      'If the file change was a human edit, append a "human" line to agent-runs.log noting it.');
    process.exit(2);
  }
  process.exit(0);
});
