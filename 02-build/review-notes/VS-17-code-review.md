<!--
feature:         F-001 slot-booking-core
producing-agent: code-reviewer
date:            2026-07-13
phase:           DONE (see PROCESS FLAG below -- reviewed on explicit request outside declared build phase)
derives-from:    02-build/jira-log.md VS-17 (line 483-500), 02-build/sprint-plan.md line 46,
                 01-discovery/technical-design.md sec2.3 (line 146-149), sec2.4 (line 158-168),
                 sec2.5 (line 170-179), REQ-058, REQ-059, EP-07, D-014
reviewed-files:  force-app/main/default/objects/VS_Notification_Log__c/VS_Notification_Log__c.object-meta.xml,
                 force-app/main/default/objects/VS_Notification_Log__c/fields/ (VS_Patient__c, VS_Appointment__c,
                 VS_Channel__c, VS_Template_Name__c, VS_Message_Body__c, VS_Status__c, VS_Provider__c,
                 VS_Helpline_Included__c, VS_Sent_At__c).field-meta.xml
org-status:      UNVERIFIED - NO ORG DRY-RUN AT REVIEW TIME (ORG SAFETY: reviewer instructed not to
                 contact any org this pass; only offline node scripts/metadata-lint.js was run).
-->

# VS-17 Independent Code Review -- VS_Notification_Log__c object & fields

## PROCESS FLAG (read first)

