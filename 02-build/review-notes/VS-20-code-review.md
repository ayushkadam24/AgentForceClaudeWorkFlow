# VS-20 Code Review — Facility-scoped sharing rules + district View All (REQ-053)

- Feature: F-001 slot-booking-core
- Producing agent: code-reviewer (independent)
- Date: 2026-07-13
- Phase: forward-build review (pipeline YAML phase = DONE; POC pilot closed — post-pilot forward ticket reviewed on orchestrator request)
- Upstream IDs: REQ-053 - design 6.2 - EP-08 - VS-20 - relates D-022 (bulk export), A-018 (prod permsets)
- Ticket ACs: (1) criteria-based facility sharing on VS_Appointment__c / VS_Patient__c to per-facility public groups; (2) District_Admin / District_MIS View All on Patient/Appointment.

> UNVERIFIED — NO ORG DRY-RUN AT REVIEW TIME. No org was contacted (org-safety constraint).
> metadata-lint clean / XML well-formed is NOT evidence of deployability. The orchestrator
> consolidated dry-run MUST confirm the two deployability risks below before "buildable".

## Files reviewed (VS-20 scope, git-confirmed)
- objects/VS_Appointment__c/VS_Appointment__c.sharingRules-meta.xml (new)
- permissionsets/VS_District_Admin.permissionset-meta.xml (modified)
- permissionsets/VS_District_MIS.permissionset-meta.xml (modified)

Scope check: git status confirms these 3 are the only VS-20 files; other changed classes/objects/
permsets in the tree belong to concurrent tickets and were NOT reviewed here.

## metadata-lint
node scripts/metadata-lint.js -> 2 FAILs, both PRE-EXISTING and unrelated to VS-20
(VS_Session__c.VS_Walk_In_Reserve_Count__c and VS_Setting__mdt.VS_Value__c CustomMetadata-in-formula,
a Sprint-1 two-phase-deploy note). ZERO lint failures on VS-20 three files. PASS for this ticket.
(Could NOT reproduce the builder-claimed NoShow/Otp >255 FAILs in my run; either way not VS-20 files.)

## Verdict by category
- CORRECTNESS vs AC: FINDINGS (AC-1 Patient deferred by design; AC-1 Appointment = template + deploy risks; AC-2 met at object level, not field level)
- 3.4 INTEGRITY: N/A (no booking-path / Apex code in this ticket)
- SECURITY / least-privilege: PASS (View All is read-only, no modifyAll, no other role broadened)
- COMPLIANCE (rules/10): PASS (no Aadhaar; no new person/health fields; District View All matches design 6.2 justified+audited)
- STANDARDS (rules/20): PASS (VS_ naming; descriptions present + under caps; no hardcoded IDs)
- DEPLOYABILITY: FINDINGS (two unverified risks — MAJOR-1, MAJOR-2)

## Findings

### MAJOR-1 — Lookup-field criteria deployability unverified (deploy gate)
File: VS_Appointment__c.sharingRules-meta.xml lines 11-15 (criteria field = VS_Facility__c).
VS_Facility__c is a Lookup relationship (confirmed: type=Lookup to VS_Facility__c). Criteria-based
sharing rules have historically not accepted Lookup relationship fields as criteria; Lookup support is
version/org dependent. Not verifiable at review time. If rejected, the primary deliverable does not
deploy and the core AC is unmet. Direction: orchestrator dry-run MUST confirm; fallback = denormalized
Text/Picklist facility-code field on Appointment (architect, new schema) OR Apex managed sharing
(re-route dev-senior). Builder surfaced this honestly — mandatory gate, not a builder defect.

### MAJOR-2 — Sharing rule references a public group that does not exist in metadata (deploy ordering)
File: VS_Appointment__c.sharingRules-meta.xml lines 8-10 (group VS_Facility_Sample_Staff).
No public-group metadata exists in the repo; per plan Blocked #4 group creation is a manual admin step.
A sharing rule referencing a non-existent group FAILS to deploy. Deploy order is load-bearing: the group
must exist in the org BEFORE this metadata deploys. Direction: devops runbook must list "create public
group VS_Facility_Sample_Staff (+membership) as a PRE-deploy step" (builder documented it as post-deploy;
for the rule to deploy it must be pre-deploy). Confirm sequencing in the dry-run.

### MAJOR-3 — AC-1 for VS_Patient__c not delivered (design 6.2 not buildable as written)
No sharingRules file for VS_Patient__c. Confirmed VS_Patient__c has no VS_Facility__c/any facility-ref
field (C1-minimal person data + consent + match key + no-show count only). Design 6.2 literally specifies
Patient facility sharing keyed on VS_Facility__c — not expressible. Builder correctly flagged rather than
forced a wrong rule (per ticket instruction). REQ-053 record-level scoping for Patient remains UNBUILT.
Direction: architect/BA decision — (a) denormalized facility field on Patient (new schema ticket) or
(b) Apex managed sharing of Patient off related visible Appointments (dev-senior). Sanctioned-partial,
not a builder defect, but must be tracked as open scope, not silently closed.

### MAJOR-4 — District View All grants no field-level read (records visible, fields blank)
Files: VS_District_Admin / VS_District_MIS — objectPermissions add allowRead+viewAllRecords on
VS_Patient__c / VS_Appointment__c, but NO fieldPermissions for any Patient/Appointment field. With OWD
Private + View All + zero FLS, district roles see records exist but every person/health field renders
blank — AC-2 aggregate visibility is structurally but not functionally met. Builder deliberately withheld
FLS as a compliance-sensitive decision (which person/health fields district roles may see) — defensible
conservative choice. Direction: explicit follow-up to grant read-only FLS on the specific fields district
roles are permitted to see (C1 person + health-event review); do not blanket-grant. Flag BA/architect.

## Minors / Nits
- MINOR-1 (access level): sharing rule grants accessLevel=Edit (line 6). Design 6.2 says facility staff
  "see only their facility" without specifying Read vs Edit. Edit is reasonable for staff who manage
  bookings/check-in, but confirm intended access is Edit and not Read (least-privilege).
- NIT-1: value "Diag Facility" is a single hardcoded facility name matching the QA seed fixture;
  correctly labelled TEMPLATE. Ongoing per-facility clone burden (new rule + group each onboarding) is
  larger than the ticket "one-time group creation" framing — ensure runbook/roadmap sizes this.

## Overall recommendation: APPROVE-WITH-FIXES
No blocker in the delivered metadata: lint-clean on VS-20 files, no Aadhaar, no CRUD/FLS over-broadening,
least-privilege read-only View All, scope confined to the two sanctioned district permsets, and the
Patient/Lookup gaps were surfaced honestly. The four MAJORs are deployment-gated / design-escalation
follow-ups — none require rewriting the delivered files, but all must be resolved before REQ-053 is
complete. This APPROVE-WITH-FIXES is explicitly contingent on the orchestrator dry-run clearing MAJOR-1
and MAJOR-2; a dry-run rejection there flips this to REQUEST-CHANGES.
