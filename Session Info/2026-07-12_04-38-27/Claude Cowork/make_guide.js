const {
  Document, Packer, Paragraph, TextRun, HeadingLevel, Table, TableRow, TableCell,
  WidthType, BorderStyle, AlignmentType, ShadingType, LevelFormat, TableOfContents, PageBreak
} = require('docx');
const fs = require('fs');

const FONT = 'Calibri';
const MONO = 'Consolas';
const ACCENT = '1F4E79';
const LIGHT = 'DEEAF6';

const p = (text, opts = {}) => new Paragraph({
  spacing: { after: 120 },
  children: [new TextRun({ text, font: FONT, size: 22, ...opts })],
});
const rich = (runs) => new Paragraph({
  spacing: { after: 120 },
  children: runs.map(r => new TextRun({ font: FONT, size: 22, ...r })),
});
const h1 = (t) => new Paragraph({ heading: HeadingLevel.HEADING_1, spacing: { before: 320, after: 160 }, children: [new TextRun({ text: t, font: FONT })] });
const h2 = (t) => new Paragraph({ heading: HeadingLevel.HEADING_2, spacing: { before: 240, after: 120 }, children: [new TextRun({ text: t, font: FONT })] });
const h3 = (t) => new Paragraph({ heading: HeadingLevel.HEADING_3, spacing: { before: 200, after: 100 }, children: [new TextRun({ text: t, font: FONT })] });
const mono = (t) => new Paragraph({
  spacing: { after: 0 },
  shading: { type: ShadingType.CLEAR, fill: 'F2F2F2' },
  children: [new TextRun({ text: t, font: MONO, size: 18 })],
});
const bullet = (t, bold0) => new Paragraph({
  numbering: { reference: 'bullets', level: 0 },
  spacing: { after: 80 },
  children: Array.isArray(t)
    ? t.map(r => new TextRun({ font: FONT, size: 22, ...r }))
    : [new TextRun({ text: t, font: FONT, size: 22 })],
});
const num = (t) => new Paragraph({
  numbering: { reference: 'steps', level: 0 },
  spacing: { after: 80 },
  children: Array.isArray(t)
    ? t.map(r => new TextRun({ font: FONT, size: 22, ...r }))
    : [new TextRun({ text: t, font: FONT, size: 22 })],
});

function table(headers, rows, widths) {
  const total = widths.reduce((a, b) => a + b, 0);
  const mk = (text, isHead) => new TableCell({
    width: { size: 0, type: WidthType.AUTO },
    shading: isHead ? { type: ShadingType.CLEAR, fill: ACCENT } : undefined,
    margins: { top: 60, bottom: 60, left: 100, right: 100 },
    children: [new Paragraph({
      spacing: { after: 0 },
      children: [new TextRun({ text, font: FONT, size: 19, bold: isHead, color: isHead ? 'FFFFFF' : '000000' })],
    })],
  });
  return new Table({
    width: { size: total, type: WidthType.DXA },
    columnWidths: widths,
    rows: [
      new TableRow({ tableHeader: true, children: headers.map((h, i) => { const c = mk(h, true); c.options = {}; return c; }) }),
      ...rows.map((r, ri) => new TableRow({
        children: r.map((cell, ci) => new TableCell({
          width: { size: widths[ci], type: WidthType.DXA },
          shading: ri % 2 === 1 ? { type: ShadingType.CLEAR, fill: 'F7F9FC' } : undefined,
          margins: { top: 60, bottom: 60, left: 100, right: 100 },
          children: [new Paragraph({
            spacing: { after: 0 },
            children: [new TextRun({ text: String(cell), font: FONT, size: 19 })],
          })],
        })),
      })),
    ],
  });
}
// header cells need explicit width too
function tbl(headers, rows, widths) {
  const head = new TableRow({
    tableHeader: true,
    children: headers.map((h, i) => new TableCell({
      width: { size: widths[i], type: WidthType.DXA },
      shading: { type: ShadingType.CLEAR, fill: ACCENT },
      margins: { top: 60, bottom: 60, left: 100, right: 100 },
      children: [new Paragraph({ spacing: { after: 0 }, children: [new TextRun({ text: h, font: FONT, size: 19, bold: true, color: 'FFFFFF' })] })],
    })),
  });
  const body = rows.map((r, ri) => new TableRow({
    children: r.map((cell, ci) => new TableCell({
      width: { size: widths[ci], type: WidthType.DXA },
      shading: ri % 2 === 1 ? { type: ShadingType.CLEAR, fill: 'F7F9FC' } : undefined,
      margins: { top: 60, bottom: 60, left: 100, right: 100 },
      children: [new Paragraph({ spacing: { after: 0 }, children: [new TextRun({ text: String(cell), font: FONT, size: 19 })] })],
    })),
  }));
  return new Table({ width: { size: widths.reduce((a, b) => a + b, 0), type: WidthType.DXA }, columnWidths: widths, rows: [head, ...body] });
}

const children = [];