PIPELINE_STATE.md YAML currently reads phase: DONE, next_command: /retro (already executed,
"POC COMPLETE" logged 2026-07-12). Per rules/00 hard constraint, agents "act only in
DEV_IN_PROGRESS or DEV_COMPLETE." VS-17 is a Sprint-4/EP-07 ticket that was never in the deployed
F-001 pilot scope (VS-01..09 only, per the DEV_COMPLETE/BA_ARCH_CONFIRM/QA gate log lines) -- this
review is happening after the pipeline's own release gate closed the POC. This is a genuine
phase/process deviation the human should reconcile (either this is legitimate forward/Sprint-2 work
that should reopen a phase, or it's an out-of-band exercise). It does NOT change the technical
verdict below -- the metadata is reviewed on its own merits -- but it must be surfaced, not silently
absorbed.

## Verdict: APPROVE-WITH-FIXES (no blocker)

Zero blockers. All stated ACs are met on disk. Findings are documentation/consistency items that
constrain later tickets (VS-18, VS-21, permission-set extension) rather than defects in VS-17
itself.

## AC walk (jira-log.md VS-17, line 495-499)

| AC | Result |
|---|---|
| Lookup -> Patient, Lookup -> Appointment, each described | PASS -- both present, VS_ prefixed, nullable, described (508/548 chars) |
| VS_Channel__c picklist (SMS/Email), described | PASS -- restricted picklist, SMS default=true, required=true, described |
| VS_Template_Name__c, described | PASS -- Text(120), described |
| VS_Message_Body__c, described | PASS -- LongTextArea(4000), described, explicit no-Aadhaar/C1 warning baked into the description text |
| VS_Status__c picklist (Logged/Sent/Failed), described | PASS -- restricted picklist, Logged default=true, required=true, described |
| VS_Provider__c, described | PASS -- Text(80), described |
| VS_Helpline_Included__c, described | PASS -- Checkbox, default false, described |
| VS_Sent_At__c, described | PASS -- DateTime, optional, described |
| Depends on VS-08 | Satisfied structurally -- VS_Appointment__c (VS-08) already exists on disk and is deployed live (Deploy 0AfgL00000QySCASA3, per PIPELINE_STATE log line 53); lookup target resolves |

## sec3.4 INTEGRITY

Not applicable -- this ticket is pure object/field metadata (no Apex, no Flow, no booking path).
Confirmed no automation of any kind was added (grep of the object folder shows only the two
metadata file types listed above; ticket text explicitly scopes "no Apex this ticket" and that
scope was honored).

## SECURITY

- sharingModel = Private set correctly on the CustomObject, matching design sec2.2 row 9 and the AC.
- No CRUD/FLS enforcement code applies (no Apex in this ticket).
- No hardcoded IDs/secrets anywhere in the reviewed files.
- No permission-set grants were added for this object (self-flagged by the builder). Net effect:
  as of this ticket, nobody except System Administrator can read or write
  VS_Notification_Log__c -- this is consistent with the ticket's explicit metadata-only scope and
  mirrors the same scope boundary already used by VS-07 (VS_Patient__c) and VS-08
  (VS_Appointment__c), both of which raised the identical flag ("permission sets not extended in
  this ticket") in their own review packets. See finding MINOR-3 below -- three tickets deep
  now without closing this gap.

## COMPLIANCE

- No-Aadhaar: grep of the object folder for "Aadhaar" returns only the deliberate compliance-warning
  prose inside VS_Message_Body__c's and the object's own description ("Must never contain
  Aadhaar numbers... No Aadhaar or extra person data stored") -- no field name, label, picklist
  value, or default value references Aadhaar. PASS (structural, matches the same
  grep-clean pattern used and accepted on VS-07/VS-08).
- C1 minimization: this object stores no person attributes of its own -- only references
  (Patient/Appointment lookups) plus message/delivery metadata (channel, template name, rendered
  body, status, provider, helpline flag, sent-at). This matches design sec2.5's explicit statement
  that "VS_OTP_Verification__c and VS_Notification_Log__c reference the patient/mobile but store
  no extra personal attributes." PASS.
- Facility-scoped visibility: correctly NOT implied by OWD/relationship alone; the object
  description explicitly defers this to Annexure C5 grants ("facility-staff visibility is not
  implied by relationship; access governed separately"), consistent with the OWD-Private +
  future-permission-set-and-sharing-rule pattern used elsewhere in this build. PASS.
- Retention: 1-yr SMS-log retention class is documented in the object description (Annexure C4);
  actual purge mechanics are VS-21's job (VS_RetentionPurgeBatch), not this ticket's -- correctly
  out of scope here. PASS.
- Synthetic-data-only reminder is present in VS_Message_Body__c's description (C3.2). No seed/test
  data was created by this ticket (metadata-only, as instructed). PASS.

## STANDARDS (rules/20)

- Naming: object and all 8 custom fields carry the VS_ prefix; Apex-style naming n/a (no Apex).
  PASS.
- Object-level flags (enableActivities/BulkApi/Feeds/History/Licensing/Reports/Search/Sharing/
  StreamingApi) and the NLOG-{00000} AutoNumber name-field pattern are structurally identical to
  the already-approved VS_Patient__c (PAT-{00000}) and VS_Appointment__c (APT-{00000}) objects --
  consistent convention, no deviation. PASS.
- Descriptions present on every object/field, well under caps (max observed: 548 chars vs the
  1000-char CustomObject/CustomField cap; full list below in Deployability). PASS.
- Declarative-first / dev-mid routing honored (Task ticket, no Apex). PASS.

## DEPLOYABILITY

Ran node scripts/metadata-lint.js (offline, no org contact) from repo root:

  == Metadata lint ==
    FAIL formula reads $CustomMetadata (checkOnly cannot validate w/ same-transaction CMDT -- needs two-phase deploy or Apex read): force-app\objects\VS_Session__c\fields\VS_Walk_In_Reserve_Count__c.field-meta.xml
    FAIL formula reads $CustomMetadata (checkOnly cannot validate w/ same-transaction CMDT -- needs two-phase deploy or Apex read): force-app\objects\VS_Setting__mdt\fields\VS_Value__c.field-meta.xml
  == 2 metadata-limit issue(s) ==

Exit code 1 (repo-wide). Both FAILs are pre-existing, unrelated to VS-17 -- neither file path is
under objects/VS_Notification_Log__c/; both are known, already-deployed Sprint-1 artifacts (D-026
et seq. two-phase-deploy CMDT coupling, tracked in memory/decisions.md, not reachable or touched by
this ticket). Zero lint findings against any of the 10 files this ticket wrote. The builder's
packet claim metadata_lint_ok: true is accurate scoped to this ticket's own files, but stated
without qualifying that the repo-wide run currently exits non-zero for unrelated reasons -- worth
tightening the wording in future packets so "lint OK" isn't misread as "whole repo lint is green."

Description-length check (computed directly, all 10 files):

| File | description length | cap |
|---|---|---|
| VS_Notification_Log__c.object-meta.xml | 536 | 1000 |
| VS_Appointment__c.field-meta.xml | 548 | 1000 |
| VS_Channel__c.field-meta.xml | 160 | 1000 |
| VS_Helpline_Included__c.field-meta.xml | 208 | 1000 |
| VS_Message_Body__c.field-meta.xml | 297 | 1000 |
| VS_Patient__c.field-meta.xml | 508 | 1000 |
| VS_Provider__c.field-meta.xml | 255 | 1000 |
| VS_Sent_At__c.field-meta.xml | 218 | 1000 |
| VS_Status__c.field-meta.xml | 156 | 1000 |
| VS_Template_Name__c.field-meta.xml | 241 | 1000 |

All comfortably clear. No __mdt elements involved (plain custom object). No dry-run was run
(ORG SAFETY instruction for this review pass) -- carries the mandatory
UNVERIFIED - NO ORG CONNECTED / NO DRY-RUN AT REVIEW TIME banner per rules/20 point 3; the
orchestrator's consolidated dry-run is the actual deployability gate.

## TESTS

Not applicable -- ticket is explicitly metadata-only, no Apex, no test class required or written.

## Findings

MINOR-1 -- deleteConstraint choice (SetNull) diverges from this codebase's own precedent for
audit-relevant lookups, with no memory entry.
File: force-app/main/default/objects/VS_Notification_Log__c/fields/VS_Patient__c.field-meta.xml:10
and .../VS_Appointment__c.field-meta.xml:10.
What: both lookups use <deleteConstraint>SetNull</deleteConstraint>. The sibling object built one
ticket earlier, VS_Appointment__c (VS-08), uses Restrict on all five of its lookups
specifically so that "a parent... with existing appointments cannot be deleted out from under its
booking history -- purge/archival is VS-21's... job... not ad hoc record deletion" (VS-08 review
packet, 02-build/review-notes/VS-08-review.md lines 78-81). VS-17's rationale text
("deleteConstraint SetNull chosen so deleting a patient does not block/cascade-delete historical
notification logs; the log row survives... for audit continuity") is in tension with that established
principle: SetNull permits an ad hoc patient/appointment delete to silently sever the very link an
audit trail depends on (Annexure C4 "audit trail... tamper-evident", C5 "every record read
attributable"), whereas Restrict would force that delete through the same controlled purge-batch
discipline VS-08 established. Why it matters: this is a real (if low-probability, since
notification-log retention is 1 yr -- shorter than patient's 10 yr) audit-integrity trade-off, not a
cosmetic choice, and the ticket text explicitly allowed either option ("choose and note") so it is
NOT an AC violation -- but per rules/30 sec3 a decision that constrains later work (VS-18's insert
pattern, VS-21's purge-batch behavior) should get a D-### entry in .claude/memory/decisions.md;
none exists. Suggested direction: architect/BA ruling at the next confirm point on SetNull vs
Restrict consistency across Patient/Appointment-referencing objects, and mint the D-### either way
so the choice is traceable, not just narrated in field prose.

MINOR-2 -- required picklists (VS_Channel__c, VS_Status__c) rely on a default that will
NOT auto-apply on the Apex-driven inserts this object is built for.
File: force-app/main/default/objects/VS_Notification_Log__c/fields/VS_Channel__c.field-meta.xml:7-14
and .../VS_Status__c.field-meta.xml:7-14.
What: both fields are <required>true</required> with a picklist <default>true</default> value.
Salesforce only auto-populates a picklist's metadata default for records created through a UI page
layout -- Apex/API inserts do NOT receive the default automatically. VS_Notification_Log__c
rows are designed to be inserted exclusively by Apex (VS_SmsService, VS-18) per D-014/EP-07, so
every insert must explicitly set both fields or the DML throws REQUIRED_FIELD_MISSING. Why it
matters: this is a well-known Salesforce gotcha that has caused real defects elsewhere; VS-18's own
AC already implies explicit values will be set on every write ("a row is written with
VS_Provider__c = LogOnly, VS_Status__c = Logged..."), so practical risk is low, but it should
be called out explicitly rather than left implicit, so the VS-18 developer doesn't assume the schema
default covers them. Suggested direction: add one line to this ticket's packet (or the VS-18 ticket
notes) stating the fields are effectively mandatory constructor inputs to whatever logging method
VS_SmsService exposes, and add a VS-18 negative test asserting the insert fails cleanly if either
is omitted (defense against a future caller regression).

MINOR-3 -- permission-set/FLS extension for this object is deferred, same unresolved gap already
flagged twice before (VS-07, VS-08).
File: no permission-set file touched by this ticket (force-app/main/default/permissionsets/
unchanged for VS_Notification_Log__c).
What: consistent with ticket scope (metadata-only, no Apex) and the identical precedent set by VS-07
and VS-08 (both of whose review packets raised this same flag and left it open), no permission set
grants read/write/FLS on any VS_Notification_Log__c field yet. Why it matters: as-is, only System
Administrator can access this object; VS-18's log-only writes would need system-mode DML or a
permission-set grant to work for any non-admin context, and no facility-staff role can ever read
its own facility's notification logs until this closes. This is the third ticket in a row to defer
the same gap (Patient VS-07, Appointment VS-08, now Notification Log VS-17) without a tracking
ticket owning the consolidated fix. Suggested direction: before any of these three objects reaches a
real user, do one consolidated FLS-extension pass across VS_Facility_Staff/VS_Nurse/
VS_MO_Facility_Admin/VS_District_Admin/VS_District_MIS covering Patient+Appointment+
Notification Log together (ties to A-018, already tracked as a production-permset gap) rather than
three more one-off deferrals.

NIT-1 -- no page layout / compact layout.
Not required for an Apex-written, report/list-view-consumed log object (no user-facing create/edit
form is implied by the ticket); the builder self-flagged this correctly. No action needed unless a
future admin console screen needs to browse individual log rows via a standard layout.

## Compliance summary

No-Aadhaar: PASS (structural grep clean, both in field values and the deliberate warning prose).
C1 minimization: PASS (zero net-new person attributes; references only). OWD/sharing intent: PASS
(Private, facility-scoping correctly deferred to permission sets/sharing, not baked into OWD).
Synthetic-data-only reminder present in the message-body description. No seed data was created.

## Overall recommendation

APPROVE-WITH-FIXES. No blocker, no major. Three minors are documentation/consistency items
(mint a D-### for the deleteConstraint choice or get an explicit architect ruling; call out the
Apex-required-field-default gotcha for VS-18; track the now-3x-deferred permission-set extension as
one consolidated item) -- none of them block this ticket's own deploy or violate its AC. Remember the
PROCESS FLAG above: this review ran with the pipeline in DONE, outside the DEV_IN_PROGRESS/
DEV_COMPLETE window rules/00 scopes agent action to; a human should reconcile why VS-17 is being
built/reviewed post-close-out.
