<!--
feature:         F-001 slot-booking-core
producing-agent: dev-mid
date:            2026-07-12
phase:           DEV_IN_PROGRESS
derives-from:    02-build/jira-log.md (VS-03 detailed spec), 02-build/sprint-plan.md,
                 01-discovery/technical-design.md §2.1/§2.2/§2.3 (capacity model, automation matrix)
                 REQ-010, REQ-011, REQ-012 / EP-01
                 D-007 (per-session capacity), D-018 (drive-day overrides holiday), D-008 (slot
                 granularity NOT set here — VS-06), D-025 (DE target org)
                 .claude/skills/flow-patterns (screen-flow structure, fault handling)
downstream:      VS-06 (slot generation reads VS_Session__c rows this flow creates), BA_ARCH_CONFIRM
                 drift-check, human deploy to the POC Developer Edition org (D-025)
-->

# VS-03 Review Packet — MO screen flow: define session capacity + drive-day

## Ticket summary

VS-03 (EP-01, Sprint 1, dev-mid, depends on VS-01/VS-02) builds a guided SCREEN FLOW so a Medical
Officer in Charge (persona P6, permission set `VS_MO_Facility_Admin` from VS-04) can create a
`VS_Session__c` — the atomic per-session capacity unit (D-007) — without developer help, including
marking a session a Drive Day (`VS_Is_Drive_Day__c`, D-018) so VS-06 slot generation later opens
that date even if `VS_Holiday__c` marks it a closure. Declarative-first was checked and satisfied:
this ticket needed no Apex — a screen flow with in-flow field validation and a fault path fully
covers the AC. No re-routing to dev-senior was needed.

## What was built

Path: `force-app/main/default/flows/VS_Session_Screen_DefineCapacity.flow-meta.xml` — one Screen
Flow (`processType` = `Flow`, `status` = `Active` per flow-patterns skill's "deploy Active" guidance
for this POC). No new object/field metadata; no validation rule was added on `VS_Session__c` (see
"Validation approach" below for the reasoning).

### Flow name

`VS_Session_Screen_DefineCapacity` — chosen to match the exact name already referenced in
`02-build/jira-log.md`'s VS-03 description and AC-1 ("when MO runs `VS_Session_Screen_DefineCapacity`")
and `02-build/sprint-plan.md`'s Sprint 1 table, so the built artifact and its ticket traceability stay
in lockstep. This departs slightly from the pure `VS_<Object>_<Trigger>_<Purpose>` record-triggered
naming convention in rules/20 (there is no single "trigger" for a user-launched screen flow), which
flow-patterns explicitly separates out as its own naming case ("Screen flow: guided staff tasks").

### Screens / logic (in flow order)

1. **`VS_Session_Details_Screen`** ("Define Session Capacity") — one screen collecting everything the
   MO needs to supply:
   - `VS_Instructions` (DisplayText) — plain-language purpose statement, clarifies slots are generated
     separately (VS-06), not here.
   - `VS_Facility_Select` (Dropdown, required) — backed by `recordChoiceSets` element
     `VS_Active_Facility_Choices`: `VS_Facility__c` filtered `VS_Is_Active__c = true`, sorted by Name,
     value = Id.
   - `VS_Service_Select` (Dropdown, required) — backed by `VS_Active_Service_Choices`: `VS_Service__c`
     filtered `VS_Is_Active__c = true`, sorted by Name, value = Id.
   - `VS_Session_Date_Input` (Date, required) — screen-level `validationRule`: must be `>= TODAY()`
     ("Session date cannot be in the past. Please choose today or a future date.").
   - `VS_Start_Time_Input` (DateTime, required).
   - `VS_End_Time_Input` (DateTime, required) — screen-level `validationRule` referencing
     `VS_Start_Time_Input` on the same screen: must be strictly after start ("End time must be after
     the start time. Please adjust the end time before continuing.").
   - `VS_Total_Capacity_Input` (Number, required) — screen-level `validationRule`: must be `> 0`
     ("Enter a total capacity greater than 0 so slots can be generated for this session.").
   - `VS_Drive_Day_Input` (Checkbox, optional, default unchecked) — "Mark as Drive Day (opens this
     session even if the date is marked a holiday closure)".
