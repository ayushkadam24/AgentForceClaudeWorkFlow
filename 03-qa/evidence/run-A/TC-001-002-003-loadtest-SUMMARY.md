<!--
feature:         F-001 slot-booking-core
producing-agent: devops
date:            2026-07-12
phase:           QA_IN_PROGRESS
derives-from:    RFP §3.4, VS-09 (VS_BookingService.book), test-plan TC-001/002/003, D-019/D-020/D-028
purpose:         §3.4 walk-in/online/mixed concurrency LOAD TEST results (crown jewel). Raw per-call
                 evidence in TC-00{1,2,3}-loadtest-run{1,2,3}.json (each holds summary + verify + all calls).
-->

# §3.4 Concurrency Load Test — Results Summary (devops-executed, temporary VS_LoadTestEndpoint harness)

Target org: `AgentForceClaudeWorkFlow` (Developer Edition, D-025). Harness deploy: `0AfgL00000Qz29BSAR`
(REAL, 16/16 tests, VS_LoadTestEndpoint 93%). Driver: `curl` + Bearer session, N calls backgrounded
(`&`) then `wait` — genuine OS-level concurrency (all forked before any returned). Per-call launch/return
epoch-millis + curl `time_starttransfer` captured in each run JSON (`calls[]`).

## Concurrency is GENUINE (proof, TC-001-run1)
25 calls launched within a 698 ms window; **peak 25 requests in-flight simultaneously** (interval-overlap
of every call's [launch,return]). Example: idx1 launch+0ms → return+847ms; idx25 launch+698ms (i.e. idx25
began while idx1 was still in-flight). ttfb 0.6–1.3s, all overlapping. Same pattern every run (peak = N).

## Verdicts

| TC | Variant | N | Repeats | Online succ | Walk-in succ | Overbooking? | Verdict |
|----|---------|---|---------|-------------|--------------|--------------|---------|
| TC-001 | online cap=1 | 25 | 3/3 | **exactly 1** each | n/a | NONE (slotBooked=1≤cap=1) | **PASS** |
| TC-002 | walk-in reserve=1 | 25 | 3/3 | n/a | **0** each | NONE (walkInUsed=0≤reserve=1) | **BLOCKED — walk-in path fails at runtime (D-028); guarantee UNPROVEN, but NO over-reserve** |
| TC-003 | disjoint (1 online + 1 walk-in place) | 26 | 3/3 | **exactly 1** each | 0 each | NONE (slotBooked=1≤1, walkInUsed=0≤1) | **PARTIAL — online + pool-disjointness PROVEN; walk-in success blocked (D-028)** |

### TC-001 (online) — PASS, all 3 repeats identical
25 concurrent `/book?channel=online`. Result each run: **1 `success:true`, 24 `SLOT_FULL`**;
verify `slotBookedCount=1, slotCapacity=1, apptCount=1, slotStatus=Full`. Exactly one success, no
overbooking, every rejection a coded `SLOT_FULL`. RFP §3.4 ONLINE no-overbooking under real concurrency: **PROVEN.**

### TC-002 (walk-in) — BLOCKED (crown jewel could not be positively proven in this org)
25 concurrent `/book?channel=walkin`. Result each run: **0 successes; all 25 fail** with
`UNEXPECTED:System.DmlException: Operation failed due to fields being inaccessible on Sobject VS_Session__c`
at `VS_BookingService.book` line 181 (the system-mode `update session;` that persists
`VS_Walk_In_Used_Count__c`). Verify: `walkInUsed=0, walkInReserve=1` → the walk-in reserve was **never
over-consumed** (0 ≤ 1), so there is NO §3.4 overbooking violation — but exactly-one-success could not be
demonstrated because the walk-in booking cannot COMPLETE in this DE org.

Root cause (reproduced under `sf apex run` too): this DE org anomalously enforces FLS on plain (system-mode)
DML inside the deployed `with sharing` `VS_BookingService` — the SAME D-028 limitation that blocked the
deploy-time walk-in unit tests, now proven to persist at **runtime** (refuting the harness premise that a
deployed system-mode class would sidestep it). The booking LOGIC is provably correct: an inline replica of
book()'s exact walk-in sequence (SELECT…FOR UPDATE with the `$CustomMetadata` formula field + counter update
+ USER_MODE appointment insert) SUCCEEDS in isolation; only the deployed service's `update session`
FLS-fails. Online passes because online never updates the session counter (it writes the plain-Number
`VS_Slot__c.VS_Booked_Count__c`).

Harness artifact (NOT a production bug): `apptCount=25` orphan appointments appear because the harness
`doBook` catches book()'s post-insert exception **without a savepoint**, so the USER_MODE appointment insert
that precedes the failing counter update is not rolled back. In production an uncaught book() failure rolls
back the whole request (atomic) — no orphan, no overbooking. Recorded for completeness; harness is removed.

