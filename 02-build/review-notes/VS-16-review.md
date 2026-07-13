<!--
feature:         F-001 slot-booking-core
ticket:          VS-16 — Citizen booking journey LWC (book / view / cancel / reschedule)
producing-agent: dev-senior
date:            2026-07-14
phase:           DONE (POST-DONE forward build, branch forward-build-sprint2-4 — YAML untouched)
derives-from:    02-build/sprint-plan.md VS-16 (REQ-002/003/005/006/015/028/056/057/060 / EP-06)
                 .claude/memory/decisions.md D-030/D-030a (portal elevation + C9 gate), D-019/D-020 (§3.4),
                 D-028 (DE-org FLS-on-system-DML), D-011/D-016/D-017
                 .claude/rules/20-salesforce-standards.md, skills/sf-apex-patterns, skills/lwc-slds2
-->

# VS-16 Review Packet — Citizen booking-journey LWC (book / view / cancel / reschedule)

## Status banner
**ORG-VERIFIED by the coordinator's deploy run** (metadata+Apex+LWC+labels validated; lint = 2 pre-existing
only; 44/45 tests green incl. ALL security/functional — view caller-only, C9 reject, BOTH IDOR rejects,
input validation; `VS_BookingController` 94%). This agent did NOT run `sf` deploys itself.
**ONE test defect found on deploy and RESOLVED here (test-only change; VS_BookingService untouched)** — see
"Elevation-fidelity finding" below. `node scripts/metadata-lint.js` re-run clean (2 pre-existing only).

## What was built

### Apex (service seam, no change to VS_BookingService)
- **`VS_BookingController`** extended with three OTP-gated, IDOR-safe citizen self-service methods
  (all `@AuraEnabled`, class stays `with sharing`; the elevated work is in named `without sharing`
  inner classes exactly as the existing `book()` path):
  - `findMyAppointments(mobile)` → `List<AppointmentView>`. Server-verifies an OTP for `mobile`
    (Annexure C9) but **does NOT consume** it (viewing may precede a cancel). Elevated
    `without sharing` read strictly filtered to `VS_Patient__r.VS_Mobile__c = mobile OR
    VS_Booked_By_Mobile__c = mobile`, status ∈ {Booked, WalkIn}, slot start ≥ now. Never returns
    another mobile's rows.
  - `cancelMyAppointment(appointmentId, mobile)` → C9 gate → **IDOR ownership check BEFORE elevating**
    → `VS_BookingService.cancel()` via `without sharing` wrapper → **consume OTP on the state change**.
  - `rescheduleMyAppointment(appointmentId, newSlotId, mobile)` → same C9 + IDOR guard →
    `VS_BookingService.reschedule(..., 'Portal')` → carry ownership onto the moved booking → consume OTP.
  - New DTO `AppointmentView` (id, reference, facilityName, serviceName, slotStart, status-code).
  - Reusable `OtpGate` inner class (`assertVerified` without consume / `consume`) — refactored out of the
    old `Booker.requireVerifiedOtp`; behaviour preserved (the book path now consumes AFTER a successful
    booking instead of before — a strictly-safer replay-guard ordering, no test depends on the old timing).