// ===== Title =====
children.push(new Paragraph({
  spacing: { before: 2400, after: 200 }, alignment: AlignmentType.CENTER,
  children: [new TextRun({ text: 'AI-Assisted Salesforce Delivery Pipeline', font: FONT, size: 56, bold: true, color: ACCENT })],
}));
children.push(new Paragraph({
  spacing: { after: 200 }, alignment: AlignmentType.CENTER,
  children: [new TextRun({ text: 'Workspace & Operations Guide', font: FONT, size: 32, color: '444444' })],
}));
children.push(new Paragraph({
  spacing: { after: 100 }, alignment: AlignmentType.CENTER,
  children: [new TextRun({ text: 'Project: Citizen Appointment & Vaccination Scheduling System (RFP/DHS/2026/014)', font: FONT, size: 22 })],
}));
children.push(new Paragraph({
  spacing: { after: 2000 }, alignment: AlignmentType.CENTER,
  children: [new TextRun({ text: 'Pilot feature F-001 slot-booking-core  ·  Version 2.0  ·  11 July 2026', font: FONT, size: 20, color: '666666' })],
}));
children.push(new Paragraph({ children: [new PageBreak()] }));

// ===== TOC =====
children.push(h1('Contents'));
children.push(new TableOfContents('Contents', { hyperlink: true, headingStyleRange: '1-2' }));
children.push(new Paragraph({ children: [new PageBreak()] }));

// ===== 1. What this workspace is =====
children.push(h1('1. What This Workspace Is'));
children.push(p('This VS Code project is a proof-of-concept agentic delivery pipeline run through Claude Code. It mirrors a real Salesforce delivery team — BA, Architect, PM, two developer tiers, QA Lead, QA Engineers — as seven AI subagents that hand work to each other through files, while a human approves every phase transition. The pilot runs one feature (appointment slot booking) from raw client documents to a QA-verified, deployable state.'));
children.push(p('Three principles govern everything:'));
children.push(bullet([{ text: 'The state file is the spine. ', bold: true }, { text: 'PIPELINE_STATE.md holds a YAML block that is the single machine-readable truth about which phase feature F-001 is in. Every agent reads it before acting and may advance it at most one step.' }]));
children.push(bullet([{ text: 'Humans hold the gates. ', bold: true }, { text: 'Four transitions (start build, end build, confirm design, release) can only be approved by a human via /advance. Agents propose; people decide.' }]));
children.push(bullet([{ text: 'Everything is graded. ', bold: true }, { text: 'The five documents in 00-inputs/ contain intentional gaps and contradictions. ANSWER-KEY-intentional-gaps.md (root, blocked from every agent) lets you grade whether the BA agent caught them.' }]));
children.push(p('The phase machine:'));
children.push(mono('NOT_STARTED → DISCOVERY → ARCH_DESIGN → SPRINT_PLANNED → DEV_IN_PROGRESS'));
children.push(mono('→ DEV_COMPLETE → BA_ARCH_CONFIRM → READY_FOR_QA → QA_IN_PROGRESS → DONE'));
children.push(new Paragraph({ spacing: { after: 120 }, children: [] }));
children.push(rich([{ text: 'Human gates: ', bold: true }, { text: 'SPRINT_PLANNED→DEV_IN_PROGRESS · DEV_COMPLETE→BA_ARCH_CONFIRM · BA_ARCH_CONFIRM→READY_FOR_QA · QA_IN_PROGRESS→DONE', font: MONO, size: 19 }]));