2. **`VS_Get_Selected_Facility`** (Get Records, `VS_Facility__c` where `Id = {!VS_Facility_Select}`,
   first-record-only) — fetches the chosen facility's Name + `VS_Helpline_Number__c` into the
   `VS_Selected_Facility` record variable, purely so the success/fault screens can show a human-
   readable facility name and helpline number (C7.3) rather than a raw Id. Carries its own
   `faultConnector` to the fault screen (flow-patterns: "EVERY element that can fail... gets a fault
   path" — Get Records included, not just the DML create).
3. **`VS_Create_Session`** (Create Records, `VS_Session__c`) — sets exactly:
   `VS_Facility__c`, `VS_Service__c`, `VS_Session_Date__c`, `VS_Start_Time__c`, `VS_End_Time__c`,
   `VS_Total_Capacity__c`, `VS_Is_Drive_Day__c`, and `VS_Status__c` = literal `"Open"` (explicit, not
   relying on the picklist's `<default>` flag — see "Formula-field boundary" below for why `VS_Status__c`
   was set explicitly while the two formula fields were deliberately left alone).
   `faultConnector` → `VS_Session_Fault_Screen`.
4. **`VS_Session_Success_Screen`** ("Session Created") — confirms facility name, date, start/end
   time, and total capacity; explicitly restates that slot generation happens separately (VS-06).
5. **`VS_Session_Fault_Screen`** ("Session Not Saved", reached from either fault connector) —
   plain-language message ("We could not save this session. Please check the details and try again in
   a few minutes.") + a facility helpline line using formula `VS_Helpline_Display`
   (`IF(ISBLANK(VS_Selected_Facility.VS_Helpline_Number__c), "your district helpline", ...)` so a
   blank helpline field never renders an empty string), satisfying C7.3's "helpline number in every
   actionable template" spirit for this internal-staff fault path. A second line surfaces
   `{!$Flow.FaultMessage}` labelled "Reference for support staff" — the MO is facility staff, not a
   citizen, so a technical fault string alongside (not instead of) the plain-language message is
   reasonable for troubleshooting; it is not shown as the primary message.

## Fault handling (flow-patterns compliance)

Both elements capable of failing — the `VS_Get_Selected_Facility` Get Records and the
`VS_Create_Session` Create Records — carry an explicit `faultConnector` to the same
`VS_Session_Fault_Screen`. Per this ticket's explicit instruction: **`VS_Error_Log__c` does not exist
on disk yet** (confirmed by searching `force-app/` — zero matches outside this new flow's own prose
description) — it is a later ticket's deliverable, not built in VS-01..VS-05/VS-04's scope so far.
Consequently the fault screen does **not** attempt to write to it; the flow-patterns "log to the
error object" instruction is honored by explicitly noting the deferral (in both the flow's own
`<description>` and here) rather than either inventing the object or silently skipping error
handling. **This is a residual gap to revisit once `VS_Error_Log__c` exists** — at that point this
flow's fault screen should gain a Create Records step (Facility, Flow name literal
`VS_Session_Screen_DefineCapacity`, fault message) ahead of showing the fault screen, matching the
pattern VS-19's design already anticipates for the notification seam.

## Input validation — explicit confirmation it is Flow-native, not Apex

Per this ticket's explicit instruction ("Use flow decision/validation, not Apex"), all three
functional checks are enforced as **screen-field `validationRule`s**, evaluated client-side before the
MO can even advance past the screen (better UX than a post-save validation-rule bounce):
1. `VS_Total_Capacity_Input > 0`.
2. `VS_End_Time_Input > VS_Start_Time_Input`.
3. `VS_Session_Date_Input >= TODAY()` (added beyond the ticket's two named examples — a reasonable,
   low-risk guardrail consistent with "define session capacity," logged as a judgment call, not a new
   requirement).

No Apex was written or considered necessary for any of this — genuinely simple field-level and
cross-field arithmetic comparisons, squarely inside the declarative boundary flow-patterns describes.

### Validation rule on `VS_Session__c`: NOT added, by choice

I deliberately did **not** add an object-level Validation Rule duplicating the three checks above.
Reasoning: the screen `validationRule`s already block a bad submission before it reaches the DML
step, giving a better UX (inline error, no round-trip); duplicating the same checks as a VR would be
redundant for this flow's only entry path. **Residual gap, logged as A-010 (see below):** if
`VS_Session__c` rows are ever created another way (e.g. a future Data Loader import, or VS-22's seed
script inserting sessions directly), these three invariants (positive capacity, end-after-start,
non-past date) would NOT be re-enforced, since they only live in this flow's screen. Flagging for
BA_ARCH_CONFIRM to decide whether a standing `VS_Session__c` validation rule should be added as a
safety net independent of entry channel — did not add one unilaterally since the ticket named flow
validation as the preferred mechanism and this flow is (for now) the only creation path in EP-01..08.

## Explicit confirmation: formula fields are NOT set by this flow

