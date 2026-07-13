# VS-12 Code Review — VS_NoShowBatch (scheduled, idempotent no-show sweep)

- Feature: F-001 slot-booking-core
- Producing agent: code-reviewer (independent)
- Date: 2026-07-13
- Phase: repo PIPELINE_STATE phase=DONE; this is a post-pilot FORWARD-BUILD review of VS-12 (see Phase note)
- Upstream IDs: EP-06 / REQ-017 (no-show capture, assumed — verify vs jira-log) / VS-12 AC-1/2/3 / D-020 (plain writable counter) / D-028 (deploy-time FLS harness) / D-029 (fresh-sObject write) / A-018 (production permset gap)
- Files reviewed:
  - force-app/main/default/classes/VS_NoShowBatch.cls (+ -meta.xml)
  - force-app/main/default/classes/VS_NoShowBatchTest.cls (+ -meta.xml)
  - force-app/main/default/permissionsets/VS_NoShow_Batch_Test_Context.permissionset-meta.xml
  - Cross-checked field metadata on VS_Appointment__c / VS_Slot__c / VS_Session__c / VS_Patient__c

> UNVERIFIED — NO ORG DRY-RUN AT REVIEW TIME. Per the org-safety directive no sf command was run against
> any org during this review. Compile, >=85% coverage, and deploy-time FLS sufficiency of the harness
> permset are NOT proven here; the orchestrator consolidated sf project deploy --dry-run + sf apex run
> test against the DE alias must confirm them. node scripts/metadata-lint.js WAS run offline. Static-read
> faithful is not buildable.

## Phase note
PIPELINE_STATE.md YAML is phase: DONE (F-001 pilot VS-01..09 released; VS-10..22 forward-planned, out of
the delivered pilot scope). This review was explicitly commissioned for VS-12 as a forward build. I did
not change phase or any shared log. Whether VS-12 is in build scope is a process decision for the
orchestrator/human; it is not a code defect.