// ===== 2. Folder structure =====
children.push(h1('2. VS Code Folder Structure'));
children.push(p('The pipeline lives at the root of the existing SFDX project, so the same window serves Salesforce development and the agentic workflow.'));
const tree = [
'Agentic Workflows/                    ← open THIS folder in VS Code',
'├── CLAUDE.md                         ← project memory, auto-loaded by Claude Code',
'├── PIPELINE_STATE.md                 ← phase state machine + audit log',
'├── ANSWER-KEY-intentional-gaps.md    ← your grading sheet (agents blocked)',
'├── README.md                         ← SFDX readme + pipeline how-to-run',
'├── .claude/',
'│   ├── agents/        9 role subagents (BA → QA + code reviewer + devops)',
'│   ├── commands/      15 slash commands (with enforced postconditions)',
'│   ├── rules/         5 binding rulebooks',
'│   ├── skills/        8 how-to skills (formats, patterns, best practices)',
'│   ├── memory/        decisions, assumptions, glossary, handoffs',
'│   ├── logs/          agent-runs.log (append-only audit)',
'│   ├── hooks/         pretool-guard.js + stop-guard.js (deterministic law)',
'│   └── settings.json  permission denies + hook wiring',
'├── 00-inputs/         five immutable client documents',
'├── 01-discovery/      BA + Architect outputs (brief, OQs, design, ERD)',
'├── 02-build/          sprint plan, jira log, review packets,',
'│                      deployments.md (deploy ledger), runbook.md (pre/post/manual steps)',
'├── 03-qa/             test plan, regression specs, bugs, evidence',
'├── 04-confirmations/  drift-check sign-offs',
'├── force-app/         Salesforce source (VS_-prefixed metadata)',
'├── config/            project-scratch-def.json (Vaccine Scheduler POC)',
'├── scripts/           org-setup.sh, health-check.js, seed-data/, apex/, soql/',
'├── manifest/          package.xml (generated) + deltas/VS-##-package.xml per ticket',
'├── .gitattributes     union-merge for append-only files (parallel lanes)',
'└── retro/             poc-learnings.md (BA grading scorecard recorded)',
];
tree.forEach(l => children.push(mono(l)));
children.push(new Paragraph({ spacing: { after: 120 }, children: [] }));
children.push(h2('2.1 What each folder is for'));
children.push(tbl(
  ['Folder', 'Purpose', 'Who writes'],
  [
    ['00-inputs/', 'RFP, workshop notes, current-state, personas, Annexure C. The fixed exam paper — contains deliberate gaps.', 'Nobody, ever'],
    ['01-discovery/', 'requirements-brief.md, open-questions.md (BA); technical-design.md, erd/ (Architect).', 'ba-analyst, architect'],
    ['02-build/', 'sprint-plan.md + jira-log.md (PM); review-notes/VS-##-review.md (developers).', 'pm-planner, dev-senior, dev-mid'],
    ['03-qa/', 'test-plan.md (QA Lead); regression/*.spec.ts, bug-reports/BUG-###.md, evidence/*.png (QA Engineer).', 'qa-lead, qa-engineer'],
    ['04-confirmations/', 'F-001-drift-check.md — the Architect’s as-built vs design verdict before QA.', 'architect'],
    ['force-app/', 'Real Salesforce metadata: Apex, LWC, Flows, objects. Draft code for human review.', 'dev-senior, dev-mid'],
    ['.claude/memory/', 'Cross-phase shared brain: D-### decisions, A-### assumptions, glossary, handoff notes.', 'Every agent (append-only)'],
    ['.claude/logs/', 'agent-runs.log — one line per agent run; /status reads the tail.', 'Every agent (append-only)'],
    ['retro/', 'poc-learnings.md — what each agent got wrong; the go/no-go evidence.', 'Human + /retro'],
  ],
  [1700, 5600, 2000]
));

