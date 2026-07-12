<!--
feature:         F-001 slot-booking-core
producing-agent: dev-senior
date:            2026-07-12
phase:           DEV_IN_PROGRESS
derives-from:    02-build/jira-log.md (VS-06 detailed spec), 02-build/sprint-plan.md,
                 01-discovery/technical-design.md §2.1/§2.3/§4.6/§5 (automation matrix),
                 REQ-009, REQ-012, REQ-013, REQ-014, REQ-062 / EP-02
                 D-008, D-018, D-023, A-005 (.claude/memory/decisions.md, assumptions.md)
                 .claude/skills/sf-apex-patterns (+ references/apex-best-practices.md)
downstream:      VS-09 (VS_BookingService.book reads/increments the VS_Slot__c counters this batch
                 seeds), VS-16 (citizen picks a generated slot), BA_ARCH_CONFIRM drift-check
                 (D-023 single-method radar), human deploy + test-run on DE org (D-025)
-->

# VS-06 Review Packet — VS_SlotGenBatch: generate slots from sessions

## Bucket A fixes applied (post-review, 2026-07-12, dev-senior)

Human-approved Bucket A fixes applied. **The D-023 single `distributeCapacity()` distribution method
and all generation logic are UNCHANGED** — MINOR-1/2/3 are NEW TESTS only, NIT-1 is a comment fix.
NOT compiled/deployed/tested in this run (deploy happens next, devops). Test count 9 → **12**.

- **MINOR-1 — configurable granularity + non-multiple window now exercised.** New
  `testConfigurableGranularity_nonMultipleWindow_dropsTrailingPartial`: a per-service
  `VS_Slot_Granularity_Mins__c = 30` (NON-15) over a 09:00–13:10 (250-min) window → asserts
  `floor(250/30) = 8` slots, each slot 30 min, the trailing 10-min partial DROPPED (last slot ends
  13:00 < 13:10 session end), and `sum(slot cap) == bookable` exactly. Proves D-008 "configurable, not
  hardcoded" — previously every test used the 15 default.
- **MINOR-2 — capacity < slotCount edge covered.** New
  `testCapacityLessThanSlotCount_trailingSlotsGetZeroCapacity`: total 7 (→ bookable 5) over 8 slots →
  asserts the first 5 slots get capacity 1, the trailing 3 get capacity 0, and the sum still equals 5
  exactly. **Emit behavior UNCHANGED.** Test comment flags that whether 0-capacity Open slots SHOULD
  be emitted is a **BA_ARCH_CONFIRM product decision**, not a code defect (see below).
- **MINOR-3 — in-batch degenerate-window skip branch covered.** New
  `testGenerateForSessions_degenerateWindow_skippedNotThrown`: an `end == start` session routed
  THROUGH `generateForSessions` (not `buildSlots` directly) → asserts it is silently SKIPPED (0 slots,
  NO exception at the batch level), covering the previously-unexercised `continue` branch (contrast:
  `buildSlots()` throws for the same input, per `testBuildSlots_invalidWindow_throws`).
- **NIT-1 — ApexDoc SOQL count corrected.** `VS_SlotGenerationService.generateForSessions` ApexDoc
  changed from "4 SOQL + 1 DML" to **"3 SOQL + 1 DML"** (per-service granularity + holidays + config
  default = 3 SOQL; single slot insert = 1 DML). The 250-session test's `SOQL ≤ 4` assertion keeps its
  headroom (actual = 3) and is unchanged.

### PRODUCT FLAG for BA_ARCH_CONFIRM (from MINOR-2)

When a session's bookable capacity is LESS than its slot count, the current code emits the trailing
slots with `VS_Capacity__c = 0` (still `Status = Open`). The sum invariant holds. **Whether 0-capacity
Open slots should be emitted at all — vs. suppressed, or the slot window widened — is a product/UX
decision for BA_ARCH_CONFIRM, not a build defect.** This ticket only COVERS the current behavior and
flags it; it does not change it.

## Ticket summary

VS-06 (EP-02, Sprint 1, **dev-senior**, L, depends VS-01/02/05) builds the slot-generation engine:
a Batch Apex job that reads each eligible `VS_Session__c` and generates its `VS_Slot__c` rows,
distributing the session's online-bookable capacity evenly across configurable-granularity slots,
honoring holidays and the drive-day override, and staying bulk-safe at 250+ sessions. This is the
feeder for the §3.4 ceiling: VS-09's booking service enforces `VS_Slot__c.VS_Capacity__c`, and this
batch is what puts a correct, exactly-summing capacity on every slot.

