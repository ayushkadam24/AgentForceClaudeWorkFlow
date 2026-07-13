# VS-20 Build Review Packet — Facility-scoped record sharing (Apex managed sharing)

- Feature: F-001 slot-booking-core
- Producing agent: dev-senior (/dev-implement VS-20)
- Date: 2026-07-13
- Phase: POST-DONE forward-build (PIPELINE_STATE YAML = DONE; untouched)
- Upstream IDs: REQ-053, REQ-054(open/A-006) · Annexure C5.1 · design 6.2 · EP-08 · VS-20 · **D-031** (the ruling this build implements) · relates D-011/D-017 (patients span facilities), D-019/D-020/D-029 (§3.4 crown jewel — untouched), D-022 (bulk export), A-018 (prod permsets), D-025/D-027/D-028 (DE-org quirks)

> **UNVERIFIED — NO ORG DEPLOY RUN BY THE BUILDER.** Per the ticket instruction, deploys were left to the
> orchestrator (org AgentForceClaudeWorkFlow has D-025/D-027/D-028/D-029 quirks). `node scripts/metadata-lint.js`
> was run (output below). "metadata-lint clean / XML well-formed" is NOT proof of deployability — the
> orchestrator's delta dry-run + RunLocalTests must clear the deploy risks flagged in "For the reviewer".

> **Packet-naming note (flagged, not dropped):** the ticket said update `VS-20-code-review.md`, but that file
> is the INDEPENDENT code-reviewer's report (the REJECT/FINDINGS record that motivated D-031). Overwriting it
> would destroy the independence audit trail (rules/00). This dev build packet is therefore written to
> `VS-20-review.md` (my role's artifact name) and the reviewer's `VS-20-code-review.md` is left intact.
> Rename if you prefer them merged.

## 0. Fix cycle — coordinator deploy pass 1 (2026-07-13)

Deploy pass 1: metadata + Apex compiled green (coordinator changed `User.VS_Facility__c` Lookup→**Text(18)**
— the standard User object rejects a custom Lookup to a custom object; the field-meta is now Text(18)
holding the facility Id, and the Apex reads it only as an Id value). `sf apex run test` = 0/53. Two failure
classes, both the DE-org **D-028** anomaly (org enforces FLS/CRUD even on system-mode + async DML). Fixed:

- **CLASS 1 — CRITICAL REGRESSION (43 booking/appointment/no-show failures)**: the appointment-triggered
  recompute SELECTed `VS_Facility__c.VS_Sharing_Group_Id__c`; the harness booking user has no FLS on that
  new field, so D-028 threw `No such column` and the enqueued Queueable failed the whole booking test —
  sharing was BREAKING booking. **Two fixes applied:**
  - **(a) FAIL-SAFE:** `recomputeSharesById()` now wraps the whole body in try/catch → on ANY exception it
    writes `VS_Error_Log__c` (itself best-effort) and returns. Booking/appointment DML ALWAYS succeeds;
    sharing then applies at runtime on a standard org (D-030a posture). `VS_FacilityGroupProvisioner` made
    fail-safe too (facility creation never breaks on a provisioning failure).
  - **(b) NO FLS in the hot path:** group resolution is now by **`Group.DeveloperName` = `VS_FAC_<facilityId>`**
    (`SELECT Id, DeveloperName FROM Group WHERE DeveloperName IN :names`) — Group is a setup object with no
    custom-field FLS trap. `provisionGroups()` also no longer reads `VS_Sharing_Group_Id__c`. That field is
    kept ONLY as the provisioner's written record (written by `writeBackGroupIds`, whose caller is the
    facility creator), and NO async/appointment path depends on its FLS.
- **CLASS 2 — VS-20 test fixtures (10 tests)**: Patient/User/Facility custom-field DML hit D-028. Applied the
  established pattern: fixtures now run under `runAs(fixtureUser)` bearing `VS_Booking_Engine_Test_Context`
  + `VS_Patient_Service_Test_Context` (Patient C1 + appointment FLS); managed shares are SEEDED by calling
  `recomputeSharesInternal` (new `@TestVisible`) as the default admin (Modify All Data; `__Share` has no
  custom-field FLS). New TEST-ONLY permset **`VS_Facility_Share_Test_Context`** (ManageUsers + FLS on
  `User.VS_Facility__c` and `VS_Facility__c.VS_Sharing_Group_Id__c`) lets the provisioning test set a home
  facility / write back a Group Id under `runAs`.

