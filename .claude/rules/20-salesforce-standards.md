# Salesforce Development Standards (binding for dev-senior and dev-mid)

## Naming
- Custom objects/fields: prefix `VS_` (Vaccine Scheduler), e.g. `VS_Appointment__c`,
  `VS_Slot__c.VS_Capacity__c`. Clear English labels; description filled on EVERY object/field.
- Apex: `VS_<Domain><Type>` — `VS_BookingService`, `VS_SlotSelector`, `VS_AppointmentTriggerHandler`,
  tests `VS_BookingServiceTest`. One trigger per object: `VS_AppointmentTrigger`.
- Flows: `VS_<Object>_<Trigger>_<Purpose>` e.g. `VS_Appointment_AfterSave_SendConfirmation`.
  LWC: camelCase `vsSlotPicker`, `vsCheckInConsole`.

## Apex
- Service layer holds logic; triggers delegate to handler; handlers call services. No logic in triggers.
- Bulkified always; no SOQL/DML in loops; use Maps for lookups.
- Slot booking MUST use `SELECT ... FOR UPDATE` on the slot row inside the service method that
  checks remaining capacity and inserts the appointment — this is the RFP §3.4 guarantee.
- `with sharing` by default; enforce CRUD/FLS (`Security.stripInaccessible` or `WITH USER_MODE`).
- Custom exceptions (`VS_BookingException`); no empty catch blocks; no hardcoded IDs;
  Custom Metadata (`VS_Setting__mdt`) or Custom Settings for tunables (cut-off hours, reminder offsets, walk-in reserve %).
- Tests: ≥85% on new classes; meaningful asserts (state, not just no-exception); @TestSetup for data;
  no SeeAllData; include a negative test and, for booking paths, a capacity-exhaustion test.

## Declarative
- Declarative-first for tickets routed dev-mid; a genuinely complex need goes back for re-routing.
- One record-triggered flow per object per context where practical; fault paths handled; entry
  criteria documented in the flow description.
- Validation rules: error messages tell the USER what to do, not what the system did.
- Permission sets over profiles for feature access (`VS_Facility_Staff`, `VS_Nurse`, `VS_MO_Facility_Admin`, `VS_District_Admin`, `VS_District_MIS`).

## Deploy/verify loop
- `sf project deploy start --dry-run` before claiming buildable; `sf apex run test --code-coverage`
  for Apex; results pasted (honestly) into the review packet.
- Target org: the POC scratch org ONLY.

## Deep best-practice skills
Apex/triggers: skills/sf-apex-patterns (incl. references/) · LWC+SLDS2: skills/lwc-slds2 · Flows: skills/flow-patterns. Binding rules here win on any conflict.

## Platform limits & deploy-readiness (added 2026-07-12 from Sprint-1 post-mortem — binding)
1. Metadata descriptions stay under the platform caps: 255 (CustomPermission, PermissionSet),
   1000 (CustomObject, CustomField). The long rationale belongs in the review packet, never the XML.
   Full checklist: skills/sf-data-model/references/metadata-deploy-limits.md.
2. Run `node scripts/metadata-lint.js` before ANY review packet is written; a lint FAIL is a
   defect, same as a failing test.
3. When an org is authenticated, a per-ticket `sf project deploy start --dry-run` (delta manifest)
   is MANDATORY before the packet may say "buildable". No org = the packet carries a prominent
   "UNVERIFIED — NO ORG CONNECTED" banner. "XML well-formed" is never evidence of deployability.
4. Build to the DESIGN SECTION ("per technical-design §2.3"), not to a paraphrased restriction.
   If an instruction conflicts with the design text, flag it in the packet — never silently drop
   a designed field/element to satisfy a narrower instruction.
5. Fix in batches: after a failed dry-run is triaged, fix ALL captured failures, then dry-run
   once — never one-defect-per-round.
