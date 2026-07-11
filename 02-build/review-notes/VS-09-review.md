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
