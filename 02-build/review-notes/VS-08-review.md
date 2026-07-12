<!--
feature:         F-001 slot-booking-core
producing-agent: dev-mid
date:            2026-07-12
phase:           DEV_IN_PROGRESS
derives-from:    02-build/jira-log.md VS-08, 02-build/sprint-plan.md VS-08,
                 01-discovery/technical-design.md §2.3/§2.4, REQ-002/REQ-008/REQ-019/REQ-045,
                 EP-03, D-016, D-019, D-020, D-025
downstream:      VS-09 (VS_BookingService.book(), booking-reference generation, counter increment),
                 VS-11 (cancel/reschedule), VS-12 (no-show), VS-17/VS-19 (notification seam),
                 VS-20 (facility-scoped sharing), VS-21 (retention purge), 04-confirmations/ drift-check
-->

# VS-08 Review Packet — VS_Appointment__c object & fields

## What was built

`VS_Appointment__c` under `force-app/main/default/objects/VS_Appointment__c/`:

- 1 object metadata file (`VS_Appointment__c.object-meta.xml`)
- 11 field metadata files under `fields/`

No Apex, no Flow, no LWC. Pure declarative object/field metadata, per this ticket's routing
(dev-mid, Task, "pure object/field metadata" per jira-log.md).

## Field list, types, relationship types

| Field | Type | Relationship type | Required | Notes |
|---|---|---|---|---|
| `VS_Patient__c` | Lookup → `VS_Patient__c` | Lookup | No | deleteConstraint=Restrict |
| `VS_Slot__c` | Lookup → `VS_Slot__c` | **Lookup** | **Yes** | deleteConstraint=Restrict; reparentable (see below) |
| `VS_Session__c` | Lookup → `VS_Session__c` | Lookup | No | denormalized off Slot for sharing/reporting |
| `VS_Facility__c` | Lookup → `VS_Facility__c` | Lookup | No | denormalized off Session |
| `VS_Service__c` | Lookup → `VS_Service__c` | Lookup | No | denormalized off Session |
| `VS_Booking_Reference__c` | Text(8) | — | No | ExternalId+Unique, case-insensitive; **defined, not populated** (see below) |
| `VS_Status__c` | Picklist | — | Yes | Booked (default) / CheckedIn / Completed / Cancelled / NoShow / WalkIn |
| `VS_Booked_Channel__c` | Picklist | — | No | Portal / Chat / Staff / WalkIn |
| `VS_Booked_By_Mobile__c` | Phone | — | No | booker's mobile, may differ from patient's |
| `VS_Dose_Number__c` | Number(2,0) | — | No | next-dose seam, not consumed by F-001 automation |
| `VS_Cancelled_At__c` | DateTime | — | No | stamped by VS-11 `cancel()`, not this ticket |

Standard Name field: AutoNumber `APT-{00000}` ("Appointment Record") — a non-PII record identifier,
consistent with the pattern already used on `VS_Patient__c` (`PAT-{00000}`) and `VS_Slot__c`
(`SLT-{00000}`).

## Relationship types — Slot confirmed as Lookup, and why (design §2.4)

**`VS_Appointment__c.VS_Slot__c` is a Lookup, NOT Master-Detail.** This was checked explicitly
against design §2.4 before building, per this ticket's instruction:

> "Slot → Appointment | **Lookup** | Booked-count is maintained manually inside the parent
> **session** lock (rules/20 forbids rollup); lookup also allows **reparenting on reschedule**
> and lets appointments (3 yr) outlive slots"

