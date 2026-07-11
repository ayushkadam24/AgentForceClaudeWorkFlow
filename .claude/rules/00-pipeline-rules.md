# Pipeline Rules (binding for every agent)

## State machine
NOT_STARTED → DISCOVERY → ARCH_DESIGN → SPRINT_PLANNED → DEV_IN_PROGRESS →
DEV_COMPLETE → BA_ARCH_CONFIRM → READY_FOR_QA → QA_IN_PROGRESS → DONE

Human gates (an agent may PROPOSE, only a human may APPROVE):
- SPRINT_PLANNED → DEV_IN_PROGRESS (build start)
- DEV_COMPLETE → BA_ARCH_CONFIRM (review done, start drift check)
- BA_ARCH_CONFIRM → READY_FOR_QA (drift check go)
- QA_IN_PROGRESS → DONE (release)

## Write-access matrix (who may write where)
| Path | ba-analyst | architect | pm-planner | dev-senior | dev-mid | qa-lead | qa-engineer |
|---|---|---|---|---|---|---|---|
| 00-inputs/ | — | — | — | — | — | — | — |
| 01-discovery/ | brief, open-questions | technical-design, erd/ | — | — | — | — | — |
| 02-build/ | — | — | sprint-plan, jira-log | review-notes/, jira-log status | review-notes/, jira-log status | — | — |
| 03-qa/ | — | — | — | — | — | test-plan | regression/, bug-reports/, evidence/, test-plan Results only |
| 04-confirmations/ | — | drift-check | — | — | — | — | — |
| force-app/ | — | — | — | yes | yes | — | — |
| .claude/memory/ | append | append | append | append | append | append | append |
| PIPELINE_STATE.md | one log line + YAML per rules | same | same | same | same | same | same |

Nobody (agent or human, at any phase before DONE) reads ANSWER-KEY-intentional-gaps.md.

## Traceability chain (non-negotiable)
REQ-### (brief) → design section + EP-## (design) → VS-## (ticket) → code/metadata + review packet → TC-### (test) → BUG-### (defect). Every artifact cites the IDs upstream of it.

## Risk tiers for QA scope
- Tier 1 (test first, block release on failure): slot integrity RFP §3.4, booking/cancel/reschedule + cut-off, no-Aadhaar anywhere, role-based visibility (Annexure C5).
- Tier 2: reminders, next-dose recall, certificates, check-in, vial/wastage view, dashboards.
- Tier 3: cosmetic, copy, layout polish.

## Honesty rules
- Never claim a command succeeded without running it; paste real output or say "not run".
- Unresolved ambiguity → open question or review-packet flag, never a silent decision.
- Every agent run appends one line to .claude/logs/agent-runs.log (format in logs/README.md).
