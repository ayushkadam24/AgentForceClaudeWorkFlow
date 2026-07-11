<!--
feature:         F-001 slot-booking-core
producing-agent: pm-planner
date:            2026-07-11
phase:           SPRINT_PLANNED
derives-from:    01-discovery/technical-design.md (EP-01..EP-08, §7.1 REQ traceability)
                 01-discovery/requirements-brief.md (REQ-001..062, personas P1-P8)
                 .claude/memory/decisions.md (D-005..D-020, esp. D-019/D-020 single-lock booking service)
                 .claude/skills/jira-tickets/SKILL.md, .claude/rules/{00,20,30}
downstream:      02-build/jira-log.md (ticket status mirror), dev-senior/dev-mid implementation,
                 03-qa/test-plan.md (TC-### will cite these VS-##)
-->

# F-001 Sprint Plan — Citizen Slot-Booking Core

**Jira status:** Atlassian MCP is **not connected** (D-004, deferred). This file and
`02-build/jira-log.md` are the ticket source of truth, worked **file-locally**. No Jira keys are
recorded below; when Jira is connected, mirror VS-## IDs into the "Public Health App" project
(key to be renamed to `VS`) and record the Jira key alongside each VS-## at that time.

**Scope guardrail:** every ticket below traces to EP-01..EP-08 only (human sign-off, 2026-07-11).
No ticket exists for REQ-054 per-record read audit (known POC limitation — Shield absent, A-006) or
for reminders/next-dose/check-in/vaccination-recording/stock/certificates/dashboards/chat-assistant
(all explicitly Deferred beyond F-001 per technical-design.md §7.1). The EP-07 notification **seam**
(log-only) is in scope; live SMS send is not.

**Routing key:** dev-senior = booking/slot-integrity service, anything transactional/async, LWC with
imperative Apex, trigger framework. dev-mid = object/field/metadata, permission sets, validation
rules, record-triggered/scheduled flows, page layouts, simple screen flows, seed scripts (skill
`jira-tickets`).

---

## Sprint 1 — Foundations: data model, permission sets, session/slot generation, the single booking service

**Sprint goal:** stand up every object EP-01..EP-03 need, the base security model, and the one
`VS_BookingService.book()` path (D-019/D-020) proven safe under concurrency — nothing later waits
on an unbuilt dependency.

| ID | Title | Story | AC (Given/When/Then) | Links | Est. | Routing | Depends on |
|---|---|---|---|---|---|---|---|
| VS-01 | Build facility/service/session capacity objects | As a Medical Officer in Charge (P6), I want facility, service, and session data modeled with capacity fields, so that I can define what my facility offers and how much capacity each session carries. | 1) Given the org has no F-001 objects, when this ticket deploys, then `VS_Facility__c`, `VS_Service__c`, `VS_Facility_Service__c`, `VS_Holiday__c`, `VS_Session__c` exist with every field from design §2.3, each with a description. 2) Given `VS_Session__c.VS_Total_Capacity__c` is set, when the record saves, then `VS_Walk_In_Reserve_Count__c` and `VS_Bookable_Capacity__c` formula fields compute per §2.1 (CEILING against `VS_Setting__mdt.WalkInReservePct`). 3) Given `VS_Facility_Service__c`, when two records are created for the same facility+service, then the `VS_External_Id__c` unique constraint rejects the duplicate. | REQ-001, REQ-009, REQ-010, REQ-011, REQ-012 / EP-01 | M | dev-mid | — |
| VS-02 | Create VS_Setting__mdt config + seed values | As a Medical Officer in Charge (P6), I want scheduling rules (walk-in %, cut-off hours, slot granularity, booking horizon) held as tunable config, so that DHS can adjust them without a code change. | 1) Given `VS_Setting__mdt` is deployed, when queried, then it exposes `CutOffHours` (=4), `WalkInReservePct` (=25), `DefaultSlotGranularityMins` (=15), `BookingHorizonDays` (=14), `ReminderOffsetsHours`, `NoShowThresholdCount` as named records. 2) Given a value changes in Setup, when any consuming formula/Apex re-reads it, then no code redeploy is needed (rules/20 — no hardcoded tunables). | REQ-007, REQ-009, REQ-013, REQ-014, REQ-015 / EP-01 | S | dev-mid | — |
| VS-03 | MO screen flow: define session capacity + drive-day | As a Medical Officer in Charge (P6), I want a guided screen to create sessions, set capacity, and mark drive days, so that I can stand up bookable capacity without developer help. | 1) Given a facility+service+date, when MO runs `VS_Session_Screen_DefineCapacity`, then a `VS_Session__c` is created with `VS_Total_Capacity__c` set and reserve/bookable formulas populated. 2) Given the MO checks "Drive Day," when saved, then `VS_Is_Drive_Day__c` = true so slot generation (VS-06) will open this date even if `VS_Holiday__c` marks it closed (D-018). 3) Given a flow element fails, when the screen runs, then a fault path shows a plain-language message + facility helpline (C7.3) and writes `VS_Error_Log__c`. | REQ-010, REQ-011, REQ-012 / EP-01 | M | dev-mid | VS-01, VS-02 |
| VS-04 | Permission sets, OWD, session timeout, MIS export gate | As a District Health Officer (P7), I want role-based permission sets and org-wide defaults configured, so that each role sees only the data it should. | 1) Given OWD is set, when checked, then reference/bookable objects (Facility, Service, Facility_Service, Session, Slot, Holiday) = Public Read Only and person/booking objects (Patient, Appointment, Notification_Log, OTP_Verification) = Private (§6.2). 2) Given permission sets `VS_Facility_Staff`, `VS_Nurse`, `VS_MO_Facility_Admin`, `VS_District_Admin`, `VS_District_MIS`, `VS_Citizen_Community` are assigned, when a user without one logs in, then they get no access beyond OWD. 3) Given a shared-device role's permission set, when idle 15 minutes, then the session times out (REQ-055). 4) Given `VS_District_MIS`, when the permission set is inspected, then it alone carries the export/bulk-data permission bit (REQ-036 role-gating only — export UI itself remains Deferred; no export mechanism is built in this ticket). | REQ-036 (gating only), REQ-055 / EP-08 | M | dev-mid | VS-01 |
| VS-05 | VS_Slot__c object & fields | As a citizen (P1), I want bookable 15-minute slots to exist under each session, so that I can pick a specific time to visit. | 1) Given `VS_Slot__c` deploys, when inspected, then it has Master-Detail to `VS_Session__c`, `VS_Slot_Start__c`/`VS_Slot_End__c`, `VS_Capacity__c`, `VS_Booked_Count__c`, `VS_Status__c` (Open/Full/Closed/Cancelled), each described. 2) Given a session is deleted, when cascading, then its slots cascade per Master-Detail (no orphan slots). | REQ-008, REQ-009, REQ-014 / EP-02 | S | dev-mid | VS-01 |
| VS-06 | VS_SlotGenBatch: generate slots from sessions | As a Medical Officer in Charge (P6), I want slots automatically generated from session capacity respecting holidays and drive-day overrides, so that citizens see accurate bookable windows without manual slot creation. | 1) Given a `VS_Session__c` with `VS_Bookable_Capacity__c` = 60 and 15-min granularity, when the batch runs, then it creates 15-min `VS_Slot__c` rows whose `VS_Capacity__c` sum equals 60 exactly (A-005 even split, remainder to earliest slots). 2) Given a facility date is in `VS_Holiday__c` and no session is flagged `VS_Is_Drive_Day__c` for that date, when the batch runs, then no slots are generated for that date/facility. 3) Given a date is a holiday but a session for that date has `VS_Is_Drive_Day__c` = true, when the batch runs, then slots ARE generated for that session only (D-018). 4) Given `BookingHorizonDays` = 14, when the batch runs, then no slots are generated beyond the horizon. 5) Given 250+ sessions queued for generation (REQ-062 bulk posture), when the batch runs, then it completes with no SOQL/DML in loops and no governor-limit exceptions (bulk test, 200+ records). | REQ-009, REQ-012, REQ-013, REQ-014, REQ-062 (bulk) / EP-02 | L | dev-senior | VS-01, VS-02, VS-05 |
| VS-07 | VS_Patient__c object & fields (C1-minimal, no-Aadhaar) | As an assisted citizen booking for family (P2), I want the system to record only the minimum required patient details with no Aadhaar, so that my family's bookings stay compliant and private. | 1) Given `VS_Patient__c` deploys, when inspected, then its only person fields are `VS_Full_Name__c`, `VS_Date_Of_Birth__c`, `VS_Gender__c` (optional), `VS_Mobile__c`, `VS_Locality__c`, `VS_Pincode__c`, `VS_Email__c` (optional) — exactly C1.1, nothing more. 2) Given the object and org metadata are searched for any Aadhaar-named field/label anywhere, when the check runs, then zero matches exist (REQ-044, QA Tier-1 will re-verify). 3) Given `VS_Match_Key__c` is marked ExternalId+Unique, when two patient records are inserted with the same normalize(name)|DOB|mobile, then the second insert is rejected at the DB (D-017, proven in VS-10). 4) Given `VS_Consent_Given__c`/`VS_Consent_Timestamp__c` exist, when a patient is created without consent = true, then the record is not usable for booking (enforced in VS-10). | REQ-043, REQ-044, REQ-045, REQ-046 / EP-05 | S | dev-mid | — |
| VS-08 | VS_Appointment__c object & fields | As a citizen (P1), I want my booking recorded with a unique reference and status, so that I can prove and manage my appointment. | 1) Given `VS_Appointment__c` deploys, when inspected, then it has lookups to Patient/Slot/Session/Facility/Service, `VS_Booking_Reference__c` (ExternalId+Unique), `VS_Status__c` (Booked/CheckedIn/Completed/Cancelled/NoShow/WalkIn), `VS_Booked_Channel__c` (Portal/Chat/Staff/WalkIn), `VS_Booked_By_Mobile__c`, `VS_Dose_Number__c`, `VS_Cancelled_At__c`. 2) Given the object is scanned for clinical/diagnosis fields (REQ-045), when checked, then none exist. | REQ-002, REQ-008, REQ-019 (field only; check-in UI deferred), REQ-045 / EP-03 | S | dev-mid | VS-01, VS-05, VS-07 |
| VS-09 | VS_BookingService.book() — single session-lock booking | As a citizen (P1), I want my slot booking confirmed only if capacity truly remains — even if many people book at once — so that I am never turned away after being told I have a slot. | 1) Given a session with one remaining bookable slot place, when 50 parallel `book()` calls target that slot, then exactly one appointment is created, `VS_Slot__c.VS_Booked_Count__c` never exceeds `VS_Capacity__c`, and every other call catches `VS_BookingException('SLOT_FULL')` (REQ-008, D-019 concurrency test). 2) Given a session with one remaining walk-in reserve place, when 50 parallel `book(..., 'WalkIn')` calls fire, then exactly one succeeds and the rest catch `VS_BookingException('RESERVE_FULL')`; `VS_Walk_In_Used_Count__c` never exceeds `VS_Walk_In_Reserve_Count__c`. 3) Given a session with exactly one remaining place shared across channels, when a **mixed burst** of online and walk-in `book()` calls fires simultaneously at that session, then exactly one booking of any type succeeds and no overbooking occurs (the D-015-retracted case D-019 must prove). 4) Given `book()` succeeds, when the appointment is inserted, then it carries a unique `VS_Booking_Reference__c` from `VS_ReferenceGenerator` (8-char Crockford base32, D-016) and the insert uses `WITH USER_MODE`/`Security.stripInaccessible` (CRUD/FLS). 5) Given the method signature, when reviewed, then there is exactly **one** public entry point `VS_BookingService.book(patientId, slotId, bookedById, channel)` for online, staff, and walk-in — no separate `VS_WalkInService`, no second lock target (D-019/D-020). 6) Test class includes a capacity-exhaustion test AND the parallel/mixed-burst test (both required by human sign-off), plus a negative test (invalid slot/closed session) with a meaningful assert on final row counts, not just "no exception." | REQ-002, REQ-006, REQ-007, REQ-008, REQ-062 (bulk/session-scoped) / EP-03 | L | dev-senior | VS-01, VS-02, VS-05, VS-07, VS-08 |

