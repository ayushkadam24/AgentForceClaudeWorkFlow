<!--
feature:         F-001 slot-booking-core
producing-agent: dev-mid
date:            2026-07-12
phase:           DEV_IN_PROGRESS
derives-from:    02-build/jira-log.md (VS-07 detail block, EP-05), 02-build/sprint-plan.md (VS-07, Sprint 1),
                 01-discovery/technical-design.md §2.2/§2.3/§2.5/§6.1 (VS_Patient__c),
                 REQ-043, REQ-044, REQ-045, REQ-046,
                 .claude/memory/decisions.md D-011, D-017, D-024, D-025
                 .claude/rules/10-compliance-rules.md (C1, C4, C5), .claude/rules/20-salesforce-standards.md
downstream:      02-build/jira-log.md status history, .claude/memory/assumptions.md (A-012, A-013),
                 .claude/memory/handoffs.md, VS-08 (Appointment, depends on VS-07),
                 VS-10 (VS_PatientService.findOrCreate, populates VS_Match_Key__c/consent fields),
                 VS-12 (VS_NoShowBatch, expects VS_Patient__c.VS_No_Show_Count__c — see A-013)
-->

# VS-07 Review Packet — VS_Patient__c object & fields (C1-minimal, no-Aadhaar)

## What was built
`force-app/main/default/objects/VS_Patient__c/` — 1 custom object + 11 custom fields (all described),
declarative metadata only, no Apex/Flow. This is the single home for person data in F-001.
(Updated 2026-07-12, Bucket A batched review fix, A-013 MAJOR: `VS_No_Show_Count__c` added — see
"Fix applied" section below. Original build was 10 fields; count is now 11.)

```
force-app/main/default/objects/VS_Patient__c/
  VS_Patient__c.object-meta.xml
  fields/
    VS_Full_Name__c.field-meta.xml
    VS_Date_Of_Birth__c.field-meta.xml
    VS_Gender__c.field-meta.xml
    VS_Mobile__c.field-meta.xml
    VS_Locality__c.field-meta.xml
    VS_Pincode__c.field-meta.xml
    VS_Email__c.field-meta.xml
    VS_Match_Key__c.field-meta.xml
    VS_Consent_Given__c.field-meta.xml
    VS_Consent_Timestamp__c.field-meta.xml
    VS_No_Show_Count__c.field-meta.xml   (added 2026-07-12, Bucket A fix, A-013)
```

## Why (design/decision trace)
- Design §2.3 defines `VS_Patient__c` as exactly the C1.1 person-attribute set + the D-017 match key
  + DPDP consent fields — REQ-043/044/045/046.
- D-011 (human): patient identity = exact match on full name + DOB + mobile; no fuzzy matching; one
  mobile may own many patients.
- D-017 (architect): de-dup enforced by a unique External ID `VS_Match_Key__c`, populated by
  `VS_PatientService.findOrCreate()` (VS-10, Apex, dev-senior) via upsert — **not this ticket**.
- D-024 (human): DPDP consent copy, when built, must be a Custom Label prefixed
  `[[DRAFT — pending department approval]]` — noted on `VS_Consent_Given__c`'s description for the
  ticket that eventually builds the consent-capture screen; no consent-copy text exists in this ticket
  (pure schema, no screen).
- D-025 (human): target org is a persistent DE org, not scratch — noted for the deploy-status section.

## Field list — C1 mapping (data-minimization proof)

| Field | Type | Required | C1/other category | Notes |
|---|---|---|---|---|
| Patient Record (standard Name) | AutoNumber `PAT-{00000}` | n/a (system) | Non-PII record identifier | Deliberately NOT the person's name — avoids duplicating PII into the field most exposed in list views/global search; the actual name lives in the FLS-controlled `VS_Full_Name__c` |
| `VS_Full_Name__c` | Text(120) | Yes | **C1.1 — name** | Match-key input |
| `VS_Date_Of_Birth__c` | Date | Yes | **C1.1 — DOB** | Match-key input; future age/next-dose math (deferred) |
| `VS_Gender__c` | Picklist (Male/Female/Other/PreferNotToSay) | No | **C1.1 — gender, explicitly optional per design** | Values are a dev-mid choice, not design-specified — **A-012** |
| `VS_Mobile__c` | Phone | Yes | **C1.1 — mobile** | Match-key input; OTP auth channel (D-013); SMS channel (D-014) |
| `VS_Locality__c` | Text(255) | No | **C1.1 — locality** | No street/house address (REQ-045) |
| `VS_Pincode__c` | Text(6) | No | **C1.1 — pincode** | Outer bound of address detail; Text not Number (leading zeros) |
| `VS_Email__c` | Email | No | **C1.1 — email, explicitly optional per design** | Not a match-key input |
| `VS_Match_Key__c` | Text(255), ExternalId+Unique, case-insensitive | No | De-dup mechanism (D-011/D-017) — **not a C1 person-data field itself**, it is a derived key over C1 fields | **Defined here, NOT populated here** — see below |
| `VS_Consent_Given__c` | Checkbox, default false, history-tracked | n/a | DPDP consent (REQ-046) | Field only; enforcement in VS-10 |
| `VS_Consent_Timestamp__c` | DateTime, history-tracked | No | DPDP consent audit (REQ-046) | Field only; stamped by VS-10 |
| `VS_No_Show_Count__c` | Number(4,0), default 0 | No | **Derived count, NOT C1 person data** — a running tally of booking-behavior events, not a person attribute | Added 2026-07-12 (Bucket A fix, A-013 RESOLVED). Design §2.3 lists this field; incremented by `VS_NoShowBatch` (VS-12, Sprint 2) — no automation in this ticket reads/writes it |