## Files delivered (all under `force-app/main/default/classes/`)

| File | Role |
|---|---|
| `VS_SlotGenBatch.cls` (+ `-meta.xml`) | Batch orchestrator: selects eligible sessions, delegates construction, tracks run metrics (Stateful). |
| `VS_SlotGenerationService.cls` (+ `-meta.xml`) | All generation logic — the bulkified builder + **the single distribution method** + holiday/granularity/config resolution. |
| `VS_SlotGenException.cls` (+ `-meta.xml`) | Separate top-level domain exception with coded messages. |
| `VS_SlotGenBatchTest.cls` (+ `-meta.xml`) | 9 test methods; @TestSetup; no SeeAllData. |

apiVersion 67.0 (matches `sfdx-project.json` `sourceApiVersion`). All 4 `-meta.xml` verified
well-formed via `python xml.dom.minidom` (0 failures). **Apex itself was NOT compiled** — see the
honesty section.

## Class & method structure

```
VS_SlotGenBatch  implements Database.Batchable<SObject>, Database.Stateful
  ctor()                          -> resolves booking horizon window from VS_Setting__mdt
  start(bc)   : QueryLocator      -> Open + in-horizon + not-yet-slotted VS_Session__c (WITH USER_MODE)
  execute(bc, List<VS_Session__c>)-> delegates to VS_SlotGenerationService.generateForSessions(scope)
  finish(bc)                      -> logs sessionsProcessed / slotsCreated
  getBookingHorizonDays()         -> VS_Setting__mdt.BookingHorizonDays.VS_Value__c (fallback 14)

VS_SlotGenerationService  (with sharing)
  generateForSessions(List<VS_Session__c>) : Integer   -- bulk orchestration, 3 SOQL + 1 DML total
  buildSlots(VS_Session__c, Integer granularityMins) : List<VS_Slot__c>  -- strict, unit-testable, throws
  >>> distributeCapacity(Integer bookableCapacity, Integer slotCount) : List<Integer>  <<< D-023 SEAM
  computeSlotCount(VS_Session__c, Integer) : Integer   -- single source of truth for the count math
  getConfiguredDefaultGranularity() : Integer          -- VS_Setting__mdt.DefaultSlotGranularityMins
  holidayKey(Id, Date) : String

VS_SlotGenException  extends Exception   -- 'INVALID_GRANULARITY' | 'INVALID_WINDOW'
```

## The D-023 single distribution method (drift-check radar — name it here)

> **The even slot-capacity distribution lives in exactly ONE private method:
> `VS_SlotGenerationService.distributeCapacity(Integer bookableCapacity, Integer slotCount)`.**

Nothing else computes a per-slot capacity. `buildSlots` calls it once and simply maps the returned
`List<Integer>` onto the slot rows. Swapping the POC's even split for a later weighted/front-loaded
scheme (A-005 owner: MO Shinde/Pawar via DHO) is a change to that method's body only — no caller,
no schema, no test structure changes. The method's ApexDoc says so explicitly, and the `buildSlots`
loop deliberately contains **no** capacity arithmetic of its own. **BA_ARCH_CONFIRM should confirm
this stayed isolated** (D-023 radar item).

Algorithm: `base = bookable / slotCount`, `remainder = mod(bookable, slotCount)`; the first
`remainder` (earliest) slots get `base + 1`, the rest get `base`. This makes
`sum(perSlot) == bookableCapacity` **exactly** and puts the remainder on the earliest slots (A-005).

## The even-distribution invariant + its assertion

Invariant: **`sum(VS_Slot__c.VS_Capacity__c) across a session == VS_Session__c.VS_Bookable_Capacity__c`,
exactly.** `VS_Bookable_Capacity__c` is the formula `Total − Walk-In-Reserve` (design §2.1) — the
walk-in reserve stays a session-level counter and is deliberately NOT distributed into slots (A-005).

