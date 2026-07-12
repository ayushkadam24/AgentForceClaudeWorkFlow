<!--
feature:         F-001 slot-booking-core
producing-agent: dev-senior
date:            2026-07-12
phase:           DEV_IN_PROGRESS
derives-from:    02-build/jira-log.md (VS-09 detailed spec + AC), 02-build/sprint-plan.md,
                 01-discovery/technical-design.md §2.1/§3.4/§4 (full)/§5 (automation matrix),
                 REQ-002, REQ-006, REQ-007, REQ-008, REQ-062 / EP-03 (crown jewel)
                 D-019 (SUPERSEDES D-015), D-020, D-016, D-009 (.claude/memory/decisions.md)
                 .claude/skills/sf-apex-patterns (FOR UPDATE + service-layer + test patterns)
downstream:      VS-11 (cancel/reschedule reuses this session-lock pattern), VS-16 (citizen LWC
                 calls book() imperatively), VS-18/VS-19 (confirmation seam fires after book()),
                 QA Tier-1 concurrency load test, human deploy + test-run on DE org (D-025)
-->

# VS-09 Review Packet — VS_BookingService.book() — single session-lock booking (THE CROWN JEWEL)

## 0. Bucket A fixes applied (post-review, 2026-07-12, dev-senior)

Human-approved Bucket A (Apex) fixes applied. **The §3.4 lock and the single `book()` write path are
UNCHANGED** — these are a collision-handling addition + documentation, not a redesign. NOT
compiled/deployed/tested in this run (deploy happens next, devops).

- **m-1 — reference-collision no longer surfaces as a raw `DmlException`.** The appointment insert is
  now routed through a private `insertAppointmentWithReferenceRetry(appt)`. It catches the
  `DmlException` and, ONLY when it is a `DUPLICATE_VALUE` on `VS_Booking_Reference__c` (checked via
  `isDuplicateReferenceError()` — `StatusCode.DUPLICATE_VALUE` AND the field name in the DML
  field-names/message), **regenerates the reference (`VS_ReferenceGenerator.next()`, still Crypto) and
  retries the insert ONCE inside the same `FOR UPDATE` transaction** (the session lock is never
  released — no savepoint/rollback). A second collision throws
  `VS_BookingException(REFERENCE_COLLISION)` (new coded reason). **Any OTHER `DmlException` is rethrown
  unchanged** — the catch is deliberately narrow, nothing unrelated is swallowed (rules/20). New
  test seam `VS_ReferenceGenerator.forceNextReference()` (`@TestVisible`, dequeued ONLY under
  `Test.isRunningTest()`; production stays pure Crypto → non-guessability intact).
- **m-2 — one-booking-per-transaction contract documented.** `book()` ApexDoc now states it takes a
  pessimistic `FOR UPDATE` lock + up to 2 appointment-insert DML (incl. the m-1 retry) + 1 counter
  update, and MUST be invoked once per transaction — callers must fan out one booking per transaction,
  never loop it. **No behavior change.**
- **New tests (2):** `testReferenceCollision_regeneratesAndRetriesOnce_bookingSucceeds` (forces one
  collision → asserts the retry yields a DISTINCT 8-char Crockford reference and the booking still
  succeeds, both rows persisted) and `testReferenceCollision_twiceInARow_throwsCodedException` (forces
  the collision on BOTH insert + retry → asserts the coded `REFERENCE_COLLISION` is thrown, no raw
  `DmlException`, only the first booking persisted). Test count 11 → **13**.

## 1. Ticket summary

VS-09 (EP-03, Sprint 1, **dev-senior**, L, Priority **Highest**, depends VS-01/02/05/07/08) is the
single point of RFP §3.4 correctness: **no overbooking under concurrency, ever, across all channels.**
It implements `VS_BookingService.book()` as the ONE write path that creates a confirmed appointment
for online, staff, chat, and walk-in, taking exactly ONE pessimistic lock — `SELECT … FOR UPDATE` on
the parent `VS_Session__c` row — for every channel (D-019/D-020).

## 2. Files delivered (all under `force-app/main/default/classes/`)

| File | Role |
|---|---|
| `VS_BookingService.cls` (+ `-meta.xml`) | The single `book()` method: one session-row lock, per-channel capacity check, appointment insert, counter increment, slot-Full flip. |
| `VS_ReferenceGenerator.cls` (+ `-meta.xml`) | Random non-guessable 8-char Crockford base32 booking reference (D-016). |
| `VS_BookingException.cls` (+ `-meta.xml`) | Domain exception; coded reasons as constants. |
| `VS_BookingServiceTest.cls` (+ `-meta.xml`) | 11 test methods; @TestSetup; no SeeAllData; capacity-exhaustion + mixed-channel + walk-in-reserve + negatives + reference uniqueness. |

apiVersion **67.0** (matches the existing classes / `sourceApiVersion`). **Apex was NOT compiled, NOT
deployed, and tests were NOT run — no org is connected in this environment** (see §10). No claim of a
passing build or coverage number is made from execution; expected values in §8 are reasoned, not measured.

## 3. The single-lock control flow (quote)

The one and only lock, taken on the **parent session row** for **every** channel:

```apex
VS_Session__c session = [
    SELECT Id, VS_Status__c, VS_Facility__c, VS_Service__c,
           VS_Walk_In_Reserve_Count__c, VS_Walk_In_Used_Count__c
    FROM VS_Session__c
    WHERE Id = :sessionId
    FOR UPDATE
];
```

Sequence inside `book(Id patientId, Id slotId, Id bookedById, String channel)`:

1. **Validate input** (before any lock): null `patientId`/`slotId`/blank `channel` → `INVALID_INPUT`;
   `channel` not in {Portal, Chat, Staff, WalkIn} → `INVALID_CHANNEL`.
2. **Resolve the owning session** for `slotId` (no lock). Slot missing → `SLOT_NOT_FOUND`.
3. **Take THE lock** — the `FOR UPDATE` above. Session not `Open` → `SESSION_NOT_OPEN`.
4. **Re-read the target slot INSIDE the lock** (its counters cannot be raced because every booking
   for this session holds this same lock).
5. **Branch by channel, still under the lock:**
   - **Online / Staff / Chat** → check the **slot** ceiling
     (`VS_Booked_Count__c >= VS_Capacity__c` or slot not `Open`) → `SLOT_FULL`; else increment
     `VS_Booked_Count__c` and flip `VS_Status__c` to `Full` at the ceiling.
   - **Walk-in** → check the **session reserve**
     (`VS_Walk_In_Used_Count__c >= VS_Walk_In_Reserve_Count__c`) → `WALKIN_RESERVE_FULL`; else
     increment `VS_Walk_In_Used_Count__c`. Never touches a slot's bookable count.