---

## Sprint 2 — Patient de-dup, cancel/reschedule, no-show (EP-04, EP-05 completion)

**Sprint goal:** close the booking lifecycle (de-dup on entry, cancel/reschedule with cut-off,
automatic no-show) — all reusing the single session-lock pattern from Sprint 1, no new lock target.

| ID | Title | Story | AC (Given/When/Then) | Links | Est. | Routing | Depends on |
|---|---|---|---|---|---|---|---|
| VS-10 | VS_PatientService.findOrCreate (exact-match de-dup) | As an assisted citizen managing bookings for multiple family members from one mobile (P2), I want the system to recognize the same patient by exact name+DOB+mobile match and avoid duplicate records, so that each family member's history stays accurate. | 1) Given a patient with name="Asha Patil", DOB=1990-05-01, mobile=9876543210 already exists, when `findOrCreate` is called with the identical normalized triple, then the existing `VS_Patient__c` Id is returned — no new row (D-011, exact match only, no fuzzy). 2) Given any single field differs (e.g., different DOB), when called, then a NEW patient is created (D-011 — possible duplicates accepted as a known POC limitation, not silently merged). 3) Given two `findOrCreate` calls race for the same new match key, when both commit, then the DB-level unique constraint on `VS_Match_Key__c` prevents a duplicate insert (D-017, race-safe by upsert, not by a prior SOQL check). 4) Given `VS_Consent_Given__c` is not passed as true, when `findOrCreate` runs for a new patient, then the method throws rather than create a patient without consent, and stamps `VS_Consent_Timestamp__c` on success (REQ-046). | REQ-004, REQ-043, REQ-045, REQ-046 / EP-05 | M | dev-senior | VS-07 |
| VS-11 | VS_BookingService.cancel/reschedule (cut-off, session-lock reuse) | As a citizen (P1), I want to cancel or reschedule my booking up until 4 hours before my slot, so that I can adjust my plans and free the slot for someone else. | 1) Given the current time is within `CutOffHours` (4h) of the slot start, when a citizen calls `cancel()`, then the call is rejected with a user-actionable message (not a stack trace) — REQ-003/015. 2) Given the cut-off has not passed, when `cancel()` succeeds, then the appointment's session row is locked `FOR UPDATE`, the slot's `VS_Booked_Count__c` decrements (or the session's `VS_Walk_In_Used_Count__c` for a walk-in), and slot status flips `Full`→`Open` if applicable, all in one transaction. 3) Given a `reschedule()` moves an appointment from Slot A (session S1) to Slot B (session S2, S1≠S2), when the method runs, then it locks both session rows **ordered by session Id** to avoid deadlock, cancels the old and books the new atomically. 4) Given old and new slots share the same session, when rescheduling, then only one lock is taken. 5) Test class includes a negative test (attempt inside cut-off) and asserts final row/counter state. | REQ-003, REQ-015, REQ-062 (bulk-safe) / EP-04 | L | dev-senior | VS-09 |
| VS-12 | VS_NoShowBatch (scheduled, idempotent) | As facility staff (P4/P5), I want unattended bookings automatically marked no-show at day's end, so that our records reflect real attendance. | 1) Given an appointment with `VS_Status__c` = "Booked" whose slot has passed and no check-in occurred, when the scheduled batch runs at end of day, then its status becomes "NoShow" and `VS_Patient__c.VS_No_Show_Count__c` increments by 1. 2) Given the batch runs twice on the same appointment (idempotency), when it re-runs, then the count does not double-increment. 3) Given 200+ appointments are due for marking (REQ-062 bulk posture), when the batch runs, then no SOQL/DML executes inside a loop and it completes within governor limits. | REQ-016, REQ-062 (bulk) / EP-04 | M | dev-senior | VS-08 |

---

## Sprint 3 — Citizen access & discovery (EP-06)

**Sprint goal:** give citizens a working, accessible front door — OTP auth, facility/service
discovery, and the full book/view/cancel/reschedule journey — on top of the Sprint 1-2 services.

| ID | Title | Story | AC (Given/When/Then) | Links | Est. | Routing | Depends on |
|---|---|---|---|---|---|---|---|
| VS-13 | VS_IOtpProvider + VS_OtpService (stub) | As a citizen (P1), I want to verify my identity with an OTP sent to my mobile, so that I can securely access my bookings without a password or Aadhaar. | 1) Given a mobile number, when a citizen requests an OTP, then `VS_OTP_Verification__c` stores only `VS_Mobile__c` + a **hashed** code + expiry — never plaintext (D-013). 2) Given the POC stub provider, when an OTP is requested in the scratch org, then a fixed test code is issued (documented for QA) instead of a live SMS send (D-013, no real gateway in POC). 3) Given `VS_IOtpProvider` is an interface, when a real provider is built later, then it swaps in with zero change to `VS_OtpService`'s callers (A-004). 4) Given 3 failed verify attempts (`VS_Attempts__c`), when a 4th is tried, then it is rejected with a user-actionable message. | REQ-004 (enabler), A-004 / EP-06 | M | dev-senior | VS-07 |
| VS-14 | Experience Cloud citizen site + sharing set | As a citizen (P1), I want a public web portal where I can log in and see my bookings, so that I have one place to manage my vaccination appointments. | 1) Given the Experience Cloud site is deployed with `VS_Citizen_Community` permission set, when an OTP-verified citizen logs in, then a sharing set keyed to their verified mobile grants visibility only to patients/appointments matching that mobile (§6.2). 2) Given a citizen without a verified session, when they try to view another mobile's bookings by guessing a URL, then access is denied (no cross-citizen leakage). 3) Given the site theme, when checked at 200% zoom, then layout remains usable (REQ-056, baseline check; full accessibility asserted in VS-16). | REQ-001, REQ-056, REQ-057 (site baseline) / EP-06 | M | dev-mid | VS-04, VS-13 |
| VS-15 | Facility/service discovery LWC (search by service + proximity) | As a citizen (P1), I want to search for vaccination services near me by facility and location, so that I can find the most convenient place to book. | 1) Given a citizen searches by service type, when results return, then only active facilities offering that service (`VS_Facility_Service__c.VS_Is_Active__c` = true) appear. 2) Given the citizen's approximate location, when results are shown, then facilities are ordered by proximity using `VS_Facility__c.VS_Location__c` (Geolocation). 3) Given a 3G-class connection (REQ-005), when the component loads, then it degrades gracefully (no heavy assets, works without map tiles if unavailable). | REQ-001, REQ-005 / EP-06 | M | dev-senior | VS-01, VS-14 |
| VS-16 | Citizen booking journey LWC (book/view/cancel/reschedule) | As a citizen (P1), I want to book, view, cancel, and reschedule my appointment through an accessible screen that works on a low-cost smartphone over 3G, so that I can complete the process in under 3 minutes regardless of device or ability. | 1) Given a citizen picks a facility, service, date and slot, when they confirm, then the LWC calls `VS_BookingService.book()` imperatively and shows the returned booking reference (or a user-actionable error) — REQ-002/006. 2) Given the same screen, when a citizen cancels or reschedules, then it calls `VS_BookingService.cancel/reschedule` and reflects the cut-off rule with a plain-language message when blocked (REQ-003/015). 3) Given a screen-reader or keyboard-only user, when they operate the whole booking journey, then every control is reachable and labelled (ARIA) with no mouse required (REQ-056). 4) Given slot availability states (Open/Full/Closed), when rendered, then they carry a text label, not colour alone (REQ-057). 5) Given the confirmation screen after a successful booking, when viewed, then it is printable and shows the essential details (REQ-028 printable aspect). 6) Given all citizen-facing strings, when inspected, then they use Custom Labels (no hardcoded English strings) so Marathi/Hindi localization is additive later (REQ-060). | REQ-002, REQ-003, REQ-005, REQ-006, REQ-015, REQ-028 (printable), REQ-056, REQ-057, REQ-060 / EP-06 | L | dev-senior | VS-09, VS-11, VS-14, VS-15 |