### TC-003 (disjoint, D-020) — PARTIAL
26 concurrent (13 online + 13 walk-in). Result each run: **1 online `success:true`, 12 `SLOT_FULL`, 13
walk-in DmlException.** Verify: `slotBookedCount=1, slotCapacity=1, walkInUsed=0, walkInReserve=1`,
`apptCount=14` (1 real online + 13 walk-in orphans). The single online success incremented ONLY the slot
pool (slotBookedCount 0→1) and left `walkInUsed=0` — **pools stay disjoint (D-020) PROVEN**; the online
ceiling held at exactly 1. Walk-in success blocked by the same D-028 runtime limitation.

## Bottom line
- §3.4 ONLINE no-overbooking under genuine concurrency: **VERIFIED** (TC-001 ×3, TC-003 online ×3).
- Pool disjointness (D-020): **VERIFIED** (TC-003).
- §3.4 WALK-IN exactly-one-success: **UNPROVEN in this DE org** — blocked by the D-028 runtime FLS-on-
  plain-DML anomaly, not by any code defect and not by any observed overbooking. No repeat produced a second
  success, `walkInUsed>reserve`, or `slotBookedCount>capacity` → **no §3.4 acceptance FAILURE occurred**;
  the crown-jewel walk-in guarantee simply could not be positively demonstrated here. Escalate to human/QA:
  the walk-in guarantee needs proof on a non-anomalous org (real scratch/sandbox) or a dev change to the
  service's counter-persist DML mode (e.g. explicit `AccessLevel.SYSTEM_MODE`) — a dev/architect decision.

---

# D-029 RE-TEST (walk-in fix) — §3.4 NOW FULLY PROVEN (2026-07-12, devops)

D-029 fix (dev-senior): `VS_BookingService.book()` persists counters via FRESH sObjects carrying ONLY the
written field(s) — walk-in `update new VS_Session__c(Id, VS_Walk_In_Used_Count__c)`, online
`update new VS_Slot__c(Id, VS_Booked_Count__c, VS_Status__c)` — so the FLS-hidden `$CustomMetadata` formula
field is no longer dragged into the DML (root cause of the prior runtime DmlException). Lock / single write
path / used+1-under-lock / insert-as-user UNCHANGED. Fix deploy: **`0AfgL00000Qz4PYSAZ`** (checkOnly:false,
VS_BookingService + harness + permset, RunSpecifiedTests **37/37 PASS**, VS_BookingService **95%**).
Evidence: `TC-00{1,2,3}-loadtest-D029-run{1,2,3}.json`. Genuine concurrency: curl burst, peak = N in-flight.

| TC | Variant | N | Repeats | Online succ | Walk-in succ | walkInUsed/reserve | slotBooked/cap | apptCount | Rejections | Verdict |
|----|---------|---|---------|-------------|--------------|--------------------|----------------|-----------|-----------|---------|
| TC-002 | walk-in | 25 | 3/3 | 0 | **exactly 1** each | **1 / 1** | 0 / 3 | 1 | 24× **WALKIN_RESERVE_FULL** (coded, no DmlException) | **PASS ✅ — §3.4 WALK-IN no-overbooking PROVEN** |
| TC-003 | disjoint | 26 | 3/3 | **exactly 1** each | **exactly 1** each | **1 / 1** | **1 / 1** | 2 | 12× WALKIN_RESERVE_FULL + 12× SLOT_FULL | **PASS ✅ — 1 online + 1 walk-in, pools disjoint (D-020)** |
| TC-001 | online | 25 | 3/3 | **exactly 1** each | 0 | 0 / 1 | **1 / 1** | 1 | 24× SLOT_FULL | **PASS ✅ — regression clean** |

**Concurrency genuine (TC-002-D029-run1):** 25 calls launched within 750 ms, **peak 25 in-flight**; idx1
succeeded (launch+0ms → return+933ms) while idx25 launched at +750ms (still in-flight). Every run peak = N.

**§3.4 acceptance:** across all 9 D-029 runs — NO second success, NEVER `walkInUsed>reserve`, NEVER
`slotBookedCount>capacity`; `apptCount` exactly equals the success count every run (D-029 also eliminated the
prior orphan-appointment artifact, because book() no longer throws after the appointment insert). **The RFP
§3.4 no-overbooking guarantee — ONLINE, WALK-IN, and DISJOINT MIXED — is PROVEN under genuine concurrency.**
The earlier TC-002/TC-003 walk-in BLOCK (D-028 runtime FLS on the formula-carrying `update session`) is
RESOLVED by D-029.
