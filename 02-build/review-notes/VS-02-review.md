<!--
feature:         F-001 slot-booking-core
producing-agent: dev-mid
date:            2026-07-11
phase:           DEV_IN_PROGRESS
derives-from:    02-build/jira-log.md (VS-02 detailed spec), 02-build/sprint-plan.md,
                 01-discovery/technical-design.md §2.2 (Config lives in VS_Setting__mdt) and §2.3
                 (VS_Session__c formula fields), EP-01
                 REQ-007, REQ-009, REQ-013, REQ-014, REQ-015
                 D-008 (slot granularity 15), D-009 (walk-in reserve 25%), D-010 (cut-off 4h),
                 D-025 (DE target org) (.claude/memory/decisions.md)
downstream:      VS-01's VS_Session__c formula fields (same-pass deploy dependency, M-1),
                 BA_ARCH_CONFIRM drift-check, every later ticket that reads a tunable
                 (VS-03/VS-06/VS-09/VS-11/VS-17/VS-18/VS-19/VS-21 per jira-log.md dependency lines)
-->

# VS-02 Review Packet — Create VS_Setting__mdt config + seed values

## Ticket summary

VS-02 (EP-01, Sprint 1, dev-mid, no dependencies) deploys `VS_Setting__mdt` as the single home for
every tunable in the design (walk-in %, cut-off hours, slot granularity, booking horizon, no-show
threshold, reminder offsets) so DHS can adjust these rules from Setup without a code deploy
(rules/20 — Custom Metadata for tunables, no hardcoded values; A-003). Pure Custom Metadata Type +
records — declarative-first, no Apex/Flow needed, nothing flagged for re-routing to dev-senior.

This ticket also discharges a **hard contract** created by VS-01: `VS_Session__c`'s
`VS_Walk_In_Reserve_Count__c` formula (already deployed-as-metadata in VS-01) reads
`$CustomMetadata.VS_Setting__mdt.WalkInReservePct.VS_Value__c`. That reference does not resolve
until this ticket's type/field/record exist, so VS-01 and VS-02 must deploy together (M-1, see
"Manual / setup steps" below).

**MIN-1 RESOLVED (2026-07-11, VS-02 review verdict — APPROVE-WITH-FIXES, Option A):** the original
build named this contract field `Value__c` — a rules/20 naming deviation (missing the mandatory
`VS_` prefix). Because neither VS-01 nor VS-02 had been deployed anywhere, the human chose to fix
this properly rather than document it as an accepted exception: the field is renamed
`Value__c`→`VS_Value__c` (and its sibling `Value_Text__c`→`VS_Value_Text__c`), and VS-01's
`VS_Walk_In_Reserve_Count__c` formula is updated to match. This is a coordinated rename across both
tickets' draft metadata — see the updated CONTRACT confirmation immediately below and the matching
update in `02-build/review-notes/VS-01-review.md`'s M-1/MIN-1 notes.

## CONTRACT confirmation (read before anything else)

**Updated 2026-07-11 for the VS-02 review verdict rename (Option A) — this section now reflects
the POST-rename state.** I originally read the actual deployed-as-metadata VS-01 formula fields
before building (per the task's instruction, rather than trusting the design doc's prose
paraphrase), found the field named `Value__c` compliant with that first draft's contract, and the
human's review verdict subsequently required a rename for full rules/20 `VS_` prefix compliance.
Both the field and VS-01's formula have now been updated together; this section verifies the
post-rename state:

- `force-app/main/default/objects/VS_Session__c/fields/VS_Walk_In_Reserve_Count__c.field-meta.xml`
  now contains: `<formula>CEILING(VS_Total_Capacity__c * $CustomMetadata.VS_Setting__mdt.WalkInReservePct.VS_Value__c / 100)</formula>`
- `VS_Bookable_Capacity__c.field-meta.xml` contains: `<formula>VS_Total_Capacity__c - VS_Walk_In_Reserve_Count__c</formula>`
  (no CMDT reference of its own — it only depends on the sibling formula above; unaffected by the
  rename).