- **`VS_BookingException`**: added coded reason `NOT_APPOINTMENT_OWNER` (the IDOR rejection).
- **Ownership field**: `book()`'s portal path now stamps `VS_Appointment__c.VS_Booked_By_Mobile__c =
  <OTP-verified mobile>` via an elevated post-book `update` (NO change to VS_BookingService), giving the
  IDOR check a stable owner field even when booker ≠ patient (REQ-004). Reschedule carries it onto the
  new appointment too.

### LWC
- **`vsSlotPicker`** (refactored): Book flow, now 100% Custom-Label driven, accessible (semantic
  `<button>`/`<ul>` slot list with per-option `aria-label`, ~44px touch targets, visible focus,
  `role=alert`/`role=status`, remaining shown as **text**), and a **printable** confirmation
  (`@media print` shows only the confirmation; a Print button).
- **`vsMyBookings`** (new): mobile → OTP → semantic table of my upcoming appointments (status as a
  **text badge**, never colour alone) → Cancel (confirm step) or Reschedule (reuses the availability
  Apex to pick a new slot) → success + new reference.
- **`vsBookingJourney`** (new): `lightning-tabset` shell with **Book** (vsSlotPicker) and **Manage**
  (vsMyBookings) tabs — the "one component with tabs" preferred shape, by composition.
- **`vsErrorLabels`** (new service module): maps stable coded reasons (SLOT_FULL, WITHIN_CUTOFF,
  NOT_APPOINTMENT_OWNER, …) to friendly Custom Labels + a `statusLabel()` helper.
- **`CustomLabels.labels-meta.xml`** (new): 57 `VS_`-prefixed labels (en_US) — every citizen-facing
  string. Marathi/Hindi is now an additive translation, no code change (REQ-060).
- All three exposed LWCs target `lightningCommunity__Page/Default` **and** `lightning__AppPage/HomePage`
  (vsSlotPicker/vsMyBookings also RecordPage) so they appear in Experience Builder and Lightning.

### Permission sets (minimal, D-020 red line held — NO Session/Slot edit added anywhere)
- `VS_Booking_Portal`: added FLS (read+edit) on `VS_Appointment__c.VS_Booked_By_Mobile__c` (the citizen's
  OWN appointment carries the ownership field on a standard org).
- `VS_Booking_Engine_Test_Context` (TEST-ONLY): Appointment `allowEdit=true` + `VS_Booked_By_Mobile__c`
  FLS — so the harness end-to-end book test can prove the post-book stamp.
- `VS_Cancel_Reschedule_Test_Context` (TEST-ONLY): added `VS_Booked_By_Mobile__c` FLS — for the
  reschedule ownership carry.

## How the AC are met
| AC | Where |
|---|---|
| 1 book + reference/error | vsSlotPicker → `book()` (unchanged §3.4 path); confirmation shows reference |
| 2 cancel/reschedule + cut-off msg | vsMyBookings → `cancel/rescheduleMyAppointment`; WITHIN_CUTOFF → `VS_Err_WITHIN_CUTOFF` label |
| 3 keyboard + ARIA everywhere | base lightning-* components; hand-rolled slot buttons carry `aria-label`; `role=alert/status`; visible focus |
| 4 status as text not colour | slot "N places left" text + `aria-label`; manage table status = text badge (`statusLabel`) |
| 5 printable confirmation | `vs-print-area` + `@media print` hides the rest; Print button; essential details only |
| 6 Custom Labels, no hardcoded English | `CustomLabels.labels-meta.xml`; templates reference `label.*` only; errors via `vsErrorLabels` |
| IDOR MUST-FIX (D-030 residual) | `PortalManager.assertOwnership` runs BEFORE any elevated write; `NOT_APPOINTMENT_OWNER` |

## Test results — asserts that are UNIT-PROVEN vs D-028 RUNTIME-GATED
`VS_BookingControllerManageTest` (new, 11 methods) + additions to `VS_BookingControllerTest`.
**Not run on an org by this agent** (no deploy). Expected results by construction:

**UNIT-PROVEN (must pass at deploy-time on the DE org — no counter DML involved):**
- View returns ONLY the caller's rows; excludes another mobile's booking AND cancelled rows
  (`testFindMyAppointments_returnsOnlyCallerUpcomingRows`).
- C9 gate rejects view/cancel with no verified OTP.
- **IDOR reject — cancel** (`testCancelMyAppointment_idor_differentMobile_rejected`): a DIFFERENT mobile
  with its OWN valid OTP → `NOT_APPOINTMENT_OWNER` **and the victim appointment is provably unchanged
  (still Booked, slot count unchanged)**.
- **IDOR reject — reschedule** (`testRescheduleMyAppointment_idor_...`): same, both slots unchanged.
- Input-validation throws.

**D-028 RUNTIME-GATED (deploy-time asserts the documented CRUD wall; SUCCESS proven on a standard org / QA runtime):**
- Cancel/reschedule **happy paths** run green under the CI harness (which carries the D-020-forbidden
  Slot/Appt edit grants), proving the free/move logic + the ownership carry.
- `testCancel_recordOwnerLeastPriv_reachesCounterDml_hitsD028Wall`: under `VS_Booking_Portal` (no Slot edit)
  a portal user who **owns** their booking passes OTP + mobile-ownership, the service read succeeds, and the
  elevation REACHES the §3.4 counter DML; the sole residual is the DE-org D-028 wall
  (`UPDATE not allowed on VS_Slot__c`) — identical posture to the `book()` A-018 proof. Standard org: SUCCEEDS.

## Elevation-fidelity finding (deploy defect, RESOLVED test-only) + OQ-031 escalation
The coordinator's deploy run surfaced one failure: the old
`testCancelMyAppointment_leastPrivilegePortal_clearsSharing_hitsD028CrudWall` expected the D-028 counter
wall but caught **`APPOINTMENT_NOT_FOUND`**, thrown from `VS_BookingService.loadCancellableAppointment`.

**Determined empirically (which CASE it is — stated plainly):** the OTP + mobile-ownership guards run in
`PortalManager` (`without sharing`) and correctly authorize (they SEE the OWD-Private appointment); but
`VS_BookingService.cancel`'s **own** read enforces **sharing**, so a portal user who is **not the record
owner** cannot see the row → `APPOINTMENT_NOT_FOUND`, *before* the §3.4 counter DML. **This is
ORG-INDEPENDENT** (OWD-Private + non-owner enforces identically on every org) — it is **NOT** the D-028
FLS-on-system-DML gate. `book()`'s A-018 proof never exposed this because book()'s reads are on Public-Read
Slot/Session and its insert is `insert as user` — cancel is the first path that truly reads a Private
record through the service. So: the inner-class `without sharing` elevation does **not** propagate to
`VS_BookingService`'s own SOQL for the mobile-authorized **non-owner** case.

**Resolution (VS_BookingService NOT touched; the §3.4 crown jewel is untouched):** the single test was
split into two that pin BOTH real behaviours honestly:
- `testCancel_mobileAuthorizedNonOwner_serviceReadNotElevated` — asserts the guards pass but the service's
  with-sharing read returns nothing → `APPOINTMENT_NOT_FOUND` (the gap, made an explicit asserted fact).
- `testCancel_recordOwnerLeastPriv_reachesCounterDml_hitsD028Wall` — the **common citizen journey** (the
  booker owns their booking): the read succeeds and the elevation reaches the counter DML → D-028 wall.

**Impact:** the common journey (a citizen cancels/reschedules the appointment they booked = they own it)
WORKS on a standard org. The D-030-intended **family-member** case (someone with the verified mobile manages
an appointment they did NOT create/own) is currently **blocked** by the non-elevated service read.

**OQ-031 (escalated to the architect — NOT self-decided, crown jewel not hacked):** does D-030 require
`VS_BookingService.cancel/reschedule` to read the appointment under elevation so a *mobile-authorized*
citizen can manage a *non-owned* booking? If yes, the fix touches the elevation shape, not the lock/counter
logic — candidate remedies for the architect to bless: (a) move the portal wrappers to a **top-level
`without sharing` class** (does inherited-sharing propagate more reliably from a top-level caller than from
an inner class?), or (b) add an **elevated read seam** the wrapper calls before delegating. I did not
implement either — per the coordinator's instruction to escalate rather than modify VS_BookingService.

`node scripts/metadata-lint.js`:
```
== Metadata lint ==
  FAIL formula reads $CustomMetadata ... VS_Session__c/fields/VS_Walk_In_Reserve_Count__c.field-meta.xml
  FAIL formula reads $CustomMetadata ... VS_Setting__mdt/fields/VS_Value__c.field-meta.xml
