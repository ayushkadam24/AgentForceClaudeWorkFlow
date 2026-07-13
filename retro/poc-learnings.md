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

### Delivery run — Build → Deploy → QA (2026-07-12, orchestrator synthesis from the paper trail)
- **dev-senior/dev-mid — coverage estimates were fiction.** Every Sprint-1 packet claimed "~90% coverage
  ESTIMATED (no org)". First real deploy-time run measured **0–5%** (tests died at FLS setup before any
  logic ran). Lesson: never state a coverage number you did not measure — mark UNVERIFIED and let the
  deploy/test loop produce the real figure. (Real end state after fixes: 86–100% per class.)
- **dev-mid — metadata authored past platform caps, repeatedly.** Description-length overflow
  (CustomPermission 255, CustomObject 1000 ×2), FLS on required/Master-Detail fields (1 → then a swept
  20), a Flow using a non-existent element name (`recordChoiceSets` → `dynamicChoiceSets`) and out-of-XSD
  order, a boolean screen input with illegal `isRequired`. All invisible until a real dry-run. Lesson:
  `metadata-lint.js` must also flag (a) `fieldPermissions` on any required=true / MD field, and (b) a
  permset granting object-read on an MD detail without its master — both cost a round here.
- **devops — the one-defect-per-round trap, then solved it.** The deploy surfaces one instance per
  component per run; fixing one unmasks the next. devops switched to **exhaustive sweeps** (return the
  full list, fix in one batch). Lesson (already in rules/20 §5, now proven): after a failed dry-run,
  sweep the whole failure class, fix all, dry-run once.