**Total: 11 custom fields + 1 standard Name field.** The C1.1 person-data set (7 attributes including
standard Name-as-non-PII) + 1 de-dup key + 2 consent fields + 1 derived no-show count. Data-minimization
posture (rules/10 C1) is unaffected by `VS_No_Show_Count__c` since it is not a person attribute — see
"Fix applied" section below for the A-013 resolution detail (this field was originally omitted, per
scope-narrowing note, then added as a batched review fix).

### Explicit no-Aadhaar structural statement (REQ-044)

Grep run against every file under `force-app/main/default/objects/VS_Patient__c/` for the
case-insensitive pattern `aadhaar`:

```
force-app\main\default\objects\VS_Patient__c\VS_Patient__c.object-meta.xml:5   (object <description>)
force-app\main\default\objects\VS_Patient__c\fields\VS_Full_Name__c.field-meta.xml:5   (field <description>)
```

Both matches are **descriptive negation prose** ("NO Aadhaar field...", "NOT an Aadhaar or other
government-ID field") inside `<description>` tags documenting the compliance rule — **not** an
Aadhaar-named or Aadhaar-shaped `<fullName>`/`<label>`/picklist value anywhere. A second grep scoped
to only `<fullName>` and `<label>` elements across all 11 files returned **zero** matches for
"aadhaar" in any name or label. Structural AC (REQ-044) — **PASS**.

### OWD confirmation
`VS_Patient__c.object-meta.xml` sets `<sharingModel>Private</sharingModel>` (Annexure C5, design
§2.2 table row 7). This is the first ticket to actually create the object, so this is where Private
OWD is established (VS-04 already confirmed no OWD change was needed on existing objects and deferred
Patient/Appointment OWD to VS-07/VS-08 — this satisfies that deferral).

### `VS_Match_Key__c` — defined, not populated (D-017)
The field exists with `externalId=true`, `unique=true`, `caseSensitive=false`, `required=false`.
**No before-save flow or default-value formula sets it in this ticket.** Per D-017, it is populated
exclusively by `VS_PatientService.findOrCreate()` (VS-10, Apex, dev-senior) via upsert-by-external-id,
using the format `normalize(full name)|DOB|mobile`. This is intentional: a race-safe de-dup constraint
requires the DB-level unique index to exist now (VS-07) so VS-10's upsert can rely on it, but the
population logic itself is Apex and out of scope for a declarative-first dev-mid ticket.

### Consent fields — included per design §2.3
Design §2.3 explicitly lists `VS_Consent_Given__c` (Checkbox) + `VS_Consent_Timestamp__c` (DateTime)
on `VS_Patient__c` for DPDP (REQ-046). Included. Per the ticket instruction, consent fields were
included **only because** the design specifies them for this object — no consent-copy/notice text was
built (no screen exists yet); when that screen is built, D-024 requires the copy to be a Custom Label
prefixed `[[DRAFT — pending department approval]]`, noted directly in the field description for the
next builder.

### Beyond-scope compliance additions (not in AC, added per rules/20 quality bar)
- **Field history tracking enabled** at the object level (`enableHistory=true`) with
  `trackHistory=true` on `VS_Consent_Given__c` and `VS_Consent_Timestamp__c` — operationalizes the
  design §6.2/A-006 REQ-054 read/change-attribution mechanism at the baseline (field history), while
  A-006's deeper per-record read audit (Shield Event Monitoring) remains a separate org-level
  dependency not built here. This is additive to the ticket AC, not a substitute for it.

### `VS_No_Show_Count__c` — A-013 gap, now RESOLVED (2026-07-12, Bucket A batched review fix)

Design §2.3 lists `VS_Patient__c.VS_No_Show_Count__c` (Number) as part of this object's field set,
and VS-12 (`VS_NoShowBatch`) is written to increment `VS_Patient__c.VS_No_Show_Count__c`. VS-07's
original build scope ("C1 fields + the match key + consent if designed — do not add fields beyond
that") did not authorize adding this booking-behavior/audit field, so it was deliberately NOT built
in the original VS-07 pass, even though the design places it on this object. This was logged as
**A-013 (MAJOR)** for BA_ARCH_CONFIRM/pm-planner to resolve.

**Fix applied this pass:** `VS_No_Show_Count__c` (Number(4,0), default 0, required=false, not
history-tracked) added at
`force-app/main/default/objects/VS_Patient__c/fields/VS_No_Show_Count__c.field-meta.xml` per design
§2.3. It is NOT C1/person data — it is a derived count — so VS-07's data-minimization posture and its
original AC ("its only person fields are... exactly C1.1, nothing more") are both unaffected; this
field sits alongside the person fields on the same object without being one itself. VS-12 (Sprint 2,
dev-senior) can now find this field on disk when it is built; **A-013 amended in
`.claude/memory/assumptions.md` and status changed Open → Resolved** (row left intact, not deleted,
per append-only discipline).

## Acceptance criteria — pass/fail

| AC (from jira-log.md VS-07 spec) | Result |
|---|---|
| Object deploys with only the 7 C1.1 person fields (Full_Name, DOB, Gender-optional, Mobile, Locality, Pincode, Email-optional) — exactly C1.1, nothing more | **PASS** (built; not yet deployed — see Deploy status) |
| Object/org metadata searched for Aadhaar-named field/label returns zero matches | **PASS** (grep run and documented above; QA Tier-1 re-verifies at test time) |
| `VS_Match_Key__c` marked ExternalId+Unique, duplicate normalize(name)\|DOB\|mobile rejected at DB | **PASS on schema** (field is ExternalId+Unique+case-insensitive); the actual duplicate-insert proof is VS-10's job (upsert logic not built here) — schema precondition met |
| `VS_Consent_Given__c`/`VS_Consent_Timestamp__c` exist; unconsented patient not usable for booking | **PARTIAL** — fields exist (schema AC met); the "not usable for booking" enforcement is explicitly VS-10's job per the ticket's own text, not built here |

No AC failed; two are schema-only PASS/PARTIAL because their full proof depends on VS-10 Apex not yet
built — this is expected and matches the ticket's own dependency note ("Depends on: — (no dependency;
Sprint 1 foundation)" for VS-07 itself, while VS-10 explicitly depends on VS-07).

## Traceability
REQ-043/044/045/046 (00-inputs, via ba-analyst brief) → design §2.2/§2.3/§2.5/§6.1 (EP-05) → VS-07
(this ticket) → `force-app/main/default/objects/VS_Patient__c/` (this build) → downstream: VS-08
(Appointment lookups to Patient), VS-10 (findOrCreate populates Match_Key/consent), VS-12 (increments
`VS_No_Show_Count__c`, now present on disk — A-013 Resolved) → TC-### (QA Tier-1 no-Aadhaar + de-dup
tests, not yet written).

