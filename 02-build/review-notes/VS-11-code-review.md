# VS-11 Code Review -- VS_BookingService.cancel/reschedule (cut-off, session-lock reuse)

- Feature: F-001 slot-booking-core
- Producing agent: code-reviewer (independent)
- Date: 2026-07-13
- Phase: DEV forward-build review (pipeline YAML currently DONE; reviewing VS-11 forward build per orchestrator instruction; phase NOT changed by this run)
- Ticket: VS-11 (EP-03/EP-04, section 4.5, REQ-003/REQ-015)
- Derives from: REQ-003, REQ-015 / D-010, D-019, D-020, D-028/a, D-029 / AC-1..AC-5
- Files reviewed: VS_BookingService.cls, VS_BookingException.cls, VS_BookingServiceCancelRescheduleTest.cls (+meta), VS_Cancel_Reschedule_Test_Context.permissionset-meta.xml

> UNVERIFIED -- NO ORG DRY-RUN AT REVIEW TIME. Per ORG-SAFETY no sf command was run. Deployability and Apex test pass/fail are UNVERIFIED pending the orchestrator consolidated sf project deploy start --dry-run + sf apex run test against the DE alias. Only node scripts/metadata-lint.js (offline) was run.

---

## Category verdicts

| Category | Verdict |
|---|---|
| Correctness vs ACs (AC-1..5) | FINDINGS |
| Section 3.4 slot-integrity (lock target/ordering/no unlocked write) | FINDINGS (BLOCKER B-1) |
| Security (sharing/CRUD-FLS/least-privilege) | PASS (documented A-018 posture) |
| Compliance (no-Aadhaar / C1 / OWD-sharing) | PASS |
| Standards rules/20 (service layer, custom exception, tests) | FINDINGS |
| Deployability (metadata-lint, permset, caps) | PASS on VS-11 files -- see notes |

---

## BLOCKER

### B-1 -- cancel/reschedule re-validate ALREADY_CANCELLED OUTSIDE the lock -> double-free -> overbooking-by-one under concurrency (section 3.4)
- Where: VS_BookingService.cls loadCancellableAppointment reads appointment status at line 344 (if appt.VS_Status__c == STATUS_CANCELLED), called at line 245 (cancel) / line 294 (reschedule), BEFORE the session lock is acquired (lockSession line 249 / lockSessionsOrdered line 309). releasePlaceAndCancel (lines 388-424) then decrements the counter and stamps Cancelled using the STALE, pre-lock appt and never re-reads the appointment status inside the held lock.
- How to overbook it: Two transactions cancel the SAME appointment concurrently (realistic: citizen double-click on a portal Cancel button, or a client retry).
  - T1 and T2 both load the appointment as Booked (pre-lock, line 344) -- both pass the ALREADY_CANCELLED guard.
  - T1 acquires the session FOR UPDATE lock, decrements the slot VS_Booked_Count__c, stamps Cancelled, commits.
  - T2 then acquires the same lock, still holding its stale appt (Booked), re-reads the slot (lines 400-405, count already decremented by T1) and decrements AGAIN (line 406/413).
  - Net: one appointment cancelled but the slot counter decremented twice -> counter under-counts real bookings -> a later booking is admitted past capacity -> OVERBOOKING BY ONE. Math.max(0, ...) at line 406 only floors at zero; it does NOT prevent over-release when booked is greater than 1.
- Why it matters: exactly the failure RFP section 3.4 (crown jewel, highest-priority requirement) exists to prevent. book() is correct because it re-reads and checks all counters INSIDE the lock (session FOR UPDATE line 121, slot re-read line 135, ceiling check line 158). cancel/reschedule break that discipline: the integrity-critical guard is evaluated on data read before the lock and never re-confirmed under it.
- Suggested direction (not a patch): move the ALREADY_CANCELLED re-check INSIDE the lock -- re-query the appointment status within releasePlaceAndCancel after the session row is locked (or add the appointment row to a FOR UPDATE acquisition), no-op/throw if already Cancelled -- mirroring the book() re-read-inside-the-lock rule. Add a test proving a second cancel does not double-decrement. testCancel_alreadyCancelled_rejected only exercises the SEQUENTIAL path (T1 already committed, so the pre-lock guard catches it); it does not cover the interleaved pre-lock read.