6. **Insert the appointment** (`insert as user` — WITH USER_MODE) with the reference, channel, status;
   then persist the counter change (`update session` for walk-in, else `update slot`) — all in the
   same transaction, still holding the lock.

**No second lock target. No `VS_WalkInService`. No roll-up/trigger maintains the counters.** This is
exactly D-019/D-020 and technical-design §4.2.

## 4. How all three channels flow through the ONE lock

| Channel arg | Pool consumed | Counter incremented | Rejection code | Appointment status |
|---|---|---|---|---|
| `Portal` / `Chat` / `Staff` | slot bookable ceiling (REQ-008) | `VS_Slot__c.VS_Booked_Count__c` | `SLOT_FULL` | `Booked` |
| `WalkIn` | session walk-in reserve (D-009) | `VS_Session__c.VS_Walk_In_Used_Count__c` | `WALKIN_RESERVE_FULL` | `WalkIn` |

Both branches execute **only after** acquiring the same `VS_Session__c` `FOR UPDATE` lock, so online
and walk-in bookings for one session are fully serialized against each other — the online-vs-walk-in
race that D-015's dual lock left open cannot occur (D-019 rationale).

## 5. Reference generator (D-016)

`VS_ReferenceGenerator.next()` returns a random 8-char **Crockford base32** code (alphabet
`0123456789ABCDEFGHJKMNPQRSTVWXYZ` — excludes I, L, O, U to avoid confusion when read aloud / typed on
a feature phone). Each char is drawn from `Crypto.getRandomInteger()` (cryptographic, not sequential →
non-guessable, REQ-030 pattern seam). It is stored in the Unique External Id
`VS_Appointment__c.VS_Booking_Reference__c` (VS-08), so the **database** is the final uniqueness
arbiter: a colliding reference is rejected at insert rather than via a non-locked SOQL check
(race-safe, same reasoning as D-017). Stateless, no SOQL/DML — safe to call inside the lock. **Since
the m-1 fix (§0), that rejection is no longer a raw `DmlException`: `book()` regenerates and retries
once in-lock, then throws the coded `REFERENCE_COLLISION` only on a second consecutive clash.**

## 6. Exception reasons (coded, no raw user strings)

`VS_BookingException` (message == code) exposes constants: `INVALID_INPUT`, `INVALID_CHANNEL`,
`SLOT_NOT_FOUND`, `SESSION_NOT_OPEN`, `SLOT_FULL`, `WALKIN_RESERVE_FULL`. Callers/LWC/Flow map these
to friendly, localized text (VS-16). **Note:** the ticket specifies `WALKIN_RESERVE_FULL`; the design
§4.2 code sketch used the shorter `RESERVE_FULL` — I used the ticket's more specific `WALKIN_RESERVE_FULL`
(flagged here so the reviewer can confirm the naming).

## 7. CRUD/FLS enforcement (deliberate, please scrutinize)

- The **appointment insert uses `insert as user`** (WITH USER_MODE), so CRUD/FLS is enforced on the
  record the acting user creates (rules/20, ticket requirement).
- The **lock/counter reads and the counter `update` on `VS_Session__c`/`VS_Slot__c` run in system
  mode by design.** Those denormalized counters are owned solely by this service under the lock
  (D-020), and a Portal citizen must **not** be granted direct edit on capacity rows (least
  privilege). Enforcing USER_MODE on the counter update would force granting citizens edit on
  Session/Slot — wrong security posture. This split is intentional. **Reviewer:** confirm you agree
  system-mode counter maintenance behind the service boundary is acceptable; the alternative is a
  narrow FLS grant on the counter fields only.
- Class is `with sharing`.

## 8. Test list + what each PROVES (expected coverage ≥ 90%, NOT measured)