Asserted in `testEvenDistribution_sumsToBookableExactly`: a 09:00–13:00 session, Total 80 → reserve
`CEILING(80×25/100)=20` → bookable **60**, 240 min / 15 = **16 slots**. The test asserts (a)
`sum(capacity) == 60`, (b) `60 mod 16 = 12` remainder lands on the **12 earliest** slots (4 each, the
rest 3), (c) every slot `VS_Booked_Count__c == 0` and `VS_Status__c == 'Open'`, (d) contiguous 15-min
windows from session start to session end. `testBulk_...` re-checks the sum invariant under 250
sessions, and `testDriveDayOverridesHoliday_...` re-checks it (Total 40 → bookable 30, sum 30).

## Bulkification — how SOQL/DML-in-loops is avoided (REQ-062)

`generateForSessions` issues a **constant** number of statements regardless of scope size:

1. One in-memory pass collects `serviceIds` / `facilityIds` / `sessionDates` (no SOQL).
2. **1 SOQL** — per-service granularity into a `Map<Id,Integer>`.
3. **1 SOQL** — holidays for those facilities+dates into a `Set<String>` of `facilityId|date` keys.
4. **1 SOQL (Custom Metadata)** — default granularity fallback.
5. One in-memory loop builds all slot rows (map/set lookups only — **no SOQL/DML inside**).
6. **1 DML** — a single `insert as user` of the whole `List<VS_Slot__c>`.

`testBulk_250Sessions_isGovernorSafe` proves it: it captures `Limits.getQueries()` /
`Limits.getDmlStatements()` around a direct 250-session service call and asserts **queries ≤ 4** and
**DML == 1** — i.e. flat, not per-session. It also asserts 250×8 = 2000 slots were created and the
sum invariant still holds. The batch's `start()` default chunk is 200; the direct-call test proves a
single 250-row execute is safe, and the horizon/holiday/idempotency tests exercise the batch
end-to-end via `Database.executeBatch`.

## Holiday / drive-day handling (D-018)

Resolved entirely in-memory from the one holidays SOQL. For each session:
`isHoliday = holidayKeys.contains(facilityId|sessionDate)`.
- **Normal session on a holiday date** → skipped (no slots). Asserted:
  `testHolidaySkip_generatesNoSlots`.
- **`VS_Is_Drive_Day__c == true` session on a holiday date** → slots ARE generated (the drive
  overrides the closure for that session only). Asserted:
  `testDriveDayOverridesHoliday_generatesSlots`.
Holiday scoping is per facility+date (matches `VS_Holiday__c` being per-facility), so a drive at one
facility never opens another facility's holiday.

## Granularity & horizon — configurable, not hardcoded (D-008 / REQ-013)

- Granularity: `VS_Service__c.VS_Slot_Granularity_Mins__c` (per-service, default 15) with fallback to
  `VS_Setting__mdt.DefaultSlotGranularityMins.VS_Value__c`. **No literal `15` drives generation** —
  the only `15` in the service is a last-resort `DEFAULT_GRANULARITY_FALLBACK` used solely if BOTH the
  service value and the config record are absent (guards a divide-by-zero), documented as such.
- Horizon: `VS_Setting__mdt.BookingHorizonDays.VS_Value__c` (14) bounds `start()`; beyond it, no
  slots. Asserted: `testBookingHorizon_excludesBeyondHorizon`.

## Security & standards (rules/20)

- `with sharing` on both non-exception classes.
- SOQL on user data (`VS_Service__c`, `VS_Holiday__c`) uses `WITH USER_MODE`; the `start()` locator
  uses `WITH USER_MODE`; the slot insert uses `insert as user` — CRUD/FLS enforced, not assumed.
  (Custom Metadata queries have no FLS surface and are intentionally left plain — noted in code.)
- Custom exception `VS_SlotGenException` with **coded** messages; **no empty catch blocks anywhere**
  (the only catches are in tests, asserting the coded message). No hardcoded IDs; tunables from
  Custom Metadata.
- Idempotent: `start()` excludes already-slotted sessions via
  `Id NOT IN (SELECT VS_Session__c FROM VS_Slot__c)`, so a re-run never double-generates
  (`testReRun_isIdempotent`).
- One DML per object per context; Maps for all lookups; DE-compatible (Batch Apex, USER_MODE DML,
  Custom Metadata SOQL are all standard DE features — D-025).

## Test list & what each asserts

