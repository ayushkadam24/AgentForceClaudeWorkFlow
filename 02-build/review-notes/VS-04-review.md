<!--
feature:         F-001 slot-booking-core
producing-agent: dev-mid
date:            2026-07-12
phase:           DEV_IN_PROGRESS
derives-from:    02-build/jira-log.md (VS-04 detailed spec block), 02-build/sprint-plan.md,
                 01-discovery/technical-design.md sect6.2/sect6.3/sect7 (EP-08),
                 .claude/memory/decisions.md D-022/D-025, .claude/memory/assumptions.md A-006/A-007
downstream:      code-reviewer (/dev-review VS-04), BA_ARCH_CONFIRM drift-check, VS-07/VS-08/VS-17/VS-20
                 (must EXTEND these permission sets), devops (runbook/manual-steps)
-->

# VS-04 Review Packet — Permission sets, OWD, session timeout, MIS export gate

**Ticket:** VS-04 | **Epic:** EP-08 Security, Sharing & Compliance | **Routing:** dev-mid | **Sprint:** 1
**Upstream:** REQ-036 (gating only), REQ-053, REQ-055 / EP-08 / D-022, D-025 / Annexure C5, C6
**Status this run:** Ready for Review (see status transitions in jira-log.md)

## 1. What was built

All metadata is declarative-only (no Apex), under `force-app/main/default/`:

| Path | Purpose |
|---|---|
| `permissionsets/VS_Facility_Staff.permissionset-meta.xml` | Front-line facility staff — read-only |
| `permissionsets/VS_Nurse.permissionset-meta.xml` | Clinical/vaccinator role — read-only (today) |
| `permissionsets/VS_MO_Facility_Admin.permissionset-meta.xml` | Medical Officer — read/create/edit Session + Holiday |
| `permissionsets/VS_District_Admin.permissionset-meta.xml` | District admin — read/create/edit Facility/Service/Facility_Service/Holiday, read-only Session/Slot |
| `permissionsets/VS_District_MIS.permissionset-meta.xml` | District MIS/reporting — read-only everywhere + `VS_Bulk_Export` custom permission |
| `customPermissions/VS_Bulk_Export.customPermission-meta.xml` | The REQ-036/D-022 export-gate bit itself |
| `settings/Security.settings-meta.xml` | Best-effort org-wide 15-min session timeout (REQ-055/C6) — **see honesty note in section 4** |