---

## Sprint 4 — Notification seam + security/compliance hardening (EP-07, EP-08 remainder)

**Sprint goal:** close out the two remaining cross-cutting concerns — the log-only notification
seam and facility-scoped sharing / retention / synthetic data — so the build is release-checkable
against Tier-1 QA (slot integrity, no-Aadhaar, facility-scoped visibility already covered earlier).

| ID | Title | Story | AC (Given/When/Then) | Links | Est. | Routing | Depends on |
|---|---|---|---|---|---|---|---|
| VS-17 | VS_Notification_Log__c object & fields | As a citizen (P1), I want every notification about my booking reliably logged, so that there's a dependable record even before real SMS sending goes live. | 1) Given `VS_Notification_Log__c` deploys, when inspected, then it has lookups to Patient/Appointment, `VS_Channel__c`, `VS_Template_Name__c`, `VS_Message_Body__c`, `VS_Status__c` (Logged/Sent/Failed), `VS_Provider__c`, `VS_Helpline_Included__c`, `VS_Sent_At__c`, each described. | REQ-058 (metadata only), REQ-059 (object) / EP-07 | S | dev-mid | VS-08 |
| VS-18 | VS_ISmsProvider + VS_SmsService (log-only) | As a citizen (P1), I want my booking confirmation captured through a replaceable notification service, so that DHS can plug in a real SMS gateway later without redesigning the confirmation flow. | 1) Given `VS_ISmsProvider` is an interface and `VS_SmsService` is its POC log-only implementation, when a confirmation is triggered, then a `VS_Notification_Log__c` row is written with `VS_Provider__c` = "LogOnly", `VS_Status__c` = "Logged", the DLT template name, and `VS_Helpline_Included__c` = true for actionable templates (C7.1-7.3) — no real SMS is sent (D-014). 2) Given a real gateway is built later, when it implements `VS_ISmsProvider`, then no caller of `VS_SmsService` changes (interface isolation, C7.4). 3) Given the service is called in bulk (e.g., a batch confirming 200 bookings), when it runs, then no SOQL/DML executes inside a loop. | REQ-002 (confirmation deliverable), REQ-058, REQ-059 / EP-07 | M | dev-senior | VS-17 |
| VS-19 | Booking-confirmation record-triggered flow | As a citizen (P1), I want a confirmation generated automatically right after I book, so that I have a record of my appointment without extra steps. | 1) Given `VS_Appointment__c` is inserted with `VS_Status__c` ∈ {Booked, WalkIn}, when the after-save flow `VS_Appointment_AfterSave_LogConfirmation` fires, then it invokes the notification seam (VS-18) exactly once per appointment. 2) Given the invocable Apex action throws, when the flow runs, then the fault path writes `VS_Error_Log__c` and does not roll back the underlying appointment (booking must not fail because of a notification issue). | REQ-002, REQ-028 / EP-07 | S | dev-mid | VS-08, VS-18 |
| VS-20 | Facility-scoped sharing rules + district View All | As facility front-desk/nursing staff (P4/P5) and a Medical Officer (P6), I want to see only my own facility's citizens and appointments, so that I never access another facility's records I'm not authorized to see. | 1) Given a facility-staff user is a member of that facility's public group, when they query `VS_Appointment__c`/`VS_Patient__c`, then criteria-based sharing (keyed on `VS_Facility__c`) returns only their facility's records (REQ-053). 2) Given the same user tries to open a record from a different facility by Id, when accessed, then it is not visible (insufficient privileges). 3) Given `VS_District_Admin`/`VS_District_MIS`, when they query the same objects, then View All on the compliance permission set grants aggregate/record-level access, consistent with C5.1's "justified + audited" language. | REQ-053 / EP-08 | M | dev-mid | VS-04, VS-08 |
| VS-21 | VS_RetentionPurgeBatch (per-class policy) | As a District Health Officer (P7), I want records purged or archived automatically per their retention class, so that DHS stays compliant with the retention directive without manual bookkeeping. | 1) Given `VS_Setting__mdt` holds a per-class retention policy (bookings 3yr, SMS logs 1yr, audit 3yr, OTP daily — vaccination 10yr class reserved for the deferred object), when the scheduled batch runs, then eligible `VS_Appointment__c`/`VS_Notification_Log__c`/`VS_OTP_Verification__c` rows older than their class threshold are archived/purged per the documented policy. 2) Given a `VS_Patient__c` is linked to a still-retained booking, when the purge evaluates the patient, then it is NOT purged before its longest-linked record's retention expires (§6.5). 3) Given 200+ eligible rows (bulk posture), when the batch runs, then no SOQL/DML executes in a loop. | REQ-052, REQ-062 (bulk) / EP-08 | M | dev-senior | VS-02, VS-07, VS-08, VS-17 |
| VS-22 | Synthetic seed data script | As the delivery team building and testing this system (enabler ticket — no P1-P8 persona applies), I want realistic synthetic (fictional) citizen, facility, and session data, so that development and testing never touch real or Aadhaar-linked data. | 1) Given the seed script runs against the scratch/dev org, when it completes, then it creates fictional facilities, sessions, slots, and patients with no real PII and no Aadhaar-shaped values anywhere (REQ-051, rules/10). 2) Given the script is re-run, when executed, then it does not duplicate reference data (idempotent or clearly reset-first). | REQ-051 / EP-08 | S | dev-mid | VS-01, VS-05, VS-07, VS-08 |