| Test method | Asserts | AC |
|---|---|---|
| `testEvenDistribution_sumsToBookableExactly` | 16 slots, sum==60, remainder→earliest (12×4, 4×3), booked=0, status Open, contiguous 15-min windows | AC1 |
| `testHolidaySkip_generatesNoSlots` | normal session on a holiday date → 0 slots | AC2 |
| `testDriveDayOverridesHoliday_generatesSlots` | drive-day session on a holiday date → 8 slots, sum==30 | AC3 |
| `testBookingHorizon_excludesBeyondHorizon` | today+30 session → 0 slots; in-horizon still generates | AC4 |
| `testReRun_isIdempotent` | second batch run does not double-generate (stays 16) | robustness/REQ-062 |
| `testBuildSlots_invalidGranularity_throws` | `buildSlots(ses,0)` throws `VS_SlotGenException('INVALID_GRANULARITY')` | NEGATIVE |
| `testBuildSlots_invalidWindow_throws` | degenerate session (end==start) throws `VS_SlotGenException('INVALID_WINDOW')` | NEGATIVE |
| `testBulk_250Sessions_isGovernorSafe` | 250 sessions → 2000 slots, **SOQL≤4, DML==1**, sum invariant holds | AC5 (REQ-062) |
| `testGenerateForSessions_emptyInput_returnsZero` | empty and null input → 0, no DML | guard |

### Expected coverage — could NOT be measured (no org)

I could not run `sf apex run test --code-coverage` (no connected org). **Expected** coverage of the
three production classes is high — every branch of `VS_SlotGenBatch` (start/execute/finish/ctor +
horizon fallback), `VS_SlotGenerationService` (generate, buildSlots, distributeCapacity via both the
even and remainder paths, computeSlotCount valid+invalid, granularity per-service and fallback,
holiday skip and drive-day override, empty guard), and both `VS_SlotGenException` message paths is
exercised by the 9 tests. I estimate **≥90%** on the new classes, comfortably above the ≥85% bar —
but this is an ESTIMATE, not a measured number, because no test run occurred here.

## AC pass/fail (against VS-06 spec in `02-build/jira-log.md`)

| # | Acceptance criterion | Status (drafted, not run) |
|---|---|---|
| 1 | 60 bookable + 15-min → slots summing to exactly 60 (even, remainder to earliest) | **PASS (asserted)** |
| 2 | Holiday date, no drive-day session → no slots for that date/facility | **PASS (asserted)** |
| 3 | Holiday date with a drive-day session → slots generated for that session only | **PASS (asserted)** |
| 4 | `BookingHorizonDays`=14 → no slots beyond horizon | **PASS (asserted)** |
| 5 | 250+ sessions → no SOQL/DML in loops, no governor errors | **PASS (asserted: SOQL≤4, DML==1)** |

All 5 ACs are met in the drafted-and-asserted code; none is *verified in a live org* (nothing was
deployed or run). See honesty section.

## Traceability

REQ-009/012/013/014/062 (brief) → design §2.1/§2.3/§4.6/§5 automation matrix + EP-02 → **VS-06**
(this ticket) → `VS_SlotGenBatch`/`VS_SlotGenerationService`/`VS_SlotGenException` + this packet →
`VS_SlotGenBatchTest` (9 TCs above) → QA Tier-1/2 downstream. Decisions honored: D-008 (configurable
granularity), D-018 (drive-day override), D-023/A-005 (single-method even distribution). Depends on
VS-01 (`VS_Session__c`/`VS_Service__c`/`VS_Holiday__c`/`VS_Facility__c`), VS-02 (`VS_Setting__mdt`
records), VS-05 (`VS_Slot__c`) — all on disk.

## Assumptions logged

- **A-015** (new, `.claude/memory/assumptions.md`): `start()` also excludes **past-dated** sessions
  (`VS_Session_Date__c >= today`), not just beyond-horizon ones. No AC/decision mandates the
  past-date exclusion — it is a dev-senior default (generating bookable slots for a past date is
  pointless). Same-day sessions ARE included. Owner: architect/BA to confirm at BA_ARCH_CONFIRM.
- A-005/D-023 (existing) are the governing distribution decisions — no new decision was made; the
  single-method seam is exactly what D-023 requires.

## What the human reviewer should scrutinize

1. **Compile it.** This Apex was NOT compiled here (no org). First action on the DE org:
   `sf project deploy start --dry-run` for the four classes, then `sf apex run test --code-coverage`.
