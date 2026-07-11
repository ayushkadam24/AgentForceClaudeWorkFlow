# Phase Handoff Notes

Outgoing agent appends 5 lines at each phase end:
**From → To | date** — 1) What I produced. 2) What I'm least sure about. 3) What you must not
miss. 4) Open items I'm passing you. 5) Where my working notes are.

---

**ba-analyst → architect | 2026-07-11**
1. Produced `01-discovery/requirements-brief.md` (62 REQs, all source-traced, MoSCoW-prioritised) and `01-discovery/open-questions.md` (27 OQs in 4 sections); logged D-005/D-006, A-002/A-003/A-004, 9 new glossary terms.
2. Least sure about: the capacity model (OQ-001) — the Shinde daily vs Pawar per-session contradiction is unresolved; I recommended time-block-with-degenerate-daily but the client must ratify before slot generation is designed.
3. Must not miss: REQ-008 §3.4 slot-integrity (highest, QA Tier-1, use `SELECT…FOR UPDATE`); REQ-044 no-Aadhaar anywhere; REQ-053 facility-scoped visibility. These three gate the whole F-001 build.
4. Open items passed to you: F-001-blocking OQs = OQ-001, 002, 003, 004, 020, 025, 027 (and OQ-011/012 before any SMS build). Do NOT silently resolve them — carry them into the design's assumptions/decisions with the client, or flag at sign-off.
5. Working notes: the two discovery artifacts above; memory in `.claude/memory/{decisions,assumptions,glossary}.md`; run line in `.claude/logs/agent-runs.log`.

---

**architect → pm-planner | 2026-07-11**
1. Produced `01-discovery/technical-design.md` (11-object F-001 model, §3.4 slot-integrity strategy, automation matrix, security/compliance mapping, 8 epics EP-01..EP-08, full 62-REQ traceability) and `01-discovery/erd/data-model.mermaid`; logged D-015/016/017/018, A-005/006, +4 glossary terms.
2. Least sure about: slot-capacity distribution algorithm (A-005) and citizen-portal sharing + read-audit approach (A-006, Shield dependency for REQ-054) — both need client/org confirmation but do not block the build.
3. Must not miss: EP-03 is the crown jewel — the FOR UPDATE lock lives on `VS_Slot__c` (D-015), booked count NEVER via rollup/trigger; route EP-03/§3.4 work to dev-senior; QA Tier-1 concurrency + no-Aadhaar + facility-scoped sharing gate release.
4. Open items passed to you: many Must REQs are Deferred-not-in-F-001 (reminders, check-in, vaccination/stock, certificates, dashboards, chat) — plan F-001 tickets against EP-01..EP-08 only; launch-blockers OQ-012/013/014/017 stay owner-dependent; SMS live-send deferred (D-014).
5. Working notes: technical-design.md §7 (epics + traceability), memory `decisions.md` D-015..018 / `assumptions.md` A-005/006, run line in `.claude/logs/agent-runs.log`.

---

**architect → pm-planner | 2026-07-11 (D-019 rework)**
1. Amended `01-discovery/technical-design.md` (§2.1/§2.2/§2.3/§2.4/§3/§4-full/§5/§7 EP-03/§8) and `erd/data-model.mermaid` to propagate D-019: ONE §3.4 lock = `VS_Session__c` FOR UPDATE for ALL booking types via one method `VS_BookingService.book(patientId, slotId, bookedById, channel)`; logged D-020, amended A-005.
2. Least sure about: nothing new — D-019 is human-signed; D-020 is the mechanical consequence (keep per-slot ceiling, read/write it only under the session lock).
3. Must not miss: EP-03 now specifies a SINGLE session-row lock — there is NO `VS_WalkInService` and NO slot-row lock; walk-in is `book(..., 'WalkIn')` on the same lock; the concurrency test MUST include a mixed online+walk-in burst on one session (the case D-015 could not prove).
4. Open items passed to you: no scope change — same 8 epics, same REQ coverage; D-015 is retracted (do not plan a dual-lock ticket); everything else in the design is unchanged.
5. Working notes: technical-design.md §4 + §8; decisions D-019/D-020; assumptions A-005 amendment; this run's log line in `.claude/logs/agent-runs.log`.

---

