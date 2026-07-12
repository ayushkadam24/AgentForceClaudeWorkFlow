# Ticket Workshop — Project Memory (day-to-day Jira ticket pipeline)

Purpose: I paste a Jira ticket; agents architect the solution, build the Salesforce metadata/code,
write tests, produce a delta `package.xml`, and register everything — one folder per ticket,
full history forever.

## ABSOLUTE: deploy policy = PACKAGE-ONLY
- Agents NEVER run `sf project deploy`, `sf org`, or ANY command that touches an org — not even
  `--dry-run`. Client production/sandbox orgs are authenticated on this machine.
- Instead, every ticket produces `deploy-steps.md`: the exact commands (with explicit
  `--target-org <HUMAN FILLS THIS>`) for the HUMAN to run, plus post-deploy verification steps.
- Agents may run LOCAL tools only: `node scripts/metadata-lint.js`, file reads/writes, git status.

## Roles (subagents in .claude/agents/)
- **ticket-architect** — reads the ticket, asks/records open questions, writes `02-solution.md`
  (approach, impacted metadata, design decisions, risks, test strategy).
- **ticket-developer** — builds metadata/code under the ticket's `src/`, follows the solution doc,
  runs metadata-lint (a FAIL is a defect), writes `03-build-notes.md`.
- **ticket-tester** — writes/extends Apex tests + manual test scripts, records expected results in
  `04-test-evidence.md` (marked NOT-RUN until the human executes them in an org).

## Ticket lifecycle (status in TICKETS.md — the master register)
NEW → SOLUTIONED → BUILT → TESTED → PACKAGED → DONE (BLOCKED allowed at any step, with reason)

## Where things live
- `TICKETS.md` — master register: one row per ticket (key, title, status, dates, package path).
- `tickets/<JIRA-KEY>-<slug>/` — everything for one ticket:
  `01-ticket.md` (pasted Jira content) · `02-solution.md` · `03-build-notes.md` ·
  `04-test-evidence.md` · `src/` (metadata) · `package/package.xml` (delta) · `deploy-steps.md`
- `.claude/memory/org-facts.md` — org quirks knowledge base (append what you learn; pre-seeded
  with the previous engagement's deploy taxonomy pointers).
- `.claude/memory/decisions.md` — cross-ticket decisions (D-###).
- `.claude/logs/agent-runs.log` — one line per agent run.

## Command map
/ticket-new KEY "title" → create folder from _template + register row (status NEW) ·
/ticket-solve KEY → ticket-architect · /ticket-build KEY → ticket-developer ·
/ticket-test KEY → ticket-tester · /ticket-package KEY → delta package.xml + deploy-steps.md ·
/ticket-close KEY → verify all artifacts, status DONE · /ticket-status → register overview

## Standards
- Follow the CLIENT'S existing naming conventions (read them from the ticket/codebase context
  pasted into 01-ticket.md — do not invent a prefix).
- Apex: service-layer pattern, bulkified, `WITH USER_MODE`/`stripInaccessible`, meaningful test
  asserts, no SeeAllData. See `.claude/skills/sf-apex-patterns/`.
- Flows: NEVER hand-author Flow XML beyond trivial edits — see skills/flow-patterns +
  skills/sf-deploy-troubleshooting §4.
- Before ANY packaging: `node scripts/metadata-lint.js` on the ticket's src/.
- Read `.claude/skills/sf-deploy-troubleshooting/SKILL.md` once per session before packaging work.

## Honesty rules
- Tests not executed in an org are ALWAYS marked "NOT RUN — expected results only".
- Unresolved ambiguity in a ticket → open question in 02-solution.md, never a silent decision.
- Never claim a command succeeded without running it; paste real output.