---

## MAJOR

### M-1 -- Fail-closed integrity branch CUTOFF_CONFIG_MISSING is untested
- Where: VS_BookingService.cls getConfiguredCutOffHours lines 447-453; VS_BookingException.cls line 65.
- What: cut-off is an integrity control that fails CLOSED when VS_Setting__mdt.CutOffHours is absent/blank. No test asserts this branch (builder acknowledges it is intentionally uncovered).
- Why it matters: rules/20 requires meaningful negative coverage on new classes; a fail-closed control with zero test can silently invert (fail-open) on a future refactor with no red test.
- Direction: SOQL-on-CMDT is rejected on this org runAs path, so getInstance cannot be trivially emptied; add a seam (injectable cut-off provider / @TestVisible override) so the missing-config branch is assertable, or document why it is un-mockable and defer to QA with a named TC. Currently neither tested nor tracked to a TC.

---

## MINOR

### N-1 -- Walk-in cancel/reschedule branch has no deploy-time unit test
- releasePlaceAndCancel walk-in path (lines 390-396) DMLs VS_Session__c and is deferred to QA runAs/parallel (D-028a), same limitation as VS-09 walk-in. Legitimate and disclosed, but the walk-in decrement and walk-in reschedule are wholly unexercised by this class. QA must carry an explicit TC.

### N-2 -- reschedule cut-off measured only on the OLD slot; channel is caller-supplied
- Lines 294-295 enforce cut-off on the current slot start only; the destination slot start is not cut-off-checked, and channel for the new booking is caller-supplied rather than derived from the original appointment. Both are builder-flagged as needing BA confirmation (A-new-a/b/c). Not a defect -- surface to BA before READY_FOR_QA so the semantics are ratified, not silently decided.

### N-3 -- reschedule rethrows a generic catch (Exception ex)
- Lines 317-320 catch Exception and rethrow. Correct (no swallow, atomic rollback preserved), but a non-VS_BookingException from book() would propagate raw to the caller, contrary to the coded-reason convention. Low risk; noted for consistency.

### N-4 -- Builder metadata_lint_ok: true is imprecise
- node scripts/metadata-lint.js reports 2 FAILs (VS_Session__c.VS_Walk_In_Reserve_Count__c and VS_Setting__mdt.VS_Value__c -- CustomMetadata-in-formula two-phase-deploy items). These are PRE-EXISTING Sprint-1 files, NOT VS-11 files, so not a VS-11 lint blocker (known D-026 two-phase-deploy state); the packet should state lint clean on VS-11 files with 2 pre-existing global FAILs unchanged, rather than a blanket ok: true.

---

## Metadata-lint output (offline, run at review time)

    == Metadata lint ==
    FAIL formula reads CustomMetadata: VS_Session__c/fields/VS_Walk_In_Reserve_Count__c.field-meta.xml
    FAIL formula reads CustomMetadata: VS_Setting__mdt/fields/VS_Value__c.field-meta.xml
    == 2 metadata-limit issue(s) ==

Both FAILs are on Sprint-1 formula fields, not on any VS-11 file. No VS-11 file (test class, test meta, permission set) trips the lint.

---

