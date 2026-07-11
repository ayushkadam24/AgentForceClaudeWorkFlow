---
name: requirements-brief
description: How to write the requirements brief and open-questions register for the vaccine-scheduler POC. Used by ba-analyst during DISCOVERY.
---

# Writing the Requirements Brief

## requirements-brief.md structure
1. Header block (per rules/30) + one-paragraph problem statement in the client's language.
2. Personas summary — one line each P1–P8 with their success criterion.
3. Requirements register — a table per capability area (citizen booking; staff/check-in;
   vaccination recording & stock; follow-up & reminders; certificates; dashboards & admin;
   chat assistant; cross-cutting/compliance):
   | ID | Requirement ("The system shall…") | Priority (MoSCoW) | Source (doc §) | Personas | Notes/OQ link |
4. Non-functional requirements — accessibility, volumes (1,900/day steady, 6,000/day peak),
   availability window, language readiness, data protection. Each with source.
5. Out of scope — restate RFP §4 explicitly so nobody builds it.
6. Traceability summary — counts by MoSCoW, requirements per source doc.

## Rules of evidence
- Priority Must = RFP mandatory or Annexure C binding. Workshop "felt right in the room" = Should
  at most, with the ⚠ carried into open-questions.
- A number nobody committed to (slot duration, walk-in %, no-show threshold, reminder timings)
  is NEVER stated as fact — it appears as a recommended default + OQ-###.
- Contradictions (e.g., daily capacity vs per-session capacity) are requirements to SUPPORT BOTH
  only if the client said so; otherwise they are open questions with a proposed resolution.

## open-questions.md structure
Summary table then one block per OQ:
| ID | Question | Why it matters (what it blocks) | Owner | Suggested default | Status |
Severity ordering: blocks-build > blocks-design > blocks-launch > clarification.
The register must have dedicated sections (not mixed together) for:
1. Contradictions between sources or attendees.
2. Stated-but-unverified figures (treat as assumptions, never facts).
3. External dependencies outside the team's control (vendors, registrations, approvals).
4. Silent gaps — scenarios the inputs never address at all. Actively hunt these by walking
   each persona's journey end-to-end and each artifact's lifecycle (booking, slot, certificate,
   SMS) asking "what happens when this goes wrong / doesn't exist?".
Do not over-flag: a register that buries real blockers under trivial TBDs is noise, not analysis.
