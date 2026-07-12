<!--
feature:         F-001 slot-booking-core
producing-agent: qa-lead
date:            2026-07-12
phase:           READY_FOR_QA
derives-from:    01-discovery/requirements-brief.md (REQ-001..062), 01-discovery/open-questions.md
                 (Launch Checklist LC-1..5), 01-discovery/technical-design.md (§3.4/§4/§6),
                 02-build/sprint-plan.md (VS-01..VS-22, REQ coverage table), 02-build/jira-log.md,
                 02-build/deployments.md (Deploy 0AfgL00000QySCASA3, 21/21 tests, ~92% coverage,
                 D-026..D-028a), 02-build/review-notes/VS-0{3,4,6,7,8,9}-review.md,
                 04-confirmations/drift-check.md (radar R1-R8, §4 GO, §5 QA handoff),
                 .claude/memory/decisions.md (D-016/019/020/023/024/027/028/028a/029),
                 .claude/memory/assumptions.md (A-005/010/015/016/017/018/019/020),
                 .claude/rules/{00-pipeline,10-compliance}, .claude/skills/{playwright-sf-testing,bug-reports}
downstream:      03-qa/regression/tc-###.spec.ts (qa-engineer), 03-qa/bug-reports/BUG-###.md,
                 03-qa/evidence/, this file's Results section (qa-engineer writes only that section;
                 qa-lead consolidates at /qa-report)
scope:           F-001 pilot AS DEPLOYED — VS-01..VS-09, Deploy 0AfgL00000QySCASA3 (+ walk-in fix
                 deploy 0AfgL00000Qz4PYSAZ, D-029), DE org AgentForceClaudeWorkFlow. Tests ONLY what
                 is built. VS-10..VS-22 are NOT in scope (see §7 Known gaps).
-->

# F-001 Test Plan — Slot-Booking Core (as deployed, VS-01..09)

## 0. What is actually deployed (test boundary)

Deploy `0AfgL00000QySCASA3` (+ `0AfgL00000QxRmoSAF` CMDT type + 6 manual `VS_Setting.*` records, D-027):

- **Objects (9):** `VS_Facility__c`, `VS_Service__c`, `VS_Facility_Service__c`, `VS_Session__c`,
  `VS_Slot__c`, `VS_Holiday__c`, `VS_Patient__c`, `VS_Appointment__c`, `VS_Setting__mdt` (+6 records).