2. **Batchable execute typing.** `execute` takes `List<VS_Session__c>` while the class implements
   `Database.Batchable<SObject>` — the standard accepted pattern, but confirm it compiles on your API
   (it should on 67.0).
3. **D-023 seam (drift radar):** confirm `distributeCapacity` is still the only place capacity is
   split, before VS-16/weighted-distribution work begins.
4. **A-015 past-date exclusion:** is skipping strictly-past-dated sessions the intended behavior?
5. **`WITH USER_MODE` + semi-join in `start()`:** the running (scheduling) user must have read on
   `VS_Session__c`/`VS_Slot__c`; whoever runs the batch must have **create on `VS_Slot__c`** and edit
   on its fields for `insert as user` to succeed (see Manual/setup steps).

## Manual / setup steps

- **Pre-deploy:** VS-01 (`VS_Session__c`, `VS_Service__c`, `VS_Holiday__c`, `VS_Facility__c`), VS-02
  (`VS_Setting__mdt` type + `DefaultSlotGranularityMins`/`BookingHorizonDays`/`WalkInReservePct`
  records), and VS-05 (`VS_Slot__c`) MUST already be deployed to the DE org — this batch reads all of
  them and the `VS_Bookable_Capacity__c` formula depends on `WalkInReservePct`. Deploy VS-06 after
  DP-001 (and the VS-05 package) per `02-build/deployments.md`.
- **Post-deploy:** the identity that RUNS the batch (scheduled job owner or the admin invoking
  `Database.executeBatch`) needs **Create on `VS_Slot__c`** + edit on `VS_Slot_Start__c`/`_End__c`/
  `VS_Capacity__c`/`VS_Booked_Count__c`/`VS_Status__c`, and Read on `VS_Session__c`/`VS_Service__c`/
  `VS_Holiday__c` — because generation runs `WITH USER_MODE`/`insert as user`. The current VS-04
  permission sets grant facility staff read on these; a batch normally runs as an admin/integration
  user — verify that runner has slot Create before scheduling.
- **Run (POC):** `Database.executeBatch(new VS_SlotGenBatch(), 200);` (Anonymous Apex), or schedule
  via a later scheduler ticket. Re-running is safe (idempotent).
- **Manual-only:** none required to make the code functional beyond a standard deploy + a runner with
  the permissions above.

## Deploy / test status — HONEST

- **Apex drafted; NOT deployed.** No org is connected in this environment.
- **`sf project deploy start --dry-run` NOT run.** **`sf apex run test` NOT run.** I ran no
  Salesforce CLI command and claim no green build. Coverage numbers above are ESTIMATES, not measured.
- **What I verified here:** the four `-meta.xml` files parse as well-formed XML (`python
  xml.dom.minidom`, 0 failures). This does NOT confirm Apex compilation, Metadata API validity, or a
  passing test run.
- **Human next step:** on the DE org **AgentForceClaudeWorkFlow** (D-025), after VS-01/02/05 are
  deployed, run `sf project deploy start --dry-run` then `sf apex run test --code-coverage` for the
  four classes and record the real result here.

## Status

Set to **Ready for Review** in `02-build/jira-log.md` (Backlog → In Progress → Ready for Review).
Recommend BA_ARCH_CONFIRM confirm: (1) D-023 distribution stayed in the single `distributeCapacity`
method; (2) A-015 past-date exclusion is acceptable; (3) the sum-exactly invariant is preserved into
VS-09's enforcement (A-005's equivalence between per-slot ceilings and the session bookable ceiling).

---

## BLOCKER C fix — test FLS/USER_MODE context (dev-senior, 2026-07-12, fix-forward)

**Status of this fix: correct-by-construction, NOT deployed/tested by dev-senior (no deploy from this
environment). devops re-runs Phase 2 real deploy + RunLocalTests to capture the real numbers.**

### The failure being fixed (from deployments.md Phase 2, Deploy `0AfgL00000QxljtSAB`)
Metadata deployed 100% clean (86/86) but RunLocalTests returned 24 run / **23 FAILED** / 1 passed,
identical in dry-run and real deploy (genuine, not a checkOnly artifact). `VS_SlotGenBatchTest`'s
failures are the same root cause as VS-09: the tests ran with **no `System.runAs` / no permset**, i.e.
as the deploying System Administrator, who has **no FLS on the freshly MDAPI-deployed `VS_` fields**.
`VS_SlotGenBatch.start()` queries `WITH USER_MODE` and `VS_SlotGenerationService` does `insert as user`
(rules/20), so every USER_MODE op failed **before** any distribution/holiday/horizon logic ran — the
even-distribution, remainder, and 250-session governor asserts never executed.