// ===== 3. Agents =====
children.push(new Paragraph({ children: [new PageBreak()] }));
children.push(h1('3. The Agents (.claude/agents/)'));
children.push(p('Each agent is a Markdown file with YAML frontmatter (name, description, tools, model) followed by its role instructions. Claude Code auto-discovers them; commands launch them. Every agent carries the same hard rules: read PIPELINE_STATE.md first and act only in its own phase, never touch 00-inputs/, never read the answer key, advance the phase at most one step, and log every run.'));
children.push(tbl(
  ['Agent', 'Real-world role', 'Works in phase', 'Model', 'Tools'],
  [
    ['ba-analyst', 'Business Analyst', 'DISCOVERY', 'opus', 'Read, Write, Grep, Glob'],
    ['architect', 'Solution Architect', 'ARCH_DESIGN + BA_ARCH_CONFIRM', 'opus', '+ Bash'],
    ['pm-planner', 'Project Manager', 'SPRINT_PLANNED', 'sonnet', 'Read, Write, Grep, Glob'],
    ['dev-senior', 'Senior Developer', 'DEV_IN_PROGRESS', 'opus', '+ Edit, Bash (sf CLI)'],
    ['dev-mid', 'Mid-level Developer', 'DEV_IN_PROGRESS', 'sonnet', '+ Edit, Bash (sf CLI)'],
    ['code-reviewer', 'Independent Code Reviewer', 'DEV_IN_PROGRESS / DEV_COMPLETE', 'opus', 'Read, Grep, Glob, Bash (no Write/Edit)'],
    ['devops', 'DevOps Engineer', 'DEV_IN_PROGRESS → QA', 'sonnet', 'Read, Write, Grep, Glob, Bash'],
    ['qa-lead', 'QA Lead', 'READY_FOR_QA / QA_IN_PROGRESS', 'sonnet', 'Read, Write, Grep, Glob'],
    ['qa-engineer', 'QA Engineer', 'QA_IN_PROGRESS', 'sonnet', '+ Edit, Bash, Playwright'],
  ],
  [1450, 1900, 2500, 950, 2500]
));
children.push(h2('3.1 ba-analyst — the graded one'));
children.push(p('Reads all five input documents and produces the requirements brief (REQ-### register with MoSCoW priority and source traceability) plus the open-questions register (OQ-###). Its core discipline: never invent a decision the client did not make. Contradictions, unverified figures, external dependencies, and silent gaps each get their own section. This output is what you grade against the answer key.'));
children.push(h2('3.2 architect — two modes'));
children.push(p('Design mode (ARCH_DESIGN): turns the brief into technical-design.md — VS_-prefixed data model, Mermaid ERD, the RFP §3.4 slot-integrity locking strategy, automation matrix, Annexure C compliance mapping, and EP-## epics. Drift-check mode (BA_ARCH_CONFIRM): after the build, re-reads force-app/ and issues a verdict per design element (MATCHES / DEVIATES-ACCEPTABLE / DEVIATES-MUST-FIX) with a go/no-go for QA. It designs; it never writes code.'));
children.push(h2('3.3 pm-planner — the only ticket authority'));
children.push(p('Decomposes the design into ~1-week sprints of VS-## tickets with Given/When/Then acceptance criteria, complexity-routed to dev-senior or dev-mid by rubric. Prints a REQ→ticket coverage table so uncovered Musts are visible. Mirrors to Jira when the Atlassian MCP is connected; otherwise jira-log.md is the source of truth. Never blocks on Jira.'));
children.push(h2('3.4 dev-senior — the hard tickets'));
children.push(p('Booking service layer, the FOR UPDATE slot lock (an overbooked slot is acceptance failure), async jobs, LWCs. One ticket at a time; writes Apex tests to ≥85% coverage including a capacity-exhaustion test; validates with sf deploy --dry-run; produces a review packet per ticket telling the human reviewer exactly what to scrutinize.'));
children.push(h2('3.5 dev-mid — declarative first'));
children.push(p('Flows (reminders, no-show marking), object metadata, validation rules, permission sets. Hard rule: if a ticket turns out to genuinely need complex Apex, it stops and flags for re-routing rather than attempting it. Every field gets a description; every flow gets fault paths.'));
children.push(h2('3.6 code-reviewer — independence by construction'));
children.push(p('Reviews each ticket\'s implementation before the human verdict. Its toolset deliberately excludes Write/Edit: it can read everything and run tests (sf apex run test), but can never fix code — so it has no stake in waving work through. Checks in priority order: correctness against the ticket\'s acceptance criteria; the §3.4 integrity path with hostile thinking ("how would I overbook this?", including unlocked paths around the service layer); security (sharing, CRUD/FLS, injection); compliance (no Aadhaar, C1-only fields, facility scoping); standards and the best-practice skills; and test quality, not just coverage numbers. Output: VS-##-code-review.md with findings ranked BLOCKER/MAJOR/MINOR/NIT, each with file:line evidence, ending in APPROVE or REQUEST-CHANGES. Zero findings is a legitimate outcome — it is instructed not to manufacture nits.'));
children.push(h2('3.7 devops — the deployment bookkeeper'));
children.push(p('Owns everything between "code approved" and "provably in the org." The POC targets a Developer Edition org with no source tracking, so the devops agent\'s records ARE the deployment state: manifests always generated from source (full manifest/package.xml plus a delta manifest per ticket in manifest/deltas/), every deploy dry-run validated and recorded in the append-only 02-build/deployments.md ledger (deploy ID, tests, result), every failure logged in its Errors & resolutions table with root cause and a recurrence marker. It also owns 02-build/runbook.md — pre-deploy, post-deploy, and manual-only steps per ticket, sourced from the "Manual / setup steps" section every developer packet must now include; a deploy is not DONE until its post-steps are checked off. Deploy execution is human-gated: the agent prepares and validates freely, runs the actual command only after your explicit yes, and can also run an org-vs-source drift check on demand.'));
children.push(h2('3.8 qa-lead — risk over coverage theatre'));
children.push(p('Turns design + tickets + drift-check into a risk-tiered test plan: Tier 1 (slot integrity, cut-off policy, no-Aadhaar, role visibility) runs first and blocks release. Splits scope into run A / run B for the engineers. At close-out, consolidates results into a GO / NO-GO recommendation.'));
children.push(h2('3.9 qa-engineer — hands on the browser'));
children.push(p('Executes assigned TC ranges against the scratch org through Playwright: evidence screenshot per test, a runnable regression spec per stable test, and a BUG-### report per failure with exact repro steps. Never marks PASS without evidence; synthetic data only.'));

