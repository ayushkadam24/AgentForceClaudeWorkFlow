#!/usr/bin/env node
/* PreToolUse guard — deterministic guardrails for the vaccine-scheduler pipeline.
 * Reads the tool call as JSON on stdin. Exit 0 = allow, exit 2 = BLOCK (stderr -> agent).
 * This is law, not advice: it fires on every Bash/Write/Edit call by any agent. */

let raw = '';
process.stdin.on('data', d => raw += d);
process.stdin.on('end', () => {
  let input = {};
  try { input = JSON.parse(raw); } catch { process.exit(0); } // never break the session on parse issues

  const tool = input.tool_name || '';
  const ti = input.tool_input || {};
  const block = (msg) => { console.error('GUARDRAIL BLOCK: ' + msg); process.exit(2); };
  const norm = (s) => String(s || '').replace(/\\/g, '/').toLowerCase();

  // ---------- File tools: Write / Edit / MultiEdit / NotebookEdit ----------
  if (/^(Write|Edit|MultiEdit|NotebookEdit)$/.test(tool)) {
    const p = norm(ti.file_path || ti.notebook_path);

    const protectedPaths = [
      ['00-inputs/',                'client inputs are immutable (rules/00). Route changes through open-questions.md.'],
      ['answer-key-intentional-gaps', 'the answer key is grading material — no agent touches it.'],
      ['.claude/rules/',            'rules are law; agents do not edit law. A human changes rules deliberately.'],
      ['.claude/settings.json',     'permission config is human-owned.'],
      ['.claude/hooks/',            'guardrails cannot be edited by the thing they guard.'],
    ];
    for (const [frag, why] of protectedPaths) {
      if (p.includes(frag)) block(`write to "${frag}" refused — ${why}`);
    }

    // Aadhaar-like content scan (Annexure C1.2): 12-digit runs, incl. 4-4-4 grouping
    const content = String(ti.content || ti.new_string || '');
    const digitsy = content.replace(/[ -]/g, '');
    if (/(?<!\d)\d{12}(?!\d)/.test(digitsy) && !/force-app\/.*\/(staticresources)\//.test(p)) {
      block('content contains a 12-digit number that looks like an Aadhaar number. Annexure C1.2 forbids collecting/storing/transmitting Aadhaar anywhere, including test data. Use obviously-fake shorter identifiers.');
    }
  }

  // ---------- Bash ----------
  if (tool === 'Bash') {
    const cmd = ' ' + norm(ti.command) + ' ';

    // Reading or writing the answer key via shell (bypass of the Read deny)
    if (cmd.includes('answer-key-intentional-gaps'))
      block('shell access to the answer key is forbidden for all agents.');

    // Any write/redirect/copy/move/delete touching 00-inputs
    if (/00-inputs/.test(cmd) && /(>|>>|\brm\b|\bmv\b|\bcp\b.*00-inputs\/|\bsed -i\b|\btee\b|\bdel\b|\bmove\b|\bcopy\b .* 00-inputs)/.test(cmd))
      block('shell write into 00-inputs/ refused — client inputs are immutable.');

    // Destructive / irreversible operations
    const destructive = [
      [/\brm\s+-rf?\s+(\/|~|\.)\s*$/,        'recursive delete of a root path'],
      [/\bgit\s+push\s+.*(--force|-f)\b/,    'force push'],
      [/\bgit\s+push\b/,                     'pushing is a human action in this POC'],
      [/\bgit\s+reset\s+--hard\b/,           'hard reset discards work'],
      [/\bsf\s+org\s+delete\b/,              'org deletion is human-only'],
      [/\bsfdx?\s+force:org:delete\b/,       'org deletion is human-only'],
      [/\bsf\s+data\s+delete\b/,             'bulk data deletion is human-only'],
      [/\bsf\s+project\s+delete\b/,          'source deletion is human-only'],
    ];
    for (const [re, why] of destructive) {
      if (re.test(cmd)) block(`"${why}" — this operation requires a human at the keyboard.`);
    }

    // Deploys: only the POC scratch org, never a -o pointing at prod-looking targets
    if (/\bsf\s+project\s+deploy\b/.test(cmd) && /(-o|--target-org)\s+\S*(prod|prd|uat|staging)/.test(cmd))
      block('deploy target looks like a non-POC org. Agents deploy to the POC scratch org only (rules/20).');
  }

  process.exit(0);
});