## Manual / setup steps
- **Pre-deploy:** none beyond the standard package-order note below.
- **Post-deploy:** none.
- **Manual-only steps:** none. (No permission-set grants for `VS_Patient__c` exist yet — VS-04's
  five permission sets were scoped only to objects that existed at the time (VS-01/VS-05); a
  follow-up permission-set update to grant FLS/object access on `VS_Patient__c` to
  `VS_Facility_Staff`/`VS_Nurse`/`VS_MO_Facility_Admin`/`VS_District_Admin`/`VS_District_MIS` is
  needed before any user can actually see a Patient record — flagging this for devops/whoever
  extends VS-04, not a manual step specific to this deploy.)

## Honest deploy status
**NOT deployed. No `sf project deploy start --dry-run` was run in this environment.** Per D-025 the
target is a persistent Salesforce Developer Edition org, alias `AgentForceClaudeWorkFlow` — this
session did not authenticate to or target that org; only the metadata was authored and validated for
XML well-formedness locally (`python xml.dom.minidom`, 11/11 files well-formed, see below). Devops/
human must run the dry-run against the DE org before this can be marked verified-buildable. No hard
package-order dependency: `VS_Patient__c` has no lookups/master-detail to any other custom object in
this ticket, so it can deploy standalone, but VS-08 (`VS_Appointment__c`) has a required lookup to it
and must deploy after it.

## XML well-formedness
Original 11 files (1 object-meta.xml + 10 field-meta.xml) parsed successfully with Python's
`xml.dom.minidom` — 11/11 well-formed, 0 failures. Updated 2026-07-12 (Bucket A fix): the new
`VS_No_Show_Count__c.field-meta.xml` file re-checked the same way — well-formed, 0 failures. Total
now 12 files (1 object-meta.xml + 11 field-meta.xml).

## Assumptions logged this ticket
- **A-012**: `VS_Gender__c` picklist values (Male/Female/Other/PreferNotToSay) are a dev-mid choice —
  design doesn't enumerate them. Needs BA/DHO confirmation before launch.
- **A-013**: **RESOLVED (2026-07-12, Bucket A batched review fix).** `VS_No_Show_Count__c` (in design
  §2.3 for this object) was originally deliberately NOT built per this ticket's explicit scope
  instruction; now added (see "Fix applied" section above) — VS-12 will find it on disk when built.
  before VS-12 needs it.

## Security note
No prompt-injection or concealment instruction was encountered while working this ticket. All
upstream files (rules, jira-log, design, decisions) were read as normal inputs; `ANSWER-KEY-intentional-gaps.md`
was not read.