// ===== 4. Model strategy =====
children.push(h1('4. Model Strategy (token optimization)'));
children.push(p('Each agent pins a model in its frontmatter, so expensive reasoning is bought only where an error cascades downstream. Rule of thumb: Opus where mistakes multiply (analysis, architecture, concurrency-critical code, and the review that must catch their errors), Sonnet where a skill or rubric already constrains the work, Haiku reserved for future mechanical helpers — none of the nine roles is safely mechanical.'));
children.push(tbl(
  ['Agent', 'Model', 'Why this tier'],
  [
    ['ba-analyst', 'opus', 'Runs once or twice; the whole POC is graded on its analysis. An uncaught gap poisons design, tickets, code, and tests.'],
    ['architect', 'opus', 'Data model + §3.4 locking design + drift check. Architecture errors are the most expensive to discover late.'],
    ['dev-senior', 'opus', 'Race conditions and governor limits are subtle; the concurrency test is pass/fail at acceptance.'],
    ['code-reviewer', 'opus', 'The last line of defense before human sign-off; a missed race condition or compliance hole costs far more than the tokens.'],
    ['devops', 'sonnet', 'Procedural, evidence-based work: generate manifest, validate, record. The rigor lives in the ledger format, not the model.'],
    ['pm-planner', 'sonnet', 'Structured decomposition against an explicit ticket format and routing rubric.'],
    ['dev-mid', 'sonnet', 'High token volume (metadata XML, Flows) where format discipline matters more than deep reasoning.'],
    ['qa-lead', 'sonnet', 'Plan derives mechanically from design + risk tiers already defined in rules.'],
    ['qa-engineer', 'sonnet', 'Highest token consumer (browser loops, spec files); guided execution, not open-ended reasoning.'],
  ],
  [1500, 1000, 6800]
));
children.push(p('Two further savings are structural: subagents run in isolated contexts (they load only the files they need, not your whole conversation), and skills/rules are read from disk per run instead of living in every prompt. To change a tier, edit the model: line in the agent file — opus, sonnet, haiku, or inherit (follows your main session).'));

// ===== 5. Commands =====
children.push(new Paragraph({ children: [new PageBreak()] }));
children.push(h1('5. Commands — How and When to Use Each'));
children.push(p('Commands are the only way work should be triggered. They check the phase before acting, launch the right agent, and print what happened. Run them inside Claude Code from the project root.'));
children.push(h2('5.1 Quick reference'));
children.push(tbl(
  ['Command', 'Phase it requires', 'What it does'],
  [
    ['/kickoff', 'NOT_STARTED', 'Verifies inputs exist, sets DISCOVERY, runs ba-analyst'],
    ['/status', 'any', 'Prints state YAML, recent log lines, artifact counts, next command'],
    ['/advance', 'any', 'Proposes the single next transition; waits for human approval'],
    ['/ba-analyze', 'DISCOVERY', 'Runs/refreshes the requirements brief + open questions'],
    ['/arch-design', 'ARCH_DESIGN', 'Runs the Architect in design mode (design doc + ERD + epics)'],
    ['/pm-plan', 'SPRINT_PLANNED', 'Runs the PM: sprints, tickets, routing, coverage table'],
    ['/dev-implement VS-##', 'DEV_IN_PROGRESS', 'Routes the ticket to dev-senior or dev-mid and builds it'],
    ['/dev-review VS-##', 'DEV_IN_PROGRESS/COMPLETE', 'Runs the code-reviewer agent, presents its findings, records your verdict'],
    ['/arch-confirm', 'BA_ARCH_CONFIRM', 'Architect drift check: as-built vs design, go/no-go'],
    ['/qa-plan', 'READY_FOR_QA', 'QA Lead builds the risk-tiered test plan + scope split'],
    ['/qa-run A|B', 'QA_IN_PROGRESS', 'QA Engineer executes a TC range via Playwright'],
    ['/qa-report', 'QA_IN_PROGRESS', 'QA Lead consolidates results into GO / NO-GO'],
    ['/deploy VS-##|sprint-1|drift-check', 'DEV_IN_PROGRESS+', 'DevOps: delta manifest, dry-run validate, human-approved execute, record in the ledger'],
    ['/health', 'any', 'Runs scripts/health-check.js — deterministic invariant check, verbatim output'],
    ['/lane setup|A|B|merge|status', 'DEV_IN_PROGRESS', 'Parallel dev lanes via git worktrees (built, currently dormant)'],
    ['/retro', 'DONE', 'Fills retro/poc-learnings.md; only now compare the answer key'],
  ],
  [2300, 2500, 4500]
));
children.push(p('Every work command ends with a mandatory FINAL VERIFICATION block: the expected output files exist, a run line was appended to agent-runs.log, PIPELINE_STATE.md and jira-log.md got their entries, and every D-###/A-### cited in outputs actually exists in memory. A command may not declare success until that checklist passes — added after the first sprint showed agents reliably doing the product work and reliably skipping the bookkeeping.'));
children.push(h2('5.2 When to reach for which'));
children.push(bullet([{ text: '/kickoff — once, at the very start. ', bold: true }, { text: 'It is the only command that works from NOT_STARTED. If it refuses, an input document is missing.' }]));
children.push(bullet([{ text: '/status — whenever you return to the project. ', bold: true }, { text: 'Safe at any time, changes nothing, always ends by telling you the exact next command.' }]));
children.push(bullet([{ text: '/advance — at every phase boundary. ', bold: true }, { text: 'It never chains steps. At the four human gates it will explicitly wait for your yes. If you feel lost, /status then /advance is always the safe pair.' }]));
children.push(bullet([{ text: '/ba-analyze — rarely after kickoff. ', bold: true }, { text: 'Use it to re-run discovery after you tighten the BA’s instructions, or scope a pass ("/ba-analyze compliance only").' }]));
children.push(bullet([{ text: '/arch-design — once per design cycle. ', bold: true }, { text: 'Re-run with an argument to rework one aspect: /arch-design slot integrity.' }]));
children.push(bullet([{ text: '/pm-plan — after design sign-off. ', bold: true }, { text: 'Re-planning mid-build requires the explicit argument "replan" plus a reason, so scope changes leave a trail.' }]));
children.push(bullet([{ text: '/dev-implement — your main loop during the build. ', bold: true }, { text: 'Run it with no argument to list open tickets in dependency order; with VS-## to build one. Routing is decided by the plan, never by the command.' }]));
children.push(bullet([{ text: '/dev-review — after each ticket, before the next. ', bold: true }, { text: 'The code-reviewer agent (Opus, read-only by design) does the deep pass first — AC verification, §3.4 hostile review, security, compliance, test quality — and hands you severity-ranked findings with file:line evidence. You stay in charge: APPROVED or CHANGES-REQUESTED goes into the packet and the ticket log. A §3.4 BLOCKER is echoed to the handoff notes so drift check and QA inherit it.' }]));
children.push(bullet([{ text: '/arch-confirm — once, after the build gate. ', bold: true }, { text: 'Any DEVIATES-MUST-FIX verdict sends tickets back to /dev-implement before QA can be approved.' }]));
children.push(bullet([{ text: '/qa-plan → /qa-run A → /qa-run B → /qa-report — the QA cycle. ', bold: true }, { text: 'Bugs found route back to /dev-implement; re-test, then /qa-report again until GO.' }]));
children.push(bullet([{ text: '/deploy — after each approved review. ', bold: true }, { text: 'Prepare + validate is free; the actual deploy waits for your explicit yes, then lands in deployments.md with its runbook steps. Use "/deploy drift-check" any time you suspect someone clicked something directly in Setup.' }]));
children.push(bullet([{ text: '/health — any time, free. ', bold: true }, { text: 'Deterministic PASS/WARN/FAIL against the pipeline invariants. If /status and /health disagree, believe /health.' }]));
children.push(bullet([{ text: '/retro — after DONE. ', bold: true }, { text: 'The only moment the answer key enters the conversation — and even then, you paste the comparison, the agent never reads the key. The Discovery scorecard (11+2 partial+1 missed of 14 planted gaps — pass) is already recorded.' }]));
children.push(h2('5.3 The happy-path run, end to end'));
['/kickoff — BA produces brief + open questions (grade this against the answer key)',
 '/advance — approve DISCOVERY → ARCH_DESIGN, then /arch-design',
 '/advance — approve design → SPRINT_PLANNED, then /pm-plan',
 '/advance — HUMAN GATE: approve build start → DEV_IN_PROGRESS',
 '/dev-implement VS-01 … VS-nn, with /dev-review after each (code-reviewer pass + your verdict), then /deploy VS-## on approval',
 '/advance — HUMAN GATE: declare DEV_COMPLETE → BA_ARCH_CONFIRM, then /arch-confirm',
 '/advance — HUMAN GATE: drift-check go → READY_FOR_QA, then /qa-plan',
 '/qa-run A and /qa-run B, fix bugs via /dev-implement, then /qa-report',
 '/advance — HUMAN GATE: GO → DONE, then /retro',
].forEach(s => children.push(num(s)));