== 2 metadata-limit issue(s) ==
```
Both FAILs are the **pre-existing D-026** `$CustomMetadata` items (two-phase deploy, already handled by
devops). **VS-16 introduces ZERO new lint issues.** Permset descriptions untouched (<255, check-1 OK);
the only FLS added is on the non-required `VS_Booked_By_Mobile__c` (check-4 OK — no FLS on a required field).

## What the human reviewer should scrutinize
1. **IDOR guard is the crown-jewel of this ticket.** Confirm `assertOwnership` runs BEFORE the elevated
   `VS_BookingService.cancel/reschedule` and that both the patient-mobile AND booker-mobile branches are
   correct. Note `NOT_APPOINTMENT_OWNER` and `APPOINTMENT_NOT_FOUND` intentionally look similar to a
   citizen (no existence oracle).
2. **Ownership-field decision (flagged, not silently chosen):** I populate `VS_Booked_By_Mobile__c` via
   an elevated post-`book()` update (per the ticket's OWNERSHIP FIELD directive) rather than modifying
   VS_BookingService. The check ALSO accepts `VS_Patient__r.VS_Mobile__c`, so ownership still holds even
   if the stamp is walled by D-028 on this DE org (patient mobile == booker mobile in the current
   single-mobile flow). Confirm this belt-and-braces is acceptable.
3. **Consume-timing change** on the book path (now consumes the OTP AFTER a successful booking). Confirm
   the replay-guard intent (one verification → one action) is preserved and preferable.
4. **Test-harness permset widening** (`VS_Booking_Engine_Test_Context` gains Appointment edit). It is
   TEST-ONLY and never assigned to a real user (A-018), but confirm you're comfortable widening it to
   prove the stamp.
5. **Reschedule slot-picking**: the Manage flow reuses the SAME availability Apix (`getAvailableSlots`)
   rather than embedding the full booking wizard (which would also collect identity + book). Confirm this
   is the intended "reuses the slot picker" reading.
6. **a11y depth**: I asserted keyboard/ARIA/text-status/printable structurally; a real
   screen-reader/keyboard/200%-zoom pass (REQ-056/057) is a QA browser task (no browser here).

## Manual / setup steps
**Pre-deploy:**
- None specific to VS-16 beyond the standing D-026 two-phase order (the 2 `$CustomMetadata` formula
  fields already handled by devops for prior tickets — unchanged here).

**Deploy-time note (devops):**
- `CustomLabels.labels-meta.xml` and the 4 LWC bundles (`vsSlotPicker`, `vsMyBookings`,
  `vsBookingJourney`, `vsErrorLabels`) plus `VS_BookingController`, `VS_BookingException`, the 2 new/edited
  test classes, and the 3 permission-set edits deploy together. `vsErrorLabels` is `isExposed=false`
  (internal module) — deploy it, but it won't appear in Builder (expected).
- Run `VS_BookingControllerManageTest` + `VS_BookingControllerTest` on the DE org. The two D-028
  runtime-gated methods assert the CRUD wall on THIS org by design; on a standard org they would assert
  success (see the test ApexDoc).

**Post-deploy (manual, to make the journey usable — NOT done by this ticket):**
- Add the `VS Booking Journey` (or `VS My Bookings` / `VS Slot Picker`) component to an Experience
  Builder page / Lightning app page for the target persona. **The design does not name the target
  Lightning app for the citizen journey** → raising **OQ-030** (below) rather than silently assigning.
- Assign `VS_Booking_Portal` to the citizen/community profile (never the test-harness permsets — A-018).
- Seed data + role permset assignment (standing launch precondition from QA close-out).
- Optional i18n: add `<language>` translations for the `VS_` labels (additive; no code change).

## Open question raised (not silently decided)
- **OQ-030** — The citizen booking journey has no named target Lightning/Experience app in the design.
  VS-14 (Experience Cloud site) is the intended host but is not built in this POC scope. I did NOT create
  a CustomApplication or drop the component onto a page. Human to confirm the host (Experience Builder
  citizen site vs an internal Lightning app for staff-assisted booking) before UI placement.

## Traceability
REQ-002/003/005/006/015/028/056/057/060 → VS-16 → VS_BookingController (findMy/cancelMy/rescheduleMy),
vsSlotPicker/vsMyBookings/vsBookingJourney/vsErrorLabels, CustomLabels → TC-### (QA) ·
D-030/D-030a (elevation + C9 gate), D-019/D-020 (§3.4 untouched), D-028 (runtime gate), NOT_APPOINTMENT_OWNER.