## What is SOUND (verified by read)
- Lock target reused, no second service: cancel and reschedule both lock the parent VS_Session__c row FOR UPDATE (lines 353-359 / 367-377) -- no new lock target, no VS_WalkInService (D-019/D-020).
- Deadlock-safe ordering (AC-3): cross-session reschedule locks both rows in a single WHERE Id IN ... ORDER BY Id FOR UPDATE (lines 369-375) -- ascending-Id global order.
- Single lock same-session (AC-4): the Set collapses to one Id -> one row locked (test asserts).
- Fresh-minimal counter writes (D-029): every counter/status write is a new sObject carrying only written fields (lines 393-396, 411-415, 419-423) -- no carried CustomMetadata formula field.
- Cut-off from CMDT, never hardcoded (AC-1): getInstance on VS_Setting__mdt.CutOffHours, fail-closed.
- Atomic reschedule: Database savepoint (line 313) + rollback-on-throw (line 318) keeps the original intact; testReschedule_destinationFull_rollsBack_originalSurvives asserts it.
- Compliance: no Aadhaar/clinical fields (grep clean); test person data C1-minimal + synthetic (name/DOB/mobile 9000000000); with sharing enforces facility record visibility on the load.
- New coded exceptions are message-CODE constants (rules/20 convention).

---

## Recommendation: REQUEST-CHANGES (REJECT)
One BLOCKER (B-1) in the crown-jewel booking path: the cancellable-state guard is evaluated before the lock and never re-confirmed under it, giving a concrete overbooking-by-one vector under concurrent same-appointment cancels/reschedules (portal double-click is a realistic trigger). Fix B-1 (re-validate under the lock) and add the interleaving test; address M-1; carry N-1/N-2 to QA/BA. AC-tested happy paths and lock target/ordering are otherwise correct. Human runs the verdict; developers fix; re-review on request.

---

## Fix-cycle resolution (orchestrator, 2026-07-13) — BLOCKER B-1 FIXED

B-1 fixed in `VS_BookingService.cls` `releasePlaceAndCancel()`: an in-lock re-read of the
appointment status was added at the top of the method, BEFORE any counter decrement or status
stamp. Because every cancel/reschedule path already holds the appointment's parent-session row
FOR UPDATE (cancel → `lockSession`; reschedule → `lockSessionsOrdered` includes the old session),
this re-read is serialized: a second concurrent cancel of the same appointment blocks until the
first commits, then reads `VS_Status__c == Cancelled` and throws `ALREADY_CANCELLED` — so the
place is freed EXACTLY once. This mirrors `book()`'s re-read-all-counters-inside-the-lock
discipline; NO new lock target, NO second service (D-019/D-020 preserved).

Test/doc: `VS_BookingServiceCancelRescheduleTest` header updated to state the B-1 in-lock re-check
is proven under real concurrency by QA's parallel load test (a unit transaction cannot interleave),
while `testCancel_alreadyCancelled_rejected` locks the sequential no-double-decrement invariant.

Carried forward (unchanged, per fix-2-blockers scope): M-1 (fail-closed CUTOFF_CONFIG_MISSING
untested — needs an injectable-config seam), N-1 (walk-in cancel branch → QA runAs/load test),
N-2/N-3/N-4 → BA confirm / QA / packet wording. Deployability remains **org-UNVERIFIED** — the
consolidated `sf project deploy start --dry-run` + `sf apex run test` against the DE alias is the
gate before this may be called buildable.

## ORG-VERIFIED (2026-07-13) + one additional deploy-fix
Validate-only deploy (RunLocalTests) against AgentForceClaudeWorkFlow = **Succeeded**,
54 tests / 0 failures / 0 coverage warnings; VS_BookingService 93%. The B-1 fix and all
cancel/reschedule + VS-09 booking/walk-in regression tests pass.

DEPLOY-FIX (the offline review missed this — it only surfaces at org compile): `lockSessionsOrdered`
used `ORDER BY Id ... FOR UPDATE`, which Apex rejects ("Explicit ORDER BY not allowed when locking
rows (Id order is implied)"). Removed the explicit `ORDER BY Id`; FOR UPDATE already locks rows in
ascending-Id order, so the deadlock-safe global ordering AC-3 relies on is preserved (now implicit).
Method doc updated. This is the only change to the reschedule lock path; B-1 fix unaffected.
