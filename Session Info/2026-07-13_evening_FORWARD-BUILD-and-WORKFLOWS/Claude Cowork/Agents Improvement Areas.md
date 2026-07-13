# Agents / Skills / Commands — Improvement Areas (Day 3, forward-build post-mortem, Cowork view)

Source: today's forward-build (VS-10..20 + app UI + VS-14 site) observed from the files, plus the
tooling work. Items marked [APPLIED] are already live in THIS project; [TEMPLATED] are baked into
the two new workflow folders in `D:\Agentforce POC's\WorkFlows with Agents\`; [OPEN] need action.

## 1. UI shell = definition-of-done [APPLIED + TEMPLATED]
The single biggest gap today: 4 sprints of objects/fields/Apex with no tabs, app, layouts, or list
views — a functionally complete org a human couldn't navigate. Root cause: no rule/template/review
check made navigability part of "done"; app assignment was a silent decision by omission.
- rules/20 new binding section; dev-mid/dev-senior build it; pm-planner tickets carry a UI-shell AC;
  architect design §UI names app/tabs/pages; code-reviewer treats a missing shell as MAJOR.
- [OPEN] architect Mode 2 (drift check) one-liner may still need pasting (PATCH file §5); delete
  `PATCH-ui-shell-definition-of-done.md` once fully applied.

## 2. Post-DONE work must not bypass the state machine [OPEN]
The forward build ran under phase=DONE: no gates, initially no run-log lines, review packets but no
QA. Candidate rule: any build work after DONE opens a NEW feature id (F-002) at SPRINT_PLANNED, or
re-enters DEV_IN_PROGRESS — "DONE means nothing is being built."

## 3. Ticket-status discipline in jira-log [OPEN]
Human verdicts (APPROVE etc.) were recorded in packets but NOT as jira-log status transitions —
Sprint 1 reads 2/9 Approved forever, and the Theater sprint strip faithfully shows the lie.
Candidate rule for rules/30: the verdict recorder appends the ticket transition in the same run.
Backfill VS-03..09 (Approved) + deployed states for VS-10..20.

## 4. Run-log gaps recurred despite the Stop-hook idea [PARTIAL]
Forward-build runs initially wrote zero agent-runs.log lines (later backfilled as lines 70–71 by
the Code session). The Day-2 improvement ("no subagent completes without its log line — enforce in
Stop/SubagentStop hook") is still the right fix; verify stop-guard.js actually checks this.

## 5. Registers must be CLOSED, not just opened [OPEN]
open-questions.md still shows 27/27 Open though several were decided (D-007..D-014). Whoever
records a D-### that resolves an OQ updates the OQ row status in the same run (rules/30 candidate).
Until then the Theater's Blockers tab over-reports.

## 6. Log timestamps = wall clock [OPEN, minor]
agent-runs.log lines 29–31 are out of chronological order (11:22 logged after 21:10 same day),
which slightly confuses time-sorted views (Theater timeline/star). Rule: log lines use actual
wall-clock time at write; never reconstruct earlier times.

## 7. Experience Cloud guest access is a Tier-1 compliance surface [OPEN — before publish]
VS-14 site layer deployed 20:31: guest profile granted object/FLS/class access, VS_BookingController
+ vsSlotPicker guest-exposed, OTP stub uses fixed TEST_CODE 000000. Before ANY publish:
- Human decides guest-write **Option A (OTP-verified authenticated path, C9-compliant) vs
  B (without-sharing portal method)** — flagged by the build agent, correctly not self-decided.
- Independent code-review of the guest profile grants (target: minimal reads; citizen records
  ONLY via OTP + sharing set, C5); re-run no-Aadhaar/OWD checks in the site-user context.
- Replace the OTP stub code; decide elevated-reads vs guest sharing rules (currently none added).
- Retrieve remaining site metadata (Network, sharing set, ExperienceBundle) into force-app.
Candidate: add a "site/guest go-live checklist" to the code-reviewer agent or a new skill.

## 8. Theater tooling notes [APPLIED + TEMPLATED]
- Sprint-progress strip added (main theater) — reads ticket sprints/statuses from jira-log.
- Jira variant built for the daily workflow: story kanban, deploy-log parsing (header format now
  LOCKED in that repo's rules/20 — keep it stable), and an intake tab that writes story.md +
  tracker rows (its one write; documented).
- make-package.js lesson: file paths with spaces (layouts!) — parse changed-files.md up to the
  "—" separator, not `\S+`. Test with a layout before trusting any path parser.