---

## REQ → ticket coverage table (in-scope REQs only: EP-01..EP-08)

| REQ | Requirement (short) | EP | Ticket(s) | Status |
|---|---|---|---|---|
| REQ-001 | Discovery by service + proximity | EP-01/EP-06 | VS-01, VS-14, VS-15 | Covered |
| REQ-002 | Advance booking + confirmation w/ reference | EP-03/EP-07 | VS-08, VS-09, VS-16, VS-18, VS-19 | Covered |
| REQ-003 | Self-service cancel/reschedule + cut-off | EP-04 | VS-11, VS-16 | Covered |
| REQ-004 | One mobile, many patients; booker≠patient | EP-05 | VS-08, VS-10, VS-13 (enabler) | Covered |
| REQ-005 | Usable by low-literacy/elderly, 3G-friendly | EP-06 | VS-15, VS-16 | Covered |
| REQ-006 | Booking completable in < 3 min | EP-03 | VS-09, VS-16 | Covered |
| REQ-007 | Confirmed priority; walk-in from reserve | EP-03 | VS-01, VS-09 | Covered |
| REQ-008 | §3.4 slot-integrity guarantee (highest) | EP-03 | VS-05, VS-06, VS-09 | Covered |
| REQ-009 | Auto slot generation from capacity, holidays | EP-01/EP-02 | VS-01, VS-06 | Covered |
| REQ-010 | Staff define services/capacity per facility | EP-01 | VS-01, VS-03 | Covered |
| REQ-011 | Per-session/time-distributed capacity model | EP-01 | VS-01, VS-03 | Covered |
| REQ-012 | Add capacity on closed day (drive day) | EP-01/EP-02 | VS-01, VS-03, VS-06 | Covered |
| REQ-013 | Configurable booking horizon | EP-02 | VS-02, VS-06 | Covered |
| REQ-014 | Configurable slot granularity | EP-02 | VS-02, VS-05, VS-06 | Covered |
| REQ-015 | Cancel/reschedule cut-off | EP-04 | VS-02, VS-11 | Covered |
| REQ-016 | Auto no-show marking EOD | EP-04 | VS-12 | Covered |
| REQ-019 | Typed booking reference (field only; check-in UI deferred) | EP-03 | VS-08, VS-09 | Covered (partial by design — check-in UI is Deferred, not F-001) |
| REQ-028 | Deliverable over SMS + printable at facility | EP-07 | VS-18, VS-19, VS-16 | Covered |
| REQ-036 | Bulk export restricted to District MIS + logged | EP-08 | VS-04 | Covered — **role-gating only**; export UI/mechanism itself is Deferred (guardrail, no new epic invented) |
| REQ-043 | Collect only C1.1 minimum person fields | EP-05 | VS-07 | Covered |
| REQ-044 | Never collect/store Aadhaar anywhere | EP-08 | VS-07 (structural: field absence) | Covered |
| REQ-045 | Health data limited to appointment lifecycle | EP-05/EP-08 | VS-07, VS-08 | Covered |
| REQ-046 | DPDP consent at registration | EP-05 | VS-07, VS-10 | Covered (wording placeholder — see Needs architect) |
| REQ-050 | India data residency, written confirmation | EP-08 | **none** | **Not ticketed** — org-provisioning/launch-gate action (OQ-014), owner-dependent (DHO/Deshmukh), not developer sprint work. See Needs architect/human. |
| REQ-051 | Synthetic/masked data only in dev/test | EP-08 | VS-22 | Covered |
| REQ-052 | Retention per class, archival/purge possible | EP-08 | VS-21 | Covered |
| REQ-053 | Facility-scoped role-based visibility | EP-08 | VS-04, VS-20 | Covered |
| REQ-054 | Every read attributable (user, timestamp) | EP-08 | **none** | **Explicitly out of scope / known POC limitation** — Shield Event Monitoring absent from scratch org (A-006); human sign-off at gate directed no ticket for this. Field history + Login History is the partial mechanism already in the design; full REQ-054 is a production prerequisite, not F-001 build. |
| REQ-055 | Individual logins, ≤15 min session timeout | EP-08 | VS-04 | Covered |
| REQ-056 | WCAG 2.1 AA, keyboard/screen-reader, 200% zoom | EP-06 | VS-14, VS-16 | Covered |
| REQ-057 | Colour never the only signal | EP-06 | VS-16 | Covered |
| REQ-058 | DLT templates, helpline in every template | EP-07 | VS-17, VS-18 | Covered (metadata/log-only; live DLT registration is a vendor/launch item, D-014) |
| REQ-059 | SMS provider isolated behind interface | EP-07 | VS-18 | Covered |
| REQ-060 | English at launch, i18n-ready architecture | EP-06 | VS-16 | Covered |
| REQ-062 | Bulk/volume posture (~1,900/day, 6,000 peak) | EP-03/EP-08 | VS-06, VS-09, VS-11, VS-12, VS-21 | Covered (bulk-safety AC on each transactional/batch ticket) |

