#!/usr/bin/env node
/* ============================================================================
 * PROPOSED replacement for .claude/hooks/stop-guard.js  (NEXT-STEPS item 7).
 *
 * This file is STAGED, not active. Guardrails cannot be edited by the thing they
 * guard, so an agent cannot write into .claude/hooks/ (blocked by settings.json
 * deny-list AND pretool-guard.js). A HUMAN must review this and copy it over the
 * live hook to activate it:
 *     cp scripts/proposed/stop-guard.js .claude/hooks/stop-guard.js
 * No settings.json change is needed — the Stop/SubagentStop hooks already point at
 * .claude/hooks/stop-guard.js.
 *
 * What it adds over the current hook: the existing hook only enforces that
 * agent-runs.log is fresh. This ALSO enforces that PIPELINE_STATE.md's
 * `next_command:` field is non-empty — closing the "appended a run line but left
 * next_command stale" gap that ate manual reconcile time.
 *
 * NOTE: an earlier draft also blocked when agent-runs.log was newer than
 * PIPELINE_STATE.md by >90s. That mtime-direction check was DROPPED: the two files
 * are legitimately edited minutes-to-hours apart (a subagent appends to the run log
 * while the orchestrator owns PIPELINE_STATE.md; humans backfill the log), so it
 * false-blocked in normal operation. The next_command check below catches the real
 * "pointer left stale" gap without the mtime race.
 * ============================================================================ */
const fs = require('fs'), path = require('path');

let raw = '';
process.stdin.on('data', d => raw += d);
process.stdin.on('end', () => {
  let input = {};
  try { input = JSON.parse(raw); } catch {}
  if (input.stop_hook_active) process.exit(0); // already continued once — don't loop

  const block = (msg) => { console.error(msg); process.exit(2); };
  const stat = (p) => { try { return fs.statSync(p).mtimeMs; } catch { return 0; } };

  // Newest work artifact across the pipeline dirs.
  const MON = ['01-discovery', '02-build', '03-qa', '04-confirmations', 'force-app'];
  let newest = { file: null, m: 0 };
  const walk = (dir) => {
    let entries; try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
    for (const e of entries) {
      if (e.name === 'node_modules' || e.name === '.git' || e.name === '.gitkeep') continue;
      const p = path.join(dir, e.name);
      if (e.isDirectory()) walk(p);
      else { const m = stat(p); if (m > newest.m) newest = { file: p, m }; }
    }
  };
  MON.forEach(d => walk(d));

  const logM = stat('.claude/logs/agent-runs.log');

  // (1) existing rule: work newer than the run log => bookkeeping is stale.
  if (newest.m > logM + 90_000) {
    block(
      'GUARDRAIL: bookkeeping is stale. "' + newest.file + '" is newer than the last entry in ' +
      '.claude/logs/agent-runs.log. Before finishing: (1) append your run line to ' +
      '.claude/logs/agent-runs.log per rules/30 §4; (2) append a PIPELINE_STATE.md log line if a ' +
      'work item completed or phase changed; (3) append a jira-log.md status line for any ticket ' +
      'whose status changed; (4) ensure every D-###/A-### you cited exists in .claude/memory/. ' +
      'If the file change was a human edit, append a "human" line to agent-runs.log noting it.');
  }

  // (2) NEW: next_command must always name the next action.
  const state = (() => { try { return fs.readFileSync('PIPELINE_STATE.md', 'utf8'); } catch { return ''; } })();
  const nextCmd = (state.match(/^next_command:\s*(.*)$/m) || [])[1];
  if (state && (nextCmd === undefined || nextCmd.trim() === '' || /^(none|tbd|-)$/i.test(nextCmd.trim()))) {
    block(
      'GUARDRAIL: PIPELINE_STATE.md `next_command:` is empty/none. Set it to the concrete next ' +
      'command (e.g. /qa-run B, /advance, /retro) so the next session knows where to resume.');
  }

  process.exit(0);
});