`VS_BookingServiceTest` — 11 methods, meaningful state asserts (final counters + row counts, not "no
exception"):

| # | Test | Proves |
|---|---|---|
| 1 | `testHappyPath_onlineBooking` | online book creates `Booked` appt, reference populated, slot count → 1, session reserve untouched, Facility/Service denormalized. |
| 2 | `testHappyPath_walkInBooking` | walk-in creates `WalkIn` appt, session reserve used → 1, **slot count stays 0** (disjoint pools). |
| 3 | **`testCapacityExhaustion_online_neverOverbooks`** (mandatory) | fill slot cap=2 to full, 3rd attempt → `SLOT_FULL`; `VS_Booked_Count__c` never exceeds `VS_Capacity__c`; slot flips to `Full`; exactly `capacity` appointment rows exist. |
| 4 | `testWalkInReserveExhaustion_neverOverbooks` | reserve=1, 2nd walk-in → `WALKIN_RESERVE_FULL`; `VS_Walk_In_Used_Count__c` never exceeds reserve. |
| 5 | **`testMixedChannels_sameSession_noOverbooking`** (mandatory, D-019 proof) | one place per pool; a burst of online+walk-in → exactly one online + one walk-in succeed (2 appts), 2nd of each rejected against its own exhausted pool; neither channel consumes the other's capacity. |
| 6 | `testBookingReference_uniqueAndPopulatedAndTypeable` | two refs are non-null, 8 chars, distinct, and match the Crockford charset (no I/L/O/U). |
| 7 | `testNegative_invalidSlotId_throwsAndCreatesNothing` | deleted (valid-format, non-existent) slot Id → `SLOT_NOT_FOUND`; zero appointment rows created; real slot untouched. |
| 8 | `testNegative_closedSession_throwsSessionNotOpen` | Closed session → `SESSION_NOT_OPEN`; no appt. |
| 9 | `testNegative_invalidChannel_throws` | unknown channel → `INVALID_CHANNEL`; no appt. |
| 10 | `testNegative_nullInput_throws` | null required args → `INVALID_INPUT`. |

All lines of `book()`, both channel branches, every throw, and `VS_ReferenceGenerator.next()` are
exercised → **expected coverage ≥ 90%** on the two new production classes. **This is an estimate;
coverage was NOT measured (no org).**

## 9. THE CONCURRENCY-TESTING LIMITATION (read this — highest-priority honesty item)

**Apex UNIT tests run in a SINGLE transaction and cannot spawn truly parallel transactions.** Inside a
test, the `FOR UPDATE` lock is never actually contended — sequential `book()` calls simply see the
counters that earlier calls in the same transaction already wrote. Therefore:

> The unit tests in this ticket prove the capacity-**CEILING LOGIC** — that check-then-insert correctly
> rejects the over-limit booking and never lets a counter exceed its ceiling. They do **NOT**, by
> themselves, prove serialization under real concurrency. **`FOR UPDATE` provides the runtime
> serialization**; that behavior must be validated by a **parallel load test on the org**.

**Do NOT read these unit tests as proof of "no overbooking under concurrency."** They prove the ceiling
logic; the lock provides the serialization; the load test proves the lock.

### How to prove REAL concurrency on the DE org (AgentForceClaudeWorkFlow, D-025)

After VS-01/02/05/07/08 + these classes are deployed and a session is seeded with **one** remaining
place (slot `VS_Capacity__c = 1`, `VS_Booked_Count__c = 0`):

1. Prepare N (e.g. 20–50) invocations of `VS_BookingService.book(patientId, slotId, userId, 'Portal')`
   all targeting that **same slot**, each with a distinct patient.
2. Fire them **simultaneously** — options:
   - N parallel `sf apex run --file book.apex --target-org AgentForceClaudeWorkFlow` processes launched
     together (e.g. a shell loop backgrounding each), or
   - N concurrent REST calls to an `@RestResource`/`@AuraEnabled` wrapper hitting `book()`, driven by a
     small load script (e.g. `xargs -P`, JMeter, or `k6`), or
   - an anonymous-apex harness that enqueues N `Queueable` jobs which each call `book()` (separate
     transactions) against the same slot.
3. **Assert exactly ONE succeeds:** query `SELECT COUNT() FROM VS_Appointment__c WHERE VS_Slot__c = :id`
   → **1**; `VS_Slot__c.VS_Booked_Count__c` = 1 (never 2+); the other N-1 calls each caught
   `SLOT_FULL`. Repeat for the walk-in reserve (`VS_Walk_In_Reserve_Count__c = 1`, channel `WalkIn`)
   and for a **mixed** online+walk-in burst on one session (one place per pool → exactly one per pool).

This is the DHS acceptance concurrency test (technical-design §4.4) and the QA Tier-1 release gate.

## 10. Deploy / test status (honest)

- `sf project deploy start --dry-run`: **NOT run.** No org is authenticated in this environment (per
  D-025 the target is the persistent DE org `AgentForceClaudeWorkFlow`; prior devops runs confirmed no
  DE alias is connected here, and unrelated client orgs must never be targeted).
- `sf apex run test --code-coverage`: **NOT run.** Coverage in §8 is an estimate, not a measurement.
- Static self-review only: the four `.cls` were reviewed for compile-correctness by hand; the four
  `-meta.xml` are the standard ApexClass shape (apiVersion 67.0, Active). No automated well-formedness
  tool was run this pass.
- **Deploy dependency:** requires VS-01/02/05/07/08 metadata deployed first (Session/Slot/Patient/
  Appointment objects + `VS_Setting__mdt.WalkInReservePct=25` seed — the walk-in reserve formula and
  test preconditions depend on it). The `insert as user` path also requires the running/community user
  to have Create on `VS_Appointment__c` — permission-set extension for Appointment is still deferred
  (VS-04 flag; VS-14/VS-20). Tests run as a sysadmin test user, which has it.

## 11. Acceptance-criteria pass/fail (VS-09)

| AC | Verdict | Evidence |
|---|---|---|
| 50 parallel `book()` at one slot → exactly one appt, count never exceeds capacity, rest get `SLOT_FULL` | **PARTIAL (by design of unit tests)** | Ceiling logic proven by test #3; the *parallel* aspect requires the §9 load test on the org (unit tests can't parallelize). Honestly flagged, not claimed. |
| 50 parallel walk-in → exactly one, `VS_Walk_In_Used_Count__c` never exceeds reserve | **PARTIAL (same reason)** | Ceiling proven by test #4; parallelism → §9 load test. |
| One place shared across channels, mixed burst → exactly one succeeds, no overbooking | **MET (design-default interpretation) + PARTIAL on parallelism** | Test #5 proves per-pool ceilings under the one lock; see **A-016** for the shared-vs-disjoint-pool interpretation. |
| Success → unique `VS_Booking_Reference__c` + CRUD/FLS | **MET** | Test #6 + `insert as user` (§7). |
| Exactly ONE public entry point for all channels — no `VS_WalkInService`, no second lock | **MET** | §3/§4; single `book()`, single `FOR UPDATE`. |
| Test class includes capacity-exhaustion AND mixed-burst AND a negative test with row-count asserts | **MET** | Tests #3, #5, #7–#10. |

The two "50 parallel" ACs are marked **PARTIAL** honestly: no Apex unit test can literally run 50
parallel transactions. The ceiling logic is proven in-test; the serialization is proven by the §9
load test, which QA Tier-1 must run on the DE org as the release gate. **This is the correct and honest
status — the unit test is not, and is not claimed to be, a concurrency proof.**

## 12. Assumptions logged (see `.claude/memory/assumptions.md`)

- **A-016** — Mixed-channel "shared place" semantics. The AC wording ("one place *shared across
  channels*, exactly one booking of *any type* succeeds") reads as if online and walk-in draw from ONE
  pool. The **design default (D-020) makes them DISJOINT pools** (slot bookable vs session reserve).
  I implemented the design default and wrote test #5 to seed **one place per pool** → exactly one online
  + one walk-in succeed, each rejected beyond its own ceiling, no cross-consumption. If DHS truly means
  a single shared last place across both channels, the model (not just this method) would need to
  merge the two counters — that is a design change for BA_ARCH_CONFIRM, not a silent code choice here.
- **A-017** — `bookedById` has no storage field in the VS-08 `VS_Appointment__c` schema (no "Booked By
  User" lookup). It is retained in the signature per the design contract (VS-16/staff attribution) but
  is currently unused for storage; audit attribution is via `CreatedById`. If per-booking user
  attribution beyond CreatedBy is required, add a lookup field (schema change, VS-08 owner).

## 13. Traceability

REQ-002/006/007/008 (+ REQ-062 session-scoped) → technical-design §2.1/§3.4/§4 (+ §5 automation
matrix) → EP-03 → **VS-09** → `VS_BookingService`/`VS_ReferenceGenerator`/`VS_BookingException` +
`VS_BookingServiceTest` (this packet) → QA TC-### (§9 concurrency load test = QA Tier-1 gate).
Decisions honored: **D-019** (single session lock, all channels), **D-020** (slot ceiling read/written
only under the session lock; no roll-up), **D-016** (reference generator), **D-009** (walk-in reserve).

## 14. What the human reviewer should scrutinize (ranked)

1. **The lock is on `VS_Session__c` (not `VS_Slot__c`)** and is taken before any counter read — confirm
   this matches D-019/D-020 and that there is exactly one `FOR UPDATE` and one lock target.
2. **System-mode counter maintenance vs USER_MODE insert** (§7) — is the least-privilege split
   acceptable, or do you want a narrow FLS grant on the counter fields instead?
3. **A-016 disjoint-pool interpretation** — is the design-default reading correct, or does DHS mean a
   single shared last place across channels (a model change)?
4. **The concurrency-testing limitation (§9)** — confirm the load test is scheduled as the QA Tier-1
   release gate; the unit tests are ceiling-logic proof only.
5. `WALKIN_RESERVE_FULL` vs design's `RESERVE_FULL` naming (§6).
6. Booking-reference collision posture — DB unique constraint is the guard; **since m-1 (§0) the
   service regenerates + retries ONCE in-lock, then throws coded `REFERENCE_COLLISION` on a second
   clash.** Confirm the narrow duplicate-detection (`StatusCode.DUPLICATE_VALUE` + field-name match)
   correctly excludes every OTHER `DmlException` from the retry (nothing unrelated swallowed).

## Manual / setup steps

- **Pre-deploy:** Deploy VS-01/02/05/07/08 metadata first (objects + `VS_Setting__mdt` seed incl.
  `WalkInReservePct=25`). The four VS-09 classes deploy together (service, generator, exception, test).
- **Pre-deploy (order):** these Apex classes reference `VS_Appointment__c`, `VS_Slot__c`,
  `VS_Session__c`, `VS_Patient__c` — all must exist in the org before this deploys or compilation fails.
- **Post-deploy (validation, human):** run `sf apex run test --tests VS_BookingServiceTest
  --code-coverage --target-org AgentForceClaudeWorkFlow` and record the real result + coverage in the
  runbook (this packet's §8 numbers are estimates).
- **Post-deploy (Tier-1 release gate, human/QA):** run the **parallel concurrency load test** in §9 on
  the DE org — this is the actual §3.4 proof and cannot be satisfied by the unit tests.
- **Permission note:** for a real Portal/community user to call `book()`, grant Create on
  `VS_Appointment__c` (permission-set extension deferred to VS-14/VS-20). Not needed for the test run
  (runs as sysadmin).
- Otherwise: none.

---

## BLOCKER C fix — test FLS/USER_MODE context (dev-senior, 2026-07-12, fix-forward)

**Status of this fix: correct-by-construction, NOT deployed/tested by dev-senior (no deploy from this
environment). devops re-runs Phase 2 real deploy + RunLocalTests to capture the real numbers.**

### The failure being fixed (from deployments.md Phase 2, Deploy `0AfgL00000QxljtSAB`)
Metadata deployed 100% clean (86/86), but RunLocalTests returned **24 run / 23 FAILED / 1 passed**,
identical in dry-run and real deploy (so genuine, not a checkOnly artifact). Two signatures, one root:
- `System.DmlException: ... fields being inaccessible ... VS_Patient__c / VS_Session__c` (21)
- `System.QueryException: No such column 'VS_Walk_In_Reserve_Count__c' on entity 'VS_Session__c'` (2)

Root cause: `VS_BookingServiceTest` ran with **no `System.runAs` / no permission-set context**, i.e. as
the deploying System Administrator, who has **no FLS on the freshly Metadata-API-deployed `VS_` fields**
(MDAPI custom fields get no profile FLS by default). `VS_BookingService.book()` inserts the appointment
`insert as user` (USER_MODE, rules/20 §Apex), so the very first USER_MODE write failed **before any
§3.4 logic ran**. The one pass (`testNegative_nullInput_throws`) throws on null input before any DML.

### What I changed in `VS_BookingServiceTest` (code UNCHANGED — test-only)
1. `@TestSetup` now also creates a `User` on the **'Standard User'** profile (present in a DE org) and
   assigns it the permission set **`VS_Booking_Engine_Test_Context`** via `PermissionSetAssignment`.
   The User+assignment DML is isolated inside `System.runAs(new User(Id=UserInfo.getUserId()))` to
   avoid `MIXED_DML_OPERATION` with the non-setup Facility/Service inserts.
2. Every test that calls `book()` now runs its body inside `System.runAs(bookingUser())` so the
   `insert as user` executes under a realistic FLS-bearing user. State asserts (booked-count/status,
   the capacity-exhaustion invariant, the mixed online/walk-in §3.4 proof, reference-collision paths)
   are all preserved verbatim — they now actually EXECUTE instead of dying at FLS setup.
3. `testNegative_nullInput_throws` deliberately keeps NO `runAs` (it must throw before any DML; that is
   why it was the single pre-fix pass) — documented inline.

### Permission set assigned and WHY — and the GENUINE GAP found
`VS_BookingService.book()`'s only USER_MODE operation is `insert as user` on `VS_Appointment__c`
(fields: Patient/Slot/Session/Facility/Service/Booking_Reference/Booked_Channel/Status). It therefore
needs **Create on `VS_Appointment__c` + FLS on those fields**. The lock/counter reads/updates on
Session/Slot run in **system mode** by design (D-020) and need no user grant.

**GENUINE FINDING (routed, NOT papered over): no existing role permission set grants `VS_Appointment__c`
at all.** VS-04 deferred Patient/Appointment perms to VS-07/08/17/20, so none of `VS_Facility_Staff`,
`VS_Nurse`, `VS_MO_Facility_Admin`, `VS_District_Admin`, `VS_District_MIS` reference the object. The
`/dev-implement` instruction's suggestion to "map to `VS_Facility_Staff`/`VS_Nurse`" therefore could not
be satisfied — those permsets do not (yet) grant booking. **This is a real runtime gap, not just a test
gap:** until a booking permset granting `VS_Appointment__c` create + FLS is built (VS-08/17/20), NO real
Portal/staff user can call `book()` under USER_MODE. (This packet's earlier "Manual/setup — Permission
note" already anticipated it; BLOCKER C makes it concrete.)

**Resolution:** I added a dedicated, clearly-named permission set **`VS_Booking_Engine_Test_Context`**
(`force-app/main/default/permissionsets/`) granting exactly the USER_MODE surface the booking + slot-gen
engines exercise — `VS_Appointment__c` (C/R + FLS on the 6 non-required fields), `VS_Slot__c` (C/R),
and read on `VS_Session__c`/`VS_Service__c`/`VS_Holiday__c` (+ read FLS on the Session formula fields).
It is assigned ONLY to the test user; it is a TEST/CI harness standing in for the deferred runtime
grants, **not** a role for real users. This is the "flag the gap, do not silently invent a permset"
path: it is invented deliberately and documented here. FLS is granted only on non-required, non-MD
fields (deploy-safe — no FLS-on-required/MD error, the VS-04 trap).

### Reviewer scrutiny points (BLOCKER C)
- Confirm `VS_Booking_Engine_Test_Context` is added to the Phase 2 deploy manifest (devops — see
  Manual/setup addendum) BEFORE the re-run, or the `PermissionSetAssignment` query fails at test time.
- Confirm the runtime booking permset (VS-08/17/20) is the right owner for the real `VS_Appointment__c`
  grant, and that the test harness permset is acceptable to keep in the org.
- Expectation for the next run: the FLS fix should let the booking-integrity asserts finally execute.
  Fixing the FLS context **may unmask previously-hidden logic failures** (asserts that never ran before);
  treat any such failure as newly-revealed, NOT a regression from this change.

## Manual / setup steps (BLOCKER C addendum)

- **Pre-deploy (devops):** add `VS_Booking_Engine_Test_Context` (PermissionSet) to the Phase 2 delta
  manifest (`manifest/deltas/SPRINT-1-phase2.xml`) alongside the 5 existing permsets, so it deploys
  before RunLocalTests executes. Without it the tests' `PermissionSetAssignment` lookup throws.
- **Post-deploy (human/QA):** the real §3.4 verdict + measured coverage come from devops's Phase 2
  re-run; this fix is unmeasured by dev-senior.
- **Runtime (real users, deferred):** a production booking permset granting `VS_Appointment__c` Create +
  field FLS is still owed by VS-08/17/20 — the test harness permset does NOT satisfy that for real users.

---

## BLOCKER D fix — master-object Read on the harness permset (dev-senior, 2026-07-12)

devops's Phase 2 dry-run after BLOCKER C surfaced ONE metadata error on the new
`VS_Booking_Engine_Test_Context` permset: *"Permission Read VS_Session__c depends on permission(s):
Read VS_Facility__c"*. `VS_Session__c` and `VS_Slot__c` are Master-Detail children of `VS_Facility__c`,
and the platform requires master-object Read before granting detail-object Read — the permset granted
Read on the details but not the master.

**Fix (the exact block added, nothing else changed):**
```xml
<objectPermissions>
    <object>VS_Facility__c</object>
    <allowRead>true</allowRead>
    <allowCreate>false</allowCreate>
    <allowEdit>false</allowEdit>
    <allowDelete>false</allowDelete>
    <viewAllRecords>false</viewAllRecords>
    <modifyAllRecords>false</modifyAllRecords>
</objectPermissions>
```
Object Read ONLY — NO field grants on `VS_Facility__c` (the engines read it only as the relationship-Id
on child records; adding FLS would risk re-tripping the required/MD FLS trap). All other object perms
and the 9 field grants are unchanged (verified: 6 objectPermissions now, 9 fieldPermissions still).
Well-formed (python minidom, 0 failures); `metadata-lint.js` unchanged (only the 2 pre-existing
`$CustomMetadata` flags). NOT deployed by dev-senior — devops re-runs Phase 2.

---

## BLOCKER E fix — fixtures moved OUT of runAs (dev-senior, 2026-07-12)

**Status: correct-by-construction, NOT deployed/tested by dev-senior. devops re-runs Phase 2.**

After BLOCKER C/D, metadata is 87/87 clean and the tests now EXECUTE — but 23 still failed at FIXTURE
CREATION (not §3.4 asserts). Signature for this class: `System.TypeException: DML INSERT not allowed on
VS_Session__c` at newSession. Root cause: my BLOCKER C edit wrapped the WHOLE test body in
`System.runAs(bookingUser())`, so the fixture inserts (newSession/newSlot/newPatient) ran as the harness
user — which INTENTIONALLY lacks Session/Slot/Patient CREATE (that permset is the runtime Appointment/
Slot surface, not a fixture grant). So the fixtures failed at object-CREATE before book() was ever reached.

**Fix (canonical USER_MODE-test pattern, test-only, code UNCHANGED):**
- ALL fixture creation (newSession/newSlot/newPatient, and any pre-created patients for loops/mixed
  cases) now runs in the DEFAULT test context with PLAIN system-mode DML — which ignores CRUD/FLS, so it
  succeeds unconditionally and does NOT depend on the harness permset.
- ONLY the `VS_BookingService.book(...)` call — the single USER_MODE path under test — stays inside
  `System.runAs(bookingUser())`. Where `book()` was previously called with an inline `newPatient(...)`
  argument (capacity-exhaustion loop, mixed-channel, negatives), the patients are now pre-created as
  fixtures and their Ids passed in, so no CREATE ever happens under runAs.
- Every state assert is preserved verbatim: booked-count/status, the capacity-exhaustion invariant
  (`VS_Booked_Count__c` never exceeds `VS_Capacity__c`, slot flips Full), the mixed online/walk-in §3.4
  proof (disjoint pools, exactly one per pool, no cross-channel overbooking), reference-collision paths.
- `testNegative_nullInput_throws` keeps NO runAs and NO fixtures (throws before any DML).

Sharing note: fixtures are owned by the default test user, but `VS_Facility__c` is OWD Public Read and
`VS_Session__c`/`VS_Slot__c` are ControlledByParent, so the `with sharing` reads inside `book()` (running
as the harness user) still see them. Appointment lookups to Private `VS_Patient__c` are fine on insert
(lookups don't require read access to the referenced record).

Braces balanced (58/58); `metadata-lint.js` unchanged (2 pre-existing `$CustomMetadata` flags only).

### Honest expectation for the next run
With fixtures in system mode and only `book()` under runAs, the fixture-creation wall is gone and the
§3.4 capacity/mixed-channel asserts should finally EXECUTE. As flagged since BLOCKER C, exercising the
real logic for the first time MAY unmask previously-hidden LOGIC failures — read any such failure as
newly-revealed, NOT a regression from this pass.

---

## BLOCKER F fix — org enforces FLS on plain DML; run fixtures under the harness user (dev-senior, 2026-07-12)

**Status: correct-by-construction, NOT deployed/tested by dev-senior. devops re-runs Phase 2.**

### Root cause (diagnostic-pinned)
This DE org ENFORCES FLS/CRUD on PLAIN Apex DML during deploy-time RunLocalTests (not the usual
system-mode bypass), and the deploying admin has no FLS on the freshly-deployed OPTIONAL VS_ fields.
Proof: booking's newSession/newSlot (only required/MD fields → implicit access) pass a plain insert;
newPatient (sets the OPTIONAL VS_Match_Key__c) and the $CustomMetadata formula reads fail. So the
BLOCKER E "plain system-mode fixtures" approach cannot win here — the running context needs REAL FLS.

### Fix — PART 1: broadened the TEST-ONLY harness permset
`VS_Booking_Engine_Test_Context` now grants a test user enough to BUILD fixtures and run the engines:
- **objectPermissions:** read+create on VS_Facility__c, VS_Service__c, VS_Holiday__c, VS_Patient__c,
  VS_Appointment__c; read+create+**edit** on VS_Session__c (book() updates the walk-in counter);
  read+create+**edit+delete** on VS_Slot__c (book() updates the booked counter; the invalid-slot
  negative deletes a slot).
- **fieldPermissions (read+edit unless noted):** the 6 non-required VS_Appointment__c fields book()
  writes; VS_Session__c.VS_Is_Drive_Day__c (optional, fixtures set it); VS_Patient__c.VS_Match_Key__c
  (optional, newPatient sets it); READ-ONLY on the two formula fields VS_Session__c.VS_Bookable_Capacity__c
  and VS_Walk_In_Reserve_Count__c.
- **Confirmed NONE of the FLS entries is required=true or Master-Detail** (Match_Key optional,
  Is_Drive_Day optional checkbox, two formulas, six optional Appointment fields) — so the VS-04
  required/MD deploy trap is not re-tripped. Required/MD fields (Slot fields, Status, dates/times,
  capacity, walk-in-used, all MD/lookup masters) get IMPLICIT access via object-level create/edit only.

### Fix — PART 2: fixtures now run under the harness user
The harness User is created (setup DML) OUTSIDE runAs in @TestSetup (User first, then the
PermissionSetAssignment); ALL non-setup fixture DML (Facility/Service in @TestSetup; Session/Slot/Patient
+ the delete in each test) AND the book() call run INSIDE `System.runAs(bookingUser())`. Setup DML
outside + non-setup inside runAs is the canonical MIXED_DML-safe ordering. Every state assert is
preserved (capacity-exhaustion invariant, mixed online/walk-in §3.4 proof, reference-collision).
`testNegative_nullInput_throws` keeps no runAs (throws before any DML).

TEST-ONLY: the broadened permset does NOT resolve the A-018 production-permset gap (a real Portal/staff
booking permset for VS_Appointment__c create, and a slot-gen automation grant for VS_Slot__c create,
are still owed) — that stays routed to BA_ARCH_CONFIRM. Braces 57/57; lint unchanged (2 known
`$CustomMetadata` flags); permset desc 251≤255.

### Honest expectation
Fixtures now build under real FLS, so the §3.4 asserts should finally execute. As flagged since
BLOCKER C, first-time execution MAY unmask previously-hidden LOGIC failures — read any as
newly-revealed, NOT a regression.

---

## BLOCKER G fix — collision detect by status code; category-1 walk-in left org-limited (dev-senior, 2026-07-12)

**Status: correct-by-construction, NOT deployed/tested by dev-senior. devops re-runs Phase 2.**

BLOCKER F made §3.4 ONLINE VERIFIED (testCapacityExhaustion_online_neverOverbooks PASSED,
VS_BookingService 88% real coverage, VS_ReferenceGenerator 100%). The two remaining booking failures
were an access-context issue, NOT a logic bug.

**FIX 2 (production robustness, better regardless of org):** `VS_BookingService.isDuplicateReferenceError`
previously confirmed the collision by reading the conflicting record's field names/message
(`getDmlFieldNames(i)` / `getDmlMessage(i)`) for `VS_Booking_Reference__c`. Under least privilege the
colliding record (e.g. another facility's appointment) can be FLS-/sharing-masked from the acting user,
so that check could return false and the retry contract would break. NEW: detect purely by
`ex.getDmlType(i) == StatusCode.DUPLICATE_VALUE`. `VS_Booking_Reference__c` is the ONLY unique field this
service sets on `VS_Appointment__c`, so a DUPLICATE_VALUE on this insert can only be the reference — the
status code is precise and needs no record visibility.
- **Contract PRESERVED EXACTLY:** only a DUPLICATE_VALUE (reference collision) triggers the single
  regenerate-and-retry; the second collision still throws coded `REFERENCE_COLLISION`; every
  NON-DUPLICATE_VALUE DmlException still returns false and is rethrown untouched (no swallow, rules/20).

**Tests this unblocks (2):** testReferenceCollision_regeneratesAndRetriesOnce_bookingSucceeds,
testReferenceCollision_twiceInARow_throwsCodedException.

### Category 1 (walk-in) — DELIBERATELY LEFT ORG-LIMITED (per coordinator)
The walk-in path's `update session` (VS_BookingService ~line 182) increments the REQUIRED field
`VS_Walk_In_Used_Count__c` in SYSTEM mode by design (D-020: the service is the sole trusted owner of the
counters; a Portal citizen must not get direct edit on capacity rows). This org abnormally FLS-filters
even system-mode DML at deploy-time on that required field — and a required field CANNOT carry
field-FLS (VS-04 trap), so it can't be "granted". Per the coordinator this is left UNTOUCHED: production
system-mode counter design UNCHANGED, tests UNCHANGED, no fieldPermissions added on the required field.
The 3 walk-in tests (testHappyPath_walkInBooking, testWalkInReserveExhaustion_neverOverbooks,
testMixedChannels_sameSession_noOverbooking) are EXPECTED to still fail next run; walk-in §3.4 is being
handled as a separate deploy-strategy decision (likely the QA parallel load test in §9), not a code fix.

Braces 25/25 (VS_BookingService); lint unchanged (2 known `$CustomMetadata` flags).

---

## BLOCKER H fix — split walk-in tests into their own class (dev-senior, 2026-07-12, D-028/D-028a)

**Status: mechanism-only test split, NOT deployed/tested by dev-senior. devops runs the class-level
RunSpecifiedTests real deploy next.**

### Why (class-level, not method-level)
The Metadata DEPLOY API's RunSpecifiedTests accepts CLASS names only — a method-level Class.method
silently runs 0 tests, so the prior real deploy rolled back on 0% coverage. To run exactly the
executable methods on deploy, the 3 walk-in methods (which cannot execute under this org's deploy-time
FLS enforcement of the system-mode counter update on the required VS_Walk_In_Used_Count__c) are moved
into their own class that is simply NOT named in the RunSpecifiedTests list.

### What moved vs. what stayed
- CREATED VS_BookingServiceWalkInTest.cls (+ -meta.xml, apiVersion 67.0 like the others). It is
  SELF-CONTAINED: its own @TestSetup (harness User VSWalkInTest + PermissionSetAssignment, then fixtures
  under runAs) and COPIES of the helpers the 3 methods use (slotStart, TEST_PERMSET, bookingUser,
  facilityId, serviceId, newPatient, newSession, newSlot, reloadSlot, reloadSession, apptCount). The 3
  methods moved VERBATIM: testHappyPath_walkInBooking, testWalkInReserveExhaustion_neverOverbooks,
  testMixedChannels_sameSession_noOverbooking. Helper duplication with VS_BookingServiceTest is accepted
  for the POC per D-028a (NOT refactored to a shared class, to keep zero risk to the deploy-run methods).
- VS_BookingServiceTest.cls: DELETED ONLY those 3 methods. Everything else untouched — the 9 remaining
  methods (online happy path, capacity-exhaustion §3.4, booking-reference, 2 reference-collision, 4
  negatives), the full @TestSetup, and ALL helper methods. Two breadcrumb comments mark the move.
  Production classes, the harness permset, and all other metadata are UNCHANGED.

Braces balanced: VS_BookingServiceTest 45/45, VS_BookingServiceWalkInTest 25/25; lint unchanged (2 known
$CustomMetadata flags). devops must add VS_BookingServiceWalkInTest to the manifest (so it deploys) but
must NOT include it in the RunSpecifiedTests class list.

### Honest coverage expectation
VS_BookingServiceTest alone still exercises the online slot-channel path (online happy + capacity-
exhaustion), the reference-collision retry/coded-exception path, and all negative/validation branches.
The only VS_BookingService lines it no longer covers are the walk-in branch (isWalkIn reserve check +
VS_Walk_In_Used_Count__c increment + the walk-in update session). Coverage was 88% with all methods; my
EXPECTATION is it stays comfortably >=75% (roughly mid-80s) — but this is my estimate; devops measures
the real number. The 3 moved walk-in methods are expected not to run on deploy by design (category-1
org-limited; walk-in overbooking is proven by QA's parallel load test).

## §3.4 load-test harness (temporary) — added 2026-07-12, dev-senior

To finally PROVE the RFP §3.4 **walk-in** no-overbooking guarantee at runtime (TC-002/TC-003 — the one
thing unit tests + CLI QA could not verify, D-028), a **human-approved, temporary** REST harness was
built. It is **NOT part of the F-001 product** and is **REMOVED from the org after the load test**.

- **New: `VS_LoadTestEndpoint.cls`** — `@RestResource(urlMapping='/vsLoadTest/*')`, `global without
  sharing`. Endpoints: `POST /seed` (fresh Facility/Service/active Facility_Service/Open Session/Slot;
  Total_Capacity=4 so `CEILING(4*25/100)=1` → walk-in reserve == **exactly 1**, un-consumed; variants
  walkin / online(slot cap 1) / disjoint(slot cap 1 AND reserve 1, D-020)), `POST /book` (fresh
  `VS_Patient__c` per call → N callers contend as N patients; calls `VS_BookingService.book()`;
  returns `{success, apptId, reason}` with the **coded** `VS_BookingException` reason, never swallowed),
  `GET /verify` (system-mode read-back of the invariant), `DELETE /reset` (optional). All harness
  SOQL/DML is **system-mode (plain)** so it runs as admin with no FLS — the deliberate mechanism that
  sidesteps D-028 at runtime.
- **New: `VS_LoadTestEndpoint_Test.cls`** — 16 request/response tests; runs fixtures under the FLS
  harness user (`runAs`) per the deploy-time-FLS org quirk.
- **`VS_Booking_Engine_Test_Context` permset**: +1 object grant (`VS_Facility_Service__c`) and +4
  optional-field FLS grants the harness `seed` writes (three `Is_Active` + facility helpline). **5
  clearly-commented "revert when the load-test class is removed" lines.** Required/MD fields left
  implicit (no FLS entry) per the VS-04 trap.
- **`VS_BookingService` and every other production class are UNCHANGED** — the endpoint only
  orchestrates (seed + call `book()` + read). No hardcoded IDs; **NO Aadhaar / no 12-digit identifier**
  anywhere (10-digit fictional mobiles + synthetic match keys only).

### Deploy verification (REAL — validate-only, not committed)
`sf project deploy start --dry-run -l RunSpecifiedTests -t VS_LoadTestEndpoint_Test` against
`AgentForceClaudeWorkFlow` (POC DE org):
- **Status: Succeeded. 16/16 tests PASS. `VS_LoadTestEndpoint` coverage = 87.5%** (Deploy id
  `0AfgL00000QyzhZSAR`). Notably the ONLINE and (in this check-only run) WALK-IN `book()` paths both
  succeeded under the harness user.
- The dry-run caught + I fixed two real defects before the packet: Apex map literals using `,` instead
  of `=>` (compile), and a missing required `VS_Date_Of_Birth__c` on the seeded patient (would have
  failed at runtime too).
- Metadata lint: unchanged 2 known `$CustomMetadata` formula flags (pre-existing, VS-01/D-026); the
  harness added zero lint issues.

### What the human reviewer should scrutinize
- The permset edit couples the temporary harness to the permanent booking-test permset. Confirm the
  "revert" plan is captured in the removal runbook so the 5 lines don't linger post-test.
- Confirm the harness endpoint/class is genuinely REMOVED after the load test (deployments.md step).
- `without sharing` + system-mode is intentional and load-test-only; it must never be reused by product
  code (Portal citizens must not get direct capacity-row edit — see VS_BookingService §Security).

### Manual / setup steps (for the devops runbook)
- **Pre-deploy:** none (delta compiles standalone; VS-09 + VS-02 CMDT already in the org).
- **Deploy:** deploy delta `ApexClass:VS_LoadTestEndpoint`, `ApexClass:VS_LoadTestEndpoint_Test`,
  `PermissionSet:VS_Booking_Engine_Test_Context` to the POC DE org (`AgentForceClaudeWorkFlow` ONLY).
- **Post-deploy (before load test):** grant the load-driver user Apex-REST access (a system-admin user
  works out of the box); no VS_ FLS is required at runtime. Optionally smoke-test `POST /vsLoadTest/seed`.
- **Manual-only:** after the load test completes, **REMOVE** `VS_LoadTestEndpoint` +
  `VS_LoadTestEndpoint_Test` from the org (destructiveChanges) and **revert the 5 harness lines** in
  `VS_Booking_Engine_Test_Context`. Record the run evidence + removal in 02-build/deployments.md.

---

## D-029 walk-in counter-persist robustness fix (dev-senior, 2026-07-12)

**Ruling:** D-029 (architect, human-requested; `.claude/memory/decisions.md`). **Classification:**
IMPLEMENTATION-ROBUSTNESS — PRESERVES the §3.4 design (D-019/D-020), NOT a deviation, no re-drift-check.
**Phase note:** applied while PIPELINE_STATE is `QA_IN_PROGRESS` — a bounded, architect-GO'd focused fix
routed back from QA; PIPELINE_STATE YAML left untouched per the D-029 handoff.

### The runtime defect being fixed
QA §3.4 load test (TC-002 ×3, harness `0AfgL00000Qz29BSAR`) proved the WALK-IN `book()` path throws
`DmlException: fields being inaccessible on VS_Session__c` at the counter persist (`update session;`).
Root cause: the `session` sObject was loaded by the `SELECT ... FOR UPDATE` lock query, which (correctly,
for the reserve ceiling check) carries the read-only `$CustomMetadata` FORMULA field
`VS_Walk_In_Reserve_Count__c`. This DE org's anomalous runtime FLS-on-system-mode-DML (D-028 extended to
runtime) treats that formula field as inaccessible for the admin context, so the whole `update session;`
fails even though the only field being *written* is the REQUIRED `VS_Walk_In_Used_Count__c` (always
accessible). The online branch's `update slot;` does not carry a formula field today, but it is given the
same treatment for symmetry / defense-in-depth per D-029.

### The change — ONLY the two counter-PERSIST DML statements (before / after)

**Walk-in branch + online branch persist block, BEFORE:**
```apex
// Counter maintenance runs in system mode by design (D-020) ...
if (updateSession) {
    update session;
} else if (updateSlot) {
    update slot;
}
```

**AFTER:**
```apex
// Counter maintenance runs in system mode by design (D-020) ...
// D-029 ROBUSTNESS: persist via a FRESH minimal sObject carrying ONLY Id + the field(s) WRITTEN ...
if (updateSession) {
    update new VS_Session__c(
        Id = session.Id,
        VS_Walk_In_Used_Count__c = session.VS_Walk_In_Used_Count__c   // = used+1, computed under the lock
    );
} else if (updateSlot) {
    update new VS_Slot__c(
        Id = slot.Id,
        VS_Booked_Count__c = slot.VS_Booked_Count__c,   // = booked+1, computed under the lock
        VS_Status__c = slot.VS_Status__c                // Open | Full, decided under the lock
    );
}
```

Note the persisted VALUES are the ones ALREADY computed under the lock earlier in `book()`
(`session.VS_Walk_In_Used_Count__c` was set to `used + 1` at the reserve check;
`slot.VS_Booked_Count__c` was set to `booked + 1` and `slot.VS_Status__c` flipped to `Full` at the
ceiling). The fresh sObjects simply re-carry those already-mutated in-memory values onto a lean record —
**no re-query, no recompute.** The fresh `VS_Session__c` does NOT carry `VS_Walk_In_Reserve_Count__c`
(the FLS-hidden formula, READ-only in `book()`); the fresh `VS_Slot__c` does NOT carry `VS_Capacity__c`
(READ-only in `book()`). Only the written fields travel.

### Why every §3.4 invariant is preserved (D-019 / D-020 / D-029)
- **The lock SELECT is UNCHANGED** — still a single `SELECT ... FROM VS_Session__c ... FOR UPDATE` that
  still loads `VS_Walk_In_Reserve_Count__c` / `VS_Walk_In_Used_Count__c` for the reserve check. Only the
  UPDATE shape changed.
- **One method / one lock / one write path, all channels** — unchanged; both branches still persist
  inside the same lock.
- **Counter incremented exactly ONCE, from the under-lock value** (`used+1` / `booked+1`) carried on the
  fresh sObject — **NO second SOQL / NO re-query** (which would break FOR UPDATE serialization / open a
  TOCTOU window).
- **Appointment insert stays `insert as user`** (USER_MODE) — untouched.
- **No roll-up / formula / trigger / flow** introduced; persist stays system-mode (the service remains the
  sole trusted counter owner).
- **`VS_Walk_In_Used_Count__c` stays REQUIRED** — no FLS granted, not made optional. The fix works
  precisely BECAUSE required fields are always accessible, so the fresh-sObject DML references only
  accessible fields.
- `book()`'s signature, exception reasons, and the reference-collision regenerate-and-retry-once path are
  all untouched — the ONLY change is the two counter-persist DML statements.

### Tests
No test change was required. `VS_BookingServiceTest` and `VS_BookingServiceWalkInTest` re-query the record
fresh (`reloadSession` / `reloadSlot`) after `book()` and assert on the PERSISTED DB state
(`VS_Walk_In_Used_Count__c`, `VS_Booked_Count__c`, `VS_Status__c`). The fresh-sObject DML persists those
exact same values, so every existing assert holds unchanged — none weakened. The walk-in tests remain
deploy-time un-runnable on this org for the pre-existing D-028 reason (the load test is the runtime proof);
after this fix, dev/devops may re-check whether `VS_BookingServiceWalkInTest` can fold back into
RunSpecifiedTests (not required for the D-029 GO).

### Verification done by me
- Brace/paren balance: 25/25 braces, 106/106 parens (whole class).
- `node scripts/metadata-lint.js`: only the 2 pre-existing `$CustomMetadata` FAILs
  (`VS_Session__c.VS_Walk_In_Reserve_Count__c`, `VS_Setting__mdt.VS_Value__c`) — no new issue; my change
  is Apex-only.
- **NOT deployed / NOT run by me** — devops re-deploys the fixed class to `AgentForceClaudeWorkFlow` and
  re-runs the §3.4 load test (D-029 re-verification bar: TC-002 ×3, TC-003 ×3, regression TC-001 ×3).

### Manual / setup steps (D-029)
- **Pre-deploy:** none.
- **Deploy:** re-deploy `ApexClass:VS_BookingService` to the POC DE org (`AgentForceClaudeWorkFlow` ONLY).
- **Post-deploy:** re-run the §3.4 walk-in + mixed-channel + online regression load test per D-029's
  re-verification bar; record verdicts in `03-qa/test-plan.md` §8 and evidence in `03-qa/evidence/`.
- **Manual-only:** none.