## Verdict by category
- CORRECTNESS vs AC: PASS (AC-1/2/3 all met and asserted)
- BULKIFICATION / GOVERNOR (rules/20): PASS (constant 1 SOQL + 2 DML per chunk, no SOQL/DML in loops)
- SECURITY (with sharing, CRUD/FLS, least privilege): PASS with FINDINGS
- COMPLIANCE (rules/10 no-Aadhaar / C1 / synthetic): PASS
- STANDARDS (naming, ApexDoc, custom exception, test quality): PASS
- METADATA-LINT (VS-12 files): PASS (3 pre-existing FAILs are on other tickets' files)
- DEPLOYABILITY / TESTS: UNVERIFIED (no org this run)

## AC walk-through
- AC-1 (Booked + slot ended -> NoShow, patient count +1): MET. start() scope = VS_Status__c='Booked'
  AND VS_Slot__r.VS_Slot_End__c != null AND < now; execute() flips status and reads-then-writes
  VS_No_Show_Count__c (null-coalesced to 0). testMarksDueBookedAsNoShow_andIncrementsPatient asserts the
  transition AND that future-slot and CheckedIn rows are untouched (count stays 0).
- AC-2 (idempotent re-run): MET. Idempotency is structural — only 'Booked' rows are in scope, so a
  flipped 'NoShow' row is permanently out of scope. testIdempotentReRun_noDoubleIncrement proves the
  re-scan is EMPTY and a second execute() does not move the count off 1.
- AC-3 (200+, no SOQL/DML in loops): MET. Per-patient increments aggregated in a Map; ONE appointment
  DML + ONE SOQL + ONE patient DML per chunk. testBulk200_constantSoqlDml_noGovernorBreach asserts
  exactly 1 query + 2 DML over 200 appts / 40 patients and per-patient count correctness.

## Integrity / hostile-thinking check (counter-writing path, not the 3.4 booking lock)
- Atomicity is sound: both Database.update(..., AccessLevel.USER_MODE) calls default to all-or-none, so a
  patient-update failure throws and rolls back the appointment transitions in the same execute() chunk —
  a still-Booked row is simply re-selected next run. No lost/double increment on failure. ApexDoc claim
  (lines 17-20) is accurate.
- Read-modify-write on VS_No_Show_Count__c is safe within and across chunks because batch chunks commit
  sequentially (chunk N+1 reads chunk N's committed count). See MINOR-1 for the concurrent-JOB caveat.

## Findings

### BLOCKERS
None.

### MAJORS (production preconditions before the schedule is wired — not edits to this class)
- MAJOR-1 (runtime permset gap, A-018 class) — VS_NoShowBatch.cls:22-25,109,126. The batch runs
  USER_MODE, so the scheduling/running user needs FLS-edit on VS_Appointment__c.VS_Status__c and
  VS_Patient__c.VS_No_Show_Count__c. No PRODUCTION role permset grants this today, and the TEST-ONLY
  VS_NoShow_Batch_Test_Context must never be assigned to a real user. Direction: architect/BA to define a
  production scheduling permset (or integration user) BEFORE System.schedule(...) is wired; block the
  schedule on it. Correctly self-flagged by the builder.
- MAJOR-2 (sweep visibility under with sharing) — VS_NoShowBatch.cls:33,72-81. with sharing + USER_MODE
  means the scheduling identity only sweeps appointments it can SEE. With VS_Appointment__c OWD Private, a
  facility-scoped scheduling user would silently skip other facilities' no-shows — a system-wide nightly
  sweep needs an all-facility-visible identity (District-Admin/integration class). Direction: architect/BA
  to confirm the intended scheduling identity and visibility and document it. Not a code defect (USER_MODE
  + with sharing is the rules/20 default) but material to sweep completeness.

### MINORS
- MINOR-1 (overlapping-run double increment) — VS_NoShowBatch.cls:98-128. AC-2 covers SEQUENTIAL re-runs
  and is met. Two OVERLAPPING executions (accidental double schedule / manual run during the window) could
  each select the same still-Booked row before either commits, and each would increment the patient (the
  status flip is idempotent, the increment is not). No FOR UPDATE / dedupe guards this. Direction: ensure
  the scheduler cannot overlap (single cron / run-lock), or accept explicitly in the packet. Low
  likelihood for a nightly job; not a blocker.
- MINOR-2 (harness least privilege) — VS_NoShow_Batch_Test_Context.permissionset-meta.xml:57-66. The
  permset grants allowDelete=true on VS_Appointment__c; neither the batch nor the fixtures delete
  appointments. Trim allowDelete to false to keep the test-harness surface minimal.
- MINOR-3 (WalkIn status not swept) — VS_NoShowBatch.cls:77. Scope is VS_Status__c='Booked' only, so an
  appointment left in status 'WalkIn' on an ended slot is never marked NoShow. This matches AC-1's literal
  wording (Booked only), but if a 'WalkIn' can legitimately go unattended, confirm with BA/architect that
  WalkIn is intentionally out of no-show scope (else a later ticket must widen it).
- MINOR-4 (finish() observability) — VS_NoShowBatch.cls:136-140. Run metrics go only to System.debug
  (VS_Error_Log__c deferred, design 2.2). Acceptable for the POC; note for a later observability ticket so
  scheduled-run outcomes are queryable, not just in transient logs.

### NITS
- NIT-1 — EP-06/REQ-017 traceability is assumed in the class header; verify against the actual VS-12
  ticket header in sprint-plan/jira-log and correct if the epic/req differs.

## Metadata lint (offline, run this review)
    == Metadata lint ==
      FAIL formula reads $CustomMetadata (...): VS_Session__c/fields/VS_Walk_In_Reserve_Count__c
      FAIL formula reads $CustomMetadata (...): VS_Setting__mdt/fields/VS_Value__c
      FAIL PermissionSet description 259 > 255: permissionsets/VS_Cancel_Reschedule_Test_Context
    == 3 metadata-limit issue(s) ==

None of the 3 FAILs are on VS-12's files (they belong to VS-01, VS-02, and VS-11 — the two $CustomMetadata
formula items are the known two-phase-deploy pattern, D-026/D-027). VS-12's permset description is within
the 255 cap and was not flagged. VS-12 metadata-lint result: PASS.

## Deploy-time FLS analysis (static, no org this run)
The harness permset grants FLS-edit on only 3 fields (VS_Patient__c.VS_Match_Key__c,
VS_Patient__c.VS_No_Show_Count__c, VS_Appointment__c.VS_Patient__c). Every OTHER field written by the batch
or the fixtures resolves to required=true (implicit FLS) or a Master-Detail relationship field (no FLS):
Appointment.VS_Status__c(req), Appointment.VS_Slot__c(req), Slot.VS_Slot_End__c/VS_Slot_Start__c/
VS_Capacity__c/VS_Booked_Count__c/VS_Status__c(all req), Slot.VS_Session__c(MD), Session.* (all req;
VS_Facility__c/VS_Service__c MD/req), Patient.VS_Full_Name__c/VS_Date_Of_Birth__c/VS_Mobile__c(all req). So
the harness permset appears FLS-COMPLETE for the D-028 pattern. Static inference only — the orchestrator's
deploy-time test run is the authority.

## Compliance notes
No Aadhaar (no field, literal, variable, or test datum). Person data is C1-minimal (full name, DOB, mobile,
match key); VS_No_Show_Count__c is a derived booking-behavior count, not a C1 person attribute (documented
on the field). Test data is synthetic (fictional names, mobile 9000000000, example-domain emails). CRUD/FLS
enforced via WITH USER_MODE (SOQL) + AccessLevel.USER_MODE (DML). with sharing preserves facility-scoped
visibility (C5) — which is exactly the MAJOR-2 tension for a system-wide sweep.

## Recommendation
APPROVE-WITH-FIXES. No blocker: the class is correct against all three ACs, bulkified to a constant
statement budget, CRUD/FLS-enforced, with sharing, well ApexDoc'd, and backed by meaningful final-state
tests (transition, idempotent re-run, 200-row SOQL/DML assertion, aggregation, null-patient,
empty/null-scope). The two MAJORs are production preconditions (scheduling identity + its permset), not
edits to this class; the MINORs are mechanical/operational. Deployability + coverage remain UNVERIFIED
pending the orchestrator's org dry-run and test run.
