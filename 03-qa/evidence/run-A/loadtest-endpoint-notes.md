<!--
feature:         F-001 slot-booking-core
producing-agent: dev-senior
date:            2026-07-12
phase:           QA_IN_PROGRESS
derives-from:    RFP §3.4 (no overbooking under concurrency), VS-09 (VS_BookingService.book),
                 test-plan.md TC-001/TC-002/TC-003, D-019, D-020, D-009, D-028
purpose:         Documents the TEMPORARY VS_LoadTestEndpoint harness for qa/devops (seed math,
                 endpoints, invariant the load driver must assert). NOT part of F-001 product.
-->

# §3.4 Walk-In Load-Test Endpoint — Harness Notes (TEMPORARY)

`VS_LoadTestEndpoint` is a **human-approved, temporary QA harness** that unblocks the RFP §3.4
walk-in concurrency test (TC-002/TC-003) which unit tests and CLI executeAnonymous could not verify
(D-028: anonymous Apex compiles field refs against caller FLS; the admin has no FLS on the VS_
capacity fields, so the CLI burst died at compile before reaching `book()`). A **deployed** class
compiles at deploy time (fields visible) and its system-mode SOQL/DML runs regardless of caller FLS,
so it can seed + invoke `book()` as admin with no harness-user browser session.

**It must be REMOVED from the org after the load test** (see 02-build/deployments.md removal step).
Production code (`VS_BookingService` and every other F-001 class) is UNCHANGED — the endpoint only
orchestrates (seed + call `book()` + read counters).

## Endpoints (base: `/services/apexrest/vsLoadTest`)

| Verb   | Path / params                                   | Returns (JSON) |
|--------|-------------------------------------------------|----------------|
| POST   | `/vsLoadTest/seed?variant=walkin\|online\|disjoint` | `{ sessionId, slotId, variant, slotCapacity, walkInReserve, bookableCapacity }` |
| POST   | `/vsLoadTest/book?slotId=..&channel=online\|walkin` | `{ success, apptId, reason }` |
| GET    | `/vsLoadTest/verify?sessionId=..` (or `?slotId=..`)  | `{ sessionId, apptCount, slotBookedCount, slotCapacity, walkInUsed, walkInReserve, slotStatus, sessionStatus }` |
| DELETE | `/vsLoadTest/reset?sessionId=..`                     | `{ deletedAppts, deletedPatients }` |

- POST routes on the trailing URL segment (`seed` / `book`); an unknown action returns HTTP 400.
- `channel` maps `online -> Portal`, `walkin -> WalkIn` for `VS_BookingService.book()`.
- `book` creates a **fresh `VS_Patient__c` per call** (fictional; 10-digit mobile + synthetic unique
  match key; **NO Aadhaar / no 12-digit identifier anywhere**) so N concurrent calls contend as N
  distinct patients. It **never swallows**: on failure it returns the `VS_BookingException` coded
  reason (`SLOT_FULL`, `WALKIN_RESERVE_FULL`, `SESSION_NOT_OPEN`, ...); an unexpected error returns
  `UNEXPECTED:<type>:<msg>`.

## Seed math — how walk-in reserve == 1 is GUARANTEED

`VS_Session__c.VS_Walk_In_Reserve_Count__c` is a **formula**, not a settable field:

```
VS_Walk_In_Reserve_Count__c = CEILING(VS_Total_Capacity__c * WalkInReservePct / 100)
WalkInReservePct = 25  (VS_Setting__mdt, VS-02 / D-009)
```

The harness sets `VS_Total_Capacity__c = 4`, so:

```
CEILING(4 * 25 / 100) = CEILING(1.0) = 1   -> reserve == 1 EXACTLY
VS_Bookable_Capacity__c = 4 - 1 = 3
VS_Walk_In_Used_Count__c defaults to 0     -> reserve is NOT pre-consumed
```

(Totals 1/2/3 also yield reserve 1; 4 is used so bookable is a non-trivial 3.) Because reserve is a
formula the harness cannot set it directly — it sets Total_Capacity and the platform computes reserve,
then **`seed` and `verify` return the ACTUAL computed `walkInReserve`** so the driver asserts against
the real value, never an assumption.

### Per-variant scenario (slot capacity is set directly by the harness, independent of bookable)

| variant  | slotCapacity | walkInReserve | Contended place(s) | Serves |
|----------|--------------|---------------|--------------------|--------|
| walkin   | 3 (roomy)    | 1             | the single walk-in reserve place | TC-002 last-walk-in-place |
| online   | 1            | 1             | the single online slot place | TC-001 online cap=1 |
| disjoint | 1            | 1             | one online place AND one walk-in place (two disjoint pools) | TC-003 (D-020) |

Prefer **re-seeding a fresh session per repeat** (each `seed` builds a brand-new Facility/Service/
Facility_Service/Session/Slot) over `reset` — simpler and race-safe for the 3 repeats.

## The invariant the load driver MUST assert (per repeat, after the burst quiesces)

Fire N genuinely-concurrent HTTP `book` calls (N ≈ 20), then call `verify` and assert ALL of:

1. **Exactly ONE success per seeded place.**
   - `online` variant: exactly 1 `book` response with `success:true` on the slot's 1 place.
   - `walkin` variant: exactly 1 `book` `success:true` on the reserve's 1 place.
   - `disjoint`: exactly 1 online success AND exactly 1 walk-in success (2 total).
2. **No overbooking (the §3.4 guarantee):**
   - `apptCount == number of successes` (every success created exactly one appointment).
   - `slotBookedCount <= slotCapacity` (online pool never exceeded).
   - `walkInUsed <= walkInReserve` (walk-in pool never exceeded); with reserve==1, `walkInUsed<=1`.
3. **Every rejection is a CODED reason** (`SLOT_FULL` for online, `WALKIN_RESERVE_FULL` for walk-in),
   never a raw exception, DUPLICATE_VALUE, or timeout-only failure.
4. **Pools stay disjoint** (disjoint variant): a walk-in success must NOT increment `slotBookedCount`,
   and an online success must NOT increment `walkInUsed`.

A single extra success, `walkInUsed > walkInReserve`, or `slotBookedCount > slotCapacity` is an
**§3.4 acceptance FAILURE** (overbooking).

## Deploy / removal notes for devops

- Delta = `ApexClass:VS_LoadTestEndpoint`, `ApexClass:VS_LoadTestEndpoint_Test`,
  `PermissionSet:VS_Booking_Engine_Test_Context` (permset gained a `VS_Facility_Service__c` object
  grant + 4 optional-field FLS grants **for the harness test only** — 5 clearly-commented lines).
- **Validate-only dry-run PASSED** against `AgentForceClaudeWorkFlow` (Deploy `0AfgL00000QyzhZSAR`,
  16/16 tests, `VS_LoadTestEndpoint` coverage 87.5%). See VS-09 review packet §load-test-harness.
- After the load test: delete `VS_LoadTestEndpoint` + `VS_LoadTestEndpoint_Test`, and revert the 5
  harness lines in `VS_Booking_Engine_Test_Context` (all marked "Revert ... when the load-test class
  is removed").
- The endpoint needs an authenticated REST session (admin). Grant the load-driver user Apex REST
  access; no VS_ FLS is needed at runtime (system-mode by design).
