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

---

**dev-mid (VS-05) → BA_ARCH_CONFIRM / next dev ticket (VS-06, dev-senior) | 2026-07-11**
1. Produced `VS_Slot__c` (1 object, 6 fields) under `force-app/main/default/objects/VS_Slot__c/`
   — Master-Detail→`VS_Session__c`, `VS_Slot_Start__c`/`VS_Slot_End__c`, `VS_Capacity__c`,
   `VS_Booked_Count__c`, `VS_Status__c` — plus `02-build/review-notes/VS-05-review.md`. No new
   assumption logged; no flow needed (design specifies no external ID on Slot).
2. Least sure about: nothing new in design terms — D-020 is human-signed and unambiguous. The only
   open item is deploy-time verification (never run in this environment): confirm the Master-Detail
   deploys cleanly against an org that already has `VS_Session__c`, and confirm
   `VS_Booked_Count__c` behaves as a plain writable field on a real save.
3. **Must not miss (single most important point of this ticket):** `VS_Booked_Count__c` MUST stay a
   plain writable `Number` field all the way through VS-09's implementation — NEVER a Roll-Up
   Summary, NEVER a formula (D-020). A roll-up/formula cannot serialize under the `VS_Session__c`
   `FOR UPDATE` lock and would silently break the §3.4 no-overbooking guarantee. Worth a specific
   check at BA_ARCH_CONFIRM and again when VS-09 is reviewed.
4. Open items passed forward: `VS_Slot__c` has a hard Master-Detail parent-must-exist dependency on
   VS-01's `VS_Session__c` — flagged for devops to sequence into a deployment package after DP-001.
   VS-06 (slot generation, dev-senior) is the next consumer of this schema — it must populate
   `VS_Capacity__c` via the single-method even-distribution algorithm (D-023), not here.
5. Working notes: `02-build/review-notes/VS-05-review.md` (full AC mapping, D-020 explanation, honest
   deploy status — nothing deployed, no dry-run run in this environment), this run's log line in
   `.claude/logs/agent-runs.log`.

---