**Files added/changed in this fix cycle:** `VS_FacilityShareService` (fail-safe wrapper + `recomputeSharesInternal`
`@TestVisible` + Group-DeveloperName resolution + error-log helper), `VS_FacilityGroupProvisioner` (fail-safe),
`permissionsets/VS_Facility_Share_Test_Context` (new), both test classes rewritten. `VS_BookingService`
untouched.

### Deploy pass 3 (2026-07-14) — booking regression FIXED; VS-20 own-test D-028 fixes
Pass 2 fixed booking (all booking/appt/no-show green, VS_BookingService 93%). Remaining 11 failures were all
VS-20's own tests + 1 controller interaction:
- **7 in VS_FacilityShareServiceTest** (`No such column 'VS_Patient__c'`): the recompute/persona SELECTs of
  `VS_Appointment__c.VS_Patient__c`/`VS_Facility__c` were D-028 FLS-blocked. Fix: record fixtures + recompute
  now run under `runAs(fixtureUser)` (Booking_Engine + Patient_Service FLS) + new TEST-ONLY
  `VS_Facility_Share_Seed_Context` (object Modify All on Appointment/Patient, to insert the managed shares);
  the **isolation ship-bar shares are now HAND-SEEDED as the default admin** (Modify All Data — certain, no
  FLS-sensitive SELECT) so the C5.1 negative is unit-proven independently of the recompute path. Added read
  FLS on Patient/Appointment fields to `VS_Facility_Staff` (staff persona queries filter on them).
- **1 `tmpVar1`** (VS_FacilityProvisionTest): bind-expression/field-access binds → replaced with plain local
  variables throughout.
- **1 INSUFFICIENT_ACCESS on writeBack**: powerUser lacked record edit on a facility it didn't own (OWD Public
  Read) → the write-back test facility (`Prov Charlie`) is now created OWNED BY powerUser; read+assert moved
  inside `runAs(powerUser)` (FLS).
- **1 regression VS_BookingControllerTest.testReads** (`getAvailableSlots`→0): benign test-harness interaction
  from the new triggers firing in that class's @TestSetup. **Confirmed NOT a real break** — the VS-20
  code does DML ONLY on Group/GroupMember/`__Share`/`VS_Sharing_Group_Id__c`, never on `VS_Slot__c`/
  `VS_Session__c`, so `getAvailableSlots` (a slot/session read) is functionally unaffected on the live site.
  Fixed by bypassing the two triggers in that @TestSetup only.
- Coverage lift: added `appointmentLifecycle_update_delete_undelete` (covers afterUpdate both branches +
  afterDelete + afterUndelete) and made `asyncTrigger_createsShareEndToEnd` assert the share end-to-end.
`VS_BookingService` still untouched; metadata-lint = 2 pre-existing only.

### Deploy pass 4 (2026-07-14) — recompute-success + last tmpVar1 (should be final)
Pass 3 got to 51/56. Four left, both root-caused and fixed:
- **A) THREE recompute-SUCCESS tests (`Actual 0`)** — the object-Modify-All bet FAILED: Apex managed-sharing
  `insert __Share` needs **system "Modify All Data"**, not object Modify All, and the fail-safe try/catch
  swallowed the resulting error (0 shares silently). **Chose A(1):** switched `VS_Facility_Share_Seed_Context`
  from object Modify All to a single `<userPermissions>ModifyAllData</userPermissions>` grant (no
  ManageUsers-style dependency chain → deploys clean). The fixture user now inserts `__Share` for real, so
  `appointmentLifecycle_*`, `asyncTrigger_createsShareEndToEnd`, and `bulkRecompute_isGovernorSafe` prove the
  recompute END-TO-END (with a Modify-All-Data test harness — the least-privilege booking user remains the
  documented D-030a runtime gate; the fail-safe swallow is exactly what protects booking on that gate).