// ===== 6. Rules =====
children.push(new Paragraph({ children: [new PageBreak()] }));
children.push(h1('6. Rules (.claude/rules/)'));
children.push(p('Rules are binding for every agent; agents are instructed to read them before acting, and CLAUDE.md re-enforces them at session start.'));
children.push(tbl(
  ['Rulebook', 'What it governs'],
  [
    ['00-pipeline-rules.md', 'The state machine and the four human gates; the write-access matrix (which agent may write to which folder); the REQ→EP→VS→TC→BUG traceability chain; QA risk tiers; honesty rules (never claim an unrun command succeeded; ambiguity becomes an open question, never a silent choice).'],
    ['10-compliance-rules.md', 'Annexure C distilled into nine enforceable rules: no Aadhaar anywhere (including test data and logs), data minimization, synthetic data only in dev/test, India residency, retention classes, facility-scoped access with audit, WCAG 2.1 AA as testable requirements, DLT-registered SMS behind a replaceable interface, chat-assistant guardrails.'],
    ['20-salesforce-standards.md', 'VS_ naming for all metadata; service-layer Apex with one trigger per object; the mandatory FOR UPDATE lock for slot booking; bulkification; with sharing + CRUD/FLS; custom metadata for tunables; ≥85% test coverage with meaningful asserts; declarative-first for dev-mid; deploy/verify loop against the POC scratch org only.'],
    ['30-documentation-rules.md', 'Header block on every artifact; the ID schemes (REQ, OQ, D, EP, VS, TC, BUG, A); memory discipline (when to write a decision vs assumption vs glossary entry vs handoff note); the agent-runs.log line format; PIPELINE_STATE.md edit discipline.'],
    ['40-parallel-lanes.md', 'Dormant until /lane setup runs: two build sessions in git worktrees — Lane A (dev-senior tickets, owns the phase YAML, primary) and Lane B (dev-mid tickets, appends only). Static ticket assignment, cross-lane dependencies wait for merge, union-merge .gitattributes keeps append-only files conflict-free, /deploy only from merged main.'],
  ],
  [2300, 7000]
));