**dev-mid (VS-02 rename, Option A) → devops / BA_ARCH_CONFIRM | 2026-07-11**
1. Applied the human's VS-02 review verdict (APPROVE-WITH-FIXES, Option A): renamed
   `VS_Setting__mdt.Value__c`→`VS_Value__c` and `Value_Text__c`→`VS_Value_Text__c` (files renamed,
   `<fullName>`s updated, all 6 seed records' `<field>` tags updated) and updated VS-01's
   `VS_Session__c.VS_Walk_In_Reserve_Count__c` formula to match
   (`$CustomMetadata.VS_Setting__mdt.WalkInReservePct.VS_Value__c`). Both review packets
   (VS-01/VS-02) updated to reflect the new contract path.
2. Least sure about: nothing new design-wise — this is a pure naming fix on undeployed metadata,
   grep-verified end-to-end (zero dangling `Value__c`/`Value_Text__c` references on
   `VS_Setting__mdt` anywhere in `force-app`, one prose-only hit narrating the rename history).
3. **DEVOPS: MUST NOT MISS** — DP-001's manifest/deltas were built (or will be built) referencing
   the OLD field names (`Value__c`/`Value_Text__c`). They must be regenerated to reference
   `VS_Value__c`/`VS_Value_Text__c` before any deploy package is assembled, or the package will
   target metadata members that no longer exist under those names.
4. Open items passed forward: none new — A-009 (tentative OQ-005/006/007 values) and M-1 (same-pass
   VS-01+VS-02 deploy order) both still stand unchanged; only the field name changed.
5. Working notes: `02-build/review-notes/VS-02-review.md` (updated CONTRACT/AC/deploy sections +
   Human Verdict section), `02-build/review-notes/VS-01-review.md` (M-1/MIN-1 notes updated),
   `02-build/jira-log.md` (status history line), this run's log line in
   `.claude/logs/agent-runs.log`.

---

**dev-mid (VS-04) → BA_ARCH_CONFIRM / VS-07/VS-08/VS-17/VS-20 (extend these permission sets) | 2026-07-12**
1. Produced 5 mandated permission sets under `force-app/main/default/permissionsets/`
   (`VS_Facility_Staff`, `VS_Nurse`, `VS_MO_Facility_Admin`, `VS_District_Admin`, `VS_District_MIS`),
   scoped only to the 6 objects that exist today (VS-01/VS-05); the `VS_Bulk_Export` custom permission
   (D-022/REQ-036 gate, enabled ONLY in `VS_District_MIS`); and a best-effort org-wide
   `settings/Security.settings-meta.xml` 15-min session-timeout attempt (REQ-055/C6). No new
   assumption logged; `02-build/review-notes/VS-04-review.md` has the full AC mapping.
2. Least sure about: whether `Security.settings-meta.xml`'s `<sessionSettings>` sub-schema is actually
   valid against this org's Metadata API — authored from memory, never dry-run, XML well-formedness
   only (not schema-validated). Also unsure whether VS-09's booking-service execution context will need
   `VS_Slot__c.VS_Booked_Count__c`/`VS_Session__c.VS_Walk_In_Used_Count__c` made editable on any of
   these permission sets (left read-only everywhere, flagged for VS-09's reviewer).
3. Must not miss: session timeout here is a SINGLE ORG-WIDE setting, not per-role/per-permission-set —
   Metadata API doesn't expose it on PermissionSet; a documented manual Setup fallback (Session
   Settings = 15 min) is in the review packet's section 4/10 regardless of whether the settings file
   deploys clean. Also: none of the 5 permission sets reference `VS_Patient__c`/`VS_Appointment__c`/
   `VS_Notification_Log__c` — VS-07/VS-08/VS-17 MUST extend them, not replace them.
4. Open items passed forward: `VS_Citizen_Community` (design §6.2's 6th role) is explicitly VS-14's
   scope, not built here. VS-20 must add `viewAllRecords=true` for District Admin/MIS once
   Patient/Appointment exist (Private OWD objects) — not meaningful on today's Public Read Only
   objects so intentionally omitted here.
5. Working notes: `02-build/review-notes/VS-04-review.md` (full AC mapping, export-gate mechanism,
   honest session-timeout limitations, deferred-perms note, honest deploy status — nothing deployed,
   no dry-run run, no confirmed POC DE org authenticated in this session), this run's log line in
   `.claude/logs/agent-runs.log`.

---

**dev-mid (VS-03) → BA_ARCH_CONFIRM / next dev ticket (VS-06, dev-senior) | 2026-07-12**
1. Produced `VS_Session_Screen_DefineCapacity` (1 screen flow) under
   `force-app/main/default/flows/` — MO-facing: Facility/Service pickers (active-only), Session
   Date/Start/End/Total Capacity/Drive Day, 3 in-flow validations (capacity>0, end>start, date not
   past), fault-wired Get Records + Create Records, shared fault screen with plain-language message +
   facility helpline — plus `02-build/review-notes/VS-03-review.md`. Logged A-010/A-011.
2. Least sure about: A-010 — the Service picker isn't cross-checked against the selected Facility's
   active `VS_Facility_Service__c` offerings, so a mismatched facility+service pairing isn't blocked;
   needs a BA_ARCH_CONFIRM call on whether that's acceptable POC scope or needs a follow-up.
3. **Must not miss:** this flow does NOT set `VS_Walk_In_Reserve_Count__c`/`VS_Bookable_Capacity__c`
   (formula fields, platform-computed from `VS_Total_Capacity__c` + `VS_Setting__mdt`) and does NOT
   generate any `VS_Slot__c` rows or touch granularity — both are VS-06's job only. Also:
   `VS_Error_Log__c` is NOT written on fault (object doesn't exist on disk yet) — AC-3 is honestly
   PARTIAL, documented not silent; revisit once that object ships.
4. Open items passed forward: A-011 (permission-set FLS assumption checks out on disk against
   `VS_MO_Facility_Admin` but unproven in a live org) and A-010 both need a dry-run/human decision
   before BA_ARCH_CONFIRM closes this ticket out. No Apex was needed; nothing routed to dev-senior.
5. Working notes: `02-build/review-notes/VS-03-review.md` (full AC mapping, fault-handling detail,
   explicit confirmation formula fields untouched, honest deploy status — nothing deployed, no
   dry-run run in this environment), `.claude/memory/assumptions.md` A-010/A-011, this run's log line
   in `.claude/logs/agent-runs.log`.

**dev-mid (VS-07) → code-reviewer/human | 2026-07-12**
1. Produced `force-app/main/default/objects/VS_Patient__c/` (1 object, sharingModel=Private + 10
   described fields — exactly C1.1 person data + de-dup match key + DPDP consent fields, no Apex/Flow)
   plus `02-build/review-notes/VS-07-review.md`. Grep-confirmed zero Aadhaar-named field/label
   anywhere (REQ-044 structural AC PASS).
2. Least sure about: A-012 — the `VS_Gender__c` picklist values are a dev-mid choice, design doesn't
   enumerate them; needs BA/DHO confirmation. Also unsure whether enabling field-history tracking
   (beyond the ticket's literal AC, to operationalize REQ-054/A-006) will be seen as welcome
   compliance-forward initiative or scope creep — flagged explicitly in the packet either way.
3. **Must not miss:** A-013 — design §2.3 places `VS_No_Show_Count__c` on this object (VS-12 depends
   on it), but this ticket's explicit scope instruction restricted the build to C1 + match key +
   consent only, so that field was deliberately NOT built. VS-12 is currently ticketed as depending
   only on VS-08, not VS-07 — someone must decide who adds `VS_No_Show_Count__c` before VS-12 builds.
4. Open items passed forward: A-012 (gender values), A-013 (No_Show_Count gap), and the standing
   VS-04 permission-set gap — no permission set on disk yet grants access to `VS_Patient__c` (VS-04
   only covered objects that existed at the time); a follow-up permission-set update is needed before
   any user can see a Patient record.
5. Working notes: `02-build/review-notes/VS-07-review.md` (C1 mapping table, no-Aadhaar grep proof,
   OWD confirmation, Match_Key defined-not-populated note, AC pass/fail, honest deploy status —
   nothing deployed, no dry-run run in this environment), `.claude/memory/assumptions.md` A-012/A-013,
   this run's log line in `.claude/logs/agent-runs.log`.

**dev-mid (VS-08) → next reviewer/dev | 2026-07-12**
1. Produced `force-app/main/default/objects/VS_Appointment__c/` (1 object, sharingModel=Private +
   11 described fields: 5 Lookups [Patient/Slot(required)/Session/Facility/Service, all
   deleteConstraint=Restrict], VS_Booking_Reference__c [Text(8) ExternalId+Unique, defined-not-
   populated per D-016], VS_Status__c [6-value picklist], VS_Booked_Channel__c [4-value picklist],
   VS_Booked_By_Mobile__c, VS_Dose_Number__c, VS_Cancelled_At__c) plus
   `02-build/review-notes/VS-08-review.md`. Confirmed against design §2.4 that Slot→Appointment and
   Patient→Appointment are Lookup, not Master-Detail (reparentable for VS-11 reschedule;
   independent retention lifecycles) — no automation, no Apex, in this ticket.
2. Least sure about: A-014 — whether VS-08 should follow VS-07's precedent of enabling object-level
   field-history tracking as a REQ-054/A-006 compliance baseline (this ticket's literal AC didn't
   require it, so it wasn't added; flagged for BA_ARCH_CONFIRM to rule on consistency).
3. **Must not miss:** the VS-04 permission-set gap is still open and now spans three objects —
   `VS_Facility_Staff`/`VS_Nurse`/`VS_MO_Facility_Admin`/`VS_District_Admin`/`VS_District_MIS` still
   grant zero access to `VS_Patient__c` (VS-07) or `VS_Appointment__c` (this ticket). No F-001
   persona can actually read or write a booking in the org yet until a permission-set ticket
   extends these. This wasn't in VS-08's scope and wasn't built here, per the same precedent VS-07
   set — but it needs to land before VS-09's Apex tests or any UI ticket can function end-to-end.
4. Open items passed forward: A-014 (field-history consistency), the cross-ticket permission-set
   gap above, and the standing hard deploy-order dependency (VS_Appointment__c cannot deploy until
   VS-01/VS-05/VS-07's objects exist in-org — none has been deployed yet).
5. Working notes: `02-build/review-notes/VS-08-review.md` (field/relationship table, Slot-as-Lookup
   reasoning quoting design §2.4, OWD confirmation, Booking_Reference defined-not-populated note,
   no-Aadhaar grep proof, AC pass/fail, honest deploy status), this run's log line in
   `.claude/logs/agent-runs.log`.

---

**dev-senior (VS-06) → BA_ARCH_CONFIRM / VS-09 (dev-senior) | 2026-07-12**
1. Produced the slot-generation engine under `force-app/main/default/classes/`: `VS_SlotGenBatch`
   (Database.Batchable+Stateful orchestrator), `VS_SlotGenerationService` (all generation logic),
   `VS_SlotGenException` (separate top-level, coded messages), and `VS_SlotGenBatchTest` (9 methods),
   plus `02-build/review-notes/VS-06-review.md`; logged assumption A-015.
2. Least sure about: A-015 — `start()` also excludes strictly-past-dated sessions
   (`VS_Session_Date__c >= today`), which is a dev-senior default not mandated by any AC (only the
   beyond-horizon exclusion is a stated AC). And the whole thing was NOT compiled/deployed and no
   test was run (no org) — coverage is an ESTIMATE (~90%), not measured.
3. **Must not miss (D-023 drift-check radar):** the EVEN capacity distribution lives in exactly ONE
   private method — `VS_SlotGenerationService.distributeCapacity(Integer bookableCapacity, Integer
   slotCount)` — remainder to the earliest slots, sum == `VS_Session__c.VS_Bookable_Capacity__c`
   EXACTLY (A-005). `buildSlots` contains NO capacity arithmetic of its own. Confirm this stayed
   isolated before any weighted-distribution work. Also: the invariant sum-exactly is what makes
   VS-09's per-slot ceiling enforcement equivalent to the session bookable ceiling — do not break it.
4. Open items passed forward: VS-09 (crown jewel, dev-senior) reads/increments the `VS_Slot__c`
   counters this batch seeds, inside the single `VS_Session__c` FOR UPDATE lock (D-019/D-020) — the
   slots now carry correct capacities to enforce against. Deploy order: VS-06 needs VS-01/02/05 in
   the org first (reads `VS_Setting__mdt`, the `VS_Bookable_Capacity__c` formula, and `VS_Slot__c`).
   The batch runner needs Create on `VS_Slot__c` (`insert as user`) — flagged for the perm-set owner.
5. Working notes: `02-build/review-notes/VS-06-review.md` (class/method map, D-023 seam named,
   bulk-safety proof [SOQL≤4/DML==1 at 250 sessions], holiday/drive-day handling, test list +
   expected coverage, AC pass/fail, honest "not compiled/not deployed/tests not run" status),
   `.claude/memory/assumptions.md` A-015, this run's log line in `.claude/logs/agent-runs.log`.

---

**dev-senior (VS-09) → BA_ARCH_CONFIRM / VS-11 (dev-senior) | 2026-07-12**
1. Produced the CROWN JEWEL: `VS_BookingService` (single `book(patientId, slotId, bookedById, channel)`
   = one write path for ALL channels; ONE lock = `... FROM VS_Session__c WHERE Id = :sessionId FOR
   UPDATE` on the parent session row — no slot-row lock, no VS_WalkInService, no second lock),
   `VS_ReferenceGenerator` (random 8-char Crockford base32, D-016), `VS_BookingException` (coded
   reasons), `VS_BookingServiceTest` (11 methods) + `02-build/review-notes/VS-09-review.md`; logged
   A-016/A-017.
2. Least sure about: A-016 — the AC's "one place SHARED across channels" wording vs the design default
   D-020 where online (slot bookable) and walk-in (session reserve) are DISJOINT pools. I implemented
   the design default (disjoint) and flagged it, rather than silently merging the counters. And nothing
   was compiled/deployed and no test ran (no org) — coverage is an ESTIMATE (~90%), not measured.
3. **Must not miss (the whole point of §3.4):** the lock is on `VS_Session__c` FOR UPDATE and it is
   taken BEFORE any counter is read; ALL channels take THAT SAME lock. Counters
   (`VS_Slot__c.VS_Booked_Count__c`, `VS_Session__c.VS_Walk_In_Used_Count__c`) are read/written ONLY
   under it — never a roll-up/trigger (rules/20). AND: **the unit tests prove the capacity-CEILING
   LOGIC only — Apex unit tests cannot run parallel transactions, so they do NOT prove FOR-UPDATE
   serialization under real concurrency.** That MUST be proven by the parallel load test in review
   packet §9 (N simultaneous `book()` for the last seat → exactly one succeeds) as the QA Tier-1
   release gate. Do not let anyone read the green unit test as a concurrency proof.
4. Open items passed forward: system-mode counter maintenance vs USER_MODE insert (§7 — reviewer
   decision); `WALKIN_RESERVE_FULL` naming vs design's `RESERVE_FULL`; A-017 (bookedById has no
   storage field). VS-11 (cancel/reschedule) MUST reuse this exact session-lock pattern (decrement
   under the lock, flip Full→Open, deadlock-safe order-by-session-Id across two sessions). Deploy needs
   VS-01/02/05/07/08 in the org first; community `book()` callers need Create on VS_Appointment__c
   (perm-set extension deferred, VS-14/VS-20).
5. Working notes: `02-build/review-notes/VS-09-review.md` (single-lock control flow with the quoted
   FOR UPDATE line, three-channel table, reference generator, exception codes, CRUD/FLS split, test
   list + what each proves, the explicit concurrency-testing limitation + how to load-test on DE org
   AgentForceClaudeWorkFlow, AC pass/fail, traceability, honest not-deployed/not-run status),
   `.claude/memory/assumptions.md` A-016/A-017, this run's log line in `.claude/logs/agent-runs.log`.

---

**dev-mid → human/BA_ARCH_CONFIRM | 2026-07-12 (Bucket A batched review-fix pass, VS-01/03/04/07)**
1. Produced: applied all 5 human-approved Bucket A declarative fixes across four tickets — VS-01
   M-2 (composite-key flow widened Create→CreateAndUpdate, recomputes on Service edit) + N-1 (packet
   field-count corrected 11/32→12/33); VS-03 (screen validationRules added so Start/End Time date
   part must equal Session Date, closing the calendar-day mismatch risk for VS-06); VS-04 NIT
   (VS_External_Id__c locked editable=false on 3 fields in VS_District_Admin only); VS-07 A-013
   MAJOR (added `VS_Patient__c.VS_No_Show_Count__c`, needed by VS-12, marked Resolved in
   assumptions.md). All four review packets updated; jira-log.md status-history lines appended.
2. Least sure about: nothing new-and-open was introduced by these fixes — they were prescriptive
   (exact target text given). One side-finding: while editing the VS-01 flow I found and fixed a
   pre-existing unescaped `&` in its `<description>` text (present since the original VS-01
   fix-forward, unrelated to M-2/N-1) — flagged by IDE XML diagnostics, not previously caught by the
   manual tag-stack checks used in this environment; worth noting that non-parser well-formedness
   checks can miss entity-reference errors.
3. Must not miss: NONE of these five fixes were deployed — same as every prior dev-mid run in this
   environment, no org/CLI access here. All five changed/added files were re-verified well-formed
   with `python xml.dom.minidom` after editing (0 failures each). VS-01's flow-widening (M-2) and
   VS-07's new field are candidate items for the BA_ARCH_CONFIRM drift-check to spot-check against
   design intent, same as any other build artifact.
4. Open items passed to you: none new. Pre-existing open items (A-005/006/007/009/010/011/012/014
   /015/016/017) are unchanged by this batch; A-013 is now Resolved (see amendment).
5. Working notes: `02-build/review-notes/{VS-01,VS-03,VS-04,VS-07}-review.md` (each has a new
   "fix applied"/equivalent section), `.claude/memory/assumptions.md` (A-013 amendment + status
   change), `02-build/jira-log.md` (4 new status-history lines), this run's log line in
   `.claude/logs/agent-runs.log`.

## dev-senior — Bucket A fix-pass (VS-09 + VS-06 Apex), 2026-07-12
1. Produced: VS-09 m-1 (reference-collision → regenerate-and-retry-once in-lock, then coded
   VS_BookingException.REFERENCE_COLLISION; narrow DUPLICATE_VALUE-on-VS_Booking_Reference__c catch,
   all other DmlExceptions propagate) + m-2 (one-booking-per-transaction contract ApexDoc, no behavior
   change) + 2 new collision tests + @TestVisible forceNextReference seam on VS_ReferenceGenerator.
   VS-06 MINOR-1/2/3 (3 new tests: non-15 granularity/non-multiple window, capacity<slotCount edge,
   in-batch degenerate-window skip branch) + NIT-1 (ApexDoc SOQL count 4→3). Updated both review
   packets (Bucket A sections), 2 jira-log status lines.
2. Unsure about: whether the duplicate-detection heuristic (StatusCode.DUPLICATE_VALUE +
   VS_Booking_Reference__c appearing in getDmlFieldNames/getDmlMessage) matches the exact runtime
   DmlException shape on the DE org — it is reasoned from the standard unique-field duplicate message
   but was NOT compiled/run here. The reviewer/devops should confirm on first real test run.
3. Must not miss: NOTHING compiled/deployed/tested this run — deploy happens NEXT (devops full deploy).
   The §3.4 VS_Session__c FOR UPDATE lock + single book() write path and the D-023 single
   distributeCapacity() method were NOT altered — fixes/tests only, as instructed.
4. Open items: VS-06 MINOR-2 surfaces a PRODUCT question for BA_ARCH_CONFIRM — whether 0-capacity Open
   slots should be emitted when bookable < slotCount (current code emits them; test locks + flags the
   behavior, does not change it). A-016/A-017 (VS-09) unchanged and still open for architect ruling.
5. Working notes: force-app/main/default/classes/{VS_BookingService,VS_ReferenceGenerator,
   VS_BookingException,VS_BookingServiceTest,VS_SlotGenerationService,VS_SlotGenBatchTest}.cls;
   02-build/review-notes/{VS-09,VS-06}-review.md; 02-build/jira-log.md (2 new lines); this run's
   agent-runs.log line. PIPELINE_STATE.md untouched.

## dev-mid — deploy-defect fix-forward (VS-02, VS-04), 2026-07-12
1. Produced: fixed 2 devops-found dry-run blockers (VS-02: removed illegal
   `<deploymentStatus>` from `VS_Setting__mdt.object-meta.xml`; VS-04: shortened the
   `VS_Bulk_Export` CustomPermission `<description>` from ~680→210 chars, cap 255) plus a
   proactive fix of the SAME 255-char trap on all 5 permission-set descriptions (was
   1007-1665 chars each, now 218-243), preserving every role's intent/grants unchanged.
2. Unsure about: whether the shortened permission-set descriptions read as "crisp enough" for
   a human reviewer vs the original prose — full rationale is retained in the VS-04 review
   packet sections 2/3/7, not lost, just moved out of the deployable XML.
3. Next role (devops) must not miss: re-run `sf project deploy start --dry-run` against
   AgentForceClaudeWorkFlow now that both bisected defects are fixed; if it passes, proceed
   to real deploy per the existing SPRINT-1-ALL runbook — nothing else in the manifest changed
   (same 95 components, only 6 files edited in place, no adds/removes).
4. Checked and found clean: the 6 `VS_Setting.*` customMetadata records' `<label>` fields (all
   well under the 40-char cap) and no `<description>` element on any of them — no fix needed.
5. Working notes: force-app/main/default/{customPermissions/VS_Bulk_Export.customPermission-meta.xml,
   objects/VS_Setting__mdt/VS_Setting__mdt.object-meta.xml, permissionsets/*.permissionset-meta.xml
   (all 5)}; 02-build/review-notes/{VS-02,VS-04}-review.md (new "Deploy-defect fix" sections);
   02-build/jira-log.md (2 new status lines); this run's agent-runs.log line. PIPELINE_STATE.md
   untouched. No logic/grant/gating changed; nothing deployed by this agent.