### What I changed in `VS_SlotGenBatchTest` (code UNCHANGED — test-only)
1. `@TestSetup` now also creates a `User` on **'Standard User'** and assigns
   **`VS_Booking_Engine_Test_Context`**. User+assignment DML is isolated in
   `System.runAs(new User(Id=UserInfo.getUserId()))` to avoid `MIXED_DML_OPERATION` with the
   Facility/Service/Session/Holiday inserts. It lives in `@TestSetup` specifically so this setup DML is
   **outside** the 250-session governor measurement.
2. Each test that runs the batch or `generateForSessions` now wraps the `Database.executeBatch(...)` +
   `Test.stopTest()` (or the direct service call) in `System.runAs(slotGenUser())`, so the batch
   executes under a realistic FLS user. `buildSlots()` tests and the empty/null-input test keep NO
   `runAs` (they touch no USER_MODE DML/SOQL) — documented inline.

### Governor-assertion integrity (SOQL<=4 / DML==1) — preserved exactly
`testBulk_250Sessions_isGovernorSafe` resolves the runAs user **before** the measured window and
captures `Limits.getQueries()/getDmlStatements()` **immediately around only** the
`generateForSessions(scope)` call, inside the `runAs` block. The User + `PermissionSetAssignment` setup
(in `@TestSetup`) and the `slotGenUser()` query and the `runAs` entry are all outside the
`qBefore..qAfter` / `dBefore..dAfter` deltas, so none of them are counted against the batch's budget.
The SOQL<=4 / DML==1 intent is unchanged; it now actually EXECUTES instead of dying at FLS setup.

### Permission set assigned and WHY — and the GENUINE GAP found
Slot-gen USER_MODE surface: `start()` reads `VS_Session__c` (+ the `VS_Bookable_Capacity__c` /
`VS_Is_Drive_Day__c` FLS + the `VS_Slot__c` NOT-IN subquery); `generateForSessions()` reads
`VS_Service__c` / `VS_Holiday__c` and does `insert as user` on `VS_Slot__c`. All `VS_Slot__c` fields the
generator writes are **required or Master-Detail → always accessible**, so the only real need is **Create
on `VS_Slot__c`** plus the Session/Service/Holiday reads.

**GENUINE FINDING (routed, NOT papered over): no existing permission set grants `VS_Slot__c` Create.**
All 5 role permsets are `VS_Slot__c` **read-only** (slots are system-generated, so human roles rightly
cannot create them). `VS_MO_Facility_Admin` — the packet's suggested candidate — grants the Session/
Service/Holiday reads but **not** slot Create, so it alone cannot cover this path. **This is a real
runtime consideration, not just a test gap:** whoever runs/schedules `VS_SlotGenBatch` under USER_MODE
must have `VS_Slot__c` Create — no current role does. (This packet's "Manual/setup" already flagged that
the batch runner needs slot Create; BLOCKER C makes it concrete.)

**Resolution:** the dedicated `VS_Booking_Engine_Test_Context` permset (added under VS-09's fix, shared
by both engine test classes) grants `VS_Slot__c` C/R + the Session/Service/Holiday reads the generator
needs. It is a TEST/CI harness assigned only to the test user — a stand-in for a real slot-gen
automation grant, documented here, not a role for real users. No FLS on any required/MD field (deploy-
safe).

### Reviewer scrutiny points (BLOCKER C)
- Confirm `VS_Booking_Engine_Test_Context` is in the Phase 2 manifest before the re-run (else the
  `PermissionSetAssignment` query fails at test time).
- Decide the real owner of the slot-gen automation's `VS_Slot__c` Create grant (a scheduler/integration
  permset), since no human role should have it.
- Expectation for the next run: with FLS fixed, the even-distribution / remainder / holiday-skip /
  drive-day / horizon / idempotency / 250-session governor asserts finally execute. Fixing FLS **may
  unmask previously-hidden logic failures** (asserts that never ran) — treat any as newly-revealed, NOT
  a regression from this change.

## Manual / setup steps (BLOCKER C addendum)