`VS_Create_Session`'s `inputAssignments` set exactly 8 fields: `VS_Facility__c`, `VS_Service__c`,
`VS_Session_Date__c`, `VS_Start_Time__c`, `VS_End_Time__c`, `VS_Total_Capacity__c`,
`VS_Is_Drive_Day__c`, `VS_Status__c`. **`VS_Walk_In_Reserve_Count__c` and `VS_Bookable_Capacity__c`
are NOT referenced anywhere in this flow** — they are formula fields (VS-01) that the platform
computes automatically from `VS_Total_Capacity__c` and `VS_Setting__mdt.WalkInReservePct.VS_Value__c`
(D-009) the instant the record is set/saved; a Flow assignment to a formula field is not even legal
metadata (Create Records simply has no `inputAssignments` entry for them, by construction, not by an
omission that needs double-checking). `VS_Walk_In_Used_Count__c` is also left unset — it has a
platform `defaultValue` of 0 (VS-05) and is owned by VS-09/VS-11's booking-service lock, never by
this ticket.

## Slot generation / granularity: confirmed out of scope

This flow creates exactly one `VS_Session__c` row and nothing else. It does **not** create any
`VS_Slot__c` rows (VS-06's `VS_SlotGenBatch` job, a separate scheduled/batch process, does that later
by reading `VS_Session__c.VS_Bookable_Capacity__c`) and does **not** set or reference slot granularity
anywhere (D-008 — granularity lives on `VS_Service__c.VS_Slot_Granularity_Mins__c` / `VS_Setting__mdt`,
not authored by the MO in this screen).

## Facility-scoping note (explicitly not built here)

The Facility dropdown (`VS_Active_Facility_Choices`) lists **every** active facility in the org, not
just the ones the running MO is assigned to. Per this ticket's explicit instruction, actual
facility-scoped record visibility is VS-20 (criteria-based sharing rules) + A-007 (manual public-group
membership, still Open) — neither is built or assumed here. In the interim, an MO's practical ability
to create sessions for a facility they don't belong to is bounded only by whatever sharing/visibility
VS-20 eventually enforces on `VS_Session__c`, not by anything in this flow.

## AC checklist (against VS-03's acceptance criteria in `02-build/jira-log.md`)

| # | Acceptance criterion | Status | Notes |
|---|---|---|---|
| 1 | Given a facility+service+date, when MO runs the flow, then a `VS_Session__c` is created with `VS_Total_Capacity__c` set and reserve/bookable formulas populated | **PASS (metadata drafted)** | `VS_Create_Session` sets `VS_Total_Capacity__c` directly; `VS_Walk_In_Reserve_Count__c`/`VS_Bookable_Capacity__c` populate automatically as platform formulas the instant the record saves — confirmed by construction (they are formula fields on `VS_Session__c`, VS-01), not independently deploy-verified in this environment. |
| 2 | Given the MO checks "Drive Day," when saved, then `VS_Is_Drive_Day__c` = true so slot generation will open this date even if `VS_Holiday__c` marks it closed (D-018) | **PASS (metadata drafted)** | `VS_Drive_Day_Input` maps 1:1 to `VS_Is_Drive_Day__c` in `VS_Create_Session`. The D-018 override behavior itself is VS-06's responsibility to honor at slot-generation time — this ticket only guarantees the flag is set correctly on the session row. |
| 3 | Given a flow element fails, when the screen runs, then a fault path shows a plain-language message + facility helpline (C7.3) and writes `VS_Error_Log__c` | **PARTIAL PASS** | Fault path + plain-language message + facility helpline: built and wired from both fault-capable elements. `VS_Error_Log__c` write: **NOT built** — the object does not exist on disk yet (confirmed via search); this is called out explicitly here and in the flow's own description as a deferred item, not silently dropped. Recommend BA_ARCH_CONFIRM treat this as a known, documented gap to close once `VS_Error_Log__c` ships (no ticket currently owns adding it retroactively to VS-03's flow — flagging for pm-planner/architect to decide whether that's a VS-03 follow-up or bundled into whichever ticket builds `VS_Error_Log__c`). |

**Overall: 2/3 ACs fully met, 1/3 partially met (documented, not silent) in the drafted metadata.**

## Traceability

| Artifact | REQ served |
|---|---|
| `VS_Session_Screen_DefineCapacity` | REQ-010 (staff define services/capacity per facility), REQ-011 (per-session/time-distributed capacity model), REQ-012 (add capacity on a closed day — the Drive Day flag; actual slot-generation override is VS-06) |

Upstream chain: REQ-010/011/012 (brief) → design §2.1/§2.2/§2.3 (capacity model) + EP-01 → VS-03
(this ticket) → this flow + review packet → downstream VS-06 (reads `VS_Session__c` rows this flow
creates, honors `VS_Is_Drive_Day__c`) → no direct TC-### yet (VS-03 is a screen flow; behavior will be
exercised by QA's Tier-2 functional pass once BA_ARCH_CONFIRM clears it — capacity/drive-day are not
themselves Tier-1 per rules/00, though they feed the Tier-1 slot-integrity chain downstream via VS-06).

## Assumptions logged