The exact merge path required is now: **object `VS_Setting__mdt`, record DeveloperName
`WalkInReservePct`, field `VS_Value__c`**. This build satisfies all three exactly:
- Custom Metadata Type API name: `VS_Setting__mdt` (`force-app/main/default/objects/VS_Setting__mdt/VS_Setting__mdt.object-meta.xml`)
- Field API name: `VS_Value__c` (`force-app/main/default/objects/VS_Setting__mdt/fields/VS_Value__c.field-meta.xml`, file renamed from `Value__c.field-meta.xml`), Number(18,0)
- Record: `force-app/main/default/customMetadata/VS_Setting.WalkInReservePct.md-meta.xml`,
  `fullName="VS_Setting.WalkInReservePct"` → DeveloperName `WalkInReservePct`, `VS_Value__c` = 25.

**CONTRACT: SATISFIED (post-rename).** Grep-verified (see "Deploy/verify status" below): zero
remaining unprefixed `Value__c`/`Value_Text__c` references to `VS_Setting__mdt` anywhere in
`force-app`; the one hit returned by the verification grep is prose in
`VS_Walk_In_Reserve_Count__c.field-meta.xml`'s own `<description>` narrating the rename history
("renamed from Value__c to VS_Value__c"), not a live reference.

## What was built

### Custom Metadata Type: `VS_Setting__mdt`
Path: `force-app/main/default/objects/VS_Setting__mdt/`

| Property | Value |
|---|---|
| Label / Plural Label | VS Setting / VS Settings |
| Visibility | Public |
| Deployment Status | Deployed |
| Description | Present — states purpose (single config home, rules/20/A-003), lists all 6 seeded tunables, and calls out the CONTRACT (do not rename type/record/field) |

### Fields (2)

| Field | Type | Required | Description present | Purpose |
|---|---|---|---|---|
| `VS_Value__c` (renamed from `Value__c`) | Number(18,0) | No | Yes | The numeric value for numeric tunables (CutOffHours, WalkInReservePct, DefaultSlotGranularityMins, BookingHorizonDays, NoShowThresholdCount). **This is the VS-01 CONTRACT field — do not rename again.** Blank on the one non-numeric record. |
| `VS_Value_Text__c` (renamed from `Value_Text__c`) | Text(255) | No | Yes | Text/multi-value form for settings that don't fit a single number — used only by `ReminderOffsetsHours` ("24,3", comma-separated hour offsets per OQ-005). Blank on all numeric records. |

Design rationale: the ticket instructions permitted a second field for non-numeric/multi-valued
settings while keeping `VS_Value__c` numeric for everything VS-01 depends on. `ReminderOffsetsHours`
is the only seeded tunable that is inherently multi-valued (two offsets), so it is the only record
using `VS_Value_Text__c`; every other record leaves `VS_Value_Text__c` blank via an explicit
`xsi:nil="true"` value (not just an absent `<values>` block, so the field is visibly documented
as intentionally empty rather than forgotten).

**Naming fix (2026-07-11, VS-02 review verdict, Option A):** both fields were originally named
`Value__c`/`Value_Text__c` — missing the mandatory `VS_` prefix (rules/20). Flagged as MIN-1 at
review; since both tickets were still draft/undeployed, the human directed a rename (not a
documented exception) to `VS_Value__c`/`VS_Value_Text__c`. Files renamed
(`Value__c.field-meta.xml`→`VS_Value__c.field-meta.xml`, same for the text field), `<fullName>`
updated, all 6 seed records' `<field>` tags updated, and VS-01's consuming formula updated to match
(see CONTRACT confirmation above).

### Custom Metadata Records (6)
Path: `force-app/main/default/customMetadata/`

