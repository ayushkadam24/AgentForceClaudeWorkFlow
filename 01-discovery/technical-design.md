<!--
feature:         F-001 slot-booking-core
producing-agent: architect
date:            2026-07-11
phase:           ARCH_DESIGN
derives-from:    01-discovery/requirements-brief.md (REQ-001..062)
                 01-discovery/open-questions.md (OQ-001..027)
                 .claude/memory/decisions.md (D-005..D-017)
                 .claude/rules/{00,10,20,30}, skills/{sf-data-model,sf-apex-patterns,flow-patterns}
downstream:      02-build/sprint-plan.md (VS-## tickets via pm-planner), 03-qa/test-plan.md
-->

# F-001 Technical Design — Citizen Slot-Booking Core

## 1. Design goals (ranked)

Ranking per `sf-data-model` skill; every lower goal yields to a higher one on conflict.

1. **Slot integrity under concurrency (RFP §3.4 / REQ-008)** — no overbooking, ever, including 200+
   simultaneous attempts. This is the crown jewel; §4 below is the whole reason the model is shaped
   as it is. QA Tier-1, release-blocking.
2. **Usability for P1/P2 citizens (REQ-005/006/056/057)** — feature-phone / 3G / low-literacy /
   WCAG 2.1 AA on the book-reschedule-cancel journeys.
3. **Compliance envelope (Annexure C / REQ-043..059)** — no Aadhaar, data minimization,
   facility-scoped visibility, retention-by-class, SMS/OTP behind replaceable interfaces.
4. **Operations visibility (REQ-032/033)** — designed-for, built later; the model must not preclude it.

Scope is **vaccination only** for F-001 (D-012); the Service object stays generic so OPD is additive.

---

## 2. Data model

### 2.1 Capacity model — the spine (D-005/D-007/D-008/D-009)

Capacity is authored **per Session** (`VS_Session__c`), the atomic capacity unit. A facility defines
1..n sessions per day (e.g. 9:00–13:00 and 14:00–17:00); a facility that thinks in daily numbers
defines **one** session covering the whole day. This single model satisfies both Mr. Shinde (daily)
and Nurse Pawar (per-session) with no special cases and structurally prevents morning-only booking,
because each session carries and exposes its own capacity.

Capacity flows downward:

```
VS_Session__c.VS_Total_Capacity__c            (MO sets, e.g. 80)          REQ-010/011
  ├─ VS_Walk_In_Reserve_Count__c  = CEILING(Total * WalkInReservePct)     25% -> 20   D-009
  └─ VS_Bookable_Capacity__c      = Total - Walk_In_Reserve_Count         -> 60
        └─ distributed across 15-min VS_Slot__c rows at generation time   D-008
             sum(VS_Slot__c.VS_Capacity__c) == VS_Bookable_Capacity__c    (A-005)
```

The 25% walk-in reserve is held as a **session-level counter** (`VS_Walk_In_Used_Count__c`) that
online slots never draw from (D-009). Online bookers only ever see and consume the 75% carried by
slots. Walk-ins consume the session reserve pool.

**Where the §3.4 ceiling lives (D-015):** although capacity is *authored* on the Session, the
*enforceable* ceiling and the `SELECT … FOR UPDATE` lock live on **`VS_Slot__c`**
(`VS_Capacity__c` / `VS_Booked_Count__c`). This is mandated by rules/20 and by REQ-008's wording
("that **slot's** published capacity"), and it gives **row-scoped** concurrency — contention exists
only between two bookers of the *same* slot, so 6,000/day drive peaks (REQ-062) scale across slots
and facilities. Walk-in serving locks the **Session** row instead (its reserve counter). See §4.

### 2.2 Object catalogue (F-001 build set)

All objects prefixed `VS_` (rules/20); every object and field carries a description. Retention class
(Annexure C4) is stated per object; a per-class purge switch is designed in §6.5. **No Aadhaar field
exists on any object** (REQ-044).

| # | Object | OWD | Purpose | Retention (C4) |
|---|---|---|---|---|
| 1 | `VS_Facility__c` | Public Read Only | PHC/CHC/District Hospital; discoverable reference (REQ-001) | permanent reference |
| 2 | `VS_Service__c` | Public Read Only | Generic service catalogue; vaccination in F-001, service-type for OPD (D-012) | permanent reference |
| 3 | `VS_Facility_Service__c` | Public Read Only | Junction: which service a facility offers (REQ-010) | permanent reference |
| 4 | `VS_Session__c` | Public Read Only | **Atomic capacity unit** (D-007); authors capacity + walk-in reserve | bookings 3 yr |
| 5 | `VS_Slot__c` | Public Read Only | Bookable window; **§3.4 lock target** (REQ-008) | bookings 3 yr |
| 6 | `VS_Holiday__c` | Public Read Only | Per-facility closure dates for slot generation (REQ-009) | permanent reference |
| 7 | `VS_Patient__c` | **Private** | Person, C1-minimal; booker≠patient (REQ-004/043/045) | linked: 10 yr if vaccinated else 3 yr |
| 8 | `VS_Appointment__c` | **Private** | The booking; carries booking reference + status | bookings 3 yr |
| 9 | `VS_Notification_Log__c` | **Private** | Every notification write; SMS/OTP seam (D-014) | SMS logs 1 yr |
| 10 | `VS_OTP_Verification__c` | **Private** | Citizen OTP auth, stub provider (D-013) | transient, purge daily |
| 11 | `VS_Error_Log__c` | **Private** | Apex + Flow fault sink (rules skills) | audit 3 yr |

Config lives in **`VS_Setting__mdt`** (Custom Metadata, not a data object): `CutOffHours=4` (D-010),
`WalkInReservePct=25` (D-009), `DefaultSlotGranularityMins=15` (D-008), `BookingHorizonDays=14`
(REQ-013), `ReminderOffsetsHours`, `NoShowThresholdCount`. No tunable is hardcoded (rules/20, A-003).

**Deferred objects (designed, NOT built in F-001 — non-preclusion):** `VS_Vaccination_Event__c`
(REQ-020/021/024), `VS_Vial__c`/`VS_Stock__c` (REQ-022/023), `VS_Certificate__c` (REQ-029/030/031).
Their lookups (Patient, Appointment, Facility, Service) are reserved in the ERD comments.

### 2.3 Key fields per object

Standard audit fields (CreatedBy/Date etc.) omitted. `ExternalId`/`Unique` marked where relevant.

**`VS_Facility__c`** — `VS_Facility_Type__c` (picklist PHC/CHC/DistrictHospital), `VS_Location__c`
(Geolocation, proximity REQ-001), `VS_Pincode__c`, `VS_Helpline_Number__c` (Phone, C7.3),
`VS_Operating_Start_Time__c`/`VS_Operating_End_Time__c` (Time, REQ-009), `VS_Is_Active__c`,
`VS_External_Id__c` (Text, ExternalId+Unique — CoWIN/U-WIN seam OQ-016).

**`VS_Service__c`** — `VS_Service_Type__c` (picklist Vaccination|OPD, D-012), `VS_Vaccine_Name__c`,
`VS_Slot_Granularity_Mins__c` (Number, default 15, D-008), `VS_Dose_Count__c` (Number, next-dose seam),
`VS_Is_Active__c`, `VS_External_Id__c` (ExternalId+Unique).

**`VS_Facility_Service__c`** — Master-Detail→`VS_Facility__c`, Lookup→`VS_Service__c`,
`VS_Is_Active__c`. Composite uniqueness (facility+service) via `VS_External_Id__c` (Unique).

**`VS_Session__c`** — Master-Detail→`VS_Facility__c`, Lookup→`VS_Service__c`, `VS_Session_Date__c`
(Date), `VS_Start_Time__c`/`VS_End_Time__c` (DateTime), `VS_Total_Capacity__c` (Number, MO-set),
`VS_Walk_In_Reserve_Count__c` (**Formula** = `CEILING(VS_Total_Capacity__c * $CustomMetadata.VS_Setting__mdt.WalkInReservePct.Value__c / 100)`),
`VS_Bookable_Capacity__c` (**Formula** = `VS_Total_Capacity__c - VS_Walk_In_Reserve_Count__c`),
`VS_Walk_In_Used_Count__c` (Number, incremented under Session lock), `VS_Status__c`
(picklist Open|Closed|Cancelled), `VS_Is_Drive_Day__c` (Checkbox — overrides holiday closure, D-018),
`VS_External_Id__c` (Unique). Formula fields mean the reserve split needs **zero automation**.

**`VS_Slot__c`** — Master-Detail→`VS_Session__c`, `VS_Slot_Start__c`/`VS_Slot_End__c` (DateTime),
`VS_Capacity__c` (Number, the enforceable ceiling REQ-008), `VS_Booked_Count__c` (Number, maintained
**only** inside the FOR UPDATE transaction — never by rollup/trigger, rules/20), `VS_Status__c`
(picklist Open|Full|Closed|Cancelled). Master-Detail to Session so slots cascade with session
lifecycle and inherit sharing.

**`VS_Holiday__c`** — Lookup→`VS_Facility__c`, `VS_Holiday_Date__c` (Date), `VS_Description__c`.
Per-facility, staff-maintained (OQ-015 default). Slot generation skips these dates unless a session
is flagged `VS_Is_Drive_Day__c` (OQ-019 / D-018).

**`VS_Patient__c`** — `VS_Full_Name__c`, `VS_Date_Of_Birth__c` (Date — de-dup + next-dose math, OQ-026),
`VS_Gender__c` (picklist, optional), `VS_Mobile__c` (Phone), `VS_Locality__c`, `VS_Pincode__c`,
`VS_Email__c` (Email, optional). **Exactly the C1.1 field set — nothing more (REQ-043/045).**
`VS_Match_Key__c` (Text 255, **ExternalId+Unique** = `normalize(name)|DOB|mobile`, enforces D-011
exact-match de-dup at the DB, D-017). `VS_Consent_Given__c` (Checkbox) + `VS_Consent_Timestamp__c`
(DateTime) for DPDP (REQ-046, wording deferred OQ-013). `VS_No_Show_Count__c` (Number — captured now,
enforcement deferred, REQ-017/OQ-007). **No Aadhaar field, no address beyond locality/pin (REQ-044/045).**

**`VS_Appointment__c`** — Lookup→`VS_Patient__c`, Lookup→`VS_Slot__c` (required), Lookup→`VS_Session__c`
+ Lookup→`VS_Facility__c` + Lookup→`VS_Service__c` (denormalized for sharing/reporting),
`VS_Booking_Reference__c` (Text, **ExternalId+Unique**, non-guessable, D-016, REQ-002/019),
`VS_Status__c` (picklist Booked|CheckedIn|Completed|Cancelled|NoShow|WalkIn), `VS_Booked_Channel__c`
(picklist Portal|Chat|Staff|WalkIn), `VS_Booked_By_Mobile__c` (Phone — booker, may differ from
patient's mobile, REQ-004), `VS_Dose_Number__c` (Number), `VS_Cancelled_At__c` (DateTime).

**`VS_Notification_Log__c`** — Lookup→`VS_Patient__c`, Lookup→`VS_Appointment__c`, `VS_Channel__c`
(picklist SMS|Email), `VS_Template_Name__c` (DLT template ref, REQ-058), `VS_Message_Body__c`
(LongText), `VS_Status__c` (picklist Logged|Sent|Failed), `VS_Provider__c` (Text — "LogOnly" in POC,
D-014), `VS_Helpline_Included__c` (Checkbox, C7.3), `VS_Sent_At__c` (DateTime).

**`VS_OTP_Verification__c`** — `VS_Mobile__c` (Phone), `VS_Code_Hash__c` (Text — hashed, never
plaintext), `VS_Expires_At__c` (DateTime), `VS_Verified__c` (Checkbox), `VS_Attempts__c` (Number).
Holds no PII beyond mobile; purged daily.

**`VS_Error_Log__c`** — `VS_Source__c` (class/flow), `VS_Record_Id__c`, `VS_Message__c` (LongText),
`VS_Severity__c` (picklist), `VS_Logged_At__c` (DateTime).

### 2.4 Master-detail vs lookup justifications

| Relationship | Type | Why |
|---|---|---|
| Facility → Session | **Master-Detail** | Sessions are meaningless without their facility; inherit facility sharing; cascade lifecycle |
| Session → Slot | **Master-Detail** | Slots are generated artifacts of a session; cascade delete/reparent on session cancel; inherit sharing |
| Facility → Facility_Service | **Master-Detail** | Offering only exists under a facility |
| Service → Session / Facility_Service | **Lookup** | Service is a shared catalogue row referenced by many facilities; must not cascade-delete |
| Slot → Appointment | **Lookup** | Booked-count is maintained manually under the lock (rules/20 forbids rollup); lookup also allows **reparenting on reschedule** and lets appointments (3 yr) outlive slots |
| Patient → Appointment | **Lookup** | Patient retention (≥10 yr if vaccinated) differs from appointment (3 yr); master-detail would force one lifecycle / cascade delete — unacceptable for retention (REQ-052) |
| Facility → Holiday | **Lookup** | Holidays are reference data queried during generation, not owned children |

### 2.5 Where Person data lives (Annexure C1 minimization)

All person data lives on **`VS_Patient__c` only**, and only the six C1.1 attributes
(name, DOB, gender-optional, mobile, locality/pin, email-optional). Health data is limited to the
appointment/vaccination lifecycle (REQ-045) — `VS_Appointment__c` and the deferred
`VS_Vaccination_Event__c`; no diagnoses/symptoms/notes fields exist anywhere. Booker identity is
**not** stored as a person — a booker is simply an authenticated mobile (`VS_Booked_By_Mobile__c`);
one mobile owning many patients is modeled as many `VS_Patient__c` sharing `VS_Mobile__c` (REQ-004).
`VS_OTP_Verification__c` and `VS_Notification_Log__c` reference the patient/mobile but store no extra
personal attributes. **No object anywhere has an Aadhaar field (REQ-044).**

---

## 3. Entity-relationship diagram

Mermaid `erDiagram` at **`01-discovery/erd/data-model.mermaid`** — all 11 F-001 objects with
cardinality- and verb-labeled relationships (master-detail vs lookup), retention class comments per
entity, an explicit no-Aadhaar note on `VS_Patient__c`, and the three deferred objects
(`VS_Vaccination_Event__c`, `VS_Vial__c`, `VS_Certificate__c`) as commented non-preclusion stubs.
The capacity spine reads Facility ||--o{ Session ||--o{ Slot, with Appointment ||--o{ hanging off
Slot (the lock target), Patient, Session and Facility.

---

## 4. Slot-integrity strategy — the RFP §3.4 guarantee (REQ-008)

**Requirement:** confirmed bookings for a slot must NEVER exceed that slot's published capacity, even
under simultaneous attempts. Acceptance = a concurrency test firing many parallel `book()` calls at a
slot with 1 remaining place; exactly one succeeds, the rest get `SLOT_FULL`, and no extra row exists.

### 4.1 The single write path

`VS_BookingService.book(Id patientId, Id slotId, Id bookedById)` is the **only** code that creates a
confirmed appointment. Portal LWC, the (later) chat assistant, and the staff console all call it — one
rule, one owner (rules/20, flow-patterns "never split a business rule between Flow and Apex").

### 4.2 Locking sequence (row-scoped pessimistic lock)

```apex
public with sharing class VS_BookingService {
    public class VS_BookingException extends Exception {}

    public static Id book(Id patientId, Id slotId, Id bookedById) {
        // 1. LOCK the slot row. Any other tx touching this slotId blocks here until we commit/rollback.
        VS_Slot__c slot = [SELECT Id, VS_Capacity__c, VS_Booked_Count__c, VS_Status__c
                           FROM VS_Slot__c WHERE Id = :slotId FOR UPDATE];   // rules/20 mandate

        // 2. Re-check capacity + cut-off INSIDE the lock (never outside it)
        if (slot.VS_Status__c != 'Open' || slot.VS_Booked_Count__c >= slot.VS_Capacity__c) {
            throw new VS_BookingException('SLOT_FULL');
        }
        // 3. Create appointment (unique VS_Booking_Reference__c, D-016) AND increment the
        //    denormalized counter in the SAME transaction. The lock makes read-check-write atomic.
        VS_Appointment__c appt = new VS_Appointment__c(
            VS_Patient__c = patientId, VS_Slot__c = slotId,
            VS_Booking_Reference__c = VS_ReferenceGenerator.next(),   // random, non-guessable
            VS_Status__c = 'Booked', VS_Booked_By_Mobile__c = ...);
        insert as user appt;                                          // WITH USER_MODE / FLS
        slot.VS_Booked_Count__c += 1;
        if (slot.VS_Booked_Count__c == slot.VS_Capacity__c) slot.VS_Status__c = 'Full';
        update slot;                                                  // still holding the lock
        // 4. Fire confirmation via the notification seam (log-only, D-014) AFTER commit is fine.
        return appt.Id;
    }
}
```

### 4.3 Why it cannot overbook — the negative (last-place) case

Two requests, R1 and R2, both want the **last** place (`VS_Booked_Count__c = capacity-1`):

1. R1 acquires the `FOR UPDATE` row lock. R2's identical `SELECT … FOR UPDATE` **blocks** on the
   same row — the database serializes them.
2. R1 re-checks inside the lock (`count < capacity` → true), inserts its appointment, sets
   `count = capacity`, status `Full`, and commits — releasing the lock.
3. R2 now acquires the lock and **re-reads the freshly committed row**: `count (capacity) >= capacity`
   → throws `SLOT_FULL`. No second insert happens.

Overbooking is impossible because the capacity check and the counter write are inside the same lock
on the capacity-bearing row, so they can never interleave. The counter is **never** maintained by a
roll-up summary or trigger — those don't serialize and would allow both inserts (rules/20).

### 4.4 How the DHS acceptance concurrency test passes

QA fires N parallel `book()` calls (Apex `@future`/enhanced parallel test or an external driver) at a
slot seeded with `VS_Capacity__c = 1`. Expected, asserted state: exactly **one** `VS_Appointment__c`
in `Booked`; `VS_Slot__c.VS_Booked_Count__c == 1 == VS_Capacity__c`; every other call caught
`VS_BookingException('SLOT_FULL')`; **zero** rows above capacity. The dev unit test (`VS_BookingServiceTest`)
includes the capacity-exhaustion test mandated by the apex skill; QA Tier-1 re-runs it as the release gate.

### 4.5 Walk-ins, reschedule, cancel (same discipline)

- **Walk-in** (`VS_WalkInService.serve`, D-009): locks the **Session** row `FOR UPDATE`, checks
  `VS_Walk_In_Used_Count__c < VS_Walk_In_Reserve_Count__c`, increments, inserts a `WalkIn` appointment.
  Different row from online booking → no cross-contention; reserve can never be exceeded (REQ-007).
- **Cancel/Reschedule** (`VS_BookingService.cancel/reschedule`): enforce the 4-hour cut-off (D-010,
  `VS_Setting__mdt.CutOffHours`) — reject inside the window with a user-actionable message (REQ-003/015);
  on success, lock the freed slot row, decrement `VS_Booked_Count__c`, flip `Full`→`Open` so the place
  is reusable the same day. Reschedule = cancel-old + book-new in one transaction, both under their
  respective row locks (lock ordering by slot Id to avoid deadlock).

### 4.6 Volume/governor posture (REQ-062)

Each `book()` is a single-row, single-slot transaction — the lock is row-scoped, so 1,900/day steady
and 6,000/day drive peaks distribute across thousands of slot rows with contention only within a slot.
Slot generation and no-show marking run as **Batch Apex** (bulk-safe, chunked). No SOQL/DML in loops
anywhere (rules/20).

---

## 5. Automation strategy (Apex vs Flow vs Scheduled)

Boundary per `flow-patterns`: FOR UPDATE locking, service-owned logic, loops over large collections,
and Queueables are **Apex**; simple same-record stamps, staff-guided screens, and notifications are
**Flow**. One owner per business rule.

| Capability | Mechanism | Component | Routing | REQ |
|---|---|---|---|---|
| **Confirmed booking (§3.4 lock)** | **Apex service** | `VS_BookingService.book` (FOR UPDATE) | **senior** | REQ-002/008 |
| Cancel / reschedule + cut-off | Apex service | `VS_BookingService.cancel/reschedule` | senior | REQ-003/015 |
| Walk-in serve (session reserve lock) | Apex service | `VS_WalkInService.serve` | senior | REQ-007 |
| Slot generation from sessions | Apex Batch | `VS_SlotGenerationService` / `VS_SlotGenBatch` (granularity D-008, holiday+drive skip) | senior | REQ-009/012/013/014 |
| Patient find-or-create (de-dup) | Apex service | `VS_PatientService.findOrCreate` (upsert by `VS_Match_Key__c`, D-011/D-017) | senior | REQ-004 |
| Booking reference generator | Apex util | `VS_ReferenceGenerator` (random non-guessable, D-016) | senior | REQ-002/019 |
| Citizen OTP auth | Apex + interface | `VS_OtpService` + `VS_IOtpProvider` (**stub** in POC, D-013) | senior | (A-004) |
| Notification dispatch | Apex + interface | `VS_SmsService` + `VS_ISmsProvider` (**log-only** → `VS_Notification_Log__c`, D-014) | senior | REQ-002/028/059 |
| End-of-day no-show marking | **Scheduled Apex Batch** | `VS_NoShowBatch` (idempotent, bulk; not-attended `Booked`→`NoShow`, +No_Show_Count) | senior | REQ-016 |
| Retention purge per class | Scheduled Apex Batch | `VS_RetentionPurgeBatch` (per-class policy in `VS_Setting__mdt`) | senior | REQ-052 |
| Trigger routing | Apex handler | `VS_AppointmentTriggerHandler`, `VS_SlotTriggerHandler` (route only, no logic — rules/20) | senior | — |
| Session reserve/bookable split | **Formula fields** (no automation) | `VS_Session__c` formulas referencing `$CustomMetadata` | — | REQ-007/D-009 |
| MO defines session capacity | **Screen Flow** | `VS_Session_Screen_DefineCapacity` (create sessions + capacity; drive-day toggle) | **mid** | REQ-010/011/012 |
| Booking-confirmation log entry | **Record-triggered Flow (after-save)** | `VS_Appointment_AfterSave_LogConfirmation` → subflow calling the notification seam | mid | REQ-002/028 |
| Slot status stamp (Full/Open) | Apex (inside the lock) | owned by `VS_BookingService` — **not** a flow (single owner) | senior | REQ-008 |
| **Reminders (pre-appt + next-dose)** | Scheduled Apex — **designed, deferred to a later feature** | `VS_ReminderScheduler` queues `VS_Notification_Log__c` via `VS_SmsService`; offsets in `VS_Setting__mdt` | — | REQ-024/025/026/027 |
| Vial/wastage visibility | **Deferred** (needs `VS_Vaccination_Event__c`/`VS_Vial__c`) — LWC over confirmed-remaining vs doses-left | — | REQ-022/023 |

Every Flow element that can fail gets a fault path → `VS_Error_Log__c` (flow-patterns); flows deploy
**Active** in the disposable scratch org; screen flows show a plain-language fault screen + helpline (C7.3).

---

## 6. Security & compliance mapping (Annexure C → platform mechanism)

### 6.1 No Aadhaar & data minimization (REQ-043/044/045 — C1)
No Aadhaar field on any object/CMT/log/seed (verified as a build check and QA Tier-1). `VS_Patient__c`
carries exactly the six C1.1 attributes; FLS restricts even those to roles that need them. Health data
confined to appointment/vaccination lifecycle; no clinical-note field exists.

### 6.2 Sharing / role-based visibility (REQ-053/054/055 — C5)
- **OWD:** reference + bookable data (Facility, Service, Facility_Service, Session, Slot, Holiday) =
  **Public Read Only** (citizens must browse to book). Person + booking data (Patient, Appointment,
  Notification_Log, OTP) = **Private**.
- **Facility staff see only their facility (REQ-053):** criteria-based sharing rules on
  `VS_Appointment__c` / `VS_Patient__c` keyed on `VS_Facility__c` → per-facility **public groups**;
  staff are permission-set + group members. District roles (`VS_District_Admin`, `VS_District_MIS`)
  get aggregate visibility via **View All** on the compliance permission set (record-level access is
  justified + audited).
- **Citizens see only their own** (Experience Cloud): **sharing sets** on the community user keyed to
  the verified mobile — a citizen sees only patients/appointments for their mobile.
- **Permission sets over profiles (rules/20):** `VS_Facility_Staff`, `VS_Nurse`, `VS_MO_Facility_Admin`,
  `VS_District_Admin`, `VS_District_MIS`, plus `VS_Citizen_Community`.
- **Enforcement in code:** every service is `with sharing`; all DML/SOQL uses `WITH USER_MODE` (or
  `Security.stripInaccessible`) so CRUD/FLS is enforced, not assumed (rules/20).
- **Attributable reads (REQ-054):** field history + Login History for the POC; per-record read audit
  beyond that needs **Shield Event Monitoring** — assumed available or accepted as a known POC gap
  (A-006). **Bulk export (REQ-036):** allowed only via a controlled path gated by the `VS_District_MIS`
  permission set; every export logged to `VS_Error_Log__c`/audit (C5.2).
- **Session timeout ≤15 min (REQ-055):** org Session Settings + permission-set session-timeout for
  shared-device roles; individual logins only (no shared credentials).

### 6.3 Residency & synthetic data (REQ-050/051 — C3)
Scratch/target org provisioned in **India region (Hyderabad/Mumbai)**; written residency confirmation
is a launch gate (OQ-014). Dev/test use **synthetic citizens only** — seed scripts generate fictional
people, and the no-Aadhaar rule binds seed data (rules/10, REQ-051).

### 6.4 SMS / OTP interface seams (REQ-058/059 — C7 / D-013 / D-014)
- `VS_ISmsProvider` + `VS_SmsService`: gateway vendor undecided (C7.4); the POC ships a **log-only**
  implementation writing every message to `VS_Notification_Log__c` with the DLT template name and
  helpline flag (C7.1–7.3). Real gateway swaps in behind the interface with no design change.
- `VS_IOtpProvider` + `VS_OtpService`: citizen auth = mobile + OTP (D-013); POC uses a **stub**
  provider with a fixed scratch-org test code, storing only a hashed code + expiry. No passwords, no
  Aadhaar.

### 6.5 Retention by class (REQ-052 — C4)
Each object states its class (table §2.2). `VS_RetentionPurgeBatch` reads a per-class policy from
`VS_Setting__mdt` and archives/purges: vaccination ≥10 yr (permanent), bookings 3 yr, SMS logs 1 yr,
audit 3 yr, OTP daily. Patient purge respects the **longest** linked record (a vaccinated patient is
retained ≥10 yr). The switch-per-class design satisfies "make archival/purge possible per class."

### 6.6 Accessibility (REQ-056/057 — C6)
Citizen journeys (book / reschedule / cancel) built as LWC: keyboard-operable, ARIA-labeled,
screen-reader tested, usable at 200% zoom; slot-availability states carry **text labels** not colour
alone (REQ-057). Custom Labels throughout so Marathi/Hindi localization is additive (REQ-060).

### 6.7 DPDP consent & rights (REQ-046/047/048 — C2)
`VS_Consent_Given__c` + `VS_Consent_Timestamp__c` captured at registration; department-approved
wording is a launch item (OQ-013). Use-limitation, access/correction, breach path (REQ-047/048/049)
are governance/process — captured for later, not F-001 build.

---

## 7. Epics (EP-##) & scope statements

| EP | Title | Scope statement | REQ coverage |
|---|---|---|---|
| **EP-01** | Facility, Service & Capacity Model | Objects Facility/Service/Facility_Service/Session/Holiday; MO screen flow to define per-session capacity (D-007); reserve/bookable formula fields (D-009); discovery data. | REQ-001, REQ-009, REQ-010, REQ-011, REQ-012 |
| **EP-02** | Slot Generation Engine | `VS_SlotGenBatch` generating 15-min slots (D-008) within sessions, distributing bookable capacity (A-005), respecting holidays + drive-day override (D-018), booking horizon (REQ-013). | REQ-009, REQ-013, REQ-014, REQ-012 |
| **EP-03** | Slot-Integrity Booking (§3.4 — crown jewel) | `VS_BookingService.book` FOR UPDATE slot lock; walk-in session-reserve lock; booking reference (D-016); confirmation seam. Includes the capacity-exhaustion + concurrency tests. | REQ-002, REQ-006, REQ-007, REQ-008 |
| **EP-04** | Cancel / Reschedule / No-Show | Self-service cancel+reschedule with 4-hour cut-off (D-010); free-the-place; `VS_NoShowBatch` end-of-day marking; capture No_Show_Count. | REQ-003, REQ-015, REQ-016 |
| **EP-05** | Patient & Identity | `VS_Patient__c` C1-minimal; `VS_PatientService.findOrCreate` exact-match de-dup via unique match key (D-011/D-017); booker≠patient; DOB/gender (OQ-026); consent capture. | REQ-004, REQ-043, REQ-045, REQ-046 |
| **EP-06** | Citizen Access & Discovery | OTP auth stub (D-013); Experience Cloud citizen surface; discovery by service+proximity (REQ-001); accessible LWC booking journey; i18n-ready labels. | REQ-001, REQ-005, REQ-056, REQ-057, REQ-060 |
| **EP-07** | Notification Seam | `VS_ISmsProvider`/`VS_SmsService` log-only → `VS_Notification_Log__c`; booking confirmation; helpline+template metadata (D-014). | REQ-002, REQ-028, REQ-058, REQ-059 |
| **EP-08** | Security, Sharing & Compliance | Permission sets; OWD + criteria/sharing-set visibility (REQ-053); WITH USER_MODE/FLS; session timeout; residency; synthetic seed; retention purge; no-Aadhaar guard; bulk-export gating. | REQ-036, REQ-044, REQ-050, REQ-051, REQ-052, REQ-053, REQ-054, REQ-055, REQ-062 |

### 7.1 Full REQ → design → epic traceability (all 62)

Legend: **In F-001** = built now; **Deferred** = captured/non-preclusion, later feature.

| REQ | Design section | EP / Status |
|---|---|---|
| REQ-001 | §2.2, §6.6 | EP-01/EP-06 |
| REQ-002 | §4.1, §5, §6.4 | EP-03/EP-07 |
| REQ-003 | §4.5 | EP-04 |
| REQ-004 | §2.5, §5 | EP-05 |
| REQ-005 | §6.6 | EP-06 |
| REQ-006 | §4.1 (single fast path) | EP-03 |
| REQ-007 | §2.1, §4.5 | EP-03 |
| REQ-008 | §4 (all) | EP-03 |
| REQ-009 | §2.1, §5 | EP-01/EP-02 |
| REQ-010 | §2.2, §5 | EP-01 |
| REQ-011 | §2.1 | EP-01 |
| REQ-012 | §2.3 (drive-day), §5 | EP-01/EP-02 |
| REQ-013 | §2.2 (BookingHorizonDays) | EP-02 |
| REQ-014 | §2.3 (granularity, D-008) | EP-02 |
| REQ-015 | §4.5 (cut-off) | EP-04 |
| REQ-016 | §5 (NoShowBatch) | EP-04 |
| REQ-017 | §2.3 (No_Show_Count capture) | **Deferred** — enforcement phase 2 (OQ-007); count captured now |
| REQ-018 | — | **Deferred** — check-in feature; booking reference built now enables it (OQ-018 offline) |
| REQ-019 | §2.3 (booking reference) | EP-03 (field built; check-in UI deferred) |
| REQ-020 | §2.2 (deferred object) | **Deferred** — vaccination recording feature |
| REQ-021 | §2.2 (deferred `VS_Vial__c`) | **Deferred** — stock feature |
| REQ-022 | §5 | **Deferred** — vial/wastage visibility (needs stock objects) |
| REQ-023 | §5 | **Deferred** — closing-time alert |
| REQ-024 | §5 (reminder engine designed) | **Deferred** — next-dose feature (needs vaccination event; OQ-010 schedules) |
| REQ-025 | §5 | **Deferred** — next-dose SMS |
| REQ-026 | §5 (re-remind interval) | **Deferred** |
| REQ-027 | §5 (reminder scheduler) | **Deferred** — pre-appt reminders (seam built, scheduling later) |
| REQ-028 | §6.4 | EP-07 (confirmation deliverable via seam) |
| REQ-029 | §2.2 (deferred `VS_Certificate__c`) | **Deferred** — certificate feature |
| REQ-030 | §2.3/D-016 (non-guessable ID pattern) | **Deferred** — pattern reused from booking ref |
| REQ-031 | §2.3 (`VS_External_Id__c` seam) | **Deferred** — phase-2 verification (OQ-016) |
| REQ-032 | §1 goal 4 | **Deferred** — dashboards feature |
| REQ-033 | — | **Deferred** — weekly reporting / drive-day live view |
| REQ-034 | §4.5 | **Deferred** — staff slot-cancel cascade + rebooking (OQ-022) |
| REQ-035 | — | **Deferred** — Excel export feature |
| REQ-036 | §6.2 (MIS-gated + logged) | EP-08 (role gating built; export UI deferred) |
| REQ-037..042 | §1 (out of pilot) | **Deferred** — chat assistant (Should / Must-if-built); not built in F-001 |
| REQ-043 | §2.3, §2.5, §6.1 | EP-05 |
| REQ-044 | §2.5, §6.1 | EP-08 (cross-cutting, QA Tier-1) |
| REQ-045 | §2.5, §6.1 | EP-05/EP-08 |
| REQ-046 | §6.7 | EP-05 (mechanism; wording OQ-013 deferred) |
| REQ-047 | §6.7 | **Deferred** — use-limitation governance |
| REQ-048 | §6.7 | **Deferred** — access/correction/deletion rights |
| REQ-049 | §6.7 | **Deferred** — breach path (OQ-017 launch) |
| REQ-050 | §6.3 | EP-08 (org config; written confirmation OQ-014 launch) |
| REQ-051 | §6.3 | EP-08 (seed scripts) |
| REQ-052 | §6.5 | EP-08 |
| REQ-053 | §6.2 | EP-08 (QA Tier-1) |
| REQ-054 | §6.2 | EP-08 (partial — Shield gap A-006) |
| REQ-055 | §6.2 | EP-08 |
| REQ-056 | §6.6 | EP-06 |
| REQ-057 | §6.6 | EP-06 |
| REQ-058 | §6.4 | EP-07 (template metadata; live send deferred, D-014) |
| REQ-059 | §6.4 | EP-07 |
| REQ-060 | §6.6 | EP-06 (Custom Labels) |
| REQ-061 | §6 (ops) | **Deferred** — availability window is ops config, not build |
| REQ-062 | §4.6 | EP-08/EP-03 (bulkification + row-scoped locks) |

**Coverage:** all 62 REQs mapped. In-F-001 build set touches EP-01..EP-08. Deferred items are
captured with a reason and, where relevant, a seam built now (booking reference → check-in/cert;
notification seam → reminders; external IDs → CoWIN) so no later phase is precluded.

---

## 8. Decision references

Design honors D-005..D-014 (client/human sign-off) verbatim. New architect decisions logged this run:

- **D-015** — §3.4 ceiling + FOR UPDATE lock live on `VS_Slot__c` (capacity authored on Session);
  25% reserve is a session-level counter; walk-ins lock the Session row. (§2.1, §4)
- **D-016** — Booking reference / certificate ID = random, non-guessable, human-typeable 8-char
  Crockford base32, stored as unique External IDs. (§2.3, §4.2)
- **D-017** — Patient exact-match de-dup enforced by a unique External ID `VS_Match_Key__c`
  (`normalize(name)|DOB|mobile`) via upsert, race-safe at the DB. (§2.3, §5)

New assumptions **A-005** (even slot-capacity distribution), **A-006** (facility-scoped sharing
implementation + Shield dependency for read audit). New glossary terms: Bookable capacity, Walk-in
pool, Match key, Booking service. All in `.claude/memory/`.

**Open items carried to pm-planner (not silently resolved):** SMS live-send (D-014 deferred),
reminders/next-dose/check-in/vaccination/stock/certificates/dashboards deferred to later features;
launch-blockers OQ-012/013/014/017 remain owner-dependent; Shield dependency (A-006) for full REQ-054.
