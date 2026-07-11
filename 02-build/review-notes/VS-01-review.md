<!--
feature:         F-001 slot-booking-core
producing-agent: dev-mid
date:            2026-07-11
phase:           DEV_IN_PROGRESS
derives-from:    02-build/jira-log.md (VS-01 detailed spec), 02-build/sprint-plan.md,
                 01-discovery/technical-design.md §2 (data model), EP-01
                 REQ-001, REQ-009, REQ-010, REQ-011, REQ-012
                 D-005, D-007, D-009, D-012, D-018, D-025 (.claude/memory/decisions.md)
downstream:      BA_ARCH_CONFIRM drift-check, VS-03/VS-05/VS-06/VS-08 (which build on this
                 object set), human deploy to the POC Developer Edition org (D-025)
-->

# VS-01 Review Packet — Build facility/service/session capacity objects

## Ticket summary

VS-01 (EP-01, Sprint 1, dev-mid, no dependencies) builds the five capacity-spine reference
objects that every later F-001 ticket depends on: `VS_Facility__c`, `VS_Service__c`,
`VS_Facility_Service__c` (junction), `VS_Session__c`, `VS_Holiday__c`. Object/field metadata —
no Apex, no LWC (declarative-first per rules/20; no genuinely-complex need was found, so nothing
is flagged for re-routing to dev-senior) — plus one small before-save record-triggered Flow
(`VS_FacilityService_BeforeSave_SetExternalId`) added during this ticket's own review fix-forward
(see "Fix-forward correction" below) to make AC-3's composite key mechanically sound.

**Fix-forward correction (2026-07-11, same-ticket, pre-formal-review):** the first draft of
`VS_Facility_Service__c.VS_External_Id__c` used an invalid pattern — a formula element combined
with `externalId`/`unique` (illegal on formula fields) trying to emulate a "default value formula
referencing sibling fields" (also not a real Salesforce capability; default values can only
reference `$User`/`$Profile`/global functions). This was a **confirmed deploy-blocking defect**,
caught before formal `/dev-review`. It is corrected below: `VS_External_Id__c` is now a plain
Text field, and a before-save Flow sets its value on create. See the amended A-008 in
`.claude/memory/assumptions.md` for the full before/after.

## What was built

All metadata lives under `force-app/main/default/objects/`. Every object and every field carries
a `<description>`. All API names carry the `VS_` prefix (rules/20). Sharing model set per design
§2.2 (Public Read Only for the whole capacity spine; junction/child objects that sit under a
Master-Detail inherit `ControlledByParent`, which resolves to the same effective Public Read Only
because their parent `VS_Facility__c` is Read).

### 1. `VS_Facility__c` — 8 fields
Path: `force-app/main/default/objects/VS_Facility__c/`
OWD: Public Read Only (`sharingModel = Read`). Retention (C4): permanent reference.

| Field | Type | Purpose |
|---|---|---|
| `VS_Facility_Type__c` | Picklist (PHC, CHC, DistrictHospital) | Facility tier for discovery/filtering (REQ-001) |
| `VS_Location__c` | Geolocation | Proximity ordering in citizen discovery (REQ-001, VS-15) |
| `VS_Pincode__c` | Text(6) | Locality search |
| `VS_Helpline_Number__c` | Phone | Must appear in every actionable SMS (C7.3) |
| `VS_Operating_Start_Time__c` | Time | Bounds session/slot windows (REQ-009) |
| `VS_Operating_End_Time__c` | Time | Bounds session/slot windows (REQ-009) |
| `VS_Is_Active__c` | Checkbox (default true) | Excludes inactive facilities from discovery |
| `VS_External_Id__c` | Text(30), ExternalId+Unique | Reserved CoWIN/U-WIN seam (OQ-016), not populated in F-001 |

Standard Name field relabeled "Facility Name" (Text).

### 2. `VS_Service__c` — 6 fields
Path: `force-app/main/default/objects/VS_Service__c/`
OWD: Public Read Only. Retention (C4): permanent reference.