**Deploy-order note (mirrors VS-01's M-1):** these permission sets grant object/field perms on
`VS_Facility__c`, `VS_Service__c`, `VS_Facility_Service__c`, `VS_Session__c`, `VS_Slot__c`,
`VS_Holiday__c` — all of which already exist on disk (VS-01/VS-05). No new deploy-order dependency is
introduced beyond what VS-01/VS-05 already require. `VS_Setting__mdt` is NOT referenced by any
permission set here (see section 3).

## 2. Five permission sets — what each grants (high level)

All five are `<license>Salesforce</license>`, standard user licenses (Developer Edition compatible,
D-025). None of the five references `VS_Patient__c`, `VS_Appointment__c`, or
`VS_Notification_Log__c` — those objects do not exist yet (VS-07/VS-08/VS-17).

- **VS_Facility_Staff** — Read-only on all 6 existing objects (Facility, Service, Facility_Service,
  Session, Slot, Holiday), every field readable/not editable. No create/edit/delete anywhere. No
  `VS_Bulk_Export`.
- **VS_Nurse** — Identical scope to VS_Facility_Staff today (read-only on the same 6 objects) — this
  role's actual write access (check-in, vaccination event) doesn't exist until `VS_Appointment__c`
  (VS-08). No `VS_Bulk_Export`.
- **VS_MO_Facility_Admin** — Read/Create/Edit on `VS_Session__c` (drives the VS-03 capacity-definition
  screen flow) and `VS_Holiday__c` (facility closure calendar); read-only on
  `VS_Facility__c`/`VS_Service__c`/`VS_Facility_Service__c` (catalog setup is District Admin's job) and
  on `VS_Slot__c` (slots are batch-generated/booking-service-owned, never hand-edited). No Delete
  anywhere — retirement is via status/active flags. No `VS_Bulk_Export`.
- **VS_District_Admin** — Read/Create/Edit on `VS_Facility__c`/`VS_Service__c`/`VS_Facility_Service__c`/
  `VS_Holiday__c` (facility/service onboarding, shared holiday calendar); read-only on
  `VS_Session__c`/`VS_Slot__c` (oversight, not day-to-day operational edits — that's the MO's role). No
  Delete anywhere. No `VS_Bulk_Export` — export gating is District MIS only, not this role.
- **VS_District_MIS** — Read-only on all 6 existing objects, no create/edit/delete anywhere, PLUS the
  `VS_Bulk_Export` custom permission (the only permission set that carries it).

Formula fields (`VS_Session__c.VS_Bookable_Capacity__c`, `VS_Session__c.VS_Walk_In_Reserve_Count__c`)
are readable-only in every permission set — platform rules do not allow marking a formula field
editable. Booking-service-owned counters (`VS_Slot__c.VS_Booked_Count__c`,
`VS_Session__c.VS_Walk_In_Used_Count__c`) are readable-only in every permission set here too — their
only intended write path is `VS_BookingService` (VS-09/VS-11) inside the session lock (D-019/D-020),
not any permission-set-driven UI edit. **Open item for VS-09's reviewer:** confirm what running-user
context `VS_BookingService.book()`/`cancel()`/`reschedule()` executes under, and whether these two
counters need editable=true added to any of these permission sets (or whether the service runs in a
context that doesn't require it) — flagging rather than guessing, since VS-09 is not yet built.

`VS_Setting__mdt` (custom metadata type, `visibility=Public`) is **not** referenced in any permission
set: Custom Metadata Types marked Public are readable by all authenticated users by platform default,
so no permission-set grant is needed for the six seeded tunables (WalkInReservePct, CutOffHours, etc.)
to be visible. Noting this explicitly so a reviewer doesn't read its absence as an oversight.

## 3. MIS export gate — mechanism (D-022/REQ-036/Annexure C5.2)

- **Mechanism:** a Custom Permission, `VS_Bulk_Export` (`customPermissions/VS_Bulk_Export.customPermission-meta.xml`),
  enabled ONLY inside `VS_District_MIS.permissionset-meta.xml`.
- **Who has it:** `VS_District_MIS` only.
- **Who does NOT have it:** `VS_Facility_Staff`, `VS_Nurse`, `VS_MO_Facility_Admin`,
  `VS_District_Admin` — none of the other four permission sets reference `VS_Bulk_Export` at all
  (absence, not `enabled=false`, since a permission set only needs to declare a custom permission it
  grants).
- **No export UI/mechanism built:** per D-022 and design sect7.1, this ticket is gating ONLY — there is
  no button, report, batch, or LWC anywhere in this codebase that checks
  `Custom Permission.VS_Bulk_Export` or performs an export. A future export feature must (a) check this
  custom permission before running and (b) log every export per C5.2 ("every export logged") — neither
  the check nor the logging mechanism exists yet; that is new scope beyond EP-01..08 per D-022's own
  rejected-alternatives note, and should come back through the architect if/when it's built.

## 4. Session timeout (REQ-055/Annexure C6) — what's metadata vs manual

**What was built:** `settings/Security.settings-meta.xml` attempts to set the org-wide idle session
timeout to `FifteenMinutes` via the `SecuritySettings` metadata type's `sessionSettings.sessionTimeout`
field, plus `lockSessionsToDomain=true` and `forceRelogin=true` as reasonable companions for a
public-facing/shared-device posture.

**Honest limitations — please read before approving:**
1. **This is a single ORG-WIDE setting, not a per-permission-set value.** The Metadata API does not
   expose session timeout on `PermissionSet` (or, as far as I can find, on `Profile` either) — there is
   no mechanism in this metadata type to give shared-device roles a 15-min timeout while giving another
   role something longer. Applying `FifteenMinutes` org-wide satisfies the "≤15 min" ceiling for
   everyone (conservative — it can only be stricter than required, never laxer), but it is a global
   effect, not a role-scoped one. If a future role genuinely needs a longer timeout, that would need a
   documented business exception, not a permission-set change.
2. **This file has NOT been validated.** No `sf project deploy start --dry-run` was run in this
   environment (see section 6 — no confirmed POC Developer Edition org is authenticated/authorized in
   this session). The exact `<sessionSettings>` sub-element schema was authored from memory/best
   effort, not confirmed against a live Metadata API describe for this org. **It is possible this file
   fails to deploy or that some sub-elements are wrong** — XML well-formedness was checked (all 7 new
   files parse cleanly), but that only proves the XML is syntactically valid, not that the schema
   matches what the org's Metadata API expects.
3. **Documented manual fallback (put on the devops runbook regardless of whether this file deploys
   clean):** Setup → Security → Session Settings → Session Timeout Value = 15 Minutes (org-wide), and
   confirm no profile carries a longer per-profile Session Settings override. A human should confirm
   this setting in the org's Setup UI post-deploy either way, since it is a security-critical org
   setting.

**Conclusion:** built what's possible in metadata, honestly flagged as unverified, with a manual/org-
setting fallback documented per the ticket's explicit instruction.

## 5. OWD — nothing invented here

Per the ticket's explicit scope: OWD on the 7 objects that exist today is already set (VS-01/VS-05) —
`VS_Facility__c`/`VS_Service__c`/`VS_Holiday__c` = **Public Read Only** (`sharingModel: Read`);
`VS_Facility_Service__c`/`VS_Session__c`/`VS_Slot__c` = **ControlledByParent** (inherit their parent's
Public Read Only). This was verified by reading each `.object-meta.xml` on disk (see section 6) — no
OWD change was made in this ticket. Design's called-for **Private** OWD on person/booking objects
(`VS_Patient__c`/`VS_Appointment__c`, sect6.2) does not apply here — those objects are VS-07/VS-08's
scope, not built yet. `VS_Setting__mdt` has no OWD concept (Custom Metadata visibility is Public/
Protected, already set to Public at VS-02).

## 6. AC pass/fail (per jira-log.md VS-04 detailed spec)

| AC | Text (paraphrased) | Result |
|---|---|---|
| AC-1 | OWD: reference/bookable = Public Read Only, person/booking = Private | **PARTIAL / N-A for this ticket** — reference/bookable OWD confirmed already correct (VS-01/VS-05, not changed here). Person/booking (Private) OWD does not apply — those objects don't exist yet; will be VS-07/VS-08's job. Not a fail: nothing to do here was skipped. |
| AC-2 | 5 permission sets assigned (Facility_Staff, Nurse, MO_Facility_Admin, District_Admin, District_MIS); unassigned user gets no access beyond OWD | **PASS** — all 5 built exactly as named in jira-log.md's AC text and rules/20's mandated list, each granting nothing beyond described object/field perms. An unassigned user still only gets OWD-level access on Public Read Only objects (Read via org default, no create/edit) — consistent. Note: the technical-design sect6.2 role list also separately names `VS_Citizen_Community`, but that permission set is explicitly VS-14's deliverable (Experience Cloud site + sharing set, EP-06, Sprint 3) — NOT this ticket's AC and NOT built here, to avoid duplicating/pre-empting VS-14. |
| AC-3 | Shared-device role's permission set → 15-min idle timeout | **PARTIAL, HONEST** — attempted via org-wide `Security.settings-meta.xml` (section 4); NOT verified by dry-run/deploy; documented manual Setup fallback provided. Cannot be scoped strictly "per permission set" — see limitation #1 in section 4. |
| AC-4 | `VS_District_MIS` alone carries the export/bulk-data permission bit; export UI itself Deferred | **PASS** — `VS_Bulk_Export` custom permission built, enabled only in `VS_District_MIS`; verified by inspection that no other permission set references it; no export UI/mechanism built (section 3). |

**Overall: 2 PASS (AC-2, AC-4), 1 PARTIAL/honest (AC-3, session timeout — platform-limited, fallback
documented), 1 PARTIAL/N-A for this ticket (AC-1, person/booking OWD belongs to VS-07/VS-08).** No AC
silently skipped; every gap is named with its owner/next ticket.

## 7. Deferred to VS-07 / VS-08 / VS-17 / VS-20 — do not forget

None of the five permission sets reference `VS_Patient__c`, `VS_Appointment__c`, or
`VS_Notification_Log__c` (they don't exist on disk yet — building against them now would fail deploy,
per this ticket's explicit instruction). When those objects are built:
- **VS-07** (`VS_Patient__c`) must extend `VS_Nurse` (read/limited edit for check-in-adjacent fields),
  `VS_MO_Facility_Admin`, `VS_District_Admin` (read/View All), `VS_District_MIS` (read/View All) — and
  decide `VS_Facility_Staff`'s scope (likely read-only, booking desk).
- **VS-08** (`VS_Appointment__c`) must extend `VS_Nurse` (check-in/status edit), `VS_Facility_Staff`
  (walk-in booking create, if that's this role's job — confirm against design), and the District roles
  (read/View All).
- **VS-17** (`VS_Notification_Log__c`) must extend at minimum `VS_District_Admin`/`VS_District_MIS`
  (read, for audit/compliance visibility).
- **VS-20** (facility-scoped sharing + district View All) must add `viewAllRecords=true` on
  `VS_Patient__c`/`VS_Appointment__c` to `VS_District_Admin` and `VS_District_MIS` (design sect6.2 —
  "record-level access is justified + audited") — NOT added here since today's objects are already
  Public Read Only/ControlledByParent (viewAllRecords would be a no-op on them).
- **VS-14** (Experience Cloud) must build `VS_Citizen_Community` (the community/citizen role named in
  design sect6.2 but not part of this ticket's AC — see AC-2 note above), out of this ticket's scope
  (dev-mid routing/EP-08 vs EP-06, Sprint 1 vs 3).

## 8. Assumptions logged this run

No new A-### was raised — the object/field access model here was derived directly from design sect6.2
("facility staff/MO/District Admin/District MIS" role descriptions) and A-006/A-007 (already logged by
architect/pm-planner), not from a new assumption. The one genuinely open judgment call — whether
`VS_MO_Facility_Admin` should also edit `VS_Facility_Service__c` (which services their facility offers)
rather than that being District Admin-only — was resolved conservatively (District Admin only, MO
read-only) because the design text doesn't explicitly assign that action to either role; flagging here
rather than silently picking a side, in case BA_ARCH_CONFIRM disagrees.

## 9. Deploy status — honest

**NOT deployed. No `sf project deploy start --dry-run` was run in this environment.** `sf org list` was
run and shows several connected orgs (ECMS Prod, ECMS DevPhase2/SIT/TEST/UAT/DM, NationalCallCenter,
edu-dev-org, AgentForceClaudeWorkFlow, etc.) but **none of them is the designated "Vaccine Scheduler
POC" Developer Edition org (D-025)** — deploying or dry-running against any of these would risk hitting
the wrong org (several are live client sandboxes/production), which rules/20 and rules/00 both forbid
("never deploy anywhere but the POC scratch org" / DE org per D-025). This matches the precedent set by
VS-01/VS-02/VS-05's review packets (also not deployed/dry-run in this environment). All 7 new metadata
files WERE checked for XML well-formedness (`xml.dom.minidom` parse — all 7 pass, see section 4's
caveat that well-formed is not the same as schema-valid).

## 9a. Deploy-defect fix (2026-07-12, devops dry-run bisection)

The first real dry-run against the DE org (AgentForceClaudeWorkFlow) FAILED and devops bisected it
to two metadata defects (see `02-build/deployments.md`/`runbook.md` and the devops
`agent-runs.log` line, 2026-07-12 19:20), one of which is this ticket's:

- **Defect (VS-04):** `force-app/main/default/customPermissions/VS_Bulk_Export.customPermission-meta.xml`
  had a ~680-char `<description>` — over the CustomPermission description's 255-char cap. **Shortened**
  to 210 chars, preserving the essential meaning: gates bulk-export, held ONLY by `VS_District_MIS`
  (D-022/REQ-036/C5.2), no export UI built yet, future export features must check the permission and
  log every export. `<label>` (`VS Bulk Export`) untouched; the gating grant itself (only
  `VS_District_MIS` enables it) is unchanged.
- **Proactive check (same 255-char trap, other permission sets):** all 5 permission-set
  `<description>`s measured and found similarly over the PermissionSet 255-char cap (they were long
  multi-sentence paragraphs). Measured/shortened counts:

  | Permission set | Before (chars) | After (chars) |
  |---|---|---|
  | VS_Facility_Staff | 1062 | 224 |
  | VS_Nurse | 1007 | 221 |
  | VS_MO_Facility_Admin | 1355 | 218 |
  | VS_District_MIS | 1105 | 243 |
  | VS_District_Admin | 1665 | 243 |

  Each shortened description preserves the role's intent (scope, read/write grants, no-Bulk-Export
  callout where applicable, deferred-to-VS-## pointers); the longer rationale already lives in this
  packet's sections 2/3/7 above — nothing lost, just moved out of the deployable XML.
- **Custom metadata records checked too:** the 6 `force-app/main/default/customMetadata/VS_Setting.*`
  records carry only a `<label>` (max 40 chars) — longest is "Default Slot Granularity (Mins)" at 31
  chars, well under limit; none carries a `<description>` field. No change needed.
- **Verification:** all 6 changed files (1 custom permission + 5 permission sets) re-checked for XML
  well-formedness (Node.js tag-stack parser, 0 mismatched/unclosed tags). Draft only — **not
  deployed, no dry-run run by this agent**; devops re-runs the dry-run next.
- No object/field permission, `customPermissions` grant (VS_Bulk_Export still enabled ONLY in
  VS_District_MIS), or any logic was touched — descriptions only.

## 9b. Deploy-defect fix #2 (required-field FLS) — 2026-07-12, dev-mid fix-forward pass 2

The Phase 2 dry-run (`02-build/deployments.md`, Deploy ID `0AfgL00000Qxf0ASAR`, 2026-07-12 12:20)
surfaced a clean, non-opaque component error on all 5 permission sets: **`"You cannot deploy to
a required field: VS_Facility_Service__c.VS_Service__c"`**.

**Root cause:** `VS_Facility_Service__c.VS_Service__c` is a `required=true` lookup (VS-01). The
platform forbids explicit field-level-security (`<fieldPermissions>`) entries on universally
required fields — they are always implicitly readable/editable, so declaring FLS on them is
illegal metadata, not merely redundant.

**Fix applied:** removed the ONE `<fieldPermissions>` block whose `<field>` is
`VS_Facility_Service__c.VS_Service__c` from each of the 5 permission sets:
`VS_Facility_Staff`, `VS_Nurse`, `VS_MO_Facility_Admin`, `VS_District_Admin`, `VS_District_MIS`.
Nothing else in any file was touched — verified by grep: zero remaining
`VS_Facility_Service__c.VS_Service__c` references anywhere under
`force-app/main/default/permissionsets/`, and all other `fieldPermissions`/`objectPermissions`
blocks (including `VS_Facility_Service__c.VS_Facility__c`, which is present and did NOT error
because it is not `required=true`) are unchanged. The `VS_Bulk_Export` custom-permission gate in
`VS_District_MIS` (C5/D-022, MIS-only) was left exactly as-is — not part of this defect.

**Effective access change:** none in practice — `VS_Facility_Service__c.VS_Service__c` remains
fully readable (and, for `VS_District_Admin`, editable, since the object itself has Create/Edit
object permission) exactly as it did before, because Salesforce grants required fields implicit
FLS regardless of any explicit permission-set entry. Removing the illegal explicit entry does not
reduce or expand any user's actual access to this field.

**Salesforce error this fix addresses (verbatim):**
`"problem": "You cannot deploy to a required field: VS_Facility_Service__c.VS_Service__c"` —
Phase 2 dry-run, Deploy ID `0AfgL00000Qxf0ASAR` (`02-build/deployments.md`, "Phase 2 dry-run"
section), reported identically across all 5 permission sets.

**Verification this pass:** all 5 files re-parsed with Python `xml.dom.minidom` — 0 failures.
`node scripts/metadata-lint.js` re-run read-only: shows only the 2 pre-existing, already-
documented `$CustomMetadata` formula flags (`VS_Session__c.VS_Walk_In_Reserve_Count__c` and the
known false positive `VS_Setting__mdt.VS_Value__c`) — nothing new, confirms no regression from
this fix. Not deployed/dry-run by this agent per this pass's explicit instruction; devops re-runs
Phase 2 next.

## 9c. Deploy-defect fix #3 (20 illegal FLS entries, Master-Detail + required, complete sweep) — 2026-07-12, dev-mid fix-forward pass 3

Removing the single `VS_Facility_Service__c.VS_Service__c` FLS entry (9b) cleared that specific
error, but only unmasked the next batch of the SAME defect class — Master-Detail and other
`required=true` fields also carrying illegal `<fieldPermissions>` entries. devops ran a complete
sweep (not another one-at-a-time dry-run cycle) and identified **20 fields across 3 categories**
that must never carry FLS, all removed in this single batched pass per rules/20 §5:

**Master-Detail (3 fields)** — MD fields inherit access entirely from the parent object's
permissions; a child MD field cannot independently carry FLS:
- `VS_Facility_Service__c.VS_Facility__c`
- `VS_Session__c.VS_Facility__c`
- `VS_Slot__c.VS_Session__c`

**Required (17 fields)** — same rule as 9b's `VS_Facility_Service__c.VS_Service__c`: required
fields get implicit read/edit and reject explicit FLS:
`VS_Facility__c.VS_Facility_Type__c`, `VS_Holiday__c.VS_Facility__c`,
`VS_Holiday__c.VS_Holiday_Date__c`, `VS_Service__c.VS_Service_Type__c`,
`VS_Service__c.VS_Slot_Granularity_Mins__c`, `VS_Session__c.VS_End_Time__c`,
`VS_Session__c.VS_Service__c`, `VS_Session__c.VS_Session_Date__c`,
`VS_Session__c.VS_Start_Time__c`, `VS_Session__c.VS_Status__c`,
`VS_Session__c.VS_Total_Capacity__c`, `VS_Session__c.VS_Walk_In_Used_Count__c`,
`VS_Slot__c.VS_Booked_Count__c`, `VS_Slot__c.VS_Capacity__c`, `VS_Slot__c.VS_Slot_End__c`,
`VS_Slot__c.VS_Slot_Start__c`, `VS_Slot__c.VS_Status__c`.

**Correction to section 9b's note:** 9b stated `VS_Facility_Service__c.VS_Facility__c` "did NOT
error because it is not `required=true`" — that was an accurate read of the round-1 dry-run
result (which only reached the one `VS_Service__c` error before stopping), but this field is in
fact illegal for FLS for a *different* reason (it's Master-Detail, not required) that only
surfaced once the complete sweep ran. Recording this correction here rather than editing 9b's
historical text.

**Fix applied:** removed the `<fieldPermissions>` block for each of the 20 fields above from
**all 5** permission sets (`VS_Facility_Staff`, `VS_Nurse`, `VS_MO_Facility_Admin`,
`VS_District_Admin`, `VS_District_MIS`) — 100 line removals total, done via a scripted pass
(exact field-string match on `<field>...</field>`, one line per entry) to guarantee consistency
across all 5 files rather than 100 manual edits. One side effect: `VS_Slot__c` had all 6 of its
fieldPermissions entries targeted (`Booked_Count__c`, `Capacity__c`, `Session__c`, `Slot_End__c`,
`Slot_Start__c`, `Status__c`), so that field-permission group is now empty in every file (the
`VS_Slot__c` **objectPermissions** grant, which is unrelated and unaffected, remains — read-only
in all 5 sets as before). Consecutive blank lines left by the empty group were collapsed to a
single blank line for readability; no content was altered.

**Effective access change:** none in practice, same reasoning as 9b — every removed field either
inherits FLS from its parent (Master-Detail) or gets implicit read/edit because it is required;
removing the illegal explicit entries does not reduce or expand any user's actual access.

**Verification — grep-confirmed zero remaining, all 5 files:** searched every permission set for
each of the 20 field strings (plus re-confirmed the round-1 `VS_Facility_Service__c.VS_Service__c`
entry, already removed, stayed removed) — **0 matches** across all 5 files. `objectPermissions`
blocks (all 6 objects, all 5 sets) and the `VS_Bulk_Export` custom-permission gate (still enabled
ONLY in `VS_District_MIS`, C5/D-022) were confirmed byte-identical to before this pass — neither
was touched.

**Salesforce errors this fix addresses:** devops's complete sweep re-run, 2026-07-12
(`02-build/deployments.md` latest Errors table) — 20× `"You cannot deploy to a required field:
<field>"` / `"...Master-Detail field: <field>"` pattern errors, one per field listed above, across
all 5 permission sets.

**Verification this pass:** all 5 files re-parsed with Python `xml.dom.minidom` — 0 failures.
`node scripts/metadata-lint.js` re-run read-only — unchanged, still only the 2 pre-existing
`$CustomMetadata` formula flags, no new issue. Not deployed/dry-run by this agent; devops re-runs
next.

## 10. Manual / setup steps

**Pre-deploy:**
- None beyond the existing VS-01/VS-05 deploy-order dependency (these permission sets require
  `VS_Facility__c`, `VS_Service__c`, `VS_Facility_Service__c`, `VS_Session__c`, `VS_Slot__c`,
  `VS_Holiday__c` to already exist in the target org — same objects DP-001 and the VS-05 package
  already cover; no new dependency introduced).

**Post-deploy:**
- Assign each permission set to the appropriate test users in the target org (permission sets are not
  auto-assigned).
- **Confirm session timeout in Setup → Security → Session Settings → Session Timeout Value = 15
  Minutes**, regardless of whether `Security.settings-meta.xml` deploys cleanly (section 4) — this is a
  security-critical org-wide setting a human should visually confirm, not just trust from a metadata
  file that was never dry-run in this environment.
- Confirm no profile carries a per-profile Session Settings override longer than 15 minutes (Setup →
  Profiles → [profile] → Session Settings), if such an override exists in this org.
- A-007 reminder (pm-planner, still Open): per-facility public group membership (staff↔facility) is a
  MANUAL admin step in the POC — this ticket does not create the sharing rules or groups themselves
  (that's VS-20); assigning `VS_Facility_Staff`/`VS_Nurse`/`VS_MO_Facility_Admin` permission sets to a
  user does not, by itself, scope them to a facility — VS-20's public groups do that.

**Manual-only steps (not on any pre/post-deploy list, ongoing):**
- Whoever builds the future export mechanism (out of EP-01..08 scope per D-022) must wire a
  `Custom Permission.VS_Bulk_Export` check + export logging before it ships — not automated, not
  ticketed, flagged here so it isn't silently skipped.