// ===== 7. Skills =====
children.push(h1('7. Skills (.claude/skills/)'));
children.push(p('Skills are how-to knowledge — output formats, technical patterns, and development best practices — loaded by the agent that needs them, when it needs them. This keeps agent prompts short and output formats consistent. Rules stay binding law; skills are craft: on any conflict, rules/20 wins. To add your own standards later, drop a reference file into the matching skill folder and add one pointer line in its SKILL.md.'));
children.push(tbl(
  ['Skill', 'Used by', 'What it teaches'],
  [
    ['requirements-brief', 'ba-analyst', 'Brief structure (REQ register per capability area, MoSCoW, source traceability); rules of evidence ("felt right in the room" is Should at most); open-questions register with dedicated sections for contradictions, unverified figures, dependencies, and silent gaps.'],
    ['sf-data-model', 'architect', 'Design-doc structure; expected domain shape (Citizen, Facility, Slot, Appointment, Vaccination Event, Vial/Stock…); booker ≠ patient modelling; Mermaid ERD conventions; retention class per object.'],
    ['jira-tickets', 'pm-planner', 'Ticket format with Given/When/Then AC; the senior/mid routing rubric ("if a race condition, governor limit, or callout can ruin it → senior"); sprint sequencing; jira-log.md as append-only history.'],
    ['sf-apex-patterns', 'dev-senior, dev-mid, code-reviewer', 'The VS_BookingService FOR UPDATE pattern with code and why it passes §3.4; trigger→handler→service shape; idempotent async; SMS provider interface; capacity-exhaustion test pattern. Plus references/apex-best-practices.md: trigger handler pattern with recursion guards, bulkification and governor limits, error handling with message codes, security (USER_MODE, sharing, injection), Queueable/Finalizer patterns, test discipline (runAs per persona, negative paths).'],
    ['lwc-slds2', 'dev-senior, dev-mid, code-reviewer', 'LWC best practices across HTML (semantics, lwc:if, stable keys), JS (@api down / events up, debounce, disable-while-in-flight, no hardcoded copy, data-testid for QA) and CSS. SLDS 2 rules: style with global --slds-g-* styling hooks only; design tokens and --slds-c-* hooks are dead; never override base-component internals; slds-linter before review. WCAG 2.1 AA, one-thumb targets, 3G-friendly loading.'],
    ['flow-patterns', 'dev-mid, architect, code-reviewer', 'When to use which flow type; the Apex-vs-Flow boundary (one owner per business rule — booking stays in Apex because of the lock); bulk-safe structure (no DML in loops); mandatory fault paths into the shared error log; VS_ flow naming; flow tests; deploy-active policy for the POC.'],
    ['playwright-sf-testing', 'qa-engineer', 'Login via sf org open --url-only + storageState (never script real credentials); selector strategy for Lightning DOM; spec structure with evidence; the two-browser concurrency test for §3.4; accessibility checks with axe.'],
    ['bug-reports', 'qa-engineer', 'BUG-### file format; severity rubric (Sev-1 = integrity/compliance broken, release-blocking); one defect per report; regression tagging.'],
  ],
  [2100, 1700, 5500]
));