- **Two DE-org platform quirks cost the most** (now in `.claude/memory/de-org-deploy-quirks.md`): D-027
  (this org rejects ALL CustomMetadata *record* MDAPI deploys → create the 6 records by hand in Setup)
  and D-028 (this org enforces FLS on plain/**system-mode** DML — at deploy-time tests AND at runtime).
  D-028 forced: runAs+permset test fixtures, a class-split so `RunSpecifiedTests` (class-level only) could
  exclude the un-runnable walk-in tests, and finally **D-029**.
- **§3.4 crown jewel — unit tests can NOT prove it; a real load test can.** Unit tests run one
  transaction and cannot exercise `FOR UPDATE` serialization. A temporary Apex REST harness firing
  genuinely-concurrent HTTP (peak 25 in-flight) proved online + walk-in + disjoint no-overbooking across
  18 runs, zero double-books. Lesson: for any concurrency guarantee, a concurrent load test is mandatory
  scope, not optional — and design the seam (an externally-callable entry) so it's testable.
- **D-029 turned a test-blocker into a real bug fix.** The walk-in `update session` dragged the
  FLS-hidden `$CustomMetadata` formula field into the DML and failed at RUNTIME on this org. Fix: persist
  via a fresh sObject carrying only written fields. Lesson (candidate for rules/20 + sf-apex-patterns):
  system-mode counter writes should update a fresh sObject holding only the changed fields — never a
  record that has formula/inaccessible fields loaded on it.

## Prompt fixes applied
- **No `.claude/agents/*.md` were edited mid-run this session** (honest: prompt changes are recorded as
  candidates below, not applied, to avoid changing agent behavior mid-delivery). The prior 2026-07-12
  session had already hardened rules/20 (platform limits) + rules/30 (ID/ log discipline) + added
  `metadata-lint.js` — those carried this run and demonstrably helped (lint caught the description caps).
- **Candidate agent/rule fixes surfaced by this run** (for the human to apply before the next feature):
  1. `metadata-lint.js`: add checks for `fieldPermissions` on required/MD fields, and MD-detail-read
     without master-read (both cost deploy rounds).
  2. dev agents: "coverage is UNVERIFIED until measured against an org — never estimate a %."
  3. sf-apex-patterns skill: the D-029 fresh-sObject system-mode-write pattern; the runAs+permset
     USER_MODE test-fixture pattern (fixtures built by the FLS-bearing user, only the engine call under
     test in runAs).
  4. A **no-Aadhaar guard that also covers Bash writes** (see friction) — a pre-commit / CI grep, since
     the Write-tool guard is bypassable via shell redirects.
  5. ba-analyst: the #13/#14 "failure-edge for the lowest-capability persona" instruction above.

### Forward-build (Sprints 2–4, 2026-07-13) — the invisible-org gap
- **Every agent built to its ticket; nobody built the front door.** Objects, fields, Apex, flows,
  and permsets shipped across 4 sprints — but zero CustomTabs, no Lightning app, no page layouts
  beyond the default field dump, no list views, no FlexiPages. The org was functionally complete
  and *unusable by a human* until the human noticed and ordered the UI shell built. Root cause:
  the design's ticket decomposition treated "object" as data model only; no template, rule, or
  reviewer check made navigability part of definition-of-done, and no agent raised "which app
  should these tabs live in?" as an OQ — a silent decision by omission, which rules/00 forbids.
- **Candidate fixes (apply before next feature):** (a) rules/20: a binding "UI shell =
  definition-of-done" section — user-facing object tickets must ship tab + layout + list views +
  FlexiPage (or an explicit internal-only exemption), app assignment is an OQ if the design is
  silent; (b) architect: design must name the app(s), tab set, per-persona pages; (c) pm-planner:
  UI-shell acceptance criterion on every user-facing-object ticket; (d) code-reviewer: missing
  UI-shell evidence without an exemption note = MAJOR finding.

## Handoff friction observed
- **Subagents produced artifacts without their audit trail.** `test-plan.md` (qa-plan) and a permset
  retrieve both landed with no `agent-runs.log` line; `health-check.js`'s freshness invariant caught the
  staleness each time and the orchestrator reconciled (after verifying the artifact was legitimate, not
  injected). The invariant check earned its keep — but the discipline should hold without it.
- **`next_command` pointer went stale repeatedly** (`/dev-implement` after Sprint-1 deployed; `/qa-run A`
  after both runs; `/qa-report` after close-out). The orchestrator corrected it each time. A subagent
  finishing a step should update the pointer, not just append a log line.
- **Gate-sequencing confusion, twice.** `/arch-confirm` requires phase BA_ARCH_CONFIRM but we were at
  DEV_COMPLETE (the orchestrator had mis-set `next_command`); `/advance` to DONE was attempted before
  `/qa-report` produced the GO/NO-GO. In both cases the command's own precondition + the orchestrator's
  "the phase hasn't done its work yet" check stopped a premature advance. Lesson: the phase's *defining
  work* must complete before its exit gate — encode that in the gate proposal, don't rely on the human.
- **Write-boundary tension on the load test.** devops executed the §3.4 load test but the evidence
  belongs under `03-qa/`; the orchestrator updated `test-plan.md §8`. Worked, but the matrix didn't
  cleanly assign "devops runs a QA load test."

## Go / no-go evidence
- **Recommendation: GO-WITH-CAVEATS** (qa-lead, `03-qa/test-plan.md` §8.2). **20 PASS / 0 FAIL /
  8 BLOCKED / 0 BUG-###**; zero open Sev-1/Sev-2.
- **§3.4 (RFP highest priority) FULLY PROVEN** under genuine concurrency: online (TC-001), walk-in
  (TC-002, post-D-029), disjoint mixed (TC-003) — exactly-one-success, `walkInUsed ≤ reserve`,
  `booked ≤ capacity`, zero overbooking across all 18 load runs; D-020 pool disjointness proven.
- **Tier-1 compliance live-verified** against the deployed grant graph: no-Aadhaar (Tooling EntityParticle,
  zero Aadhaar/clinical fields), OWD (Patient/Appointment Private), role-visibility (0 Patient/Appointment
  grants on the 5 production permsets — A-018), `VS_Bulk_Export` gated to `VS_District_MIS` only.
- **8 BLOCKED are environment, not defects:** 6 browser/Playwright TCs (incl. 3 Tier-1 MO-flow, specs
  written for a browser run) + TC-021 config-Setup edit. TC-005 covered by TC-002 load evidence.
- **Accepted launch preconditions (caveats):** browser-run TC-012/013/014; build the A-018 production
  booking/slot-gen permset (harness permset never on a real user); seed data + role permset assignment;
  reconfirm org quirks D-027/028/029 on any non-DE org; pilot scope VS-01..09 (VS-20 record-level facility
  sharing = most consequential unbuilt gap). REQ coverage: 13 Covered / 7 Partial / 0 uncovered for built.
- **Deploy of record:** `0AfgL00000QySCASA3` (88 comp) + `0AfgL00000QxRmoSAF` (CMDT type) + 6 manual
  records + D-029 fix `0AfgL00000Qz4PYSAZ`. Org is at the clean Sprint-1 state; the temporary load harness
  was fully removed (HTTP 404 / Tooling count 0).

## Security & compliance events (this run)
- **Injection (carried from 2026-07-11, resolved):** a fabricated `agent-runs.log` line ("BA scored
  11+2p+1m … ANSWER-KEY … pass") delivered via a fake file-modified reminder that also demanded
  concealment. Refused, restored the genuine ba-analyst line, scanned clean. The human later confirmed
  the *number* (11+2p+1m) matched their own real Discovery grading — the injection had mimicked it. The
  ANSWER-KEY was never read by any agent, this session included.
- **Two no-Aadhaar near-misses (self-caught, redacted).** A qa-engineer used an Aadhaar-shaped 12-digit
  literal as TC-007 test data; the Write-tool guard blocked it, but a **Bash-written** evidence file and
  a **Bash-written** `handoffs.md` prose copy slipped through the guard (Bash bypasses it). Both were
  found and redacted; full-workspace re-scan and the health no-Aadhaar invariant are clean. → drives the
  "no-Aadhaar guard must cover Bash" candidate fix above.