**Every in-scope Must/Should REQ (EP-01..EP-08) maps to at least one ticket except the two named
above (REQ-050, REQ-054), both of which were explicitly excluded from sprint scope at gate sign-off
and are called out here rather than silently dropped.** REQ-017/018/020..027/029..035/037..042/047..049/
061 remain Deferred per technical-design.md §7.1 and are out of this plan by design (not uncovered —
never in scope).

---

## Blocked / Needs architect

1. **REQ-050 residency written confirmation (OQ-014)** — this is an org-provisioning/launch-gate
   action for a human (DHO/Deshmukh), not developer sprint work. No ticket invented. Flagging so it
   is not forgotten before UAT.
2. **A-005 slot-capacity distribution algorithm** — VS-06 implements an even split with remainder to
   the earliest slots. If MOs Shinde/Pawar actually want a front-loaded/weighted distribution once
   they see it, VS-06 will need rework. Not blocking Sprint 1 (assumption already logged, owner DHO).
3. **OQ-013 DPDP consent wording** — VS-07/VS-10 will ship with a placeholder consent string since
   department-approved wording is not yet available. Needs BA/architect to source final copy before
   this is production-ready; does not block Sprint 1/2 build or test.
4. **Per-facility public group membership (VS-20)** — the design assumes facility staff are added to
   their facility's public group; this plan treats initial membership as a manual admin step for the
   POC (no automated user↔facility sync ticket exists in EP-01..08). If the architect intended
   declarative automation (e.g., a Flow syncing a `Facility__c` field on User to group membership),
   that is new scope not currently in any epic — flagging rather than inventing it.
5. **REQ-036 export mechanism** — only the District MIS permission-gating is built (VS-04). If a
   future phase needs an actual export UI/report, that is new epic scope beyond EP-01..08 and should
   come back through the architect, not be silently added here.