- **Pre-deploy (devops):** add `VS_Booking_Engine_Test_Context` (PermissionSet) to
  `manifest/deltas/SPRINT-1-phase2.xml` so it deploys before RunLocalTests. Shared with VS-09 — add once.
- **Post-deploy (human/QA):** measured coverage + the even-distribution/governor verdicts come from
  devops's Phase 2 re-run; unmeasured by dev-senior.
- **Runtime (deferred):** a real slot-gen automation grant for `VS_Slot__c` Create is still owed (no
  human role should carry it) — the test harness permset does NOT satisfy that for a production runner.

---

## BLOCKER E note — fixtures already plain DML; only the engine call is in runAs (dev-senior, 2026-07-12)

**Status: verified by inspection, NOT deployed/tested by dev-senior. devops re-runs Phase 2.**

The BLOCKER E wave (23 fixture-creation failures after the FLS-read wall cleared) was driven by the
BOOKING class over-wrapping its fixtures in runAs (fixed in VS-09-review "BLOCKER E fix"). I re-audited
`VS_SlotGenBatchTest` against the same canonical pattern:
- **`@TestSetup makeData()` uses PLAIN system-mode DML** for every fixture (`insert fac; insert svc;
  insert sessions; insert holidays;`) — it was NEVER using `insert as user` / `WITH USER_MODE` /
  `Database.insert(..., AccessLevel.USER_MODE)`. Grep-confirmed: the only USER_MODE strings in the file
  are in comments/doc. So there was nothing to convert — the fixtures are already system-mode.
- **Only the engine calls are inside runAs:** every `Database.executeBatch(...)`+`Test.stopTest()` and
  the direct `generateForSessions(...)` calls run inside `System.runAs(slotGenUser())`. `buildSlots()`
  and the empty-input test correctly have no runAs (no USER_MODE op).
- **Governor window intact:** `testBulk_250Sessions` still measures `Limits` only around
  `generateForSessions` (setup in `@TestSetup`, outside the window) — SOQL<=4 / DML==1 preserved.
- Even-distribution + remainder asserts preserved verbatim.

Honest caveat: the same-run report cited `makeData line 66 (insert sessions)` failing with a
`fields-inaccessible` DmlException. That line is plain, default-context @TestSetup DML, which
canonically does NOT enforce FLS — and the sibling booking class proved its identical User-creation
@TestSetup pattern completed (its null-input test passed, which requires @TestSetup success). So I
expect this class's `makeData` to succeed on the re-run alongside the booking fix. **IF `makeData`
still fails on plain @TestSetup DML, that would indicate a deploy-time @TestSetup FLS-enforcement
behavior specific to this org — a genuine environment finding to escalate, NOT a code weakness** (I will
not weaken the code or grant fixtures FLS via the permset to mask it). No code change was needed here.

### Honest expectation for the next run
With the booking class's fixtures fixed and this class already canonical, the even-distribution /
remainder / holiday-skip / drive-day / horizon / idempotency / 250-session governor asserts should
finally EXECUTE. Exercising them for the first time MAY unmask previously-hidden LOGIC failures — read
any such as newly-revealed, NOT a regression.

---

## BLOCKER F fix — org enforces FLS on plain DML; run fixtures under the harness user (dev-senior, 2026-07-12)

**Status: correct-by-construction, NOT deployed/tested by dev-senior. devops re-runs Phase 2.**

### Root cause (diagnostic-pinned)
This DE org ENFORCES FLS/CRUD on PLAIN Apex DML during deploy-time RunLocalTests. `VS_SlotGenBatchTest`'s
`makeData` line-66 `insert sessions` failed because slotgen's newSession sets the OPTIONAL
VS_Is_Drive_Day__c and the deploying admin has no FLS on it (booking's newSession, required/MD-only,
passed). So plain @TestSetup DML is NOT FLS-exempt here — the fixtures must be built by an FLS-bearing
user. (This confirms the caveat I flagged in the BLOCKER E note, now resolved.)

### Fix
- **PART 1** (shared with VS-09): the `VS_Booking_Engine_Test_Context` harness permset is broadened —
  read+create on VS_Facility__c/VS_Service__c/VS_Holiday__c/VS_Patient__c/VS_Appointment__c,
  read+create+edit on VS_Session__c, read+create+edit+delete on VS_Slot__c, and read+edit FLS on
  VS_Session__c.VS_Is_Drive_Day__c (the field that broke makeData) — all non-required/non-MD, so no
  required/MD FLS trap.