Reasoning applied field-for-field:
1. **Reparenting**: VS-11 (`VS_BookingService.reschedule()`) must be able to move an existing
   appointment from Slot A to Slot B without deleting and recreating the row (which would lose the
   booking reference's history and complicate the audit trail). Master-Detail relationships in
   Salesforce are only reparentable if explicitly flagged `reparentableMasterDetail=true`, and even
   then the design didn't choose that path — it chose Lookup outright, which is always freely
   reparentable and is the simpler, more standard mechanism.
2. **Counter ownership**: `VS_Slot__c.VS_Booked_Count__c` is a plain writable Number (VS-05,
   D-020) incremented only inside the parent `VS_Session__c`'s `FOR UPDATE` lock by VS-09/VS-11 —
   never by a roll-up summary. Master-Detail would tempt a roll-up summary field on the parent,
   which rules/20 and D-020 explicitly forbid (roll-ups don't serialize under concurrent writes).
3. **Independent retention**: appointments retain 3 yr (Annexure C4); slots share the session's
   reference-data-adjacent lifecycle. A Master-Detail cascade-delete on Slot would delete
   Appointments too, which is wrong for a 3-yr-retained booking record.

The same Lookup-not-Master-Detail reasoning was applied to **`VS_Patient__c`** (design §2.4:
"Patient retention (≥10 yr if vaccinated) differs from appointment (3 yr); master-detail would
force one lifecycle / cascade delete — unacceptable for retention, REQ-052") and, by extension of
the same "reference/shared data must not cascade-delete its bookings" principle, to the
denormalized `VS_Session__c`/`VS_Facility__c`/`VS_Service__c` lookups (§2.3 lists these as plain
lookups "denormalized for sharing/reporting", not master-detail parents of Appointment — §2.4 does
not name a Master-Detail relationship anywhere that has Appointment as the child).

All five lookups carry `deleteConstraint=Restrict` so a parent (Patient/Slot/Session/Facility/
Service) with existing appointments cannot be deleted out from under its booking history —
purge/archival is VS-21's (`VS_RetentionPurgeBatch`) job per retention class, not ad hoc record
deletion (design §6.5).

## OWD — Private confirmed

`sharingModel` = `Private` in `VS_Appointment__c.object-meta.xml`, matching design §2.2's object
register (row 8: `VS_Appointment__c` | **Private**) and Annexure C5 (booking/person-adjacent data
is not Public Read Only like the reference objects). Facility-scoped visibility for staff is built
in VS-20 (sharing rules, not OWD) — out of this ticket's scope.

## VS_Booking_Reference__c — defined here, populated by VS-09

Per D-016, `VS_Booking_Reference__c` is a random, non-guessable, human-typeable 8-character
Crockford base32 code. **This ticket defines the field only** (Text(8), ExternalId+Unique,
case-insensitive) — no before-save flow, no default-value formula, no value is ever set by this
ticket. The value is generated and populated exclusively by `VS_ReferenceGenerator` inside
`VS_BookingService.book()` (VS-09, Apex, dev-senior) at insert time, mirroring the same
defined-not-populated pattern VS-07 used for `VS_Patient__c.VS_Match_Key__c` (D-017). Marking it
ExternalId+Unique at the field level means the database — not a prior SOQL check — rejects a
colliding reference outright, which is the same race-safety reasoning as D-017.

**No Flow was added in this ticket to populate the booking reference or the field's default
value** — this was a specific instruction (D-016 says Apex generates it) and is honored: zero
automation exists on this object in this ticket.

## No-Aadhaar confirmation

Grepped `force-app/main/default/objects/VS_Appointment__c/` (case-insensitive) for
`aadhaar|diagnos|clinical|symptom`: the only match is the object description's own negation prose
("No clinical/diagnosis fields exist anywhere on this object... NO Aadhaar field, no Aadhaar-shaped
field, anywhere"). No field name, label, or value references Aadhaar or clinical/diagnosis data.
REQ-045 structural AC: **PASS**.

## AC pass/fail summary (jira-log.md VS-08 block)

| AC | Result |
|---|---|
| Object deploys with lookups to Patient/Slot/Session/Facility/Service, `VS_Booking_Reference__c` (ExternalId+Unique), `VS_Status__c` (6-value picklist), `VS_Booked_Channel__c` (4-value picklist), `VS_Booked_By_Mobile__c`, `VS_Dose_Number__c`, `VS_Cancelled_At__c` | **PASS** (metadata built exactly as specified; not yet deployed — see Deploy status) |
| Object scanned for clinical/diagnosis fields — none exist (REQ-045) | **PASS** (structural grep, see above) |

Both ACs are metadata-shape ACs and are satisfied on disk. Neither AC requires a live deploy to
verify structurally, but a deploy/dry-run is still the honest gate before calling this
"buildable" — see Deploy status below.

## Traceability

REQ-002 (booking + confirmation reference) → REQ-008 (§3.4 ceiling, schema seam only) →
REQ-019 (booking reference field; check-in UI deferred) → REQ-045 (no clinical data) → design
§2.3 (field list) / §2.4 (relationship justifications) → EP-03 (Slot-Integrity Booking) → VS-08
(this ticket) → force-app/main/default/objects/VS_Appointment__c/ → (downstream) VS-09 booking
logic, VS-11 cancel/reschedule, VS-12 no-show, VS-17/19 notification seam, VS-20 sharing, VS-21
retention purge. D-016 (booking reference generation ownership) and D-019/D-020 (single
session-lock, slot counter ownership) are cited inline in field descriptions so the "why" survives
in the metadata itself, not just this packet.

## Assumptions / open items logged

- **A-014 (new, this ticket)**: Field-history tracking was NOT enabled on `VS_Appointment__c` in
  this ticket (neither at the object level nor on any individual field). VS-07 set a precedent of
  enabling object-level history tracking on `VS_Patient__c` as a REQ-054/A-006 audit-trail baseline
  (not required by that ticket's AC either, but done as a compliance-consistent default). This
  ticket's explicit instructions did not call for field history on Appointment, and REQ-054
  (read-audit) is explicitly **not ticketed** for F-001 per the sprint-plan gate note ("REQ-054
  read-audit = no ticket (known POC limitation)"). Flagging for BA_ARCH_CONFIRM to decide whether
  VS-08 should follow VS-07's precedent for consistency, or whether the sprint-plan's "not
  ticketed" call already covers this object too. Owner: architect/BA at drift-check. How to
  verify: check `enableHistory` on `VS_Appointment__c.object-meta.xml` (currently `false`).
- **Permission sets not extended in this ticket.** VS-04's review packet flagged that
  `VS_Facility_Staff`/`VS_Nurse`/`VS_MO_Facility_Admin`/`VS_District_Admin`/`VS_District_MIS` grant
  no access to `VS_Appointment__c` yet and that VS-07/VS-08/VS-17 "must EXTEND" them. This ticket's
  explicit build instructions scoped only object/field metadata and did not include permission-set
  edits, and VS-07 (the preceding mid ticket) followed the same scope boundary. Consistent with
  that precedent, no permission-set file was touched here. This is a real gap before any role can
  actually read/write `VS_Appointment__c` in the org — flagging it again here so it isn't lost
  between VS-08 and whichever ticket is expected to close it (VS-20 facility-scoped sharing touches
  Appointment access but is sharing rules, not FLS/object permissions).
- No new decision (D-###) was required — this ticket followed D-016/D-019/D-020/design §2.3-2.4
  exactly with no ambiguity requiring a human call.

## Deploy status — honest confirmation

**NOT deployed. No `sf project deploy start --dry-run` was run in this environment.** This
ticket's parent objects (`VS_Patient__c` VS-07, `VS_Slot__c` VS-05, `VS_Session__c`/
`VS_Facility__c`/`VS_Service__c` VS-01) are themselves still in "Ready for Review" /
not-yet-deployed status per jira-log.md — none of VS-01/02/04/05/07 have been executed against the
target org yet (all "PREPARED, not executed" per devops's DP-001 entries in
`02-build/deployments.md`). `VS_Appointment__c` has hard Lookup dependencies on all five of those
parent objects existing in-org before it can deploy; per rules/20 and D-025 the only legitimate
target is the POC Developer Edition org (alias `AgentForceClaudeWorkFlow`), and per devops's prior
note several unrelated client sandbox/prod orgs are connected in this environment — none of them is
the DE org, and none was targeted. Deploy/dry-run must happen after the DP-001-class deployment
package that includes VS-01/02/05/07 lands in the DE org; this ticket is metadata-only, staged for
that same or a subsequent package, and devops should sequence it accordingly in
`02-build/deployments.md`/the manifest.

## Description-trim (deploy-limit fix) — 2026-07-12, dev-mid fix-forward pass

devops's 2nd dry-run bisection (`02-build/deployments.md`, 20:10 re-run) found
`VS_Appointment__c.object-meta.xml`'s `<description>` at **1401 chars**, over the CustomObject
1000-char cap (`skills/sf-data-model/references/metadata-deploy-limits.md`), causing a clean
component-level deploy failure ("Value too long for field: Description maximum length is:1000").
Fixed by shortening the XML `<description>` to **696 chars** (well under the 1000 cap, with
headroom). No metadata behavior changed — description-only edit; object structure, fields,
relationships, OWD, and all other content on this object are untouched.

**Full original text (1401 chars), preserved here for the record:**

> F-001 slot-booking-core (VS-08, EP-03 -- §3.4 slot-integrity booking, crown-jewel epic). The
> booking record that VS_BookingService.book() (VS-09, Apex, dev-senior) inserts for every channel
> (Portal/Chat/Staff/WalkIn). This ticket builds SCHEMA ONLY -- no booking logic, no
> VS_Booking_Reference__c generation, no VS_Slot__c/VS_Session__c counter increment (all VS-09
> Apex per D-019/D-020). Relationships to Patient/Slot/Session/Facility/Service are all Lookup
> (never Master-Detail): design §2.4 requires VS_Slot__c -> VS_Appointment__c to be reparentable so
> VS-11's reschedule() can move an appointment to a different slot/session without a
> delete+recreate, and requires VS_Patient__c -> VS_Appointment__c to be a Lookup because patient
> retention (>=10 yr if vaccinated) and appointment retention (3 yr, Annexure C4) are different
> lifecycles that a Master-Detail cascade-delete would incorrectly couple. No clinical/diagnosis
> fields exist anywhere on this object (REQ-045 -- health data here is limited to the
> booking/appointment lifecycle only). NO Aadhaar field, no Aadhaar-shaped field, anywhere. OWD is
> Private (Annexure C5 -- booking is person-adjacent data). Retention class (Annexure C4): bookings
> 3 yr, purge/archive governed by VS_RetentionPurgeBatch (VS-21) honoring the patient's
> longest-linked record (design §6.5) -- this object's retention class does not itself force early
> patient purge.

**Why it's safe to trim:** every substantive fact in the original (relationship-type rationale,
retention class, no-clinical/no-Aadhaar confirmation, OWD) is already captured in full detail
elsewhere in this same review packet ("Relationship types — Slot confirmed as Lookup, and why",
"OWD — Private confirmed", "No-Aadhaar confirmation" sections above) and in the field-level
descriptions on disk. The XML description now states the object's purpose and cites the same
ticket/design/decision IDs (VS-08, EP-03, RFP §3.4, D-019/D-020, design §2.4, REQ-045, Annexure
C5, VS-21/design §6.5) so a reader can still trace to the full rationale without the XML itself
carrying it.

## Manual / setup steps

None required by this ticket beyond the standard deploy-order sequencing already noted above
(this object must deploy after its five Lookup parents exist in-org). No post-deploy manual
configuration, no user/permission-set assignment, and no data migration are needed for this
ticket's metadata alone.
