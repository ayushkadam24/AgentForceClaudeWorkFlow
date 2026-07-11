<!--
feature:         F-001 slot-booking-core
producing-agent: dev-mid
date:            2026-07-11
phase:           DEV_IN_PROGRESS
derives-from:    02-build/jira-log.md (VS-05 detailed spec), 02-build/sprint-plan.md,
                 01-discovery/technical-design.md §2.2/§2.3/§2.4 (data model)
                 REQ-008, REQ-009, REQ-014 / EP-02
                 D-008, D-019, D-020 (SUPERSEDES D-015) (.claude/memory/decisions.md)
downstream:      VS-06 (slot generation populates these fields), VS-09/VS-11 (booking service
                 reads/increments VS_Booked_Count__c under the VS_Session__c lock), BA_ARCH_CONFIRM
                 drift-check, human deploy to the POC Developer Edition org (D-025)
-->

# VS-05 Review Packet — VS_Slot__c object & fields

## Ticket summary

VS-05 (EP-02, Sprint 1, dev-mid, depends on VS-01) builds `VS_Slot__c` — the bookable 15-minute
window a citizen picks (D-008) and the Master-Detail child of `VS_Session__c` (which VS-01 already
built). Object/field metadata only — no Apex, no LWC, no slot-generation logic (VS-06), no
booking-increment logic (VS-09/VS-11). Declarative-first was checked and satisfied: this ticket is
pure schema, no automation was needed and none was found to require re-routing to dev-senior.

## The single most important correctness point of this ticket (D-020)

Per **D-019 (supersedes D-015)**, the §3.4 `SELECT ... FOR UPDATE` lock is taken **only** on the
parent `VS_Session__c` row — never on `VS_Slot__c`. Per **D-020**, `VS_Slot__c` still carries the
per-slot published ceiling REQ-008 requires (`VS_Capacity__c`/`VS_Booked_Count__c`), but those two
counters are read and incremented **only inside the session's lock**, by `VS_BookingService.book()`
(VS-09, not built here).

**Therefore `VS_Booked_Count__c` in this build is a plain, writable `Number` field (default 0). It
is deliberately NOT a Roll-Up Summary and NOT a formula.** A roll-up/formula cannot serialize under
a `FOR UPDATE` row lock — Salesforce recalculates roll-ups asynchronously/outside the transaction's
lock semantics, and a formula is read-only and cannot be incremented by DML at all. Either would
silently break the §3.4 no-overbooking guarantee the whole VS-09 crown-jewel design depends on. This
is called out explicitly in the field's own `<description>` (see metadata below) so the contract
survives independent of this packet.

## What was built

Path: `force-app/main/default/objects/VS_Slot__c/` — 1 object-meta.xml + 6 field-meta.xml files.
Every object and field carries a `<description>`; all API names carry the `VS_` prefix (rules/20).
No flow was built — the design does not specify a composite external ID on `VS_Slot__c` (unlike
`VS_Facility_Service__c` in VS-01), so no before-save-flow pattern was needed here.

