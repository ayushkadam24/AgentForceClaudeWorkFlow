---
name: flow-patterns
description: Flow best practices — when to use which flow type, structure, fault handling, and the Apex-vs-Flow boundary. Used by dev-mid (primary) and architect (automation matrix).
---

# Flow Best Practices

## Choosing the tool (the boundary matters more than the rules)
- Record-triggered flow: field updates on same record (before-save, fast), notifications,
  simple related-record updates. Our uses: appointment confirmation SMS log entry, status stamps.
- Scheduled flow: time-based batch work on modest volumes — end-of-day no-show marking,
  next-dose due computation, reminder queuing.
- Screen flow: guided staff tasks — check-in fallback, walk-in registration.
- APEX instead when: FOR UPDATE locking (booking!), complex branching >~15 elements, loops over
  large collections, anything needing a Queueable, or logic already owned by a service class.
  NEVER split one business rule between a flow and Apex — one owner per rule (see design's automation matrix).

## Structure & naming
- Name: VS_<Object>_<Context>_<Purpose> (VS_Appointment_AfterSave_LogConfirmationSMS);
  description field filled with trigger condition + what it does + ticket VS-##.
- One record-triggered flow per object per context (before/after) where practical; inside it,
  decision-first layout: entry conditions in the START element (not a decision after), so
  non-matching records never enter.
- Subflows for reused logic (e.g., "queue SMS from template" used by confirmation, reminder, cancellation).
- No hardcoded IDs/emails/numbers: Custom Metadata (VS_Setting__mdt) or Custom Labels via formula.

## Bulk-safety
- Flows run in bulk too: no Get/Update inside loops — collect into collection variables, one
  Update at the end. An after-save flow looping DML dies on drive-day volumes (6,000/day peak).
- Entry criteria as narrow as possible — every record entering costs limits shared with Apex.

## Fault handling (non-negotiable — rules/00 honesty applies to automation)
- EVERY element that can fail (DML, subflow, action) gets a fault path → log to the error object
  (same VS_Error_Log__c as Apex) with flow name, record id, fault message.
- Scheduled flows: fault path must not kill the whole batch silently — log and continue.
- User-facing screen flows: fault screen with a plain-language message + helpline number (C7.3 spirit).

## Testing & deploy
- Flow tests (Setup → Flow → Tests) for record-triggered flows: happy path + a path that must NOT fire.
- Deactivated-by-default in the repo is wrong for this POC: deploy ACTIVE (status=Active in meta),
  scratch org is disposable. Note activation state in the review packet.
- Versioning: never edit the active version live in the org — change in source, redeploy.