**pm-planner → dev-senior/dev-mid | 2026-07-11**
1. Produced `02-build/sprint-plan.md` (22 tickets VS-01..VS-22, 4 sprints, EP-01..EP-08 only, REQ coverage table) and `02-build/jira-log.md` (register + status history, file-local since Jira MCP not connected — D-004); logged D-021/D-022, A-007.
2. Least sure about: A-005's even slot-capacity split (VS-06 will need rework if MOs want front-loaded distribution) and whether per-facility public-group membership (VS-20) should be automated (A-007) — neither blocks Sprint 1/2.
3. Must not miss: VS-09 is the crown jewel — ONE `VS_BookingService.book()` method, ONE `VS_Session__c` FOR UPDATE lock for online/staff/walk-in (D-019/D-020); its test class MUST include a capacity-exhaustion test AND a mixed online+walk-in parallel-booking burst on the same session, not just same-channel bursts. Do not split it into per-channel services.
4. Open items passed to you: REQ-050 (residency written confirmation) and REQ-054 (per-record read audit) have NO ticket by design — do not build them, they are a launch-gate item and a known POC limitation respectively (see sprint-plan.md's coverage table and "Blocked/Needs architect" section for the other 3 flagged gaps).
5. Working notes: sprint-plan.md (tickets + coverage table + Needs-architect §), jira-log.md (register + status history), memory `decisions.md` D-021/D-022 / `assumptions.md` A-007, this run's log line in `.claude/logs/agent-runs.log`.

---

**dev-mid (VS-01) → BA_ARCH_CONFIRM / next dev-mid ticket (VS-02/VS-03) | 2026-07-11**
1. Produced 5 objects / 32 fields under `force-app/main/default/objects/` (`VS_Facility__c`,
   `VS_Service__c`, `VS_Facility_Service__c`, `VS_Session__c`, `VS_Holiday__c`) — every object and
   field described, VS_-prefixed, OWD Public Read Only per design §2.2 — and
   `02-build/review-notes/VS-01-review.md`; logged assumption A-008.
2. Least sure about: A-008 — whether a Default Value formula on `VS_Facility_Service__c.VS_External_Id__c`
   (`VS_Facility__c & "-" & VS_Service__c`) reliably populates on API/bulk inserts, not just UI saves;
   needs a real dry-run + duplicate-insert test in the DE org before it's trusted to prove AC3.
3. Must not miss: `VS_Session__c.VS_Walk_In_Reserve_Count__c`'s formula references
   `$CustomMetadata.VS_Setting__mdt.WalkInReservePct.Value__c` (VS-02's deliverable, not yet built)
   — **VS-02 must deploy before or together with VS-01's `VS_Session__c`**, or the formula fails
   validation. This is a hard cross-ticket deploy-order dependency, not a design gap.
4. Open items passed forward: no Page Layouts/List Views were built (pure object/field metadata
   scope per the ticket's Issue Type) — intentional, not an oversight; flag if BA_ARCH_CONFIRM
   expects otherwise. `VS_Slot__c` (VS-05), `VS_Patient__c` (VS-07), `VS_Appointment__c` (VS-08)
   were explicitly NOT built here per ticket scope.
5. Working notes: `02-build/review-notes/VS-01-review.md` (full AC mapping + honest deploy status
   — nothing deployed, no dry-run run in this environment), `.claude/memory/assumptions.md` A-008,
   this run's log line in `.claude/logs/agent-runs.log`.

---

**dev-mid (VS-02) → BA_ARCH_CONFIRM / next dev-mid ticket (VS-03) | 2026-07-11**
1. Produced `VS_Setting__mdt` (type + `Value__c`/`Value_Text__c` fields) and 6 seed records under
   `force-app/main/default/customMetadata/` (`CutOffHours`=4, `WalkInReservePct`=25,
   `DefaultSlotGranularityMins`=15, `BookingHorizonDays`=14, `NoShowThresholdCount`=3,
   `ReminderOffsetsHours`="24,3") plus `02-build/review-notes/VS-02-review.md`; logged A-009.
2. Least sure about: A-009 — `BookingHorizonDays`/`NoShowThresholdCount`/`ReminderOffsetsHours` are
   BA-suggested defaults from OQ-006/OQ-007/OQ-005, all three still status Open (no human-signed
   D-### like the other three tunables have); if DHO changes these, it's a CMDT record edit only,
   but any later ticket that hardcodes assumptions about them into logic should re-verify.
3. Must not miss: the VS-01 CONTRACT is verified and held exactly — type `VS_Setting__mdt`, field
   `Value__c`, record DeveloperName `WalkInReservePct` — matching `VS_Session__c`'s
   `$CustomMetadata.VS_Setting__mdt.WalkInReservePct.Value__c` formula built in VS-01. **VS-01 and
   VS-02 still MUST deploy in the same pass** (M-1, owned by devops DP-001) — this ticket does not
   resolve that deploy-order dependency, it only supplies VS-02's side of it.
4. Open items passed forward: no Apex/Flow was needed (pure Custom Metadata, declarative-first);
   nothing flagged for re-routing to dev-senior. A-009's three tentative values need DHO/BA
   ratification before BA_ARCH_CONFIRM or launch.
5. Working notes: `02-build/review-notes/VS-02-review.md` (full AC mapping, CONTRACT confirmation
   quoting VS-01's actual formula text, honest deploy status — nothing deployed, no dry-run run in
   this environment), `.claude/memory/assumptions.md` A-009, this run's log line in
   `.claude/logs/agent-runs.log`.
