# SETUP — do this before /kickoff (15 minutes)

## 1. Rename placeholder tokens (project-wide find & replace)
| Token | Replace with | Where |
|---|---|---|
| `<PROJECT_NAME>` | your project name | CLAUDE.md, rules, agents |
| `<CLIENT_SYSTEM_NAME>` | the client system being built | CLAUDE.md |
| `<RFP_REFERENCE>` | RFP/SOW reference number | CLAUDE.md, rules |
| `F-001 <pilot-feature>` | your pilot feature slug | CLAUDE.md, rules |
| `PFX_` | your metadata prefix (e.g. `ACM_`) | rules/20, skills, agents |
| `<POC_ORG_ALIAS>` | your POC org's sf CLI alias | CLAUDE.md, devops agent, deploy command |
| `<CRITICAL_REQ...>` | the client's non-negotiable requirement ref | CLAUDE.md, rules/20 |
| `<RESTRICTED_PII>` | the PII class you must never store (per client compliance) | rules/10, agents, hooks docs |
| `<domain>` / `<domain-item>` | leftover generic nouns — replace or delete as you read | rules/10, skills |

## 2. Paste client documents into 00-inputs/
Expected set (adjust to what the client gave you):
- `00-inputs/rfp.md` (or .pdf converted) — the RFP / requirements source
- `00-inputs/discovery-notes.md` — workshop/interview notes
- `00-inputs/current-state.md` — as-is system description
- `00-inputs/stakeholders.md` — who decides what
- `00-inputs/compliance/` — every compliance annexure
After pasting, `00-inputs/` is READ-ONLY forever (rules/00 + pretool-guard hook).

## 3. Rewrite rules/10-compliance-rules.md
The file is a TEMPLATE. Distill the client's real compliance annexures into numbered, binding,
testable rules (data minimization, residency, retention, access, accessibility, messaging, etc.).
The BA will cite them; QA will test them.

## 4. Org + tooling
- Authenticate the POC org: `sf org login web --alias <POC_ORG_ALIAS>` — NEVER develop against
  client orgs. Verify with `sf org display --target-org <POC_ORG_ALIAS>` (check the instance URL).
- `config/project-scratch-def.json`: set orgName; adjust features/settings.
- Node available? `node scripts/health-check.js` and `node scripts/metadata-lint.js` must run.
- OPTIONAL: connect Atlassian MCP (Jira) and Playwright MCP.

## 5. Session start
- Open this folder in Claude Code. Hooks + CLAUDE.md load at session start — restart the session
  if you edit them later.
- Run `/health` once (expect a clean baseline), then `/kickoff`.

## The 4 human gates (you approve, agents only propose)
SPRINT_PLANNED → DEV_IN_PROGRESS · DEV_COMPLETE → BA_ARCH_CONFIRM ·
BA_ARCH_CONFIRM → READY_FOR_QA · QA_IN_PROGRESS → DONE

## Carried-over lessons already baked in
- `metadata-lint before every review packet` + `per-ticket dry-run` are binding (rules/20).
- `.claude/skills/sf-deploy-troubleshooting/` documents the deploy-failure taxonomy from the
  previous engagement (opaque UNKNOWN_EXCEPTION bisection, CMDT-record real-deploy-only orgs,
  checkOnly limitations, USER_MODE test recipe, RunSpecifiedTests class-level trap). Devops and
  both dev agents should read it before Sprint 1.
- Fix-in-batches: after a failed dry-run is triaged, fix ALL captured failures of that class,
  then dry-run once — never one-defect-per-round.