- **PART 2:** the harness User is created (setup DML) OUTSIDE runAs in @TestSetup; ALL fixture inserts
  (fac/svc/sessions/holidays in makeData, and the per-test fixtures) AND the executeBatch /
  generateForSessions engine calls run INSIDE `System.runAs(slotGenUser())`. Setup DML outside +
  non-setup inside runAs avoids MIXED_DML.
- **GOVERNOR WINDOW kept honest:** `testBulk_250Sessions` builds its 250 fixtures and the scope query
  BEFORE `Test.startTest()`, inside the runAs block, and captures Limits ONLY around
  `generateForSessions` — so the fixtures, the runAs entry, and @TestSetup are all outside the
  SOQL<=4/DML==1 window. Even-distribution + remainder asserts preserved.

TEST-ONLY: does NOT resolve the A-018 runtime gap (a slot-gen automation grant for VS_Slot__c create is
still owed) — routed to BA_ARCH_CONFIRM. Braces 49/49; lint unchanged (2 known `$CustomMetadata` flags).

### Honest expectation
makeData and the engine calls now run under real FLS, so the even-distribution / remainder /
holiday-skip / drive-day / horizon / idempotency / 250-session governor asserts should finally execute.
First-time execution MAY unmask previously-hidden LOGIC failures — read any as newly-revealed, not a
regression.

---

## BLOCKER G fix — Custom Metadata read via getInstance() (dev-senior, 2026-07-12)

**Status: correct-by-construction, NOT deployed/tested by dev-senior. devops re-runs Phase 2.**

BLOCKER F made §3.4 ONLINE VERIFIED (testCapacityExhaustion_online PASSED, VS_BookingService 88% real
coverage). The remaining slot-gen failures were a real access-context issue, NOT a logic bug: on the
runAs harness-user path, plain SOQL on the Custom Metadata Type `VS_Setting__mdt` is rejected in this
org ("sObject type 'VS_Setting__mdt' is not supported").

**FIX 1 (production code, better regardless of org):** switched both CMDT reads from SOQL to the
cache-backed, FLS-free `VS_Setting__mdt.getInstance('<DeveloperName>')` — the SF-recommended way to read
Custom Metadata:
- `VS_SlotGenBatch.getBookingHorizonDays()` — was `[SELECT VS_Value__c FROM VS_Setting__mdt WHERE
  DeveloperName = 'BookingHorizonDays' LIMIT 1]`; now `VS_Setting__mdt.getInstance('BookingHorizonDays')`.
- `VS_SlotGenerationService.getConfiguredDefaultGranularity()` — was the same SOQL for
  `DefaultSlotGranularityMins`; now `VS_Setting__mdt.getInstance('DefaultSlotGranularityMins')`.
- **Default-fallback PRESERVED EXACTLY:** `getInstance` returns null when the record is absent, so the
  guards are `if (setting != null && setting.VS_Value__c != null) return …; else return <default>;` —
  same defaults (14 for horizon; DEFAULT_GRANULARITY_FALLBACK=15 for granularity), same null handling.
  Only the read mechanism changed. Grep confirms NO `FROM VS_Setting__mdt` SOQL remains in any class.

**Tests this unblocks (the 8 slot-gen tests that reach a CMDT read via the batch constructor
`getBookingHorizonDays()` or `generateForSessions`→`getConfiguredDefaultGranularity()`):**
testEvenDistribution_sumsToBookableExactly, testHolidaySkip_generatesNoSlots,
testDriveDayOverridesHoliday_generatesSlots, testBookingHorizon_excludesBeyondHorizon,
testReRun_isIdempotent, testBulk_250Sessions_isGovernorSafe,
testConfigurableGranularity_nonMultipleWindow_dropsTrailingPartial,
testGenerateForSessions_degenerateWindow_skippedNotThrown. (The 3 buildSlots/empty tests never read
CMDT, so they were unaffected.) §3.4 slot-gen even-distribution + governor asserts should now execute.

Braces 7/7 (VS_SlotGenBatch), 28/28 (VS_SlotGenerationService); lint unchanged (2 known `$CustomMetadata`
flags — those are on the FORMULA fields, unrelated to this Apex read change).