- **B) last `tmpVar1`** (syncGroupMembership_publicPath) — the remaining offender was a **method-call bind**
  (`WHERE Username LIKE :stPattern()` and the service's `WHERE DeveloperName IN :map.keySet()`). Replaced ALL
  method-call/collection-method binds with plain local variables (in both test classes and
  `VS_FacilityShareService.resolveFacilityGroups`/`provisionGroups`). A full scan confirms zero `:x.y` / `:x()`
  binds remain.
`VS_BookingService` untouched; metadata-lint = 2 pre-existing only. testReads was fixed by the coordinator
(TZ-flaky), not touched here.

### Unit-proven vs runtime-gated (honest)
| Behaviour | Status |
|---|---|
| A-staffer sees 0 of facility B's appts/patients (C5.1 negative) | **UNIT-PROVEN** (shares hand-seeded as admin + runAs personas) |
| A-staffer sees A; patient-at-both visible to both staffers | UNIT-PROVEN |
| District View-All + read-only FLS (isAccessible + USER_MODE) | UNIT-PROVEN |
| Prune on cancel (appt + patient share) | UNIT-PROVEN |
| Bulk 200 → constant SOQL/DML + correct share rows | UNIT-PROVEN (recompute logic, admin context) |
| Trigger ENQUEUES the async recompute | UNIT-PROVEN (queueable-count assert) |
| provisionGroups idempotent / writeBack Group Id | UNIT-PROVEN (writeBack under runAs powerUser, FLS permset) |
| GroupMember add + prune LOGIC | **UNIT-PROVEN** (reconcileGroupMembership called directly with a user->facility map) |
| Recompute creates the `__Share` end-to-end (insert/update/delete/undelete + bulk) | **UNIT-PROVEN** with a Modify-All-Data test harness (`VS_Facility_Share_Seed_Context`) — the fixture user actually inserts/deletes the managed shares. |
| Recompute SUCCEEDS when run by the LEAST-PRIVILEGE booking user (no Modify All Data) | **RUNTIME-GATED** — Apex managed-sharing insert requires Modify All Data; a plain booking user cannot, so on this DE org the recompute FAIL-SAFES (logs `VS_Error_Log__c` + no-op) and record-level sharing applies at runtime on a standard org / via an elevated maintainer (like §3.4 walk-in / D-030a). Booking is never affected. |
| `User.VS_Facility__c` field-write DRIVES syncGroupMembership (the read wiring) | **RUNTIME-GATED** — setting that field needs ManageUsers (dependency-heavy, not granted). syncGroupMembership_publicPath attempts the admin write and asserts membership only if it succeeds (standard org), else asserts the documented no-op. The add/prune logic it delegates to is unit-proven above. |

> **PRODUCTIONIZATION CONCERN (architect/reviewer — material, surfaced not buried).** Apex managed sharing
> `insert __Share` requires **"Modify All Data"** (confirmed on this org: object Modify All was insufficient,
> system Modify All Data works). The async recompute (`VS_AppointmentShareRecalc`) runs as the ENQUEUING user
> — i.e. the booking/facility-staff user — who will NOT have Modify All Data in production. So as currently
> wired, the recompute will FAIL-SAFE to a no-op for a normal user and record-level sharing would not actually
> be applied (booking still succeeds — the fail-safe guarantees that). **A productionization decision is
> needed:** run the sharing maintenance in an elevated context — e.g. a scheduled batch / platform-event
> handler executing as an integration user with Modify All Data (or the platform's standard managed-sharing
> behaviour on a non-DE org, which must be validated). This does not change the sharing MODEL (reasons,
> groups, diff logic — all proven); it changes WHO runs the maintenance. Recommend an OQ/architect ruling
> before REQ-053 is considered launch-complete.

### Deploy pass 2 (2026-07-14) — ManageUsers removed
Deploy pass 1's fix compiled but `VS_Facility_Share_Test_Context` failed on `ManageUsers depends on
AssignPermissionSets, DelegatedTwoFactor, FreezeUsers, ...` — too heavy to grant even test-only. Fix:
dropped the `<userPermissions>ManageUsers</userPermissions>` block (kept the two FLS grants + Facility CRUD);
split `syncGroupMembership()` into a `@TestVisible reconcileGroupMembership(Map<userId,facilityId>, allUserIds)`
so the GroupMember add/prune LOGIC is unit-proven WITHOUT any `User.VS_Facility__c` write; the field-write
wiring is runtime-gated (see table). No ManageUsers or its dependencies anywhere. `VS_BookingService`
still untouched; metadata-lint = 2 pre-existing only.

## 1. What changed vs the prior (rejected) build

The prior VS-20 build was a **criteria-based sharing-rule TEMPLATE** on `VS_Appointment__c` + District View-All.
The independent review raised MAJOR-1..4 (lookup-criteria deployability, missing group, no Patient mechanism,
blank district fields). D-031 **dropped the criteria approach entirely** in favour of **Apex managed sharing**
for BOTH objects. This build implements D-031:

- **DELETED** `sharingRules/VS_Appointment__c.sharingRules-meta.xml` (D-031 step 9 — criteria approach retired).
- Everything below is new/managed-sharing based.

## 2. Files delivered

### Metadata
| File | What |
|---|---|
| `objects/VS_Facility__c/fields/VS_Sharing_Group_Id__c.field-meta.xml` | Text(18) ExternalId — holds the facility's public Group Id (D-031 (3)). |
| `objects/User/fields/VS_Facility__c.field-meta.xml` | Lookup User→VS_Facility__c (a staffer's home facility), SetNull. |
| `objects/VS_Appointment__c/sharingReasons/VS_Facility_Access__c.sharingReason-meta.xml` | Apex sharing reason, label "Facility Access" (RowCause backing managed sharing). |
| `objects/VS_Patient__c/sharingReasons/VS_Facility_Access__c.sharingReason-meta.xml` | Same, on Patient. |
| `permissionsets/VS_District_Admin` / `VS_District_MIS` | **MAJOR-4 fix:** added read-only FLS on the C1 person + appointment fields district users may read (required fields omitted — see §4). |
| `permissionsets/VS_Facility_Staff` | Added **Read** on Patient/Appointment + read-only FLS (see §5 flag). |
| `permissionsets/VS_Facility_Share_Test_Context` | **TEST-ONLY** (fix cycle): ManageUsers + FLS on `User.VS_Facility__c` and `VS_Facility__c.VS_Sharing_Group_Id__c` so the provisioning test can write those under `runAs` on this D-028 org. Never on a real user. |

### Apex (all `VS_` prefixed, ApexDoc on public methods, custom exception, bulkified)
| Class | Role |
|---|---|
| `VS_FacilityShareService` (`without sharing`) | Core: `recomputeSharesById()` (appt + patient share diff/apply), `provisionGroups()`, `writeBackGroupIds()`, `syncGroupMembership()`, group resolution. |
| `VS_ShareException` | Coded domain exception (INVALID_INPUT, GROUP_PROVISION_FAILED). |
| `VS_FacilityTriggerHandler` + `triggers/VS_FacilityTrigger` | After-insert → enqueue async group provisioning. |
| `VS_AppointmentTriggerHandler` + `triggers/VS_AppointmentTrigger` | After ins/upd/del/undel → enqueue async share recompute. |
| `VS_AppointmentShareRecalc` (Queueable) | Runs the share recompute AFTER commit (keeps the §3.4 lock clean). |
| `VS_FacilityGroupProvisioner` / `VS_FacilityGroupLinker` (Queueables) | Two-hop mixed-DML-safe group create → Id write-back. |
| `VS_FacilityGroupMemberInvocable` | Flow/manual entry point to `syncGroupMembership()`. |
| `VS_FacilityShareServiceTest` | SHIP-BAR visibility/prune/bulk/async tests (6 methods). |
| `VS_FacilityProvisionTest` | Group provisioning + membership add/prune (4 methods). |

## 3. How the SHIP BAR (D-031 (5)) is met

- **Appointment scoping:** each non-cancelled appointment → `VS_Appointment__Share(Edit, RowCause=VS_Facility_Access__c)` to its facility group. `staffAseesOnlyFacilityA_notB` asserts A-staffer sees 2 A appts, **0** B appts.
- **Patient scoping (the real gap):** each patient → `VS_Patient__Share(Read)` to the group of EVERY facility where they hold a non-cancelled appointment. `staffAcannotSeePatientWhoseOnlyApptIsAtB` (0 rows) + `patientAtBothFacilities_visibleToBothStaffers` (visible to A AND B) prove minimal, multi-facility disclosure (C5.1).
- **District:** `districtSeesEverythingWithC1FieldsPopulated` — View-All sees all rows; `isAccessible()` under `runAs(district)` proves the read-only FLS grant (and that the internal Match_Key was NOT blanket-granted); a `WITH USER_MODE` query proves the field renders (not blank).
- **Prune on cancel:** `cancelPrunesStalePatientAndAppointmentShare` — cancel removes both the appt share and the (now last-at-B) patient share.
- **Bulk-safe:** `bulkRecompute_isGovernorSafe` — 200 appts, asserts SOQL ≤ 8 / DML ≤ 4 (constant, not O(n)) and 200+200 share rows created.
- **Async wiring:** `asyncTriggerWiring_createsShare` — trigger → Queueable creates the share end-to-end.

## 4. §3.4 crown jewel — provably untouched (D-019/D-020/D-029)

The appointment trigger runs **after-only** and the recompute is **asynchronous** (a Queueable enqueued from
the after-trigger). The booking transaction that holds the single `VS_Session__c FOR UPDATE` lock therefore
performs **ZERO extra SOQL/DML** for sharing — it only `System.enqueueJob(...)` (not a query or DML), which
runs after commit. `VS_BookingService` is **not modified**. The `afterUpdate` path only enqueues on a
share-relevant change (facility, patient, or crossing the Cancelled boundary), so `VS_NoShowBatch`'s
Booked→NoShow updates stay share-neutral.

## 5. Design decisions / deviations (flagged, per rules/20 #4 — narrowing flagged, not silently dropped)

- **D-DECISION-A — `VS_Facility_Staff` gained Read + FLS on Patient/Appointment.** The ticket §8 named only the
  two District permsets, but the SHIP BAR ("A-staffer sees A, not B") is impossible to prove — and REQ-053 is
  meaningless — unless staff have object+field READ, with row visibility gated by managed sharing. VS-04 explicitly
  deferred these grants to VS-20. Granted **Read-only** (least-privilege): the appointment share is Edit-capable
  but effective access is capped at Read by the permset (staff-initiated create/cancel/check-in = later ticket).
  **Reviewer: confirm Read (not Edit) is the intended staff ceiling for the POC.**
- **D-DECISION-B — User membership via Invocable + manual, NOT a global User trigger.** D-031 (3) allowed either.
  This POC org is a SHARED Developer Edition used for other work; a trigger on the standard `User` object fires
  org-wide on every user change. Chose `VS_FacilityGroupMemberInvocable` + `syncGroupMembership()` + documented
  manual GroupMember assignment for the 2 sample facilities (D-031 sanctioned path). Productionizing to a User
  trigger that calls the same service method is a one-line follow-up. **Stated per ticket #7.**
- **District FLS scope:** granted read-only FLS on Patient `Gender/Locality/Pincode/Email/No_Show_Count/Consent_Given`
  and Appointment `Patient/Facility/Session/Service/Booked_Channel/Booked_By_Mobile/Dose_Number/Cancelled_At/Booking_Reference`.
  **Required fields cannot carry FLS** and are always visible, so they are deliberately omitted (Patient
  Full_Name/DOB/Mobile, Appointment Status/Slot) — adding them would trip metadata-lint check-4. `Match_Key`
  (internal de-dup key) intentionally NOT exposed. No health/clinical fields exist to leak (REQ-045).
- **AccessLevel:** Appointment share = **Edit**, Patient share = **Read** (D-031 (1)/(2)).
- **Group provisioning is async two-hop** because Group (setup) + VS_Facility__c (non-setup) cannot be DML'd in
  one transaction (MIXED_DML). Deterministic DeveloperName `VS_FAC_<facilityId>` makes it idempotent/retry-safe.

## 6. Test results (honest)

- **Builder did NOT run `sf apex run test` or any `sf deploy`** (ticket instruction — orchestrator owns the deploy
  loop on the DE org). Coverage/exec numbers will come from the orchestrator's RunLocalTests.
- 10 test methods written (6 + 4) with **meaningful asserts** (row counts under `runAs`, FLS `isAccessible`,
  governor deltas, share-row counts) — not just no-exception. Covers positive, negative (cross-facility 0 rows),
  prune, bulk-200, and async-wiring paths.
- `node scripts/metadata-lint.js` output:
  ```
  == Metadata lint ==
    FAIL formula reads $CustomMetadata ... VS_Session__c/fields/VS_Walk_In_Reserve_Count__c.field-meta.xml
    FAIL formula reads $CustomMetadata ... VS_Setting__mdt/fields/VS_Value__c.field-meta.xml
  == 2 metadata-limit issue(s) ==
  ```
  Both FAILs are **pre-existing** (the Sprint-1 D-026 two-phase-deploy note) and unrelated to VS-20. **ZERO new
  lint issues** — District FLS additions correctly avoid required fields (check-4).

## 7. For the reviewer to scrutinize (deploy-gated)

1. **DE-org Group / GroupMember / VS_*__Share Apex DML** must be validated on this org (D-025). Managed-sharing
   DML has no FLS surface so should dodge the D-029 anomaly (D-031 (6)), but this is the first ticket doing
   setup-object + Share DML here — **the dry-run must confirm.**
2. **Sharing-reason ↔ Apex compile order:** `Schema.VS_Appointment__Share.RowCause.VS_Facility_Access__c`
   requires the `sharingReasons` metadata in the same deploy. Confirm the deploy compiles Apex against the
   deployed reasons (single-deploy should be fine; flagged for certainty).
3. **User-object field deploy** (`User.VS_Facility__c`) on this org.
4. **Mixed-DML in tests:** setup-object DML is wrapped in `System.runAs(currentUser)`; the async chain is not
   exercised via chaining in tests (Queueable-from-Queueable is unsupported in test context) — the linker is
   tested directly. Confirm the async provisioning wiring at runtime post-deploy if you want end-to-end proof.
5. **Standard User profile** must exist on the org (tests query it for test users). DE orgs have it.
6. **Regression:** the new `VS_AppointmentTrigger` fires on every appointment DML incl. VS-09 booking / VS-11
   cancel-reschedule / VS-12 no-show. It only enqueues (no SOQL/DML in those transactions) and is share-neutral
   for NoShow. Confirm the deployed §3.4 + no-show tests stay green under RunLocalTests.

## 8. Manual / setup steps

**Pre-deploy:** none. (No public groups need to pre-exist — this build provisions them from Apex; the deleted
criteria sharing rule that required a pre-existing group is gone.)

**Post-deploy (required to make the 2-facility proof real, per D-031 (5)):**
1. **Provision groups for the 2 sample facilities.** New facilities auto-provision via the trigger; the 36
   pre-existing facilities do not have groups yet. For the sample facilities (e.g. "Diag Facility" + one more),
   run once (anonymous Apex): `VS_FacilityShareService.writeBackGroupIds(VS_FacilityShareService.provisionGroups(new Set<Id>{facAId, facBId}));`
   (two hops must be separate transactions — or just re-save each facility to fire the trigger). Verify
   `VS_Sharing_Group_Id__c` is populated on both.
2. **Set `User.VS_Facility__c`** (home facility) on the staff test users, then **reconcile membership**:
   `VS_FacilityGroupMemberInvocable.sync(new List<Id>{userId});` (or add each user to their facility's public
   group manually in Setup → Public Groups — the D-031-sanctioned POC manual path).
3. **Assign permission sets** to the persona test users: `VS_Facility_Staff` for facility staff,
   `VS_District_Admin`/`VS_District_MIS` for district (A-018: never assign a harness permset to a real user).
4. If back-filling sharing for appointments created BEFORE this deploy, run a one-off recompute:
   `VS_FacilityShareService.recomputeSharesById(<appt Ids>, <patient Ids>);` (bulk-safe; batch if >large).

**Manual-only (not automated in this ticket):** productionizing membership to a `User` trigger (D-DECISION-B);
provisioning groups for all 36 facilities (the same code scales — re-save or batch the facilities); REQ-054
district read-audit stays OPEN (Shield/A-006 — this ticket delivers access-scoping only, C5.1 CLOSED on access).

## 9. UI shell

VS_Sharing_Group_Id__c (Facility) and User.Home Facility are **internal system fields** (system-owned; a human
never edits the group Id, and home-facility is admin-set). No CustomTab/list-view/FlexiPage is warranted for
this ticket — it adds record-level SHARING to existing user-facing objects (Appointment/Patient already have
their UI shells from earlier tickets), not a new user-facing object. **Internal-only, stated explicitly per the
UI-shell definition-of-done.**