- **A-010** (new, this ticket): the Service picker is not scoped to only services the selected
  Facility actually offers (no `VS_Facility_Service__c` cross-check) — an MO could pair a facility with
  a service it doesn't provide. No VR was added to block this (see "Validation rule... NOT added"
  above). Owner: dev-mid/architect, decide at BA_ARCH_CONFIRM.
- **A-011** (new, this ticket): the flow omits an explicit `runInMode`, relying on the platform default
  (User Context). Cross-checked against `VS_MO_Facility_Admin.permissionset-meta.xml` (VS-04, already
  on disk) — it does grant Create+Edit on `VS_Session__c` and Read on `VS_Facility__c`/`VS_Service__c`,
  and every field this flow writes is editable there, so the assumption checks out **on the static
  metadata** but has not been proven in a live org. Owner: dev-mid/human, confirm at first dry-run.

Both entries appended to `.claude/memory/assumptions.md` this run.

## Manual / setup steps

- **Pre-deploy:** confirm `VS_Facility__c`, `VS_Service__c`, `VS_Session__c` (VS-01) and
  `VS_Setting__mdt`'s `WalkInReservePct` record (VS-02) already exist in the target org — the
  `VS_Bookable_Capacity__c`/`VS_Walk_In_Reserve_Count__c` formula fields this flow relies on (but
  never sets) depend on both being present, per the same cross-ticket contract VS-01/VS-02 already
  established. Also confirm `VS_MO_Facility_Admin` (VS-04) is deployed and assigned to the MO users who
  will run this flow — the flow assumes (A-011) that permission set already grants Create on
  `VS_Session__c`.
- **Post-deploy:** this screen flow is **not** automatically surfaced anywhere in the UI on deploy —
  a human must add it to a Lightning App Page (Utility Bar / tab) or expose it via a Global Quick
  Action / Home page component so MOs can actually launch it. This is a one-time manual Setup
  configuration step, out of this ticket's metadata scope (no FlexiPage was built).
- **Manual-only:** once `VS_Error_Log__c` exists (a future ticket), a human/architect decision is
  needed on whether to retrofit this flow's fault screen with an error-log Create Records step (see
  "Fault handling" above) — no automatic mechanism currently schedules that follow-up.
- If none of the above blocks the human, the honest answer for "must this deploy differently than
  prior tickets" is: no new deploy-order dependency beyond the existing VS-01/VS-02 formula contract
  already tracked by devops' DP-001 package.

## Deploy/verify status — HONEST

- **Metadata drafted, NOT deployed.** No org is connected in this environment.
- **`sf project deploy start --dry-run` was NOT run** — no CLI/org access available here. I did not
  run any Salesforce CLI command and am not claiming one succeeded.
- **What I did verify in this environment:** the flow's XML was parsed with Python's
  `xml.dom.minidom` (`m.parse(path)`) and completed with no errors — this confirms the file is
  syntactically well-formed XML. It does **not** confirm Metadata API schema validity (e.g. that every
  element/attribute combination I hand-authored, such as the `recordChoiceSets`/`recordLookups`
  structures, matches the exact Flow metadata schema for this API version) or a successful deploy —
  that can only be confirmed by an actual `sf project deploy start --dry-run` against the DE org
  (D-025), which a human must run next.
- **Depends on** `VS_Facility__c`/`VS_Service__c`/`VS_Session__c` (VS-01) and `VS_Setting__mdt`
  (VS-02) already existing in the target org (formula-field contract, not a new dependency this
  ticket introduces) — both are already tracked in devops' DP-001 deployment package.
- **Human next step:** run `sf project deploy start --dry-run` against the POC Developer Edition org
  (D-025) once `VS_Session__c`/`VS_Setting__mdt` are present, then manually launch the flow (via
  Setup → Flows → run, or an ad-hoc Lightning page) as a test user with only `VS_MO_Facility_Admin`
  assigned, and confirm: (a) the Facility/Service dropdowns populate from active records only, (b) all
  three validation messages fire correctly, (c) a successful create shows the confirmation screen with
  the correct formula-computed reserve/bookable values visible on the created `VS_Session__c` record in
  Setup, and (d) deliberately breaking the create (e.g., temporarily revoking Create on `VS_Session__c`
  for the test user) surfaces the fault screen with the facility helpline text, not a raw error page.

## Status

Set to **Ready for Review** in `02-build/jira-log.md` (status history appended: Backlog → In
Progress → Ready for Review). Recommend BA_ARCH_CONFIRM drift-check confirm: (1) `VS_Error_Log__c`
non-write is an accepted, documented gap (not a silent omission) until that object ships, (2) A-010's
facility/service pairing gap is either accepted as a POC-scope limitation or routed to a follow-up
validation-rule/flow-rework ticket, (3) the formula fields (`VS_Bookable_Capacity__c`,
`VS_Walk_In_Reserve_Count__c`) remain untouched by this and every future flow that creates
`VS_Session__c` rows.