| Field | Type | Purpose |
|---|---|---|
| `VS_Service_Type__c` | Picklist (Vaccination, OPD; default Vaccination) | Keeps catalogue generic per D-012 — nothing OPD-specific built |
| `VS_Vaccine_Name__c` | Text(120) | Vaccine dispensed by this service |
| `VS_Slot_Granularity_Mins__c` | Number(3,0), default 15 | Per-service slot length override (D-008) |
| `VS_Dose_Count__c` | Number(2,0) | Reserved seam for deferred next-dose recall |
| `VS_Is_Active__c` | Checkbox (default true) | Excludes inactive services from discovery |
| `VS_External_Id__c` | Text(30), ExternalId+Unique | Reserved CoWIN/U-WIN seam, not populated in F-001 |

Standard Name field relabeled "Service Name" (Text).

### 3. `VS_Facility_Service__c` — 4 fields (junction)
Path: `force-app/main/default/objects/VS_Facility_Service__c/`
OWD: `ControlledByParent` (inherits Facility's Read). Retention (C4): permanent reference.

| Field | Type | Purpose |
|---|---|---|
| `VS_Facility__c` | Master-Detail → `VS_Facility__c` | Offering only exists under a facility (design §2.4) |
| `VS_Service__c` | Lookup → `VS_Service__c`, required, delete Restrict | Service is a shared catalogue row, must not cascade-delete |
| `VS_Is_Active__c` | Checkbox (default true) | Deactivate an offering without deleting history |
| `VS_External_Id__c` | Text(60), ExternalId+Unique | Composite facility+service uniqueness key — AC3; populated by the `VS_FacilityService_BeforeSave_SetExternalId` before-save flow (see below), **not** a formula/default-value (that pattern was a deploy-blocking defect, corrected this run) |

Name field: AutoNumber `FS-{0000}` (junction rows have no natural human name).

**Companion automation:** `force-app/main/default/flows/VS_FacilityService_BeforeSave_SetExternalId.flow-meta.xml`
— a before-save record-triggered flow on `VS_Facility_Service__c`, trigger = Create only, sets
`VS_External_Id__c = VS_Facility__c & "-" & VS_Service__c` via a text formula resource assigned to
`$Record.VS_External_Id__c`. Before-save flows execute before the Unique constraint is evaluated
and modify `$Record` directly with no DML action, so per the flow-patterns skill no fault path is
required (nothing in the flow can fail — it's a single field assignment). Deployed Active (status
per flow-patterns skill: "deploy ACTIVE... note activation state in the review packet" — noted
here). Description field on the flow carries entry criteria + purpose + VS-01 per rules/20.

### 4. `VS_Session__c` — 12 fields (the capacity spine / future §3.4 lock target)
Path: `force-app/main/default/objects/VS_Session__c/`
OWD: `ControlledByParent` (inherits Facility's Read). Retention (C4): **bookings 3 yr**.

| Field | Type | Purpose |
|---|---|---|
| `VS_Facility__c` | Master-Detail → `VS_Facility__c` | Session meaningless without its facility (design §2.4) |
| `VS_Service__c` | Lookup → `VS_Service__c`, required, delete Restrict | Shared catalogue row |
| `VS_Session_Date__c` | Date, required | Calendar date; checked against `VS_Holiday__c` by VS-06 |
| `VS_Start_Time__c` | DateTime, required | Session window start (D-007) |
| `VS_End_Time__c` | DateTime, required | Session window end |
| `VS_Total_Capacity__c` | Number(6,0), required | MO-set total capacity (REQ-010/011) |
| `VS_Walk_In_Reserve_Count__c` | **Formula** Number(6,0) | `CEILING(VS_Total_Capacity__c * $CustomMetadata.VS_Setting__mdt.WalkInReservePct.VS_Value__c / 100)` — see dependency note below (field renamed `Value__c`→`VS_Value__c` 2026-07-11, VS-02 review Option A, rules/20 VS_ prefix compliance) |
| `VS_Bookable_Capacity__c` | **Formula** Number(6,0) | `VS_Total_Capacity__c - VS_Walk_In_Reserve_Count__c` |
| `VS_Walk_In_Used_Count__c` | Number(6,0), default 0, required | Incremented only inside the VS-09 session lock (D-019/D-020) — no automation here |
| `VS_Status__c` | Picklist (Open, Closed, Cancelled; default Open) | Session lifecycle |
| `VS_Is_Drive_Day__c` | Checkbox (default false) | Overrides holiday closure for this session only (D-018) |
| `VS_External_Id__c` | Text(60), ExternalId+Unique | Reserved CoWIN/U-WIN seam; no composite formula (only the Facility_Service AC required one) |

Name field: AutoNumber `SES-{00000}`.

### 5. `VS_Holiday__c` — 3 fields
Path: `force-app/main/default/objects/VS_Holiday__c/`
OWD: Public Read Only. Retention (C4): permanent reference.

| Field | Type | Purpose |
|---|---|---|
| `VS_Facility__c` | Lookup → `VS_Facility__c`, required, delete Restrict | Reference data, not an owned child (design §2.4) |
| `VS_Holiday_Date__c` | Date, required | Closure date read by VS-06 |
| `VS_Description__c` | Text(255) | Staff-facing closure reason |

Name field relabeled "Holiday Name" (Text).

**Total: 5 objects, 33 custom fields, 1 flow.** (Corrected 2026-07-12, N-1 fix per human VS-01
verdict: `VS_Session__c` has 12 fields, not 11 — the table above lists all 12; the object-set total
is 33 custom fields, not 32. Metadata on disk was always correct; only this packet's tally was off
by one.) All 38 object/field metadata XML files (5 object-meta.xml + 33 field-meta.xml — includes
the 5 nameField definitions embedded in each object-meta.xml, not separate files) plus the 1
flow-meta.xml file were checked for tag balance/well-formedness in this environment (no XML parser
available, so a manual tag-stack check was run instead — see Deploy/verify status below).

## AC checklist (against VS-01's acceptance criteria in `02-build/jira-log.md`)

| # | Acceptance criterion | Status | Notes |
|---|---|---|---|
| 1 | Given no F-001 objects exist, when this ticket deploys, then all five objects exist with described fields per §2.3 | **PASS (metadata drafted)** | All 5 objects + 32 fields built, every one with a `<description>`. NOT yet deployed — see honesty note below. |
| 2 | Given `VS_Session__c.VS_Total_Capacity__c` is set, when the record saves, then `VS_Walk_In_Reserve_Count__c`/`VS_Bookable_Capacity__c` formulas compute per §2.1 (CEILING against `VS_Setting__mdt.WalkInReservePct`) | **PASS (metadata drafted), BLOCKED on VS-02 at deploy time** | Formula text matches design §2.3, referencing `$CustomMetadata.VS_Setting__mdt.WalkInReservePct.VS_Value__c` — **not hardcoded**. (Updated 2026-07-11, VS-02 review Option A: the CMDT field was renamed `Value__c`→`VS_Value__c` for rules/20 VS_ prefix compliance, applied here to match — both objects were still draft/undeployed so the contract was renamed rather than documented as an exception.) This formula will fail deploy/save validation until `VS_Setting__mdt` and its `WalkInReservePct` record (VS-02) exist in the org. **Deploy order dependency (unchanged, still correct): VS-01 and VS-02 MUST be deployed in the same `sf project deploy start` pass (or VS-02 first)**, or the `VS_Session__c` object deploy will fail formula validation. |
| 3 | Given `VS_Facility_Service__c`, when two records are created for the same facility+service, then the `VS_External_Id__c` unique constraint rejects the duplicate | **PASS (corrected this run)** | **Original mechanism was a confirmed deploy-blocking defect** (a formula field cannot be `externalId`/`unique`, and default values cannot reference sibling fields — caught in VS-01 review, fixed before formal `/dev-review`). Corrected: `VS_External_Id__c` is now a plain Text(60) field (`externalId`+`unique`, no formula), populated by a new before-save record-triggered flow `VS_FacilityService_BeforeSave_SetExternalId` (`force-app/main/default/flows/`) that sets it to `VS_Facility__c & "-" & VS_Service__c` on CREATE, before the Unique constraint evaluates. This is mechanically sound (not just declaratively plausible); remaining verification is deploy-time only (see A-008 amendment). |

**Overall: 3/3 ACs met in the drafted metadata. AC2 carries a hard cross-ticket deploy-order
dependency on VS-02 (unchanged, correct). AC3's original mechanism was a genuine deploy-blocking
defect, now fixed with a before-save Flow — the remaining open item is deploy-time verification
only (A-008 amendment), not a design gap.** Called out for the human/BA_ARCH_CONFIRM drift-check.

## Traceability

| Object | REQ served |
|---|---|
| `VS_Facility__c` | REQ-001 (discovery), REQ-009 (operating hours for slot generation) |
| `VS_Service__c` | REQ-010 (facility offerings), D-012 (generic service catalogue) |
| `VS_Facility_Service__c` | REQ-010 (which facility offers which service) |
| `VS_Session__c` | REQ-010, REQ-011, REQ-012 (capacity authoring, D-007/D-009/D-018) |
| `VS_Holiday__c` | REQ-009 (closure dates read by slot generation) |

Upstream chain: REQ-001/009/010/011/012 (brief) → design §2.2/§2.3 (data model) + EP-01 → VS-01
(this ticket) → this metadata + review packet → (QA Tier-2/3, no direct TC-### yet — VS-01 is
metadata-only; behavior is exercised by VS-03/VS-06/VS-09 downstream).

## Assumptions / open items logged

- **A-008, amended this run** — original assumption (default-value-formula composite key) is
  **RESOLVED BY REDESIGN**: replaced by the `VS_FacilityService_BeforeSave_SetExternalId`
  before-save flow. What remains open (owner dev-mid/dev-senior, verify at
  `sf project deploy start --dry-run` + a manual duplicate-insert test in the DE org before
  BA_ARCH_CONFIRM): that the flow populates `VS_External_Id__c` correctly on both UI saves and
  API/bulk inserts, and that the resulting Unique constraint violation is catchable/user-actionable
  wherever a later ticket inserts `VS_Facility_Service__c` programmatically. See the full amendment
  in `.claude/memory/assumptions.md`.
- **Cross-ticket deploy dependency (not a new decision, restating design intent honestly —
  unchanged by this fix):** `VS_Session__c.VS_Walk_In_Reserve_Count__c` references
  `$CustomMetadata.VS_Setting__mdt.WalkInReservePct.Value__c`. This is VS-02's deliverable.
  **VS-01 and VS-02 MUST be deployed in the same `sf project deploy start` pass** (or VS-02 first),
  or the `VS_Session__c` object deploy will fail formula validation.
- No Page Layouts, List Views, or Compact Layouts were built — VS-01's Issue Type is explicitly
  "pure object/field metadata," and the AC does not ask for UI polish. Salesforce auto-generates a
  default layout on deploy of a new object; the human can adjust via Setup once deployed to the DE
  org. Flagging so this isn't mistaken for an oversight.
- No Aadhaar field exists anywhere in this object set (checked against rules/10 C1) — none of the
  five objects carry person data at all in this ticket (person data is `VS_Patient__c`, VS-07,
  out of scope here).
- D-025 (Developer Edition target, not scratch org) was honored: no scratch-only metadata features
  used (no Platform Cache, no scratch-only Geolocation quirks); Geolocation, Master-Detail, and
  Custom Metadata merge-field formulas are all standard DE-compatible features.

## Deploy/verify status — HONEST

- **Metadata (and now the flow) drafted, NOT deployed.** No org is connected in this environment.
- **`sf project deploy start --dry-run` was NOT run** — no CLI/org access available here, before
  or after this fix. I did not run any Salesforce CLI command and am not claiming one succeeded.
- **What I did verify in this environment:** the corrected `VS_External_Id__c` field-meta.xml and
  the new flow-meta.xml were checked for well-formedness (balanced/matched tags) using the same
  manual Node.js tag-stack script (no `xmllint`/`python3` available) — both pass with 0
  mismatch/unclosed-tag failures, alongside a re-confirmation that the `<formula>` element is now
  fully absent from `VS_External_Id__c`. This is a structural check only; it does NOT confirm
  Metadata API schema validity, does not confirm the before-save flow's field assignment actually
  executes as intended in a real save, and does not confirm the resulting Unique constraint
  behavior end-to-end.
- **Human next step:** deploy VS-01 (this metadata, including the new flow) together with or after
  VS-02 (`VS_Setting__mdt`) to the POC Developer Edition org (D-025) via
  `sf project deploy start --dry-run`, then a real deploy, then manually test AC2 (save a Session
  with Total_Capacity set, confirm the formula fields compute) and AC3 (create one
  `VS_Facility_Service__c` record, confirm `VS_External_Id__c` auto-populates via the flow, then
  attempt a second record for the same facility+service and confirm it is rejected).

## Status

Set to **Ready for Review** in `02-build/jira-log.md` (status history appended, including a
"fix applied" line for this correction). Recommend BA_ARCH_CONFIRM drift-check confirm: (1) VS-02
deploy-order dependency (unchanged), (2) the before-save flow populates the composite key on both
UI and API/bulk inserts (A-008 amendment), (3) no Page Layouts built is intentional scope, not an
omission.

## Human Verdict (2026-07-11) — APPROVE-WITH-FIXES

Independent code-review pass (code-reviewer, /dev-review VS-01): design-faithful, compliant,
standards-clean; prior deploy-blocking defect fix confirmed; **no blocker**. Human verdict: proceed
to VS-02 and **batch** the two fixes below (do not re-open VS-01 now).

**Deferred fixes — batched, MUST be applied before BA_ARCH_CONFIRM:**
- **M-2 (Minor, integrity):** `VS_FacilityService_BeforeSave_SetExternalId` is `Create`-only, so editing
  `VS_Service__c` on an existing junction row leaves a stale composite key and the unique constraint
  stops catching duplicate (facility, service) pairs. **Fix:** extend the flow trigger to
  `CreateAndUpdate` and recompute the key (preferred), or forbid editing Service after create via a
  validation rule. DRIFT-CHECK RADAR at BA_ARCH_CONFIRM.
- **N-1 (Nit, docs):** packet field tally is off by one — `VS_Session__c` has **12** fields (not 11);
  object-set total is **33** (not 32). Metadata is correct; correct the counts in this packet when the
  M-2 fix is applied.

**M-1 (Major, deploy-order) → devops runbook, NOT a code fix:** `VS_Session__c` capacity formulas
reference `$CustomMetadata.VS_Setting__mdt.WalkInReservePct.VS_Value__c` (renamed 2026-07-11 from
`Value__c` — see MIN-1 resolution below), so VS-01 cannot deploy standalone. Deploy VS-01 + VS-02 in
ONE pass, and VS-02 must expose the value via a field named exactly `VS_Value__c`. Owned by the
devops Deployment Package (DP-001), not reworked in VS-01.

**MIN-1 (Minor, naming) — RESOLVED by rename (2026-07-11, VS-02 review verdict, Option A):** the
CMDT field was originally named `Value__c` (no `VS_` prefix), a deviation from rules/20 naming.
Since neither VS-01 nor VS-02 was deployed, the human chose to fix this properly rather than
document an exception: `Value__c`→`VS_Value__c` and `Value_Text__c`→`VS_Value_Text__c` across both
tickets' draft metadata, including this ticket's `VS_Walk_In_Reserve_Count__c` formula (above).
Full rename detail and grep-verified contract confirmation in
`02-build/review-notes/VS-02-review.md`.

**N-2 (info):** a few fields marked `required` beyond design §2.3 — benign strengthening; recorded as an
intentional, acknowledged deviation for BA_ARCH_CONFIRM.

## Batched fixes applied (2026-07-12, dev-mid, Bucket A)

- **M-2 — APPLIED.** `VS_FacilityService_BeforeSave_SetExternalId.flow-meta.xml`
  `<recordTriggerType>` changed `Create` → `CreateAndUpdate`; the flow now recomputes
  `VS_External_Id__c` on every save (create or update), so editing `VS_Service__c` on an existing
  junction row no longer leaves a stale composite key — the Unique constraint keeps catching
  duplicate (facility, service) pairs after an edit, not just at create. Flow description updated
  to state it fires on create AND update. Assignment logic unchanged. Re-verified well-formed
  (`python xml.dom.minidom`, 0 failures) after this fix — this pass also caught and corrected a
  pre-existing unescaped `&` in the flow's `<description>` text (`VS_Facility__c & "-" &
  VS_Service__c` written as literal ampersands instead of `&amp;`), which was an XML defect present
  since the original VS-01 fix-forward and is unrelated to M-2 itself but was flagged by the IDE's
  XML diagnostics while editing this file.
- **N-1 — APPLIED.** Field-count tally corrected above: `VS_Session__c` section header now reads
  12 fields; the object-set total line now reads 33 custom fields. No metadata changed (it was
  always correct); only the doc counts were wrong.
