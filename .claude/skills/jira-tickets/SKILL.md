---
name: jira-tickets
description: Ticket format, complexity-routing rubric, and sprint plan structure. Used by pm-planner in SPRINT_PLANNED.
---

# Tickets & Sprint Plan

## Ticket format (in sprint-plan.md, mirrored to Jira when connected)
| Field | Rule |
|---|---|
| ID | VS-## sequential |
| Title | verb-first, ≤ 10 words |
| Story | As a <persona P1–P8>, I want…, so that… |
| AC | numbered Given/When/Then; each independently checkable |
| Links | REQ-### list + EP-## |
| Estimate | S (≤half day) / M (day) / L (2-3 days) — split anything larger |
| Routing | dev-senior or dev-mid per rubric below |
| Depends on | VS-## list |

## Routing rubric
dev-senior: booking/slot-integrity service (FOR UPDATE), anything transactional or async
(queueable/scheduled Apex), LWCs with imperative Apex, trigger framework, certificate generation.
dev-mid: object/field/metadata definition, permission sets, validation rules, record-triggered
and scheduled flows (reminders, no-show marking), page layouts/apps, simple screen flows, seed scripts.
Rule of thumb: if a race condition, governor limit, or callout can ruin it → senior.

## Sprint plan structure
1. Header block; sprint goal per sprint (one sentence each).
2. Sprint 1 = foundations: data model + permission sets + slot generation + booking service core.
   Sequence so nothing waits on an unbuilt dependency.
3. Tickets table per sprint; REQ→ticket coverage table at the end; "Needs architect" section for gaps.
4. jira-log.md: append-only status history `date | VS-## | old→new | by | note` (+ Jira key when mirrored).
