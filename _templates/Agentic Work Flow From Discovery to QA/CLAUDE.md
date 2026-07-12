# <PROJECT_NAME> — Project Memory (Discovery → Build → QA pipeline template)

AI-assisted Salesforce delivery pipeline (Discovery → Build → QA) for <CLIENT_SYSTEM_NAME>
(<RFP_REFERENCE>). Pilot feature: **F-001 <pilot-feature>**.
Nine role subagents in `.claude/agents/`; humans approve every gate.

> TEMPLATE: before `/kickoff`, complete `SETUP.md` (rename placeholder tokens, paste client
> documents into `00-inputs/`, set the metadata prefix, connect/confirm the POC org alias).

## Before doing ANYTHING
1. Read `PIPELINE_STATE.md` — the YAML block is the single source of truth for phase.
2. Read `.claude/rules/` (00-pipeline, 10-compliance, 20-salesforce-standards, 30-documentation, 40-parallel-lanes).
3. Work only within your role's write-access (matrix in rules/00) and only in your phase.

## Absolute constraints
- `00-inputs/**` is read-only for everyone, always.
- No restricted PII anywhere — fields, test data, logs, prompts (rules/10). Synthetic data only.
- Phase transitions: one step at a time; the 4 human gates require explicit human approval.
- Never claim a CLI command succeeded without running it; paste real output.
- Deploys target ONLY the POC org alias `<POC_ORG_ALIAS>` — ALWAYS pass `--target-org` explicitly,
  never rely on a default (client production/sandbox orgs may be authenticated on this machine).

## Command map (who does what)
/kickoff → start Discovery · /ba-analyze → ba-analyst · /arch-design → architect (design) ·
/pm-plan → pm-planner · /dev-implement T-## → dev-senior|dev-mid by routing ·
/dev-review T-## → code-reviewer agent + human verdict · /arch-confirm → architect (drift check) ·
/qa-plan → qa-lead · /qa-run A|B → qa-engineer · /qa-report → qa-lead close-out ·
/deploy T-##|sprint-1|drift-check → devops (validate, human-approved execute, record) ·
/advance → gate proposal (human approves) · /status → where are we · /health → invariant check ·
/lane setup|A|B|merge → parallel dev lanes (rules/40) · /retro → close the project

## Where things live
Inputs `00-inputs/` · Discovery `01-discovery/` · Build `02-build/` + `force-app/` ·
QA `03-qa/` · Gate sign-offs `04-confirmations/` · Shared memory `.claude/memory/`
(decisions D-###, assumptions A-###, glossary, handoffs) · Run log `.claude/logs/agent-runs.log` ·
Skills (how-to formats) `.claude/skills/` · Retro `retro/`.

## Config-load boundaries (learned the hard way)
Hooks + CLAUDE.md load at SESSION START (restart after changing them). Agent .md files load at
each subagent LAUNCH. Command .md files load at each INVOCATION.

## Salesforce specifics
- All metadata prefixed `PFX_` (set your real prefix in SETUP.md; standards in rules/20).
  Scratch org def: `config/project-scratch-def.json`. Setup skeleton: `scripts/org-setup.sh`.
- Identify the client's <CRITICAL_REQ (e.g. RFP §x.y)> — the single highest-priority requirement —
  during Discovery, and carry it as the top priority through design, build, and test.
- Run `node scripts/metadata-lint.js` before ANY review packet; a lint FAIL is a defect.
- Per-ticket `sf project deploy start --dry-run` (delta manifest) is MANDATORY before a packet
  says "buildable". No org connected = packet carries an "UNVERIFIED — NO ORG CONNECTED" banner.
- Read `.claude/skills/sf-deploy-troubleshooting/SKILL.md` BEFORE the first deploy — it carries
  the full failure taxonomy from the previous engagement so you don't pay for it twice.
- Jira (Atlassian MCP) and Playwright MCP are optional accelerators: if not connected, pm-planner
  and qa-engineer work file-locally and say so — never block, never pretend.