| DeveloperName | Label | VS_Value__c | VS_Value_Text__c | Source |
|---|---|---|---|---|
| `CutOffHours` | Cut-Off Hours | 4 | *(blank)* | D-010 |
| `WalkInReservePct` | Walk-In Reserve Pct | 25 | *(blank)* | D-009 — **VS-01 CONTRACT record** |
| `DefaultSlotGranularityMins` | Default Slot Granularity (Mins) | 15 | *(blank)* | D-008 |
| `BookingHorizonDays` | Booking Horizon (Days) | 14 | *(blank)* | REQ-013 / OQ-006 (BA suggested default, **status Open** — no D-### yet, see A-009) |
| `NoShowThresholdCount` | No-Show Threshold Count | 3 | *(blank)* | OQ-007 (BA suggested default "3 no-shows / 6 months" — this ticket only captures the count, not the 6-month restriction window, which OQ-007 itself defers enforcement of to phase 2; status Open, see A-009) |
| `ReminderOffsetsHours` | Reminder Offsets (Hours) | *(blank)* | `"24,3"` | OQ-005 (BA suggested default "24 h + 3 h before"; status Open, see A-009) |

All 6 records match the ticket's named-record AC exactly: `CutOffHours`, `WalkInReservePct`,
`DefaultSlotGranularityMins`, `BookingHorizonDays`, `ReminderOffsetsHours`, `NoShowThresholdCount`.

## AC checklist (against VS-02's acceptance criteria in `02-build/jira-log.md`)

| # | Acceptance criterion | Status | Notes |
|---|---|---|---|
| 1 | Given `VS_Setting__mdt` is deployed, when queried, then it exposes `CutOffHours` (=4), `WalkInReservePct` (=25), `DefaultSlotGranularityMins` (=15), `BookingHorizonDays` (=14), `ReminderOffsetsHours`, `NoShowThresholdCount` as named records | **PASS (metadata drafted)** | All 6 records built with the exact DeveloperNames the AC names, matching values per D-008/009/010 for the three human-signed ones; `BookingHorizonDays`/`NoShowThresholdCount`/`ReminderOffsetsHours` seeded from BA-suggested defaults (A-009 — these 3 remain OQ-005/006/007 "Open", not yet ratified). Not yet deployed — see honesty note below. |
| 2 | Given a value changes in Setup, when any consuming formula/Apex re-reads it, then no code redeploy is needed | **PASS (by construction, structurally)** | This is an inherent property of Custom Metadata (`$CustomMetadata` merge fields and SOQL against `__mdt` objects always read the current record value; no caching requires a redeploy). Cannot be behaviorally proven without a live org — no CLI/org access was exercised in this environment (see below) — but no mechanism in this design defeats it (no hardcoded literal anywhere; every tunable is record-driven). |

**Overall: 2/2 ACs met in the drafted metadata.** AC1's three non-human-signed values are flagged
(A-009) as build-enabling defaults, not final numbers — same treatment A-003 already gave every
open tunable, so this doesn't block the ticket.

## Traceability

| Artifact | REQ / upstream served |
|---|---|
| `VS_Setting__mdt` type | REQ-007 (config rules generally), rules/20 (no hardcoded tunables) |
| `CutOffHours` record | REQ-015 (cancel/reschedule cut-off), D-010 |
| `WalkInReservePct` record | REQ-009 (walk-in reserve capacity split), D-009 — **also the VS-01 CONTRACT record** |
| `DefaultSlotGranularityMins` record | REQ-014 (configurable slot granularity), D-008 |
| `BookingHorizonDays` record | REQ-013 (configurable booking horizon), OQ-006 |
| `NoShowThresholdCount` record | REQ-017-adjacent (no-show penalty threshold, count only), OQ-007 |
| `ReminderOffsetsHours` record | REQ-026/027 (reminder timings), OQ-005 |

Upstream chain: REQ-007/009/013/014/015 (brief) → design §2.2 ("Config lives in VS_Setting__mdt")
→ EP-01 → VS-02 (this ticket) → this metadata + review packet → consumed by VS-01's already-built
`VS_Session__c` formulas (deploy-order dependency, M-1) and by every later ticket in jira-log.md
that lists VS-02 as a dependency (VS-03, VS-06, VS-09, VS-11, VS-17/18/19, VS-21).

## Assumptions / open items logged

- **A-009 (new, this ticket)** — `BookingHorizonDays`=14, `NoShowThresholdCount`=3, and
  `ReminderOffsetsHours`="24,3" are BA-suggested defaults from OQ-006/OQ-007/OQ-005
  (`01-discovery/open-questions.md`), all three still status **Open** — unlike `CutOffHours`,
  `WalkInReservePct`, and `DefaultSlotGranularityMins`, which carry human-signed decisions
  (D-010/D-009/D-008). Seeded anyway per the existing A-003 umbrella ("open tunables do not block
  build"), so this is not a new blocking gap, just an explicit flag: DHO/BA should ratify these
  three before BA_ARCH_CONFIRM or launch. See `.claude/memory/assumptions.md`.
- **Design choice flagged (not a design gap, a build-time decision):** the technical-design.md
  passage on `VS_Setting__mdt` (§2.2/§2.3) describes the type only as "Custom Metadata" holding
  named tunables — it does not prescribe the field shape. I chose a single numeric `Value__c`
  (mandatory per the VS-01 contract) plus one text sibling `Value_Text__c` for the one genuinely
  multi-valued setting (`ReminderOffsetsHours`), rather than e.g. separate typed fields per
  tunable. This keeps the schema minimal and lets future settings reuse the same two fields without
  further object changes. Flagging per the ticket's own instruction ("if the design is thin on
  structure, design it minimally and flag your choice").
- No Aadhaar or person data of any kind in this object set (rules/10 C1) — `VS_Setting__mdt` holds
  only operational tunables.
- D-025 (Developer Edition target) honored: Custom Metadata Types are fully supported on DE orgs
  (no scratch-only feature used); no Platform Cache or other scratch-only dependency.

## Deploy/verify status — HONEST

- **Metadata drafted, NOT deployed.** No org is connected in this environment. This remains true
  after the rename below.
- **`sf project deploy start --dry-run` was NOT run**, before or after the rename. The `sf` CLI
  binary is present in this environment (`sf 2.140.6`, confirmed via `sf --version`), but this
  ticket's instructions are explicit that dev-mid does not deploy for VS-02 — only SFDX source +
  this review packet. No deploy or dry-run command was executed, and none is claimed to have
  succeeded.
- **What I verified at initial build:** all 9 new XML files (1 object-meta.xml, 2 field-meta.xml,
  6 customMetadata .md-meta.xml) were checked for well-formedness with a manual Node.js tag-stack
  script (no `xmllint`/`python3` available in this environment) — 0 mismatched/unclosed-tag
  failures.
- **What I verified for the rename (2026-07-11, this run):**
  - Renamed `Value__c.field-meta.xml`→`VS_Value__c.field-meta.xml` and
    `Value_Text__c.field-meta.xml`→`VS_Value_Text__c.field-meta.xml`, updating each `<fullName>`
    and in-description mention to match.
  - Updated all 6 `force-app/main/default/customMetadata/VS_Setting.*.md-meta.xml` records'
    `<field>` tags from `Value__c`/`Value_Text__c` to `VS_Value__c`/`VS_Value_Text__c` (values
    unchanged — `WalkInReservePct` still 25, etc.).
  - Updated VS-01's `force-app/main/default/objects/VS_Session__c/fields/VS_Walk_In_Reserve_Count__c.field-meta.xml`
    formula from `...WalkInReservePct.Value__c...` to `...WalkInReservePct.VS_Value__c...`.
  - **Grep verification:** `grep -rnE "(^|[^_A-Za-z])Value__c|(^|[^_A-Za-z])Value_Text__c" force-app --include="*.xml"`
    returns exactly one hit, and it is prose in `VS_Walk_In_Reserve_Count__c.field-meta.xml`'s
    `<description>` narrating "renamed from Value__c to VS_Value__c" for audit-trail purposes — not
    a live field/formula reference. No dangling old reference remains in any `<fullName>`,
    `<field>`, or `<formula>` tag.
  - Re-ran the same Node.js tag-stack well-formedness check on all 9 touched files (2 renamed field
    files, the object-meta.xml's description edit, 6 customMetadata records, plus VS-01's formula
    field) — 0 mismatched/unclosed-tag failures.
  - This is a structural check only; it does not confirm Metadata API schema validity (e.g.
    whether `xsi:nil="true"` is accepted by the real Metadata API for a blank Custom Metadata field
    value, or whether `Number(18,0)` is an allowed precision/scale pair) and does not confirm the
    `$CustomMetadata.VS_Setting__mdt.WalkInReservePct.VS_Value__c` merge field in VS-01's formula
    actually resolves at save time in a live org.

## Manual / setup steps

- **Pre-deploy:** none beyond the standard org connection (`sf org login web` to the POC Developer
  Edition org per D-025).
- **Deploy-order (MUST, M-1 from the VS-01 human verdict):** deploy VS-01 and VS-02 **in the same
  `sf project deploy start` pass** (or VS-02 first, then VS-01) — `VS_Session__c`'s formula fields
  reference `$CustomMetadata.VS_Setting__mdt.WalkInReservePct.VS_Value__c` (post-rename) and will
  fail Metadata API validation if `VS_Setting__mdt`/`WalkInReservePct` do not already exist in the
  target org. This is owned by the devops Deployment Package (DP-001) per the VS-01 human verdict,
  not re-solved here. **Rename delta flag for devops:** DP-001's manifest/deltas must be
  regenerated to reflect the field renames (`Value__c`→`VS_Value__c`,
  `Value_Text__c`→`VS_Value_Text__c`) — see handoff note in `.claude/memory/handoffs.md`.
- **Post-deploy (manual, one-time):** none required for VS-02 itself — Custom Metadata records
  deploy with their values already set (no separate Setup data-entry step needed, unlike Custom
  Settings). A human should spot-check in Setup → Custom Metadata Types → VS Setting → Manage
  Records that all 6 records show their expected values after deploy, and specifically that
  `WalkInReservePct.VS_Value__c` = 25 resolves correctly in a saved `VS_Session__c` record's formula
  fields (this is the practical proof of the CONTRACT, beyond the structural XML check above).
  Recommend DHO/BA review of A-009's three tentative values (`BookingHorizonDays`,
  `NoShowThresholdCount`, `ReminderOffsetsHours`) before those numbers are relied on by any
  consuming Flow/Apex in a later ticket.
- **Manual-only (ongoing, not a deploy step):** if/when DHS wants to change a tunable in
  production, that is a Setup → Custom Metadata Types → VS Setting → Manage Records edit — no
  deploy needed (this is AC2, by design).

## Status

Set to **Ready for Review** in `02-build/jira-log.md` (status history appended: Backlog → In
Progress → Ready for Review). Recommend BA_ARCH_CONFIRM drift-check confirm: (1) the VS-01
CONTRACT (type/field/record names) holds unchanged through any later rework, (2) A-009's three
tentative values get DHO/BA ratification before launch, (3) M-1's same-pass deploy-order dependency
is carried into the devops DP-001 runbook.

## Deploy-defect fix (2026-07-12, devops dry-run bisection)

The first real dry-run against the DE org (AgentForceClaudeWorkFlow) FAILED and devops bisected it
to two metadata defects (see `02-build/deployments.md`/`runbook.md` and the devops
`agent-runs.log` line, 2026-07-12 19:20), one of which is this ticket's:

- **Defect (VS-02):** `force-app/main/default/objects/VS_Setting__mdt/VS_Setting__mdt.object-meta.xml`
  carried `<deploymentStatus>Deployed</deploymentStatus>` — an element the Metadata API rejects on a
  `__mdt` type ("Cannot specify: deploymentStatus for Custom Metadata Type"). **Removed** the element
  entirely; nothing else in the file changed (`<label>`, `<pluralLabel>`, `<visibility>`, and the
  764-char `<description>` — under the 1000-char object limit, untouched — are the only remaining
  elements, all valid on a `__mdt`).
- **Proactive check (same file):** verified no other CustomObject-only elements are present
  (`sharingModel`, `enableActivities`, `enableReports`, `enableHistory`, `actionOverrides`, or a
  Number/AutoNumber `nameField`) — none were there to begin with; this file now contains exactly the
  4 elements a `__mdt` validly supports.
- **Verification:** file re-checked for XML well-formedness (Node.js tag-stack parser, 0
  mismatched/unclosed tags). Draft only — **not deployed, no dry-run run by this agent**; devops
  re-runs the dry-run next.
- No field, record value, or the VS-01 CONTRACT (`VS_Value__c`/`WalkInReservePct`/25) was touched.

## Human Verdict (2026-07-11) — APPROVE-WITH-FIXES (Option A)

Human review verdict on this packet's first draft: APPROVE-WITH-FIXES. Finding **MIN-1** (Minor,
naming): the CMDT field lacked the mandatory `VS_` prefix (`Value__c`/`Value_Text__c` instead of
`VS_Value__c`/`VS_Value_Text__c`), a rules/20 deviation. Verdict: **Option A — fix the naming
properly now** rather than document it as an accepted exception, since neither VS-01 nor VS-02 is
deployed yet and the "contract" between them is still ours to change. Applied this run: rename
across both tickets' draft metadata (files, `<fullName>`s, all 6 records' `<field>` tags, and
VS-01's consuming formula), grep-verified end-to-end with zero dangling old references, XML
well-formedness re-checked (0 failures). Status remains **Ready for Review**; jira-log.md status
history carries the rename note. Devops flagged separately (handoffs.md) that DP-001's
manifest/deltas need regeneration for the renamed members.