// ===== 8. Memory & logs =====
children.push(h1('8. Memory & Logs'));
children.push(p('Memory is the pipeline’s shared brain across phases; logs are its audit trail. Both are append-only.'));
children.push(tbl(
  ['File', 'What lives there', 'Example already seeded'],
  [
    ['memory/decisions.md', 'D-### decisions that constrain later work: decider, rationale, alternatives rejected. Corrections supersede, never edit.', 'D-003: 00-inputs are immutable; gaps stay until retro'],
    ['memory/assumptions.md', 'A-### anything treated as true without client confirmation, with owner and impact-if-wrong.', 'A-001: 60/40 smartphone split (⚠ unverified)'],
    ['memory/glossary.md', 'Domain terms every agent must use consistently.', 'ASHA worker, DLT template, open-vial decision, walk-in reserve'],
    ['memory/handoffs.md', '5-line note at each phase end: produced / least sure about / must not miss / open items / where my notes are.', '(fills as phases complete)'],
    ['logs/agent-runs.log', 'One line per run: time, agent, command, phase, inputs read, outputs written, result OK/PARTIAL/BLOCKED.', 'Seeded with the scaffold entry'],
  ],
  [2200, 4600, 2500]
));
// ===== 9. Guardrails & Enforcement =====
children.push(h1('9. Guardrails & Enforcement (the layered stack)'));
children.push(p('The system\'s central design lesson so far: prompts are advice, permissions are policy, hooks are law. Five layers, softest to hardest — each catches what the layer above lets through.'));
children.push(tbl(
  ['Layer', 'Mechanism', 'What it stops'],
  [
    ['1. Prompt rules', 'Hard rules in every agent + the write-access matrix in rules/00', 'Most mistakes, most of the time — but ultimately advisory'],
    ['2. Structural limits', 'Per-agent tool lists (code-reviewer has no Write/Edit; qa-lead has no Bash), model pinning, the four human gates', 'An agent cannot misuse a tool it does not have'],
    ['3. Permission denies', 'settings.json: no Read of the answer key; no Write to 00-inputs/, rules/, hooks/, or settings.json itself', 'File-tool access to protected paths — agents cannot edit the law or the enforcement'],
    ['4. PreToolUse hook', '.claude/hooks/pretool-guard.js runs before EVERY Bash/Write/Edit call, deterministically', 'Shell bypasses (cat/redirect on protected files), Aadhaar-like 12-digit values in any written content, git push, org deletion, hard resets, deploys to prod-looking targets'],
    ['5. Stop hooks', '.claude/hooks/stop-guard.js on Stop + SubagentStop', 'Finishing with stale bookkeeping: if work artifacts are newer than the last agent-runs.log entry, the agent is blocked from stopping until logs, jira-log lines, and cited memory IDs exist'],
  ],
  [1650, 3800, 3850]
));
children.push(p('Independent of all five: scripts/health-check.js, run via /health or /status, validates the whole invariant set from outside — phase-artifact consistency, packet-per-ticket, citation integrity (every cited D-###/A-### exists in memory), log freshness, and a no-Aadhaar scan over source and seed data. Deterministic PASS/WARN/FAIL with honest counts. Guardrails fail open on malformed input (a broken guardrail should never brick the session) and only a human editing the files directly can bypass them — which is the point.'));
children.push(h2('9.1 CLAUDE.md and settings.json'));
children.push(p('CLAUDE.md at the root is auto-loaded by Claude Code at session start — it carries the absolute constraints, the command map, and where everything lives, so even a conversation that never launches a subagent still obeys the pipeline. settings.json holds both the permission denies and the hook wiring. Note: hooks load at session start — after editing them, restart the Claude Code session.'));

// ===== 10. Day-to-day =====
children.push(h1('10. Operating the Pipeline Day-to-Day'));
children.push(p('Current position: Discovery, design, and sprint planning are complete and human-approved; the BA scored 11 clean + 2 partial + 1 missed against the 14-gap answer key (pass); 30 work items are imported to Jira (keys recorded in jira-log.md); the build is mid-Sprint-1 under DEV_IN_PROGRESS.'));
['Returning to the project: /status (includes the health check). If /health reports FAIL, fix the invariants before new work.',
 'Build loop: /dev-implement VS-## → /dev-review VS-## (code-reviewer findings + your verdict) → /deploy VS-## on approval → next ticket.',
 'Gates ahead: DEV_COMPLETE → /arch-confirm (drift check) → /qa-plan → /qa-run A and B → /qa-report → DONE → /retro. Each gate transition goes through /advance and waits for you.',
 'Jira stays file-first (D-004) until the Atlassian MCP is connected: claude mcp add --transport http atlassian https://mcp.atlassian.com/v1/mcp/authv2, then /mcp to sign in, then ask any session to mirror jira-log.md.',
 'Parallel lanes are built but dormant — /lane setup activates them when Sprint 2 warrants two build sessions (requires a clean git state; see rules/40).',
].forEach(s => children.push(num(s)));
children.push(p('From there, the pipeline itself tells you what to run next — and when in doubt, /health is never wrong.'));

const doc = new Document({
  styles: {
    default: { document: { run: { font: FONT, size: 22 } } },
    paragraphStyles: [
      { id: 'Heading1', name: 'Heading 1', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { size: 32, bold: true, color: ACCENT, font: FONT },
        paragraph: { spacing: { before: 320, after: 160 }, outlineLevel: 0 } },
      { id: 'Heading2', name: 'Heading 2', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { size: 26, bold: true, color: '2E74B5', font: FONT },
        paragraph: { spacing: { before: 240, after: 120 }, outlineLevel: 1 } },
      { id: 'Heading3', name: 'Heading 3', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { size: 23, bold: true, color: '404040', font: FONT },
        paragraph: { spacing: { before: 200, after: 100 }, outlineLevel: 2 } },
    ],
  },
  numbering: {
    config: [
      { reference: 'bullets', levels: [{ level: 0, format: LevelFormat.BULLET, text: '•', alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 480, hanging: 240 } } } }] },
      { reference: 'steps', levels: [{ level: 0, format: LevelFormat.DECIMAL, text: '%1.', alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 480, hanging: 300 } } } }] },
    ],
  },
  sections: [{ properties: {}, children }],
});

Packer.toBuffer(doc).then(buf => {
  fs.writeFileSync('/home/claude/PIPELINE-GUIDE.docx', buf);
  console.log('written', buf.length, 'bytes');
});
