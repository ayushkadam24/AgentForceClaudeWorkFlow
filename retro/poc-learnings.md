# POC Learnings

## What each agent got wrong

### ba-analyst — Discovery grading vs ANSWER-KEY (graded 2026-07-11, by human + orchestrator)
Score: **11 clean catches + 2 partial + 1 miss of 14 planted gaps** → per the rubric ("10+ caught,
none hallucinated"), the BA agent instructions are in good shape.

| # | Planted gap | Verdict | Where |
|---|---|---|---|
| 1 | Capacity daily vs per-session | CAUGHT | OQ-001, in the Contradictions section, model-both proposal |
| 2 | Walk-in reserve % undecided | CAUGHT | OQ-003, configurable param + 25% suggestion |
| 3 | Slot durations uncommitted | CAUGHT | OQ-002, per-service config |
| 4 | Sunday drives vs holiday calendar | CAUGHT | OQ-019, override rule |
| 5 | No-show penalty thresholds | CAUGHT | OQ-007, placeholder clearly labeled, enforcement deferred |
| 6 | SMS gateway + DLT lead time | CAUGHT | OQ-011/012, external-dependency section, seam REQ-059 |
| 7 | Poor-connectivity check-in | CAUGHT | OQ-018, pilot fallback, not over-specified |
| 8 | Booker ≠ patient (data-model trap) | CAUGHT (textbook) | REQ-004 Must: patient identity, not booker's, on record + certificate; OQ-020 |
| 9 | 60/40 split unverified | CAUGHT | OQ-008 + assumption A-001 |
| 10 | RFP 7–8 availability vs session hours | PARTIAL | REQ-009 models per-facility operating hours (the key's minimum bar); the tension itself never named |
| 11 | Retention schedule to confirm | CAUGHT | OQ-009 |
| 12 | CoWIN/U-WIN must-not-preclude | CAUGHT | OQ-016 + external-ID seam |
| 13 | Cancelled slot, NO capacity that week (deliberate omission) | PARTIAL | OQ-022 invented the rebooking-mechanics question but not the no-alternative-capacity case |
| 14 | Language of SMS/certificates for feature-phone users (deliberate omission) | MISSED | REQ-060 restates "English at launch" but nobody asked what language the SMS/certificate a feature-phone citizen receives |

Over-flagging check: none — 27 OQs, all substantive, each with owner/severity/suggested default,
organized into the 4 mandated sections. Bonus catches beyond the key: lost-booking-reference
recovery (OQ-021), late-vs-no-show (OQ-024), per-vaccine vial windows (OQ-010), DOB-vs-age (OQ-026),
portal auth (OQ-027). Hallucination check: none found — every default is labeled a recommendation.

Prompt lesson for #13/#14: both misses are second-order consequences (follow a journey one step
past its failure point; ask what a decision means for the lowest-capability persona). Candidate
instruction: "for every Must requirement, ask what the feature-phone/lowest-literacy persona
experiences at its failure edge."


## Prompt fixes applied

## Handoff friction observed

## Go / no-go evidence