### `VS_Slot__c` — 6 custom fields
OWD: `ControlledByParent` (Master-Detail to `VS_Session__c`, which itself is `ControlledByParent`
under `VS_Facility__c`'s Public Read Only — design §2.2, mandatory for MD children, matches design).
Retention (C4): bookings 3 yr.

| Field | Type | Purpose |
|---|---|---|
| `VS_Session__c` | Master-Detail → `VS_Session__c` | Session this slot was generated within; MD (not Lookup) so slots cascade with session lifecycle, inherit sharing, and are protected by the session's single booking lock (design §2.4, D-019/D-020) |
| `VS_Slot_Start__c` | DateTime, required | Start of the 15-min bookable window (D-008); populated by VS-06 |
| `VS_Slot_End__c` | DateTime, required | End of the 15-min bookable window; populated by VS-06 |
| `VS_Capacity__c` | Number(6,0), required | The enforceable per-slot published ceiling REQ-008 demands; populated by VS-06's even-distribution algorithm (D-023/A-005) such that `sum(VS_Capacity__c)` across a session's slots == `VS_Session__c.VS_Bookable_Capacity__c` |
| `VS_Booked_Count__c` | **Number(6,0), default 0, required — plain writable field, NOT roll-up, NOT formula (D-020, see above)** | Running count of confirmed bookings against `VS_Capacity__c`; read/incremented only inside the `VS_Session__c` FOR UPDATE lock by VS-09/VS-11 |
| `VS_Status__c` | Picklist (Open/Full/Closed/Cancelled; default Open), required | Slot lifecycle; flipped by VS-09/VS-11 inside the session lock — no automation built here |

Name field: AutoNumber `SLT-{00000}` (slots have no natural human name, matching the `VS_Session__c`/
`VS_Facility_Service__c` convention already on disk).

**Total: 1 object, 6 custom fields, 0 flows.**

## Master-Detail relationship confirmation

`VS_Slot__c.VS_Session__c` is `MasterDetail` → `VS_Session__c`, matching design §2.4 exactly
("Session → Slot: Master-Detail ... slots are generated artifacts of a session; cascade
delete/reparent on session cancel; inherit sharing; the session is also the booking lock that
guards its slots' counters"). Confirmed against the actual `VS_Session__c` object on disk
(`force-app/main/default/objects/VS_Session__c/VS_Session__c.object-meta.xml`, sharing model
`ControlledByParent`, deployed by VS-01) — the parent object exists and the relationship API name
(`VS_Session__c` lookup field, relationship name `VS_Slots`) resolves to it. `reparentableMasterDetail`
= false and `writeRequiresMasterRead` = false, matching the pattern used for
`VS_Facility_Service__c.VS_Facility__c` and `VS_Session__c.VS_Facility__c` already on disk.

Cascade-on-delete: because this is Master-Detail (not Lookup), deleting a `VS_Session__c` cascades
its child `VS_Slot__c` rows automatically (platform-enforced) — no orphan slots, satisfying AC2
without any custom logic.

## AC checklist (against VS-05's acceptance criteria in `02-build/jira-log.md`)

| # | Acceptance criterion | Status | Notes |
|---|---|---|---|
| 1 | Given `VS_Slot__c` deploys, when inspected, then it has Master-Detail to `VS_Session__c`, `VS_Slot_Start__c`/`VS_Slot_End__c`, `VS_Capacity__c`, `VS_Booked_Count__c`, `VS_Status__c` (Open/Full/Closed/Cancelled), each described | **PASS (metadata drafted)** | All 6 fields built exactly as specified, every one with a `<description>` covering purpose + D-020 constraint where relevant. NOT yet deployed — see honesty note below. |
| 2 | Given a session is deleted, when cascading, then its slots cascade per Master-Detail (no orphan slots) | **PASS (structural, by construction)** | Master-Detail is a platform-enforced cascade; no additional logic required or built. Not yet verified in a live org (no deploy run in this environment). |

**Overall: 2/2 ACs met in the drafted metadata.**

## Traceability

| Object | REQ served |
|---|---|
| `VS_Slot__c` | REQ-008 (per-slot published capacity ceiling, §3.4), REQ-009 (bookable window generated within session/facility operating hours), REQ-014 (booking horizon boundary applies at slot level) |

Upstream chain: REQ-008/009/014 (brief) → design §2.2/§2.3/§2.4 (data model) + EP-02 → VS-05 (this
ticket) → this metadata + review packet → downstream VS-06 (populates fields), VS-09/VS-11 (reads/
increments `VS_Booked_Count__c` under the session lock) → no direct TC-### yet (VS-05 is
metadata-only; behavior is exercised by VS-06/VS-09/VS-11's test classes and QA Tier-1 concurrency
tests downstream).

## Assumptions / open items logged

- **No new assumption ID was logged.** The one genuinely load-bearing judgment call in this ticket —
  that `VS_Booked_Count__c` must be a plain writable Number, never a roll-up/formula — is not a new
  assumption; it is a direct, unambiguous restatement of the already-human-signed D-020, so no new
  `A-###` entry was added to `.claude/memory/assumptions.md`.
- **No external ID was invented on `VS_Slot__c`.** Design §2.3's `VS_Slot__c` field list does not
  specify a `VS_External_Id__c`/composite-uniqueness requirement (unlike `VS_Facility_Service__c` in
  VS-01, which needed one for its facility+service composite key AC). Per this ticket's explicit
  instruction not to invent one if the design doesn't require it, none was built — and therefore no
  before-save flow was needed either.
- No Page Layouts, List Views, or Compact Layouts were built — VS-05's Issue Type is explicitly "pure
  object/field metadata." Salesforce auto-generates a default layout on deploy; the human can adjust
  via Setup once deployed to the DE org.
- D-025 (Developer Edition target, not scratch org) was honored: Master-Detail and standard Number/
  DateTime/Picklist fields are all standard DE-compatible features, no scratch-only dependencies.
- **Hard deploy-order dependency (restating design intent, not a new decision):** `VS_Slot__c` is a
  Master-Detail child of `VS_Session__c` (VS-01). `VS_Session__c` MUST already exist in the target
  org before `VS_Slot__c` can deploy (Master-Detail parent must exist first) — flag for devops to
  sequence `VS_Slot__c` into a deployment package **after** DP-001 (VS-01+VS-02), per the existing
  deployment-package discipline established in `02-build/deployments.md`/`02-build/runbook.md`.

## Manual / setup steps

- **Pre-deploy:** confirm `VS_Session__c` (VS-01/DP-001) is already deployed to the target org — this
  is a hard Master-Detail parent-must-exist-first dependency, not optional sequencing.
- **Post-deploy:** none required by this ticket alone (no page layouts, no permission changes, no
  sharing rules — those are VS-04/VS-20 scope). Once deployed, a human should spot-check in Setup
  that the default page layout shows all 6 custom fields.
- **Manual-only:** none. (No CLI/manual step is needed to make this metadata functional beyond a
  standard deploy; VS-06 will populate slot rows later and VS-09 will read/write the counters — both
  out of scope for this ticket.)

## Deploy/verify status — HONEST

- **Metadata drafted, NOT deployed.** No org is connected in this environment.
- **`sf project deploy start --dry-run` was NOT run** — no CLI/org access available here. I did not
  run any Salesforce CLI command and am not claiming one succeeded.
- **What I did verify in this environment:** all 7 XML files (1 object-meta.xml + 6 field-meta.xml)
  were checked for well-formedness by parsing each with PowerShell's `[xml]` cast (`[xml](Get-Content
  -Raw <file>) | Out-Null`) — all 7 parsed successfully with 0 failures. This confirms the files are
  syntactically valid XML; it does NOT confirm Metadata API schema validity or a successful deploy.
- **Depends on VS-01's `VS_Session__c` being deployed first** (Master-Detail parent-must-exist
  constraint) — flagged above for devops to sequence into a deployment package after DP-001.
- **Human next step:** deploy `VS_Slot__c` (this metadata) to the POC Developer Edition org (D-025)
  via `sf project deploy start --dry-run` after confirming `VS_Session__c` is present, then a real
  deploy, then manually create one `VS_Session__c` + one `VS_Slot__c` child record and confirm (a)
  the slot deletes when its session is deleted (AC2) and (b) `VS_Booked_Count__c` accepts a direct
  field update (i.e. behaves as a plain writable Number, not a read-only roll-up/formula).

## Status

Set to **Ready for Review** in `02-build/jira-log.md` (status history appended: Backlog → In
Progress → Ready for Review). Recommend BA_ARCH_CONFIRM drift-check confirm: (1) `VS_Booked_Count__c`
stayed a plain writable Number field through to VS-09's implementation (D-020 is the single most
important correctness point of this whole ticket — worth a second look at BA_ARCH_CONFIRM), (2) the
Master-Detail-parent-must-exist deploy-order dependency on VS-01 is sequenced correctly by devops,
(3) no external ID/composite key was needed on `VS_Slot__c` (confirmed against design §2.3, which
lists none).