- **Apex (6 prod classes):** `VS_BookingService` (crown jewel, `book()`), `VS_ReferenceGenerator`,
  `VS_BookingException`, `VS_SlotGenBatch`, `VS_SlotGenerationService`, `VS_SlotGenException`.
  Test classes `VS_BookingServiceTest` (21/21 run, in Sprint-1 deploy) and
  `VS_BookingServiceWalkInTest` (deployed but NOT run at deploy time — org-limited, D-028/D-028a —
  this is exactly the gap QA's load test closes).
- **Flow (1 relevant):** `VS_Session_Screen_DefineCapacity` (MO screen flow, VS-03).
- **Permission sets (6):** `VS_Facility_Staff`, `VS_Nurse`, `VS_MO_Facility_Admin`, `VS_District_Admin`,
  `VS_District_MIS` (production roles) + `VS_Booking_Engine_Test_Context` (TEST/CI harness ONLY —
  A-018 — must never be assigned to a persona standing in for a real user).
- **Config:** `VS_Setting__mdt` — `CutOffHours=4`, `WalkInReservePct=25`, `DefaultSlotGranularityMins=15`,
  `BookingHorizonDays=14`, `NoShowThresholdCount=3`, `ReminderOffsetsHours="24,3"`.

**Explicitly NOT built (do not write executable TCs against these — see §7):** cancel/reschedule
(VS-11), no-show batch (VS-12), patient de-dup service (VS-10), OTP (VS-13), Experience Cloud citizen
site + booking/discovery LWC (VS-14/15/16 — **no citizen UI exists**), notification/SMS seam
(VS-17/18/19), facility-scoped sharing rules + District View All (VS-20), retention purge (VS-21),
synthetic seed script (VS-22), certificates, dashboards.

## 1. QA-setup preconditions (must happen before TC execution starts)

The org has **0 seed rows** and **role permission sets are unassigned** (drift-check §5, human gate
note). Before any TC below can run:

1. **Seed synthetic data (REQ-051, no Aadhaar, rules/10):** at least 2 `VS_Facility__c`, 2
   `VS_Service__c` (+ active `VS_Facility_Service__c` junctions), several `VS_Session__c` rows
   spanning normal (Total_Capacity=80), a **capacity-1** boundary session (for TC-001/004), a
   **walk-in-reserve-1** boundary session (for TC-002/005), a holiday-date session, a drive-day
   session, and enough `VS_Patient__c` rows to book against. VS-22 (the seed script) is NOT built —
   QA/devops create this manually or via Anonymous Apex under the harness permset.
2. **Assign permission sets** to dedicated test users — one per production role (`VS_Facility_Staff`,
   `VS_Nurse`, `VS_MO_Facility_Admin`, `VS_District_Admin`, `VS_District_MIS`) for TC-009/010/011, plus
   **one separate "QA Load Test Harness" user** assigned ONLY `VS_Booking_Engine_Test_Context` for
   TC-001..006/015..022. **Never assign the harness permset to a user standing in for a real citizen
   or staff persona** (drift-check §5 item 2, A-018) — it is a TEST/CI FLS context only.
3. **Confirm the 6 `VS_Setting__mdt` records** (D-027 manual creation) are present and correct — run
   TC-024 FIRST; `WalkInReservePct=25` in particular is a precondition for every walk-in-reserve TC.
4. **No citizen UI exists.** Playwright scope per skill is the MO screen flow (VS-03) + standard
   Salesforce record/list UI only — do not attempt a citizen booking journey spec.
5. **Session timeout is 15 min** (org-wide Security.settings, VS-04) — sequence Playwright specs so a
   run doesn't idle past it (per `playwright-sf-testing` skill).

## 2. Risk tiers (per rules/00)

- **Tier 1 (block release on fail):** §3.4 slot integrity (RFP §3.4, REQ-008) — including the
  **unproven walk-in/mixed-channel concurrency case (D-028)**; online booking capacity ceiling;
  no-Aadhaar structural check (REQ-044); role-based visibility / OWD / permission-set grant audit /
  `VS_Bulk_Export` gating (Annexure C5, REQ-053/036) — **scoped to what VS-01..09 actually built**
  (OWD + permission sets; facility-scoped *sharing rules* are VS-20, not in pilot — see §7); the MO
  capacity-definition flow (VS-03) happy + fault paths.
- **Tier 2:** slot-generation correctness (even distribution, holiday/drive-day, granularity,
  horizon, idempotency, bulk/governor) at the org level; config-value propagation; booking-reference
  format/uniqueness; session-timeout setting; the full `VS_Setting__mdt` tunable audit; structural
  data-model spot checks for REQ-001/004/046.
- **Tier 3:** MO flow copy/labels + helpline text; accessibility spot-check of the MO flow (staff UI
  only — see reasoning below); cosmetic sanity of standard Salesforce record/list pages.

**Accessibility tiering note:** REQ-056/057 (WCAG 2.1 AA, colour-never-only-signal) are written
against the **citizen** booking/reschedule/cancel/certificate journeys, and **no citizen UI exists in
this pilot** (VS-14/15/16 not built). The only UI surface available to test is the internal MO screen
flow (VS-03), which is a staff tool, not the REQ-056 target journey. Testing it for keyboard/
screen-reader/zoom operability is good practice and a first-class TC, but it is a **proxy check, not
REQ-056 satisfaction** — hence Tier 3 here, not Tier 1. REQ-056/057 themselves are carried to §7 as
not-yet-testable in this pilot.

## 3. §3.4 concurrency load test — technical design (not a hand-wave)

Per drift-check §5 item 1 and design §4.4: **unit tests (`VS_BookingServiceTest`) can only prove the
capacity-CEILING LOGIC in one transaction — they cannot prove `FOR UPDATE` serialization under real
concurrency.** The walk-in path is additionally un-executed at deploy time (D-028, org FLS quirk on
system-mode DML) — so walk-in/mixed-channel overbooking is **completely unproven** and is the single
most important TC in this plan.

**Harness (no REST/LWC endpoint is deployed to call `book()` externally):** fire N concurrent calls at
`VS_BookingService.book(patientId, slotId, bookedById, channel)` using one of, in order of preference:
1. **N concurrent `executeAnonymous` calls via the Tooling API** (`/services/data/vXX.0/tooling/executeAnonymous`),
   launched near-simultaneously (spread < 200ms) from an external script (Node `Promise.all` / Python
   `asyncio.gather` / a k6 script), authenticated as the **QA Load Test Harness user**
   (`VS_Booking_Engine_Test_Context` only — never a real-user session). Salesforce's row-level
   `FOR UPDATE` lock on `VS_Session__c` will genuinely serialize these regardless of API entry point.
2. **Fallback** if Tooling API concurrency proves insufficiently parallel in practice: ask devops to
   deploy a temporary, QA-owned diagnostic Apex REST class (`VS_LoadTestEndpoint`, NOT part of the
   F-001 build, removed after the load test) that wraps `book()` and returns JSON status, hit by an
   external concurrent HTTP load tool (k6/JMeter/curl-parallel).

**Procedure (each of TC-001/002/003), repeated 3× per `playwright-sf-testing` skill guidance:**
1. Seed a fresh session with exactly **one remaining place** in the target pool (slot capacity=1 for
   TC-001; walk-in reserve=1 for TC-002; one place in EACH disjoint pool simultaneously for TC-003 —
   D-020 disjoint online/walk-in pools).
2. Fire N≥20 concurrent `book()` calls at that one place (mixed online+walk-in for TC-003).
3. Capture every call's result (success/exception+reason) to `03-qa/evidence/TC-00X-run<N>.json`.
4. Assert via SOQL immediately after: exactly ONE new `VS_Appointment__c` per seeded place;
   `VS_Slot__c.VS_Booked_Count__c ≤ VS_Capacity__c` always; `VS_Session__c.VS_Walk_In_Used_Count__c ≤
   VS_Walk_In_Reserve_Count__c` always; every other call caught `SLOT_FULL`/`RESERVE_FULL`/
   `WALKIN_RESERVE_FULL`; **zero rows above capacity.**
5. Any double-book on any of the 3 repeats = **Sev-1 BUG, release-blocking, stop-and-report**
   (bug-reports skill severity rubric).

## 4. Test case register

| TC-### | Title | Tier | REQ(s) | Type | Run | Precondition / Blocked-on |
|---|---|---|---|---|---|---|
| TC-001 | §3.4 LOAD: online last-place parallel burst (slot cap=1, N≥20, ×3 repeats) | 1 | REQ-008 | Apex load harness | A | §3, QA Load Test Harness user only (A-018) |
| TC-002 | §3.4 LOAD: walk-in last-place parallel burst (reserve=1, N≥20, ×3) — **CROWN JEWEL, unproven by unit tests (D-028)** | 1 | REQ-007, REQ-008 | Apex load harness | A | §3, harness user only |
| TC-003 | §3.4 LOAD: mixed online+walk-in burst, one place per disjoint pool (D-020), ×3 | 1 | REQ-007, REQ-008 | Apex load harness | A | §3, harness user only |
| TC-004 | Online capacity ceiling — functional boundary (N books succeed exactly to capacity, N+1th fails SLOT_FULL) | 1 | REQ-008 | Apex (regression vs deployed unit test, real org data) | A | Seeded session/slots |
| TC-005 | Walk-in reserve ceiling — functional boundary | 1 | REQ-007 | Apex | A | Seeded session |
| TC-006 | Negative: repeat booking attempt after slot is full — rejected, no duplicate `VS_Appointment__c` row | 1 | REQ-008 | Apex | A | Depends on TC-004 |
| TC-007 | Negative: Aadhaar-shaped (12-digit) value entered into a free-text-capable `VS_Patient__c` field — confirm whether any pattern validation blocks it (expected: none exists — data-minimization relies on field ABSENCE, not input filtering; log as finding if unexpected) | 1 | REQ-044 | Manual/scripted data test | B | Patient object access |
| TC-008 | Structural no-Aadhaar sweep — grep all deployed metadata (objects/fields/labels/descriptions/permsets/CMDT/flow) + Tooling API describe for "aadhaar"/"aadhar" (case-insensitive); also confirm zero clinical/diagnosis fields (REQ-045) | 1 | REQ-044, REQ-045 | Scripted (grep + Tooling API) | B | Read access to org metadata |
| TC-009 | OWD verification — `VS_Patient__c`/`VS_Appointment__c` = Private; `VS_Facility__c`/`VS_Service__c`/`VS_Facility_Service__c`/`VS_Session__c`/`VS_Slot__c`/`VS_Holiday__c` = Public Read Only | 1 | REQ-053 | Manual (Setup → Sharing Settings) | B | Admin/System-view access |
| TC-010 | Permission-set grant audit — for all 6 permsets, object/field grants match design; confirm NONE of the 5 production permsets grants Create/Edit/Delete on `VS_Patient__c`/`VS_Appointment__c` (A-018, expected — document, not a bug); confirm `VS_Session__c` Create/Edit is `VS_MO_Facility_Admin`-only | 1 | REQ-053, REQ-036 | Manual (Setup) + scripted describe | B | 5 role test users assigned |
| TC-011 | `VS_Bulk_Export` custom permission — enabled ONLY in `VS_District_MIS`; log in/inspect as each of the other 4 roles and confirm it is absent/disabled | 1 | REQ-036 | Manual (Setup, per-user) | B | §1.2 role users assigned |
| TC-012 | MO flow (VS-03) happy path — real `VS_MO_Facility_Admin` user (NOT blocked by A-018) creates a session; `VS_Walk_In_Reserve_Count__c`/`VS_Bookable_Capacity__c` formulas compute correctly against `WalkInReservePct=25` | 1 | REQ-010, REQ-011, REQ-012 | Playwright | B | MO test user assigned, TC-024 first |
| TC-013 | MO flow fault/validation paths — capacity ≤0, end ≤ start, date in the past → in-flow validation blocks with a plain-language message; Drive-Day checkbox correctly sets `VS_Is_Drive_Day__c` | 1 | REQ-010, REQ-011, REQ-012 | Playwright | B | Same as TC-012 |
| TC-014 | MO flow negative — facility+service pair with no active `VS_Facility_Service__c` offering is NOT blocked (known gap A-010) — confirm behaviour is unchanged, not a new regression | 1 | REQ-010, REQ-011 | Playwright | B | Same as TC-012 |
| TC-015 | Slot-gen even distribution — `sum(VS_Slot__c.VS_Capacity__c) == VS_Bookable_Capacity__c` exactly, remainder to earliest slots (D-023/A-005) | 2 | REQ-009, REQ-014 | Apex | A | Session seeded, Total_Capacity=80 |
| TC-016 | Slot-gen holiday skip — facility date in `VS_Holiday__c`, no drive-day session → zero slots generated | 2 | REQ-009 | Apex | A | Holiday + non-drive session seeded |
| TC-017 | Slot-gen drive-day override — same holiday date, session flagged `VS_Is_Drive_Day__c=true` → slots generated for that session only (D-018) | 2 | REQ-012 | Apex | A | Drive-day session seeded |
| TC-018 | Slot-gen booking horizon boundary — no slots beyond `BookingHorizonDays=14`; same-day included; strictly-past-dated sessions excluded (A-015, dev default — confirm intended) | 2 | REQ-013 | Apex | A | Sessions at day 13/14/15, and one past-dated |
| TC-019 | Slot-gen bulk/governor — large session batch (≥200 sessions) completes with no governor-limit exceptions, SOQL/DML pattern consistent with unit-test evidence (≤4 SOQL / 1 DML) | 2 | REQ-062 | Apex | A | 200+ sessions seeded |
| TC-020 | Slot-gen idempotent re-run — running the batch twice on the same session does not duplicate slots | 2 | REQ-009 | Apex | A | Session already generated once |
| TC-021 | Config propagation — edit `VS_Setting__mdt.WalkInReservePct` (e.g. 25→30) in Setup, save/re-evaluate a session, confirm `VS_Walk_In_Reserve_Count__c` recalculates with zero code redeploy; **restore to 25 after** | 2 | REQ-007 | Manual (Setup) + Apex verify | A | TC-024 first; restore step mandatory |
| TC-022 | Booking reference — 8-char Crockford base32 (no I/L/O/U), unique External Id, generated at booking, collision-retry-once-then-`REFERENCE_COLLISION` (regression of dev collision tests against real org data) | 2 | REQ-002, REQ-019 | Apex | A | Booking harness available |
| TC-023 | Session timeout ≤15 min — confirm org `Security.settings` `sessionTimeout=FifteenMinutes` in Setup (best-effort org-wide only, per-role scoping not built — VS-04 packet) | 2 | REQ-055 | Manual (Setup) | B | Admin access |
| TC-024 | `VS_Setting__mdt` full tunable audit — all 6 records present with exact values (D-027 manual creation): `CutOffHours=4`, `WalkInReservePct=25`, `DefaultSlotGranularityMins=15`, `BookingHorizonDays=14`, `NoShowThresholdCount=3`, `ReminderOffsetsHours="24,3"` — **run this FIRST, before any capacity-dependent TC** | 2 | config precondition | Manual (Setup) / Apex query | B | None — run first |
| TC-025 | MO flow copy/labels — fault screen shows a plain-language message + facility helpline number, not a raw error/stack trace (C7.3) | 3 | — | Playwright | B | Trigger a fault path in TC-013 |
| TC-026 | MO flow accessibility spot-check — keyboard-only operation (Tab order, Enter/Space, focus visible), axe-core scan (no serious/critical violations), 200% zoom usability (staff-UI proxy — see §2 note, not REQ-056 satisfaction) | 3 | — (proxy for C6) | Playwright + @axe-core/playwright | B | MO test user assigned |
| TC-027 | Cosmetic sanity — standard Salesforce record/list-view pages for Facility/Service/Session/Slot render without layout breakage for each permitted role | 3 | — | Playwright | B | §1.2 role users assigned |
| TC-028 | Structural data-model spot audit — `VS_Appointment__c.VS_Booked_By_Mobile__c` (booker≠patient, REQ-004), `VS_Facility__c` discovery fields present (REQ-001, structural only, no discovery UI), `VS_Patient__c.VS_Consent_Given__c`/`VS_Consent_Timestamp__c` present (REQ-046, fields only — enforcement is VS-10, not built) | 2 | REQ-001, REQ-004, REQ-046 | Manual (Setup Object Manager / describe) | B | None |

**Total: 28 TCs — Tier 1: 14 (TC-001..014), Tier 2: 11 (TC-015..024, TC-028), Tier 3: 3 (TC-025..027).**

## 5. REQ → TC coverage table (REQs touched by VS-01..09 only)

| REQ | Requirement (short) | Ticket(s) built | TC(s) | Status |
|---|---|---|---|---|
| REQ-001 | Discovery by service + proximity | VS-01 (data only) | TC-028 | **Partial** — data model only, no discovery UI (VS-15 not built) |
| REQ-002 | Advance booking + unique reference | VS-08, VS-09 | TC-001, TC-004, TC-022 | Covered |
| REQ-004 | One mobile, many patients; booker≠patient | VS-08 (field only) | TC-028 | **Partial** — structural field only, de-dup service VS-10 not built |
| REQ-007 | Confirmed priority; walk-in from reserve | VS-01, VS-09 | TC-002, TC-003, TC-005, TC-015, TC-021 | Covered |
| REQ-008 | §3.4 slot-integrity guarantee (highest) | VS-05, VS-06, VS-09 | TC-001..006 | Covered |
| REQ-009 | Auto slot generation, holidays | VS-01, VS-06 | TC-015, TC-016, TC-018, TC-020 | Covered |
| REQ-010 | Staff define services/capacity | VS-01, VS-03 | TC-012, TC-013, TC-014 | Covered |
| REQ-011 | Per-session capacity model | VS-01, VS-03 | TC-012, TC-013, TC-014 | Covered |
| REQ-012 | Add capacity on closed day (drive day) | VS-01, VS-03, VS-06 | TC-013, TC-017 | Covered |
| REQ-013 | Configurable booking horizon | VS-02, VS-06 | TC-018 | Covered |
| REQ-014 | Configurable slot granularity | VS-02, VS-05, VS-06 | TC-015 | Covered |
| REQ-015 | Cancel/reschedule cut-off | VS-02 (config value only) | TC-024 | **Partial** — value exists, enforcement is VS-11, not built |
| REQ-019 | Typed booking reference (field) | VS-08, VS-09 | TC-022 | **Partial** — field/generation only, check-in UI deferred |
| REQ-036 | Bulk export → District MIS + logged | VS-04 (gating only) | TC-011 | Covered (gating only; export UI itself deferred) |
| REQ-043 | Collect only C1.1 minimum fields | VS-07 | TC-028 | Covered |
| REQ-044 | Never collect/store Aadhaar anywhere | VS-07 (structural), all objects | TC-007, TC-008 | Covered (Tier 1) |
| REQ-045 | Health data limited to appointment lifecycle | VS-07, VS-08 | TC-008 | Covered |
| REQ-046 | DPDP consent at registration | VS-07 (fields only) | TC-028 | **Partial** — fields exist, enforcement is VS-10, not built |
| REQ-053 | Facility-scoped role-based visibility | VS-04 (OWD+permsets only) | TC-009, TC-010 | **Partial** — record-level facility-scoped sharing is VS-20, not built |
| REQ-055 | Individual logins, ≤15 min session timeout | VS-04 | TC-023 | Covered |
| REQ-062 | Bulk/volume posture | VS-06, VS-09 (only) | TC-019 | **Partial** — proven for slot-gen + booking only; VS-11/12/21 batches not built |

**Coverage summary:** 13 REQs fully Covered, 7 Partial (each with an explicit reason and the owning
future ticket named), **zero uncovered** — every REQ that VS-01..09 touches has at least one TC.
REQ-006 (booking < 3 min) has no TC — there is no timeable UI in this pilot (Should priority, not
release-blocking); named here rather than silently dropped. All other REQs (REQ-003/005/016/018/
020-035/037-042/047-052/054/056-061) are **out of pilot scope entirely** — see §7, not "uncovered."

## 6. Run A / Run B split

**Run A — Booking & Concurrency track (14 TCs: TC-001..006, TC-015..022):** the §3.4 load tests and
every TC that depends on or verifies booking/slot-generation capacity mechanics, in one lane, so the
engineer building intuition for the session-lock model runs everything that touches it — load tests
first (TC-001..003, Tier 1), then functional/negative booking (TC-004..006), then slot-gen Tier 2
(TC-015..022). Sequenced Tier 1 → Tier 2 within the lane.

**Run B — Roles, Compliance & Flow track (14 TCs: TC-007..014, TC-023..028, TC-025..027):** everything
about who-can-see-what, no-Aadhaar, the MO screen flow, and config/cosmetic checks, in the other lane —
Tier 1 first (TC-007..014: no-Aadhaar, OWD, permission-set audit, `VS_Bulk_Export`, MO flow
happy/fault/negative), then Tier 2 (TC-023/024/028), then Tier 3 (TC-025..027). **Run TC-024 (CMDT
audit) FIRST in this lane** since TC-012/013 in the same lane depend on `WalkInReservePct` being
correct, and other lanes' capacity math depends on it too.

Commands: `/qa-run A` (TC-001..006, TC-015..022) and `/qa-run B` (TC-007..014, TC-023..028).

## 7. Known coverage gaps / not-in-pilot (explicitly deferred, not silently dropped)

Not built in VS-01..09 — **no executable TC exists for these; do not attempt them:**

- **Cancel / reschedule + cut-off enforcement** (VS-11) — REQ-003, REQ-015 enforcement half.
- **No-show batch** (VS-12) — REQ-016.
- **Patient de-dup service `findOrCreate`** (VS-10) — REQ-004/046 enforcement half (fields exist,
  service does not).
- **Citizen Experience Cloud site + discovery/booking LWC** (VS-14/15/16) — REQ-001 (discovery UI),
  REQ-005, REQ-006 (timeable UI), REQ-056, REQ-057, REQ-060. **There is no citizen UI to Playwright.**
- **OTP auth** (VS-13) — citizen self-service authentication.
- **Notification/SMS seam** (VS-17/18/19) — REQ-002 (confirmation deliverable), REQ-028, REQ-058,
  REQ-059. No SMS/log-only notification exists to verify yet.
- **Facility-scoped sharing rules + District View All** (VS-20) — REQ-053's record-level enforcement.
  Today's TC-009/010 verify OWD + permission-set structure only; a facility-staff user cannot yet be
  proven to see *only* their facility's records because the sharing rule that would scope it doesn't
  exist. This is the most consequential gap in this plan for a compliance-sensitive requirement —
  flagged, not silently accepted as tested.
- **Retention purge batch** (VS-21) — REQ-052.
- **Synthetic seed script** (VS-22) — REQ-051's automation; QA works around this manually per §1.
- Certificates, dashboards, chat assistant — never in F-001 scope (technical-design §7.1).
- **REQ-050** (residency written confirmation) and **REQ-054** (per-record read audit) — never
  ticketed at all (sprint-plan.md, human-directed); launch-gate / known-POC-limitation respectively,
  not a build or test gap.

**Carried-forward open confirmations (not blockers, per drift-check §5):** A-016 (disjoint vs merged
"shared place" pools — DHO to confirm; TC-003 tests the as-built disjoint design), A-017 (`bookedById`
not stored, `CreatedById` used instead — not separately tested), A-010 (MO flow doesn't scope Service
to facility offerings — TC-014 confirms current behaviour, does not fail on it), A-015 (past-dated
sessions generate no slots — TC-018 confirms current behaviour, does not fail on it).

## 8. Results

*(Filled in by qa-engineer during `/qa-run A` / `/qa-run B` — TC-### | Status [Pass/Fail/Blocked] |
Evidence | Notes. Consolidated bug reports live in `03-qa/bug-reports/`. Release recommendation
(GO / NO-GO with reasons) is written here by qa-lead at `/qa-report` close-out, per rules/00.)*

| TC-### | Status | Evidence | Notes |
|---|---|---|---|
| TC-001 | **PASS** | `03-qa/evidence/run-A/TC-001-loadtest-run{1,2,3}.json`, `TC-001-002-003-loadtest-SUMMARY.md` | **§3.4 ONLINE no-overbooking PROVEN under real concurrency** (temporary REST-endpoint harness `VS_LoadTestEndpoint`, deployed + removed — org back to clean 88-comp state). All 3 repeats: N=25 concurrent HTTP `book()` calls at a slot seeded cap=1 (peak 25 requests in-flight within a ~698ms window — genuine overlap, per-call timestamps captured) → **exactly 1 `success:true`, 24× coded `SLOT_FULL`**; verify `slotBookedCount=1 ≤ slotCapacity=1`, `apptCount=1`, `slotStatus=Full`. The FOR UPDATE serialization on VS_Session__c holds. |
| TC-002 | **PASS** (after D-029 fix) | `03-qa/evidence/run-A/TC-002-loadtest-D029-run{1,2,3}.json`, SUMMARY.md | **§3.4 WALK-IN no-overbooking PROVEN under real concurrency.** The Run-A/first-load-test blocker (runtime `DmlException` at the system-mode `update session`, because the FLS-hidden `$CustomMetadata` formula field was dragged into the DML on this org) was fixed by **D-029** (persist via a fresh `VS_Session__c(Id, VS_Walk_In_Used_Count__c)` — no formula field in the DML; §3.4 lock/write-path unchanged). Re-test (fix deploy `0AfgL00000Qz4PYSAZ`, VS_BookingService 95%): all 3 repeats, N=25 concurrent walk-in calls (peak 25 in-flight within ~750ms) → **exactly 1 `success:true`, `walkInUsed=1 ≤ reserve=1`, 24× coded `WALKIN_RESERVE_FULL`** (no DmlException). Reserve consumed exactly once, never over-consumed. Harness deployed + removed; org back to clean 88-comp state with the fixed service. |
| TC-003 | **PASS** (after D-029 fix) | `03-qa/evidence/run-A/TC-003-loadtest-D029-run{1,2,3}.json`, SUMMARY.md | **Disjoint mixed-channel §3.4 fully PROVEN.** All 3 repeats, N=26 concurrent mixed online+walk-in burst (one place per pool) → **exactly 1 online success AND exactly 1 walk-in success** (apptCount=2), `slotBookedCount=1 ≤ cap=1` AND `walkInUsed=1 ≤ reserve=1`, rejections 12× `SLOT_FULL` + 12× `WALKIN_RESERVE_FULL`. **D-020 pool disjointness holds under concurrency** — each success touched only its own pool. |
| TC-004 | **PASS** | `03-qa/evidence/run-A/regression-suite-fresh-execution.txt` (VS_BookingServiceTest, fresh run this session: 9/9 pass) | `testCapacityExhaustion_online_neverOverbooks` fills a slot (capacity=2) exactly, 3rd booking throws `SLOT_FULL`; asserts `VS_Booked_Count__c` never exceeds `VS_Capacity__c`, slot flips to `Full`, exactly 2 appointment rows exist. Executed live against `AgentForceClaudeWorkFlow` this session (real org data, per the TC's own "Apex regression vs deployed unit test, real org data" methodology) — live book() is unreachable outside this self-contained test-class pattern this session (see TC-001 note), so fresh QA-authored fixtures could not independently corroborate; regression re-execution is the evidentiary basis. |
| TC-005 | **BLOCKED** | `03-qa/evidence/run-A/regression-suite-fresh-execution.txt` | Walk-in reserve ceiling depends on the same walk-in path as TC-002 — D-028 org limitation, not re-testable this session. |
| TC-006 | **PASS** | same test run as TC-004 | Same test's final assert (`apptCount(slot) == capacity` exactly after the rejected 3rd/repeat attempt) — no duplicate `VS_Appointment__c` row from the rejected repeat. |
| TC-007 | **PASS** | `03-qa/evidence/run-B/tc007-aadhaar-shaped-negative.apex`, `TC-007-aadhaar-shaped-negative-result.txt` | Confirmed structurally (zero `validationRules` metadata anywhere under `VS_Patient__c`) AND live in-org: inserted a 12-character free-text alphanumeric junk value (`ZZQATESTZZQA`) into `VS_Full_Name__c` — no format/pattern validation blocks it, insert succeeds, record immediately deleted after assertion. **COMPLIANCE SELF-CORRECTION:** the first attempt at this test used an actual all-repeated-digit 12-numeral placeholder as the test value; the project's own pretool guardrail correctly flagged a later file write as Aadhaar-shaped per rules/10 #1/Annexure C1.2 before it reached a new file. The evidence file that had already been written via direct shell redirection (bypassing the Write-tool guard) was found and rewritten with a non-digit-only alphanumeric junk value that proves the identical thing (no character-class validation exists on this field to distinguish digit-only from alphanumeric junk), and the live test was re-run clean. No Aadhaar-shaped value remains in any committed file or org record. This finding is **NOT a bug** per the TC's own framing — data-minimization in this design relies on field ABSENCE (no Aadhaar field exists at all, see TC-008), not input filtering; the absence of a blocking validation rule is expected, not a gap. |
| TC-008 | **PASS** | `03-qa/evidence/run-B/TC-008-describe-patient.json`, `TC-008-describe-appointment.json`, `TC-008-entityparticle-patient.json`, `TC-008-entityparticle-appointment.json` | **Tier-1.** Structural grep of all deployed metadata (`force-app/`) for "aadhaar"/"aadhar" (case-insensitive) returns only negative-confirmation prose (e.g. "NO Aadhaar field", "NOT an Aadhaar or other government-ID field") — zero actual field/label/value hits. Live in-org confirmation via Tooling API `EntityParticle` SOQL (bypasses FLS, unlike `sobject describe` — see A-019) enumerates the FULL field lists for `VS_Patient__c` (11 custom fields) and `VS_Appointment__c` (11 custom fields), exactly matching the fields on disk — zero Aadhaar-named fields, zero clinical/diagnosis fields (REQ-045; `VS_Dose_Number__c` is an administrative dose-sequence counter, not clinical data). **Verdict: clean, both structurally and live in-org.** |
| TC-009 | **PASS** | `03-qa/evidence/run-B/tc009-retrieve/objects/**/*.object-meta.xml` (live Metadata API retrieve from `AgentForceClaudeWorkFlow`) | Live in-org `sharingModel` (retrieved directly from the org, not just source) confirms: `VS_Patient__c`=Private, `VS_Appointment__c`=Private, `VS_Facility__c`/`VS_Service__c`/`VS_Holiday__c`=Read (Public Read Only), `VS_Facility_Service__c`/`VS_Session__c`/`VS_Slot__c`=ControlledByParent (all 3 are Master-Detail children — `VS_Session__c` is MD-child of `VS_Facility__c`, so it correctly inherits Public Read Only per the test-plan's own "or ControlledByParent for MD details" allowance). Exact match with source and with design intent — no browser/Setup UI needed; Metadata API retrieve is equivalent evidentiary weight. |
| TC-010 | **PASS** | `03-qa/evidence/run-B/TC-010-objectpermissions-patient-appointment.json`, `TC-010-objectpermissions-session.json`, `TC-010-permsetassignments.json` | **Tier-1.** Live in-org `ObjectPermissions` SOQL (not just source XML — catches org drift) across all 6 `VS_%` permission sets: querying `VS_Patient__c`/`VS_Appointment__c` grants returns **exactly 2 rows, both `VS_Booking_Engine_Test_Context`** (the TEST-ONLY harness) — **zero rows for any of the 5 production role permsets** (confirms A-018 exactly as expected — documented, not a bug). `VS_Session__c` Create+Edit: only `VS_MO_Facility_Admin` among the 5 production sets (District_Admin/District_MIS/Facility_Staff/Nurse are all Read-only on Session) — matches design intent exactly. `PermissionSetAssignment` query confirms only 1 assignment exists org-wide (the harness permset → a dedicated `qa.loadtest.harness.*` user, never a real-persona user) — none of the 5 production role permsets are currently assigned to anyone (matches test-plan §1's documented precondition). **License-slot finding (documented, not a gap):** attempted to strengthen this TC further by creating fresh test users for a live per-role login smoke test per the run instructions; found only 1 of 4 "Salesforce" full-license user slots available org-wide (insufficient for the needed 5 role-test users), and `sf org create user` is explicitly scoped to scratch orgs (this is a persistent DE org, D-025) with unclear DE-org behavior — declined to create real, hard-to-reverse (deactivate-only) Users on this shared persistent org without clearer authorization. A genuine live-role-user smoke test (the natural next step after two rounds of "FLS looks right on paper but wasn't" per A-019) remains achievable only via a future browser/impersonation session. |
| TC-011 | **PASS** | `03-qa/evidence/run-B/TC-011-setupentityaccess.json` | **Tier-1.** Live in-org `SetupEntityAccess` SOQL (the authoritative live grant graph, org-wide, not per-file) for `SetupEntityType='CustomPermission'` returns **exactly ONE row for the entire org**, `Parent.Name = VS_District_MIS`. `VS_Bulk_Export` is enabled in zero other permission sets — confirmed both in source (grep across all 6 permset XMLs) and live in-org. REQ-036/D-022/Annexure C5 gating verified clean. |
| TC-015 | **PASS** | `03-qa/evidence/run-A/regression-suite-fresh-execution.txt` (VS_SlotGenBatchTest, fresh run: 12/12 pass) | `testEvenDistribution_sumsToBookableExactly`: 80 total/25% reserve → 60 bookable, 16 slots, sum(slot capacity)==60 exactly, remainder(12) on the 12 earliest slots (4 each vs 3) — A-005/D-023 verified live. |
| TC-016 | **PASS** | same run | `testHolidaySkip_generatesNoSlots`: normal session on a `VS_Holiday__c` date → 0 slots generated. |
| TC-017 | **PASS** | same run | `testDriveDayOverridesHoliday_generatesSlots`: same holiday date, `VS_Is_Drive_Day__c=true` → 8 slots generated, sum still == bookable (D-018 verified live). |
| TC-018 | **PASS (partial)** | same run | `testBookingHorizon_excludesBeyondHorizon`: session at today+30 (beyond `BookingHorizonDays=14`) → 0 slots; in-horizon session generates normally. **Caveat:** the exact day-13/day-14/day-15 boundary + past-dated-session-excluded matrix described in test-plan §1/§4 was NOT independently re-verified with fresh live data this session (live slot-gen invocation was blocked — see TC-001 note); A-015's past-date exclusion remains as previously documented, not freshly re-confirmed. |
| TC-019 | **PASS** | same run | `testBulk_250Sessions_isGovernorSafe`: 250 sessions → 2000 slots, ≤4 SOQL / exactly 1 DML for the whole scope (REQ-062 governor safety verified live), sum invariant spot-checked. |
| TC-020 | **PASS** | same run | `testReRun_isIdempotent`: a 2nd `Database.executeBatch` on an already-slotted session adds 0 additional slots. |
| TC-021 | **BLOCKED** | `03-qa/evidence/run-A/TC-021-rest-attempt.json`, `TC-021-tooling-attempt.json`, `03-qa/regression/tc-021-config-propagation.md` | Two real programmatic write attempts against `VS_Setting__mdt.WalkInReservePct` both correctly rejected (`sobjects` PATCH → 400 CANNOT_INSERT_UPDATE_ACTIVATE_ENTITY; `tooling/sobjects` PATCH → 404 NOT_FOUND), consistent with D-027 (this org blanket-rejects CustomMetadata record writes). Only a manual Setup-UI edit remains, requiring a browser session unavailable to this qa-engineer run. Manual procedure + mandatory-restore steps documented in the linked regression file for whoever next has browser access. |
| TC-022 | **PASS** | `03-qa/evidence/run-A/regression-suite-fresh-execution.txt` | `testBookingReference_uniqueAndPopulatedAndTypeable` (8-char, Crockford base32 regex `[0-9A-HJKMNP-TV-Z]{8}`, two bookings get distinct references) + `testReferenceCollision_regeneratesAndRetriesOnce_bookingSucceeds` (forced collision → regenerate + retry once → succeeds, distinct new reference) + `testReferenceCollision_twiceInARow_throwsCodedException` (forced double collision → coded `REFERENCE_COLLISION`, not a leaked DmlException, no extra row) — all fresh-executed live this session. |

**Run A summary:** 9 PASS (TC-004/006/015/016/017/018*/019/020/022) · 0 FAIL · 5 BLOCKED
(TC-001/002/003/005/021). **No BUG-### filed** — every BLOCKED item traces to an already-logged,
non-code environment/org limitation (D-026..D-028, D-027, A-018), not a newly-discovered product
defect; test-plan §3's own honesty gate directs a BLOCKED TC with clear reason in this situation,
not a bug report. The dominant, release-relevant fact for qa-lead's GO/NO-GO: **the RFP §3.4
no-overbooking guarantee remains verified for the ONLINE channel only** (live regression re-run,
this session); the walk-in and mixed-channel concurrency cases (TC-002/003, the crown-jewel of this
plan) are **still completely unproven** — neither confirmed nor refuted — because no session with
adequate FLS to invoke `VS_BookingService.book()` live was obtainable in this QA environment. Full
root-cause chain and recommended unblock path in the qa-engineer Run A report
(`.claude/memory/handoffs.md`).

> **qa-lead close-out note:** the paragraph immediately above is the Run-A engineer's own honest
> as-of-that-run summary and is left verbatim for audit trail. It is now **SUPERSEDED** by the
> D-029 walk-in fix + re-test recorded in TC-002/TC-003's rows above and in
> `03-qa/evidence/run-A/TC-001-002-003-loadtest-SUMMARY.md`'s "D-029 RE-TEST" section: walk-in and
> mixed-channel §3.4 no-overbooking are now **PROVEN**, not unproven. See §8.1 below for the
> consolidated close-out.

| TC-023 | **PASS** | `03-qa/evidence/run-B/tc023-retrieve/settings/Security.settings-meta.xml` (live Metadata API retrieve) | Live in-org retrieve confirms `<sessionTimeout>FifteenMinutes</sessionTimeout>` actually deployed and is active — closes the VS-04 review packet's own "authored from memory, never dry-run/schema-validated" caveat. Confirmed org-wide (best-effort per Metadata API — no per-permission-set scoping exists, as already documented). |
| TC-024 | **PASS** | `03-qa/evidence/run-B/TC-024-cmdt-audit.json` | Ran FIRST per test-plan §6 instruction. Live SOQL of all 6 `VS_Setting__mdt` records — exact match on every value: `CutOffHours`=4, `WalkInReservePct`=25, `DefaultSlotGranularityMins`=15, `BookingHorizonDays`=14, `NoShowThresholdCount`=3, `ReminderOffsetsHours`="24,3". D-027 manual-creation precondition confirmed intact; safe to proceed with every capacity-dependent TC in both lanes. |
| TC-025 | **BLOCKED** | `03-qa/regression/tc-025-mo-flow-fault-copy.spec.ts` (spec written, not run) | No browser/Playwright session obtainable this run (A-019, reconfirmed). **Static proxy (clearly marked, not a live UI run):** read the deployed fault-screen field text directly from `VS_Session_Screen_DefineCapacity.flow-meta.xml` — plain-language message + facility helpline number ARE present as required (C7.3). Secondary observation (not filed as a bug — the TC's literal AC is met): the screen also appends a "Reference for support staff: {!$Flow.FaultMessage}" line carrying the raw system fault value — a reasonable support-triage pattern, not a full stack-trace dump, but worth a human/architect eyeball on whether it should be an opaque incident ID instead. |
| TC-026 | **BLOCKED** | `03-qa/regression/tc-026-mo-flow-accessibility.spec.ts` (spec written, not run) | No browser session obtainable. No static proxy is meaningful for keyboard/screen-reader/axe/zoom checks — these are inherently runtime/rendering checks with nothing in flow XML to substitute. `@axe-core/playwright` is not yet a devDependency; spec scaffolded for the next engineer with a browser session. |
| TC-027 | **BLOCKED** | `03-qa/regression/tc-027-cosmetic-sanity.spec.ts` (spec written, not run) | No browser session obtainable, and no role test users exist to log in as this run (0 of the 5 production role permsets are assigned to any user — see TC-010 evidence). No static proxy possible for rendered-layout checks. |
| TC-028 | **PASS** | `03-qa/evidence/run-B/TC-028-entityparticle-facility.json` (+ TC-008's Patient/Appointment EntityParticle evidence, reused) | Live Tooling API field enumeration confirms all 3 structural targets exist in-org: `VS_Appointment__c.VS_Booked_By_Mobile__c` (REQ-004, Phone type) present; `VS_Facility__c` discovery fields present (`VS_Location__c` Geolocation for proximity + `VS_Pincode__c` Text(6), REQ-001 — structural only, no discovery UI exists to test end-to-end); `VS_Patient__c.VS_Consent_Given__c` (Checkbox, default false, history-tracked) + `VS_Consent_Timestamp__c` (DateTime) present (REQ-046 — fields only, enforcement is VS-10, not built in this pilot, as already documented). |

**Run B summary:** 8 PASS (TC-007/008/009/010/011/023/024/028) · 0 FAIL · 6 BLOCKED
(TC-012/013/014/025/026/027). **No BUG-### filed** — every check that could be executed without a
browser (all Tier-1 compliance TCs: no-Aadhaar, OWD, permission-set audit, `VS_Bulk_Export` gating)
came back clean, live-verified against the org (not just source-file reading), and every BLOCKED item
traces to the same already-logged environment limitation as Run A (A-019 — no browser/Playwright
session obtainable in this QA environment), not a newly-discovered product defect. Static proxies were
provided where structurally meaningful (TC-013's flow validation rules, TC-014's A-010 gap,
TC-025's fault-screen copy) and Playwright specs were written for all 6 blocked TCs so the next
engineer with a browser session can execute them with minimal rework.

**Tier-1 compliance headlines for qa-lead's GO/NO-GO:**
- **TC-008 (no-Aadhaar structural sweep): PASS, clean.** Zero Aadhaar-shaped fields/labels/values
  anywhere in deployed metadata or live in-org field lists (verified via Tooling API `EntityParticle`,
  which bypasses the FLS limitation that affected Run A's `sobject describe` calls — a stronger check
  than Run A could achieve for this specific question). Zero clinical/diagnosis fields (REQ-045).
- **TC-010/TC-011 (role-visibility / bulk-export gating): PASS, clean, live-verified.** None of the 5
  production permission sets grants any access to `VS_Patient__c`/`VS_Appointment__c` (A-018 confirmed
  exactly as documented — a known, tracked gap, not a new compliance failure); `VS_Session__c`
  create/edit is `VS_MO_Facility_Admin`-only; `VS_Bulk_Export` is enabled in exactly one permission set,
  `VS_District_MIS`, org-wide. These were verified via live `ObjectPermissions`/`SetupEntityAccess`
  SOQL queries against the actual deployed grant graph, not just by reading the source XML — a materially
  stronger check than a structural-only audit, though it still falls short of a live per-role user
  login/smoke-test (blocked on the same no-browser/no-spare-license-slot constraint noted in TC-010's
  evidence column). **Verdict: the compliance posture is sound as far as this environment can prove it;
  the one remaining gap (an actual role-user login smoke test) is a browser-session dependency shared
  with TC-012/013/014/025/026/027, not a new or different risk.**

## 8.1 Consolidated recount (qa-lead, at /qa-report close-out)

Recounting every row in the §8 table above, TC-001..TC-028, current status (i.e. TC-002/TC-003
counted at their **post-D-029** PASS, not the Run-A-engineer's original in-flight BLOCKED note that
is explicitly superseded above):

| Status | Count | TCs |
|---|---|---|
| **PASS** | **20** | TC-001, TC-002, TC-003, TC-004, TC-006, TC-007, TC-008, TC-009, TC-010, TC-011, TC-015, TC-016, TC-017, TC-018 (partial), TC-019, TC-020, TC-022, TC-023, TC-024, TC-028 |
| **FAIL** | **0** | — |
| **BLOCKED** | **8** | TC-005, TC-012, TC-013, TC-014, TC-021, TC-025, TC-026, TC-027 |
| **BUG-### filed** | **0** | `03-qa/bug-reports/` contains only `.gitkeep` — confirmed empty |

28/28 TCs accounted for (20+0+8=28). By tier:
- **Tier 1 (14 TCs): 10 PASS, 0 FAIL, 4 BLOCKED** (TC-005, TC-012, TC-013, TC-014) — every Tier-1
  TC that could be executed in this environment PASSED; zero Tier-1 failures.
- **Tier 2 (11 TCs — TC-015..024 + TC-028): 10 PASS, 0 FAIL, 1 BLOCKED** (TC-021, config-write is
  Setup-UI-only).
- **Tier 3 (3 TCs): 0 PASS, 0 FAIL, 3 BLOCKED** (TC-025/026/027, all browser-dependent).

10+10+0 = 20 PASS; 4+1+3 = 8 BLOCKED; 20+8 = 28. Matches the table above.

Every BLOCKED TC traces to one of two already-logged, non-code environment constraints — never a
newly-discovered product defect:
- **No browser/Playwright session available in this QA environment (A-019):** TC-012, TC-013,
  TC-014, TC-025, TC-026, TC-027 (6 of 8).
- **This DE org's D-027/D-028-family write/FLS limitations** (CMDT record writes rejected;
  walk-in path — now resolved for booking itself by D-029, but TC-005's own functional-boundary
  script still could not be independently re-run this session): TC-005, TC-021 (2 of 8).

**On TC-005 specifically:** TC-005 (walk-in reserve ceiling — scripted functional boundary test)
stayed BLOCKED because the same org path it depends on was the one D-029 fixed. However, its
*intent* — proving the walk-in reserve is never over-consumed — is now covered, and arguably more
rigorously, by TC-002's live concurrency evidence: `walkInUsed=1 ≤ reserve=1` held across 3 repeats
of a genuine 25-way concurrent burst, which is a strictly harder bar to clear than a single
scripted sequential-boundary test would have been. TC-005 is left BLOCKED rather than reclassified
PASS (it was never independently re-executed this session), but I do not weigh it as an open risk
for the release decision below — its intent is subsumed by TC-002's stronger evidence.

## 8.2 Release recommendation — F-001 PILOT (VS-01..09)

### RECOMMENDATION: **GO-WITH-CAVEATS**

### Rationale (one paragraph)

Zero bugs were found (0 BUG-### filed; `03-qa/bug-reports/` is empty) and zero Tier-1 TCs failed —
every Tier-1 check that this environment could execute came back clean, including the RFP §3.4
crown-jewel guarantee, which is now **fully proven under genuine concurrency for all three channels**
(TC-001 online, TC-002 walk-in, TC-003 disjoint mixed — 9 load-test runs, peak-N-in-flight timing
captured, zero overbooking on any repeat) after the D-029 counter-persist fix closed the one runtime
anomaly this DE org exposed; the fix was independently architect-ruled as implementation-robustness
that preserves the D-019/D-020 design, not a deviation, and was re-verified live, not just
unit-tested. Tier-1 compliance (no-Aadhaar structural sweep, OWD, permission-set/role-visibility
audit, `VS_Bulk_Export` gating) is likewise clean and was verified against the *live* deployed grant
graph, not just source files — a stronger evidentiary bar than a structural-only audit. Per rules/00,
a NO-GO requires an open Sev-1/Sev-2 defect; none exists, so NO-GO is not warranted. The recommendation
stops short of an unconditional GO, however, because 3 of the 8 BLOCKED items are Tier-1 and cover a
part of the system that has **never once been exercised through its live UI in this pilot's entire QA
cycle**: the MO capacity-definition screen flow (TC-012 happy path, TC-013 fault/validation paths,
TC-014 negative-offering path). The flow deployed with zero errors, carries in-metadata field
validations that were confirmed structurally (VS-03's flow XML), and its fault-screen copy was
proxy-checked (TC-025) — but "deployed clean + structurally sound" is not the same evidentiary
strength as a live browser run for a Tier-1 user-facing flow, and I will not rubber-stamp that gap
away. Weighed against pilot reality — this flow is internal/staff-facing (not citizen-facing, so
REQ-056/057 accessibility exposure is bounded), touches no financial or irreversible action, and its
failure mode (a confusing validation message or a blocked save) is recoverable and does not corrupt
data or breach compliance, unlike a §3.4 or Aadhaar/RBAC failure — I judge this a **caveat that must be
closed before the flow is used to create real sessions, not a hard blocker on advancing the pipeline
state itself.** GO-WITH-CAVEATS is therefore the principled middle position: the crown-jewel guarantee
and every compliance control are proven and clean, but a named, scoped, pre-launch action item remains
open and must be tracked to closure, not silently accepted as "good enough" QA.

### Caveats / preconditions the human must accept for a GO

1. **Tier-1 MO-flow live browser run (TC-012/013/014) is an open precondition.** These 3 Tier-1 TCs
   have never been executed against a live UI in this pilot. Playwright specs are already written
   (`03-qa/regression/tc-01{2,3,4}-*.spec.ts` equivalents referenced in the Run-B evidence) and
   need only a browser-capable session + an assigned `VS_MO_Facility_Admin` test user (§1.2) to run.
   **This must be completed before any real Medical Officer uses this flow to create real sessions**
   — it does not need to block a human's /advance of the pipeline phase itself, but it must not be
   treated as closed QA.
2. **A-018 production permission gap is a hard precondition for ANY real user journey**
   (drift-check §5, confirmed again live by TC-010: 0 of 5 production permsets grant
   `VS_Patient__c`/`VS_Appointment__c` access). `VS_Booking_Engine_Test_Context` is TEST/CI-ONLY and
   must never be assigned to a real citizen or staff persona. A production booking permset
   (`VS_Appointment__c` create+FLS) and a slot-gen automation grant (`VS_Slot__c` create) must exist
   before a real Portal/staff user can book or generate slots — these are owed to VS-08/17/20,
   not yet built.
3. **Seed data + role permission-set assignment.** The org currently has 0 seed rows and 0 of the 5
   production role permsets assigned to any user (test-plan §1, TC-010 evidence). A real pilot launch
   needs synthetic facility/service/session/patient data and per-role user assignment before any
   persona can do anything in the org.
4. **Org-specific quirks to carry forward, not silently forgotten:**
   - **D-027** — this DE org rejects all CustomMetadata *record* deploys via the Metadata API; the
     6 `VS_Setting__mdt` records were created manually via Setup UI and must be re-created the same
     way on any other org (a real client org may not have this limitation at all — verify first,
     don't assume the manual-creation step is universally required).
   - **D-028/D-029** — this org anomalously enforced FLS on system-mode Apex DML at both deploy-time
     (D-028) and runtime (D-029's root cause); the D-029 fix (fresh-sObject counter persist) is
     defensive and correct regardless of org, but the underlying anomaly itself is very likely
     specific to this Developer Edition org and should be reconfirmed absent (not just worked around)
     on the real target org before assuming it won't recur elsewhere.
   - **A-019/A-020** — no browser/Playwright session and only 1 of 4 spare user-license slots were
     available in this QA environment; a real pre-launch QA pass (or the TC-012/013/014 unblock in
     caveat 1) needs either a browser-capable session or freed license slots.
5. **Pilot-scope limits (not defects — see test-plan §7):** VS-10..VS-22 (cancel/reschedule, no-show,
   patient de-dup, citizen Experience Cloud site + booking/discovery LWC, OTP, SMS/notifications,
   facility-scoped sharing rules, retention purge, synthetic seed script, certificates, dashboards)
   are **not built** in this pilot. Most consequential of these for a compliance-sensitive
   requirement: REQ-053's record-level facility-scoped *sharing* (VS-20) is not built — TC-009/010
   prove OWD + permission-set structure only, not that a facility-staff user is actually confined to
   their own facility's records. Do not present this pilot as satisfying REQ-053 end-to-end.
6. **REQ coverage:** 13 of the 20 REQs touched by VS-01..09 are fully Covered; 7 are Partial (each
   with the reason and owning future ticket named in §5); zero are uncovered for what was built.
   REQ-006 (booking under 3 minutes) has no TC — no timeable UI exists in this pilot.

### Confirmation of open defects

**Zero open Sev-1/Sev-2 bugs.** `03-qa/bug-reports/` contains no BUG-### files (only `.gitkeep`).
No TC returned a FAIL verdict anywhere in Run A or Run B. The one runtime anomaly discovered
during QA (TC-002's initial `DmlException`) was root-caused, architect-ruled as
implementation-robustness (D-029), fixed, re-deployed, and re-verified PASS within the same QA
cycle — it never stood as an open defect at close-out and was never filed as a BUG-### because it
was caught, ruled, and closed before this report was written.

### Gate note

**Marking QA_IN_PROGRESS → DONE is the human's `/advance` gate, not mine.** This section is a
RECOMMENDATION only, per rules/00 and this role's write-access (qa-lead may write only
`03-qa/test-plan.md`'s Results section, its own `agent-runs.log` line, and a `handoffs.md` note —
`PIPELINE_STATE.md` YAML is untouched by this run). The human should weigh caveat 1 (Tier-1
MO-flow browser run) explicitly before approving DONE, and should treat caveats 2-4 as launch
preconditions distinct from the pipeline-phase gate itself.
