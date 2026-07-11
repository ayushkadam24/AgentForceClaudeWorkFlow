# Vaccine Scheduler POC — Project Memory

AI-assisted Salesforce delivery pipeline (Discovery → Build → QA) for the Citizen Appointment &
Vaccination Scheduling System (RFP/DHS/2026/014). Pilot feature: **F-001 slot-booking-core**.
Seven role subagents in `.claude/agents/`; humans approve every gate.

## Before doing ANYTHING
1. Read `PIPELINE_STATE.md` — the YAML block is the single source of truth for phase.
2. Read `.claude/rules/` (00-pipeline, 10-compliance, 20-salesforce-standards, 30-documentation).
3. Work only within your role's write-access (matrix in rules/00) and only in your phase.

## Absolute constraints
- `00-inputs/**` is read-only for everyone, always.
- `ANSWER-KEY-intentional-gaps.md` is never read by any agent (grading material; also blocked in settings).
- No Aadhaar data anywhere — fields, test data, logs, prompts (Annexure C / rules/10).
- Phase transitions: one step at a time; the 4 human gates require explicit human approval.
- Never claim a CLI command succeeded without running it; paste real output.

## Command map (who does what)
/kickoff → start Discovery · /ba-analyze → ba-analyst · /arch-design → architect (design) ·
/pm-plan → pm-planner · /dev-implement VS-## → dev-senior|dev-mid by routing ·
/dev-review VS-## → human review helper · /arch-confirm → architect (drift check) ·
/qa-plan → qa-lead · /qa-run A|B → qa-engineer · /qa-report → qa-lead close-out ·
/advance → gate proposal (human approves) · /status → where are we · /retro → close the POC

## Where things live
Inputs `00-inputs/` · Discovery `01-discovery/` · Build `02-build/` + `force-app/` ·
QA `03-qa/` · Gate sign-offs `04-confirmations/` · Shared memory `.claude/memory/`
(decisions D-###, assumptions A-###, glossary, handoffs) · Run log `.claude/logs/agent-runs.log` ·
Skills (how-to formats) `.claude/skills/` · Retro `retro/poc-learnings.md`.

## Salesforce specifics
- All metadata prefixed `VS_`; standards in rules/20. Scratch org def: `config/project-scratch-def.json`
  (orgName "Vaccine Scheduler POC"). Setup skeleton: `scripts/org-setup.sh`.
- The RFP §3.4 slot-integrity guarantee (no overbooking under concurrency) is the highest-priority
  requirement in design, build, and test. Pattern: `.claude/skills/sf-apex-patterns/SKILL.md`.
- Jira (Atlassian MCP) and Playwright MCP are optional accelerators: if not connected, pm-planner
  and qa-engineer work file-locally and say so — never block, never pretend.
