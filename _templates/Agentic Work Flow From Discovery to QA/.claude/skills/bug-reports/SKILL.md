---
name: bug-reports
description: Bug report format and severity rubric. Used by qa-engineer; consumed by pm-planner and developers.
---

# Bug Reports

## File: 03-qa/bug-reports/BUG-###.md
```
# BUG-### — <one-line summary, symptom not cause>
Severity: Sev-1..4 | Status: Open | Found: <date> | TC: TC-### | REQ: REQ-### | Ticket: T-##
Environment: <scratch org alias, browser>

## Steps to reproduce   (numbered; exact data values used; start state stated)
## Expected             (cite the AC/REQ verbatim)
## Actual               (what happened, verbatim error text)
## Evidence             (03-qa/evidence/... screenshots; console/network notes if relevant)
## Notes                (frequency: always/intermittent-x-of-y; suspected area — clearly a guess)
```

## Severity rubric
- Sev-1: integrity/compliance broken — overbooking, data visible across facilities, <RESTRICTED_PII>
  accepted anywhere, certificate for a <domain> that didn't happen. Release-blocking, stop-and-report.
- Sev-2: a primary journey (book/cancel/check-in/record/certificate) fails with no workaround.
- Sev-3: journey works via workaround; wrong copy with functional impact; Tier-2 feature defect.
- Sev-4: cosmetic/polish.

## Rules
- One defect per report; two symptoms = two bugs, cross-referenced.
- A bug the developer cannot reproduce from the steps is a defective report — include exact data.
- Regressions of previously passing TCs: note "REGRESSION of TC-### (passed <date>)".
- Mirror to Jira when connected; local file remains the source of truth.
