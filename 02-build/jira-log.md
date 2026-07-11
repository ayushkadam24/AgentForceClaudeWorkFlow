<!--
feature:         F-001 slot-booking-core
producing-agent: pm-planner
date:            2026-07-11
phase:           SPRINT_PLANNED
derives-from:    02-build/sprint-plan.md, .claude/memory/decisions.md (D-004)
downstream:      dev-senior/dev-mid status updates (this file's write-access for them is "status
                 changes only" per rules/00 write-access matrix), qa-lead/qa-engineer TC-### links
-->

# F-001 Jira Log — Ticket Register & Status History

**Jira (Atlassian MCP) is NOT connected (D-004).** This file is the **ticket source of truth** for
F-001. No Jira project/keys exist for these tickets yet. A Jira project does exist ("Public Health
App", key `SCRUM`, to be renamed/re-keyed to `VS` — D-004) but pm-planner did not attempt to create
epics/issues in it this run, per instruction to never block on Jira and to say so plainly here. When
Jira is connected, mirror each VS-## below to a Jira issue and record the Jira key in the "Jira key"
column; until then that column stays blank.

**2026-07-11 import-prep note:** the sprint plan and ticket set (VS-01..VS-22, 4 sprints, EP-01..08)
are FINAL as of the SPRINT_PLANNED gate approval. This file has been enriched below with a
Jira-import-ready detail block per ticket, and `02-build/jira-import.csv` has been produced, to
support a **manual CSV import** into the SCRUM project (site ayushkadam28.atlassian.net) to
initiate the board. This is packaging only — no scope, routing, estimate, or decision changed.

## Ticket register (created this run — all start in status Backlog)

| VS-## | Title | EP | Routing | Estimate | Sprint | Jira key |
|---|---|---|---|---|---|---|
| VS-01 | Build facility/service/session capacity objects | EP-01 | dev-mid | M | 1 | SCRUM-13 |
| VS-02 | Create VS_Setting__mdt config + seed values | EP-01 | dev-mid | S | 1 | SCRUM-14 |
| VS-03 | MO screen flow: define session capacity + drive-day | EP-01 | dev-mid | M | 1 | SCRUM-15 |
| VS-04 | Permission sets, OWD, session timeout, MIS export gate | EP-08 | dev-mid | M | 1 | SCRUM-16 |
| VS-05 | VS_Slot__c object & fields | EP-02 | dev-mid | S | 1 | SCRUM-17 |
| VS-06 | VS_SlotGenBatch: generate slots from sessions | EP-02 | dev-senior | L | 1 | SCRUM-18 |
| VS-07 | VS_Patient__c object & fields (C1-minimal, no-Aadhaar) | EP-05 | dev-mid | S | 1 | SCRUM-19 |
| VS-08 | VS_Appointment__c object & fields | EP-03 | dev-mid | S | 1 | SCRUM-20 |
| VS-09 | VS_BookingService.book() — single session-lock booking | EP-03 | dev-senior | L | 1 | SCRUM-21 |
| VS-10 | VS_PatientService.findOrCreate (exact-match de-dup) | EP-05 | dev-senior | M | 2 | SCRUM-22 |
| VS-11 | VS_BookingService.cancel/reschedule (cut-off, session-lock reuse) | EP-04 | dev-senior | L | 2 | SCRUM-23 |
| VS-12 | VS_NoShowBatch (scheduled, idempotent) | EP-04 | dev-senior | M | 2 | SCRUM-24 |
| VS-13 | VS_IOtpProvider + VS_OtpService (stub) | EP-06 | dev-senior | M | 3 | SCRUM-25 |
| VS-14 | Experience Cloud citizen site + sharing set | EP-06 | dev-mid | M | 3 | SCRUM-26 |
| VS-15 | Facility/service discovery LWC (search by service + proximity) | EP-06 | dev-senior | M | 3 | SCRUM-27 |
| VS-16 | Citizen booking journey LWC (book/view/cancel/reschedule) | EP-06 | dev-senior | L | 3 | SCRUM-28 |
| VS-17 | VS_Notification_Log__c object & fields | EP-07 | dev-mid | S | 4 | SCRUM-29 |
| VS-18 | VS_ISmsProvider + VS_SmsService (log-only) | EP-07 | dev-senior | M | 4 | SCRUM-30 |
| VS-19 | Booking-confirmation record-triggered flow | EP-07 | dev-mid | S | 4 | SCRUM-31 |
| VS-20 | Facility-scoped sharing rules + district View All | EP-08 | dev-mid | M | 4 | SCRUM-32 |
| VS-21 | VS_RetentionPurgeBatch (per-class policy) | EP-08 | dev-senior | M | 4 | SCRUM-33 |
| VS-22 | Synthetic seed data script | EP-08 | dev-mid | S | 4 | SCRUM-34 |

---


**Jira epic keys (imported 2026-07-11):** EP-01=SCRUM-5 · EP-02=SCRUM-6 · EP-03=SCRUM-7 ·
EP-04=SCRUM-8 · EP-05=SCRUM-9 · EP-06=SCRUM-10 · EP-07=SCRUM-11 · EP-08=SCRUM-12.
Stories/tasks map VS-nn = SCRUM-(nn+12). Sprint + parent-epic assignment done manually in
Jira (importer rejects sprint names; Epic Link not supported in team-managed projects).

## Detailed ticket specs (Jira-import source)

> **S/M/L → Story Points mapping (Fibonacci):** S = 2, M = 5, L = 8. This mapping is packaging
> convention only — it does not re-estimate any ticket; it exists because Jira's CSV importer wants
> a numeric Story Points value and the sprint plan carries only S/M/L.
>
> **Import order:** import the 8 epics (rows 1-8 of `jira-import.csv`) in the SAME import as the 22
> stories/tasks — Jira's CSV importer matches a child issue's `Epic Link` column to an epic's
> `Epic Name` column within one import file, so epics do not need to be created as a separate pass.
>
> **Dependencies are NOT wired as Jira issue links by this import.** Every ticket below carries a
> `Depends on: VS-##, VS-##` line inside its Description (sourced from the status-history
> "depends" notes below). Because Jira assigns issue keys only at import time, VS-## IDs cannot be
> resolved to Jira keys before the CSV is imported — **the human must manually add "blocks"/"is
> blocked by" issue links after import**, using this file as the map (VS-## → Jira key, once
> populated in the register table above).
>
> **Priority basis (rules/00 risk tiers):** VS-09 (`VS_BookingService.book()`, the single-lock
> §3.4 guarantee) is the crown jewel → Highest. VS-06 (slot generation, feeds the §3.4 ceiling),
> VS-08 (Appointment object, foundational to booking/cancel/reschedule), VS-10 (patient de-dup,
> booking-adjacent), and VS-11 (cancel/reschedule + cut-off, explicitly Tier-1) → High, per this
> task's explicit instruction. All other tickets → Medium. Note for human sanity-check: VS-07
> (no-Aadhaar) and VS-04/VS-20 (role-based visibility) are also Tier-1 categories per rules/00 but
> were **not** included in the explicit High-priority list given for this packaging pass, so they
> are shipped as Medium priority (they DO carry the `Tier-1` label below, since that label reflects
> QA risk tier, not Jira priority — flagging the priority/label mismatch for human review).

### VS-01 — Build facility/service/session capacity objects
- **Issue Type:** Task (pure object/field metadata — no Apex/LWC)
- **Epic:** EP-01 — Facility, Service & Capacity Model
- **Sprint:** 1
- **Routing label:** dev-mid
- **Estimate:** M → **Story Points:** 5
- **Priority:** Medium
- **Upstream IDs:** REQ-001, REQ-009, REQ-010, REQ-011, REQ-012 / EP-01 / D-005, D-007, D-009
- **Labels:** EP-01, dev-mid, F-001
- **Description:** Build `VS_Facility__c`, `VS_Service__c`, `VS_Facility_Service__c`, `VS_Holiday__c`,
  `VS_Session__c` with every field from design §2.3, each field carrying a description, operationalizing
  the per-session capacity model (D-007) and the walk-in reserve/bookable split (D-009).
  Acceptance criteria:
  - Given the org has no F-001 objects, when this ticket deploys, then all five objects exist with
    described fields per §2.3.
  - Given `VS_Session__c.VS_Total_Capacity__c` is set, when the record saves, then
    `VS_Walk_In_Reserve_Count__c` and `VS_Bookable_Capacity__c` formula fields compute per §2.1
    (CEILING against `VS_Setting__mdt.WalkInReservePct`).
  - Given `VS_Facility_Service__c`, when two records are created for the same facility+service, then
    the `VS_External_Id__c` unique constraint rejects the duplicate.
  - Depends on: — (no dependency; Sprint 1 foundation)

### VS-02 — Create VS_Setting__mdt config + seed values
- **Issue Type:** Task (pure config — Custom Metadata Type + records)
- **Epic:** EP-01 — Facility, Service & Capacity Model
- **Sprint:** 1
- **Routing label:** dev-mid
- **Estimate:** S → **Story Points:** 2
- **Priority:** Medium
- **Upstream IDs:** REQ-007, REQ-009, REQ-013, REQ-014, REQ-015 / EP-01 / D-008, D-009, D-010
- **Labels:** EP-01, dev-mid, F-001
- **Description:** Deploy `VS_Setting__mdt` as the single home for every tunable in the design
  (walk-in %, cut-off hours, slot granularity, booking horizon) so DHS can adjust rules without a
  code deploy (rules/20 — no hardcoded tunables).
  Acceptance criteria:
  - Given `VS_Setting__mdt` is deployed, when queried, then it exposes `CutOffHours` (=4, D-010),
    `WalkInReservePct` (=25, D-009), `DefaultSlotGranularityMins` (=15, D-008), `BookingHorizonDays`
    (=14), `ReminderOffsetsHours`, `NoShowThresholdCount` as named records.
  - Given a value changes in Setup, when any consuming formula/Apex re-reads it, then no code
    redeploy is needed.
  - Depends on: — (no dependency; Sprint 1 foundation)

### VS-03 — MO screen flow: define session capacity + drive-day
- **Issue Type:** Story (delivers a user-facing guided workflow, not just static config)
- **Epic:** EP-01 — Facility, Service & Capacity Model
- **Sprint:** 1
- **Routing label:** dev-mid
- **Estimate:** M → **Story Points:** 5
- **Priority:** Medium
- **Upstream IDs:** REQ-010, REQ-011, REQ-012 / EP-01 / D-007, D-018
- **Labels:** EP-01, dev-mid, F-001
- **Description:** Build the `VS_Session_Screen_DefineCapacity` screen flow so a Medical Officer in
  Charge can create sessions, set capacity, and mark drive days without developer help, including the
  drive-day override of holiday closures (D-018) that VS-06 slot generation will honor.
  Acceptance criteria:
  - Given a facility+service+date, when MO runs the flow, then a `VS_Session__c` is created with
    `VS_Total_Capacity__c` set and reserve/bookable formulas populated.
  - Given the MO checks "Drive Day," when saved, then `VS_Is_Drive_Day__c` = true so slot generation
    will open this date even if `VS_Holiday__c` marks it closed (D-018).
  - Given a flow element fails, when the screen runs, then a fault path shows a plain-language
    message + facility helpline (C7.3) and writes `VS_Error_Log__c`.
  - Depends on: VS-01, VS-02

### VS-04 — Permission sets, OWD, session timeout, MIS export gate
- **Issue Type:** Task (pure permission-set/sharing/security configuration)
- **Epic:** EP-08 — Security, Sharing & Compliance
- **Sprint:** 1
- **Routing label:** dev-mid
- **Estimate:** M → **Story Points:** 5
- **Priority:** Medium (see priority-basis note above — role-based visibility is a Tier-1 QA
  category per rules/00, but this packaging pass's explicit High list did not include VS-04; carries
  the `Tier-1` label to preserve that QA signal)
- **Upstream IDs:** REQ-036 (gating only), REQ-055 / EP-08
- **Labels:** EP-08, dev-mid, F-001, Tier-1
- **Description:** Configure org-wide defaults and the six role permission sets so each persona sees
  only the data it should, enforce the ≤15-minute shared-device session timeout (REQ-055), and gate
  (permission-bit only — no export mechanism) bulk-export capability to District MIS (REQ-036).
  Acceptance criteria:
  - Given OWD is set, when checked, then reference/bookable objects = Public Read Only and
    person/booking objects = Private (§6.2).
  - Given permission sets `VS_Facility_Staff`, `VS_Nurse`, `VS_MO_Facility_Admin`,
    `VS_District_Admin`, `VS_District_MIS`, `VS_Citizen_Community` are assigned, when a user without
    one logs in, then they get no access beyond OWD.
  - Given a shared-device role's permission set, when idle 15 minutes, then the session times out.
  - Given `VS_District_MIS`, when inspected, then it alone carries the export/bulk-data permission
    bit (gating only — export UI itself remains Deferred; no export mechanism built here).
  - Depends on: VS-01

### VS-05 — VS_Slot__c object & fields
- **Issue Type:** Task (pure object/field metadata)
- **Epic:** EP-02 — Slot Generation Engine
- **Sprint:** 1
- **Routing label:** dev-mid
- **Estimate:** S → **Story Points:** 2
- **Priority:** Medium (see priority-basis note above — slot integrity §3.4 is Tier-1; carries the
  `Tier-1` label)
- **Upstream IDs:** REQ-008, REQ-009, REQ-014 / EP-02 / D-020
- **Labels:** EP-02, dev-mid, F-001, Tier-1
- **Description:** Build `VS_Slot__c` as the object that carries the per-slot published capacity
  ceiling required by REQ-008 and read/written only inside the VS_Session__c lock per D-020 (VS-09
  is where the lock itself is implemented; this ticket is the schema only).
  Acceptance criteria:
  - Given `VS_Slot__c` deploys, when inspected, then it has Master-Detail to `VS_Session__c`,
    `VS_Slot_Start__c`/`VS_Slot_End__c`, `VS_Capacity__c`, `VS_Booked_Count__c`, `VS_Status__c`
    (Open/Full/Closed/Cancelled), each described.
  - Given a session is deleted, when cascading, then its slots cascade per Master-Detail (no orphan
    slots).
  - Depends on: VS-01

### VS-06 — VS_SlotGenBatch: generate slots from sessions
- **Issue Type:** Story (functional Apex batch job)
- **Epic:** EP-02 — Slot Generation Engine
- **Sprint:** 1
- **Routing label:** dev-senior
- **Estimate:** L → **Story Points:** 8
- **Priority:** High (explicit — Tier-1 slot-integrity adjacent; feeds the §3.4 ceiling)
- **Upstream IDs:** REQ-009, REQ-012, REQ-013, REQ-014, REQ-062 (bulk) / EP-02 / D-008, D-018, D-023
- **Labels:** EP-02, dev-senior, F-001, Tier-1
- **Description:** Build `VS_SlotGenBatch` to generate 15-minute `VS_Slot__c` rows from each
  session's bookable capacity, honoring holidays and the drive-day override (D-018) and the
  configurable booking horizon. **D-023 requirement: the even-capacity-distribution algorithm MUST
  live in exactly ONE private method of this batch/service**, so a later switch to weighted/
  front-loaded distribution is a single-method change, not a redesign — this is a drift-check radar
  item for BA_ARCH_CONFIRM. Must be proven bulk-safe at 250+ sessions (REQ-062).
  Acceptance criteria:
  - Given a session with `VS_Bookable_Capacity__c` = 60 and 15-min granularity, when the batch runs,
    then it creates 15-min slots whose capacity sums to exactly 60 (even split, remainder to
    earliest slots, A-005/D-023).
  - Given a facility date is a holiday with no drive-day session, when the batch runs, then no slots
    generate for that date/facility.
  - Given a holiday date has a session flagged `VS_Is_Drive_Day__c` = true, when the batch runs,
    then slots ARE generated for that session only (D-018).
  - Given `BookingHorizonDays` = 14, when the batch runs, then no slots generate beyond the horizon.
  - Given 250+ sessions queued (REQ-062 bulk posture), when the batch runs, then it completes with
    no SOQL/DML in loops and no governor-limit exceptions.
  - Depends on: VS-01, VS-02, VS-05

### VS-07 — VS_Patient__c object & fields (C1-minimal, no-Aadhaar)
- **Issue Type:** Task (pure object/field metadata)
- **Epic:** EP-05 — Patient & Identity
- **Sprint:** 1
- **Routing label:** dev-mid
- **Estimate:** S → **Story Points:** 2
- **Priority:** Medium (see priority-basis note above — no-Aadhaar is Tier-1; carries the `Tier-1`
  label)
- **Upstream IDs:** REQ-043, REQ-044, REQ-045, REQ-046 / EP-05 / D-011, D-017, D-024
- **Labels:** EP-05, dev-mid, F-001, Tier-1
- **Description:** Build `VS_Patient__c` with exactly the C1.1 minimum person fields and **NO
  Aadhaar field, no Aadhaar-named or Aadhaar-shaped field anywhere** (REQ-044) — this is a
  **structural acceptance criterion**: the object and org metadata must be searchable for
  Aadhaar-named fields/labels and return zero matches; QA Tier-1 will re-verify this at test time.
  Also carries the unique `VS_Match_Key__c` (D-017, enforced in VS-10) and consent fields. **Per
  D-024, DPDP consent/notice copy must be a Custom Label prefixed `[[DRAFT — pending department
  approval]]`, never hardcoded text** — swapping in approved wording later is a Custom Label edit
  only, zero code change.
  Acceptance criteria:
  - Given `VS_Patient__c` deploys, when inspected, then its only person fields are
    `VS_Full_Name__c`, `VS_Date_Of_Birth__c`, `VS_Gender__c` (optional), `VS_Mobile__c`,
    `VS_Locality__c`, `VS_Pincode__c`, `VS_Email__c` (optional) — exactly C1.1, nothing more.
  - Given the object and org metadata are searched for any Aadhaar-named field/label anywhere, when
    the check runs, then zero matches exist (REQ-044, structural AC, QA Tier-1 re-verifies).
  - Given `VS_Match_Key__c` is marked ExternalId+Unique, when two patient records are inserted with
    the same normalize(name)|DOB|mobile, then the second insert is rejected at the DB (D-017,
    proven in VS-10).
  - Given `VS_Consent_Given__c`/`VS_Consent_Timestamp__c` exist (consent copy = Custom Label,
    DRAFT-prefixed per D-024), when a patient is created without consent = true, then the record is
    not usable for booking (enforced in VS-10).
  - Depends on: — (no dependency; Sprint 1 foundation)

### VS-08 — VS_Appointment__c object & fields
- **Issue Type:** Task (pure object/field metadata)
- **Epic:** EP-03 — Slot-Integrity Booking (§3.4 — crown jewel)
- **Sprint:** 1
- **Routing label:** dev-mid
- **Estimate:** S → **Story Points:** 2
- **Priority:** High (explicit — foundational to booking/cancel/reschedule, Tier-1 adjacent)
- **Upstream IDs:** REQ-002, REQ-008, REQ-019 (field only; check-in UI deferred), REQ-045 / EP-03 /
  D-016, D-020
- **Labels:** EP-03, dev-mid, F-001, Tier-1
- **Description:** Build `VS_Appointment__c` as the record `VS_BookingService.book()` (VS-09)
  inserts, carrying the unique typeable `VS_Booking_Reference__c` (D-016 — 8-char Crockford base32)
  and NO clinical/diagnosis fields (health data limited to appointment lifecycle only, REQ-045).
  Acceptance criteria:
  - Given `VS_Appointment__c` deploys, when inspected, then it has lookups to
    Patient/Slot/Session/Facility/Service, `VS_Booking_Reference__c` (ExternalId+Unique),
    `VS_Status__c` (Booked/CheckedIn/Completed/Cancelled/NoShow/WalkIn), `VS_Booked_Channel__c`
    (Portal/Chat/Staff/WalkIn), `VS_Booked_By_Mobile__c`, `VS_Dose_Number__c`, `VS_Cancelled_At__c`.
  - Given the object is scanned for clinical/diagnosis fields (REQ-045), when checked, then none
    exist.
  - Depends on: VS-01, VS-05, VS-07

### VS-09 — VS_BookingService.book() — single session-lock booking
- **Issue Type:** Story (functional Apex service — the crown-jewel §3.4 guarantee)
- **Epic:** EP-03 — Slot-Integrity Booking (§3.4 — crown jewel)
- **Sprint:** 1
- **Routing label:** dev-senior
- **Estimate:** L → **Story Points:** 8
- **Priority:** Highest (explicit — the crown jewel; single point of §3.4 correctness)
- **Upstream IDs:** REQ-002, REQ-006, REQ-007, REQ-008, REQ-062 (bulk/session-scoped) / EP-03 /
  D-019, D-020, D-016, D-009
- **Labels:** EP-03, dev-senior, F-001, Tier-1
- **Description:** Build `VS_BookingService.book(patientId, slotId, bookedById, channel)` as the
  **single public entry point for online, staff, and walk-in booking**. Per **D-019/D-020, this
  method MUST take exactly one lock: `SELECT ... FOR UPDATE` on the parent `VS_Session__c` row** —
  never a lock on `VS_Slot__c` (D-015 is superseded/retracted) — and must check both the per-slot
  published ceiling (`VS_Slot__c.VS_Capacity__c`/`VS_Booked_Count__c`, read/written only inside the
  session lock) and the walk-in reserve (`VS_Walk_In_Used_Count__c`/`VS_Walk_In_Reserve_Count__c`)
  inside that one lock before inserting the appointment with a unique `VS_Booking_Reference__c`
  (D-016). **The test class is mandatory and must include, at minimum: (1) a capacity-exhaustion
  test, and (2) a mixed online/walk-in parallel-booking (concurrency) test proving no overbooking
  when a burst of both channel types races for the last shared place — this is the case D-015 could
  not prove and D-019 exists specifically to prove.** A negative test (invalid slot/closed session)
  with a meaningful assert on final row counts is also required. Insert must use
  `WITH USER_MODE`/`Security.stripInaccessible` (CRUD/FLS).
  Acceptance criteria:
  - Given a session with one remaining bookable slot place, when 50 parallel `book()` calls target
    that slot, then exactly one appointment is created, `VS_Booked_Count__c` never exceeds
    `VS_Capacity__c`, and every other call catches `VS_BookingException('SLOT_FULL')`.
  - Given a session with one remaining walk-in reserve place, when 50 parallel `book(...,'WalkIn')`
    calls fire, then exactly one succeeds and `VS_Walk_In_Used_Count__c` never exceeds
    `VS_Walk_In_Reserve_Count__c`.
  - Given a session with exactly one remaining place shared across channels, when a **mixed burst**
    of online and walk-in `book()` calls fires simultaneously, then exactly one booking of any type
    succeeds and no overbooking occurs (mandatory D-019 proof).
  - Given `book()` succeeds, when the appointment is inserted, then it carries a unique
    `VS_Booking_Reference__c` (D-016) and enforces CRUD/FLS.
  - Given the method signature, when reviewed, then there is exactly ONE public entry point for
    all channels — no separate `VS_WalkInService`, no second lock target (D-019/D-020).
  - Test class includes the capacity-exhaustion test AND the mixed-burst test (both mandatory) plus
    a negative test with meaningful row-count asserts.
  - Depends on: VS-01, VS-02, VS-05, VS-07, VS-08

### VS-10 — VS_PatientService.findOrCreate (exact-match de-dup)
- **Issue Type:** Story (functional Apex service)
- **Epic:** EP-05 — Patient & Identity
- **Sprint:** 2
- **Routing label:** dev-senior
- **Estimate:** M → **Story Points:** 5
- **Priority:** High (explicit — patient-identity correctness underpins booking integrity)
- **Upstream IDs:** REQ-004, REQ-043, REQ-045, REQ-046 / EP-05 / D-011, D-017, D-024
- **Labels:** EP-05, dev-senior, F-001
- **Description:** Build `VS_PatientService.findOrCreate` implementing D-011's exact-match
  (name+DOB+mobile) de-dup with NO fuzzy matching, race-safe via the D-017 unique `VS_Match_Key__c`
  external ID (upsert-by-external-id, not a prior SOQL check). Enforces DPDP consent capture (D-024
  Custom Label, DRAFT-prefixed) before a new patient can be created.
  Acceptance criteria:
  - Given a patient with an identical normalized name+DOB+mobile triple already exists, when
    `findOrCreate` is called, then the existing `VS_Patient__c` Id is returned — no new row.
  - Given any single field differs, when called, then a NEW patient is created (known-duplicate
    limitation accepted per D-011, not silently merged).
  - Given two `findOrCreate` calls race for the same new match key, when both commit, then the
    DB-level unique constraint on `VS_Match_Key__c` prevents a duplicate insert (D-017, race-safe).
  - Given `VS_Consent_Given__c` is not passed as true, when `findOrCreate` runs for a new patient,
    then the method throws rather than creating a patient without consent, and stamps
    `VS_Consent_Timestamp__c` on success.
  - Depends on: VS-07

### VS-11 — VS_BookingService.cancel/reschedule (cut-off, session-lock reuse)
- **Issue Type:** Story (functional Apex service)
- **Epic:** EP-04 — Cancel / Reschedule / No-Show
- **Sprint:** 2
- **Routing label:** dev-senior
- **Estimate:** L → **Story Points:** 8
- **Priority:** High (explicit — Tier-1: booking/cancel/reschedule + cut-off)
- **Upstream IDs:** REQ-003, REQ-015, REQ-062 (bulk-safe) / EP-04 / D-010, D-019, D-020
- **Labels:** EP-04, dev-senior, F-001, Tier-1
- **Description:** Extend the booking service with `cancel()`/`reschedule()`, reusing the SAME
  session-row lock pattern from VS-09 (D-019/D-020) — no new lock target. Enforces the 4-hour
  cut-off (D-010). Reschedule across two different sessions must lock both session rows **ordered
  by session Id** to avoid deadlock.
  Acceptance criteria:
  - Given current time is within `CutOffHours` (4h) of slot start, when `cancel()` is called, then
    it is rejected with a user-actionable message (not a stack trace).
  - Given cut-off has not passed, when `cancel()` succeeds, then the session row is locked FOR
    UPDATE, `VS_Booked_Count__c` (or `VS_Walk_In_Used_Count__c`) decrements, and slot status flips
    Full→Open if applicable, all in one transaction.
  - Given `reschedule()` moves between two different sessions, when the method runs, then it locks
    both session rows ordered by session Id (deadlock-safe), cancels the old and books the new
    atomically.
  - Given old and new slots share the same session, when rescheduling, then only one lock is taken.
  - Test class includes a negative test (attempt inside cut-off) with final row/counter asserts.
  - Depends on: VS-09

### VS-12 — VS_NoShowBatch (scheduled, idempotent)
- **Issue Type:** Story (functional scheduled Apex batch)
- **Epic:** EP-04 — Cancel / Reschedule / No-Show
- **Sprint:** 2
- **Routing label:** dev-senior
- **Estimate:** M → **Story Points:** 5
- **Priority:** Medium
- **Upstream IDs:** REQ-016, REQ-062 (bulk) / EP-04
- **Labels:** EP-04, dev-senior, F-001
- **Description:** Build a scheduled, idempotent batch marking unattended bookings NoShow at day's
  end and incrementing `VS_Patient__c.VS_No_Show_Count__c`.
  Acceptance criteria:
  - Given a Booked appointment whose slot has passed with no check-in, when the batch runs EOD,
    then its status becomes NoShow and No_Show_Count increments by 1.
  - Given the batch runs twice on the same appointment, when re-run, then the count does not
    double-increment (idempotency).
  - Given 200+ appointments due for marking (REQ-062), when the batch runs, then no SOQL/DML
    executes inside a loop and it completes within governor limits.
  - Depends on: VS-08

### VS-13 — VS_IOtpProvider + VS_OtpService (stub)
- **Issue Type:** Story (functional Apex service + interface)
- **Epic:** EP-06 — Citizen Access & Discovery
- **Sprint:** 3
- **Routing label:** dev-senior
- **Estimate:** M → **Story Points:** 5
- **Priority:** Medium
- **Upstream IDs:** REQ-004 (enabler), A-004 / EP-06 / D-013
- **Labels:** EP-06, dev-senior, F-001
- **Description:** Build `VS_IOtpProvider` interface + `VS_OtpService` with a POC stub provider
  (fixed test code, D-013) so mobile+OTP auth works in the scratch org without a live SMS gateway;
  a real provider swaps in later with zero caller change.
  Acceptance criteria:
  - Given a mobile number, when a citizen requests an OTP, then `VS_OTP_Verification__c` stores
    only `VS_Mobile__c` + a hashed code + expiry — never plaintext.
  - Given the POC stub provider, when an OTP is requested, then a fixed test code is issued
    (documented for QA) instead of a live SMS send.
  - Given `VS_IOtpProvider` is an interface, when a real provider is built later, then it swaps in
    with zero change to `VS_OtpService`'s callers.
  - Given 3 failed verify attempts, when a 4th is tried, then it is rejected with a user-actionable
    message.
  - Depends on: VS-07

### VS-14 — Experience Cloud citizen site + sharing set
- **Issue Type:** Task (site + sharing-set configuration, not custom code)
- **Epic:** EP-06 — Citizen Access & Discovery
- **Sprint:** 3
- **Routing label:** dev-mid
- **Estimate:** M → **Story Points:** 5
- **Priority:** Medium
- **Upstream IDs:** REQ-001, REQ-056, REQ-057 (site baseline) / EP-06 / D-013
- **Labels:** EP-06, dev-mid, F-001
- **Description:** Stand up the Experience Cloud citizen site with `VS_Citizen_Community` permission
  set and a sharing set keyed to the OTP-verified mobile number, so citizens see only their own
  patients/appointments.
  Acceptance criteria:
  - Given the site is deployed, when an OTP-verified citizen logs in, then a sharing set grants
    visibility only to patients/appointments matching their verified mobile (§6.2).
  - Given a citizen without a verified session, when they try to view another mobile's bookings by
    guessing a URL, then access is denied.
  - Given the site theme, when checked at 200% zoom, then layout remains usable (baseline check;
    full accessibility asserted in VS-16).
  - Depends on: VS-04, VS-13

### VS-15 — Facility/service discovery LWC (search by service + proximity)
- **Issue Type:** Story (LWC)
- **Epic:** EP-06 — Citizen Access & Discovery
- **Sprint:** 3
- **Routing label:** dev-senior
- **Estimate:** M → **Story Points:** 5
- **Priority:** Medium
- **Upstream IDs:** REQ-001, REQ-005 / EP-06
- **Labels:** EP-06, dev-senior, F-001
- **Description:** Build a discovery LWC letting citizens search active facility+service offerings
  and order results by proximity, degrading gracefully on 3G-class connections.
  Acceptance criteria:
  - Given a citizen searches by service type, when results return, then only active facilities
    offering that service appear.
  - Given the citizen's approximate location, when results are shown, then facilities are ordered
    by proximity using Geolocation.
  - Given a 3G-class connection, when the component loads, then it degrades gracefully (no heavy
    assets, works without map tiles if unavailable).
  - Depends on: VS-01, VS-14

### VS-16 — Citizen booking journey LWC (book/view/cancel/reschedule)
- **Issue Type:** Story (LWC + imperative Apex integration)
- **Epic:** EP-06 — Citizen Access & Discovery
- **Sprint:** 3
- **Routing label:** dev-senior
- **Estimate:** L → **Story Points:** 8
- **Priority:** Medium
- **Upstream IDs:** REQ-002, REQ-003, REQ-005, REQ-006, REQ-015, REQ-028 (printable), REQ-056,
  REQ-057, REQ-060 / EP-06 / D-019, D-020, D-010, D-016
- **Labels:** EP-06, dev-senior, F-001
- **Description:** Build the citizen-facing LWC covering the full book/view/cancel/reschedule
  journey, calling `VS_BookingService.book()`/`cancel()`/`reschedule()` (VS-09/VS-11) imperatively,
  fully accessible (WCAG 2.1 AA) and localization-ready (Custom Labels only, no hardcoded strings).
  Acceptance criteria:
  - Given a citizen picks facility/service/date/slot and confirms, when submitted, then the LWC
    calls `VS_BookingService.book()` and shows the returned booking reference or a user-actionable
    error.
  - Given the same screen, when a citizen cancels or reschedules, then it calls
    cancel/reschedule and reflects the cut-off rule with a plain-language message when blocked.
  - Given a screen-reader or keyboard-only user, when they operate the whole journey, then every
    control is reachable and ARIA-labelled with no mouse required.
  - Given slot availability states, when rendered, then they carry a text label, not colour alone.
  - Given a successful booking, when the confirmation screen is viewed, then it is printable and
    shows essential details.
  - Given all citizen-facing strings, when inspected, then they use Custom Labels (no hardcoded
    English) so Marathi/Hindi localization is additive later.
  - Depends on: VS-09, VS-11, VS-14, VS-15

### VS-17 — VS_Notification_Log__c object & fields
- **Issue Type:** Task (pure object/field metadata)
- **Epic:** EP-07 — Notification Seam
- **Sprint:** 4
- **Routing label:** dev-mid
- **Estimate:** S → **Story Points:** 2
- **Priority:** Medium
- **Upstream IDs:** REQ-058 (metadata only), REQ-059 (object) / EP-07 / D-014
- **Labels:** EP-07, dev-mid, F-001
- **Description:** Build `VS_Notification_Log__c` as the durable record every notification writes
  to (D-014 log-only architecture) — lookups to Patient/Appointment, channel, template name, message
  body, status, provider, helpline-included flag, sent-at.
  Acceptance criteria:
  - Given `VS_Notification_Log__c` deploys, when inspected, then it has lookups to
    Patient/Appointment, `VS_Channel__c`, `VS_Template_Name__c`, `VS_Message_Body__c`,
    `VS_Status__c` (Logged/Sent/Failed), `VS_Provider__c`, `VS_Helpline_Included__c`,
    `VS_Sent_At__c`, each described.
  - Depends on: VS-08

### VS-18 — VS_ISmsProvider + VS_SmsService (log-only)
- **Issue Type:** Story (functional Apex service + interface)
- **Epic:** EP-07 — Notification Seam
- **Sprint:** 4
- **Routing label:** dev-senior
- **Estimate:** M → **Story Points:** 5
- **Priority:** Medium
- **Upstream IDs:** REQ-002 (confirmation deliverable), REQ-058, REQ-059 / EP-07 / D-014
- **Labels:** EP-07, dev-senior, F-001
- **Description:** Build `VS_ISmsProvider` interface + `VS_SmsService`, the POC implementation of
  which is **log-only per D-014 — it writes a `VS_Notification_Log__c` row and sends NO real SMS**.
  This preserves the send surface (DLT template name, helpline-included flag per C7.1-7.3) so a real
  gateway can implement the same interface later with zero caller redesign; SMS vendor/DLT
  registration is explicitly deferred and does not block F-001.
  Acceptance criteria:
  - Given `VS_ISmsProvider` is an interface and `VS_SmsService` is its POC log-only implementation,
    when a confirmation is triggered, then a `VS_Notification_Log__c` row is written with
    `VS_Provider__c` = "LogOnly", `VS_Status__c` = "Logged", the DLT template name, and
    `VS_Helpline_Included__c` = true for actionable templates — no real SMS is sent (D-014).
  - Given a real gateway is built later, when it implements `VS_ISmsProvider`, then no caller of
    `VS_SmsService` changes.
  - Given the service is called in bulk (e.g., confirming 200 bookings), when it runs, then no
    SOQL/DML executes inside a loop.
  - Depends on: VS-17

### VS-19 — Booking-confirmation record-triggered flow
- **Issue Type:** Task (simple background record-triggered automation, not user-facing)
- **Epic:** EP-07 — Notification Seam
- **Sprint:** 4
- **Routing label:** dev-mid
- **Estimate:** S → **Story Points:** 2
- **Priority:** Medium
- **Upstream IDs:** REQ-002, REQ-028 / EP-07 / D-014
- **Labels:** EP-07, dev-mid, F-001
- **Description:** Build `VS_Appointment_AfterSave_LogConfirmation`, the record-triggered flow that
  invokes the log-only notification seam (VS-18) exactly once per new appointment, with a fault path
  that never rolls back the underlying booking.
  Acceptance criteria:
  - Given `VS_Appointment__c` is inserted with status Booked or WalkIn, when the flow fires, then it
    invokes the notification seam exactly once per appointment.
  - Given the invocable Apex action throws, when the flow runs, then the fault path writes
    `VS_Error_Log__c` and does not roll back the underlying appointment.
  - Depends on: VS-08, VS-18

### VS-20 — Facility-scoped sharing rules + district View All
- **Issue Type:** Task (sharing-rule configuration, not custom code)
- **Epic:** EP-08 — Security, Sharing & Compliance
- **Sprint:** 4
- **Routing label:** dev-mid
- **Estimate:** M → **Story Points:** 5
- **Priority:** Medium (see priority-basis note above — role-based visibility is Tier-1; carries the
  `Tier-1` label)
- **Upstream IDs:** REQ-053 / EP-08
- **Labels:** EP-08, dev-mid, F-001, Tier-1
- **Description:** Configure criteria-based sharing rules keyed on `VS_Facility__c` so facility
  staff see only their own facility's citizens/appointments, and a compliance-tier View All for
  District Admin/MIS (C5.1 "justified + audited").
  Acceptance criteria:
  - Given a facility-staff user is a member of that facility's public group, when they query
    `VS_Appointment__c`/`VS_Patient__c`, then sharing returns only their facility's records.
  - Given the same user tries to open a record from a different facility by Id, when accessed, then
    it is not visible (insufficient privileges).
  - Given `VS_District_Admin`/`VS_District_MIS`, when they query the same objects, then View All on
    the compliance permission set grants aggregate/record-level access.
  - Depends on: VS-04, VS-08

### VS-21 — VS_RetentionPurgeBatch (per-class policy)
- **Issue Type:** Story (functional scheduled Apex batch)
- **Epic:** EP-08 — Security, Sharing & Compliance
- **Sprint:** 4
- **Routing label:** dev-senior
- **Estimate:** M → **Story Points:** 5
- **Priority:** Medium
- **Upstream IDs:** REQ-052, REQ-062 (bulk) / EP-08
- **Labels:** EP-08, dev-senior, F-001
- **Description:** Build a scheduled batch that archives/purges `VS_Appointment__c`/
  `VS_Notification_Log__c`/`VS_OTP_Verification__c` rows per their retention-class threshold in
  `VS_Setting__mdt` (bookings 3yr, SMS logs 1yr, audit 3yr, OTP daily), never purging a patient
  ahead of its longest-linked record.
  Acceptance criteria:
  - Given per-class retention policy in `VS_Setting__mdt`, when the scheduled batch runs, then
    eligible rows older than their class threshold are archived/purged per policy.
  - Given a `VS_Patient__c` is linked to a still-retained booking, when the purge evaluates the
    patient, then it is NOT purged before its longest-linked record's retention expires.
  - Given 200+ eligible rows (bulk posture), when the batch runs, then no SOQL/DML executes in a
    loop.
  - Depends on: VS-02, VS-07, VS-08, VS-17

### VS-22 — Synthetic seed data script
- **Issue Type:** Task (seed-data script, per explicit routing instruction)
- **Epic:** EP-08 — Security, Sharing & Compliance
- **Sprint:** 4
- **Routing label:** dev-mid
- **Estimate:** S → **Story Points:** 2
- **Priority:** Medium
- **Upstream IDs:** REQ-051 / EP-08
- **Labels:** EP-08, dev-mid, F-001
- **Description:** Build a seed script producing fictional facilities, sessions, slots, and patients
  for the scratch/dev org, with no real PII and no Aadhaar-shaped values anywhere (rules/10).
  Acceptance criteria:
  - Given the seed script runs against the scratch/dev org, when it completes, then it creates
    fictional facilities, sessions, slots, and patients with no real PII and no Aadhaar-shaped
    values anywhere.
  - Given the script is re-run, when executed, then it does not duplicate reference data (idempotent
    or clearly reset-first).
  - Depends on: VS-01, VS-05, VS-07, VS-08

---

## Status history (append-only: `date | VS-## | old→new | by | note`)

- 2026-07-11 | VS-01 | —→Backlog | pm-planner | created, EP-01, dev-mid, Sprint 1
- 2026-07-11 | VS-02 | —→Backlog | pm-planner | created, EP-01, dev-mid, Sprint 1
- 2026-07-11 | VS-03 | —→Backlog | pm-planner | created, EP-01, dev-mid, Sprint 1, depends VS-01/02
- 2026-07-11 | VS-04 | —→Backlog | pm-planner | created, EP-08, dev-mid, Sprint 1, depends VS-01
- 2026-07-11 | VS-05 | —→Backlog | pm-planner | created, EP-02, dev-mid, Sprint 1, depends VS-01
- 2026-07-11 | VS-06 | —→Backlog | pm-planner | created, EP-02, dev-senior, Sprint 1, depends VS-01/02/05 — crown-jewel-adjacent, bulk-safety AC required
- 2026-07-11 | VS-07 | —→Backlog | pm-planner | created, EP-05, dev-mid, Sprint 1 — no-Aadhaar structural AC (REQ-044)
- 2026-07-11 | VS-08 | —→Backlog | pm-planner | created, EP-03, dev-mid, Sprint 1, depends VS-01/05/07
- 2026-07-11 | VS-09 | —→Backlog | pm-planner | created, EP-03, dev-senior, Sprint 1, depends VS-01/02/05/07/08 — **crown jewel**: single VS_Session__c FOR UPDATE lock (D-019/D-020), ONE method for all channels, capacity-exhaustion + mixed online/walk-in parallel-booking tests mandatory
- 2026-07-11 | VS-10 | —→Backlog | pm-planner | created, EP-05, dev-senior, Sprint 2, depends VS-07
- 2026-07-11 | VS-11 | —→Backlog | pm-planner | created, EP-04, dev-senior, Sprint 2, depends VS-09 — reuses session lock, deadlock-safe ordering across sessions
- 2026-07-11 | VS-12 | —→Backlog | pm-planner | created, EP-04, dev-senior, Sprint 2, depends VS-08
- 2026-07-11 | VS-13 | —→Backlog | pm-planner | created, EP-06, dev-senior, Sprint 3, depends VS-07
- 2026-07-11 | VS-14 | —→Backlog | pm-planner | created, EP-06, dev-mid, Sprint 3, depends VS-04/13
- 2026-07-11 | VS-15 | —→Backlog | pm-planner | created, EP-06, dev-senior, Sprint 3, depends VS-01/14
- 2026-07-11 | VS-16 | —→Backlog | pm-planner | created, EP-06, dev-senior, Sprint 3, depends VS-09/11/14/15
- 2026-07-11 | VS-17 | —→Backlog | pm-planner | created, EP-07, dev-mid, Sprint 4, depends VS-08
- 2026-07-11 | VS-18 | —→Backlog | pm-planner | created, EP-07, dev-senior, Sprint 4, depends VS-17 — log-only per D-014, no live SMS
- 2026-07-11 | VS-19 | —→Backlog | pm-planner | created, EP-07, dev-mid, Sprint 4, depends VS-08/18
- 2026-07-11 | VS-20 | —→Backlog | pm-planner | created, EP-08, dev-mid, Sprint 4, depends VS-04/08
- 2026-07-11 | VS-21 | —→Backlog | pm-planner | created, EP-08, dev-senior, Sprint 4, depends VS-02/07/08/17
- 2026-07-11 | VS-22 | —→Backlog | pm-planner | created, EP-08, dev-mid, Sprint 4, depends VS-01/05/07/08
- 2026-07-11 | ALL | n/a | pm-planner | Jira MCP not connected (D-004) — worked file-locally; no Jira keys assigned; mirror when connected
- 2026-07-11 | ALL | n/a | pm-planner | Import-prep enrichment: added "Detailed ticket specs (Jira-import source)" section above and produced 02-build/jira-import.csv (8 epics + 22 stories/tasks) for manual CSV import into Jira project SCRUM (site ayushkadam28.atlassian.net). No ticket, routing, estimate, or scope changed — packaging only. Jira MCP still not connected (D-004); issue keys will be assigned by Jira on import, so cross-ticket dependency links must be added manually post-import using the "Depends on:" lines in each ticket's description above.

## Write-access note (per rules/00)

pm-planner creates tickets and sets initial status (Backlog) only. dev-senior/dev-mid append status
transitions as they pick up work (e.g., Backlog→In Progress→Ready for Review); qa-lead/qa-engineer do
not write here. Nobody but pm-planner creates new VS-## rows.
- 2026-07-11 | ALL | Backlog→Backlog(Jira) | human | 30 items imported to Jira (SCRUM-5..34); keys recorded in register
- 2026-07-11 | VS-01 | Backlog→In Progress | dev-mid | started build: 5 capacity-spine objects (VS_Facility__c, VS_Service__c, VS_Facility_Service__c, VS_Session__c, VS_Holiday__c) per design §2.3
- 2026-07-11 | VS-01 | In Progress→Ready for Review | dev-mid | 32 fields across 5 objects drafted under force-app/main/default/objects/, all described, VS_ prefixed; AC2 flags a hard deploy-order dependency on VS-02 (VS_Setting__mdt); AC3 mechanism flagged as A-008 (unverified default-value-formula pattern); review packet at 02-build/review-notes/VS-01-review.md; NOT deployed, dry-run NOT run in this environment
- 2026-07-11 | VS-01 | Ready for Review (fix applied) | dev-mid | pre-formal-review fix-forward: VS_Facility_Service__c.VS_External_Id__c's original default-value-formula pattern was a confirmed deploy-blocking defect (formula fields cannot be externalId/unique; default values cannot reference sibling fields) — corrected to a plain Text field populated by new before-save flow VS_FacilityService_BeforeSave_SetExternalId (force-app/main/default/flows/); A-008 amended (not deleted); review packet AC-3/assumptions/deploy-status sections updated; still NOT deployed, dry-run still NOT run in this environment
- 2026-07-11 | VS-01 | Ready for Review→Approved (with batched fixes) | human (/dev-review) | code-reviewer pass: no blocker, design-faithful/compliant/standards-clean, defect fix confirmed. Verdict APPROVE-WITH-FIXES: proceed to VS-02, BATCH M-2 (Create-only key flow → CreateAndUpdate) + N-1 (packet field count 12/33) before BA_ARCH_CONFIRM; M-1 (VS-01+VS-02 same-pass deploy-order + Value__c contract) → devops DP-001 runbook. Verdict + deferred fixes recorded in review packet.
- 2026-07-11 | VS-02 | Backlog→In Progress | dev-mid | started build: VS_Setting__mdt custom metadata type (Value__c/Value_Text__c fields) + 6 seed records per D-008/009/010 + BookingHorizonDays/NoShowThresholdCount/ReminderOffsetsHours
- 2026-07-11 | VS-02 | In Progress→Ready for Review | dev-mid | VS_Setting__mdt drafted under force-app/main/default/objects/VS_Setting__mdt/ (type + Value__c + Value_Text__c, both described) + 6 customMetadata records under force-app/main/default/customMetadata/ (CutOffHours=4, WalkInReservePct=25, DefaultSlotGranularityMins=15, BookingHorizonDays=14, NoShowThresholdCount=3, ReminderOffsetsHours="24,3" via Value_Text__c); VS-01 CONTRACT verified and satisfied — field named exactly Value__c, record DeveloperName exactly WalkInReservePct, matching VS_Session__c.VS_Walk_In_Reserve_Count__c's formula `$CustomMetadata.VS_Setting__mdt.WalkInReservePct.Value__c`; A-009 logged (BookingHorizonDays/NoShowThresholdCount/ReminderOffsetsHours use BA-suggested-default values from OQ-006/007/005, all still status Open, not human-signed decisions like D-008/009/010); review packet at 02-build/review-notes/VS-02-review.md; NOT deployed, no dry-run run in this environment — must deploy in the SAME pass as VS-01 (M-1, devops DP-001) to the Developer Edition org (D-025)
