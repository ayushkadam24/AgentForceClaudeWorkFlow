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

## dev-mid — deploy-defect fix-forward (VS-07, VS-08, VS-03), 2026-07-12
1. Produced: fixed devops's 2nd dry-run bisection's 3 blockers — VS-08 (`VS_Appointment__c`
   description 1401→696 chars), VS-07 (`VS_Patient__c` description 1108→845 chars, both under
   the 1000-char CustomObject cap), and VS-03 (`VS_Session_Screen_DefineCapacity.flow-meta.xml`
   top-level elements reordered into Metadata API Flow XSD sequence — was rejected with "Element
   ...recordChoiceSets invalid at this location"). All 3 confirmed the two `recordChoiceSets`
   entries are real, distinct choice sets (Facility, Service), not a duplicate — both kept.
2. Unsure about: whether the trimmed object descriptions still read as sufficiently self-
   explanatory to a future reader who never opens the review packet — full original text +
   rationale for the trim is preserved verbatim in both packets, but the XML itself is now much
   terser than the original authoring style used across this build.
3. Next role (devops) must not miss: re-run the full dry-run WITH tests against
   AgentForceClaudeWorkFlow now that all 3 of this bisection's source defects are fixed —
   BUT the deploy-strategy question flagged in the same devops run (`VS_Session__c` +
   `VS_Setting__mdt` pairing throwing `UNKNOWN_EXCEPTION` under checkOnly, likely a
   $CustomMetadata-in-same-transaction limitation) is UNRESOLVED and NOT something I fixed or
   was asked to fix — it needs a human/architect deploy-strategy decision (two-phase deploy vs.
   authorized real-deploy test) before or alongside the next dry-run attempt.
4. Checked and found clean: read-only self-check with `node scripts/metadata-lint.js` after my
   edits shows exactly 2 remaining FAILs, both the known `$CustomMetadata` checkOnly issue on
   `VS_Session__c.VS_Walk_In_Reserve_Count__c` and `VS_Setting__mdt.VS_Value__c` — i.e. my 3
   assigned blockers are gone from the lint output; nothing new introduced.
5. Working notes: force-app/main/default/objects/{VS_Appointment__c,VS_Patient__c}/*.object-
   meta.xml, force-app/main/default/flows/VS_Session_Screen_DefineCapacity.flow-meta.xml;
   02-build/review-notes/{VS-08,VS-07,VS-03}-review.md (new fix-forward sections with full
   original description text preserved); 02-build/jira-log.md (3 new status-history lines); this
   run's agent-runs.log line. PIPELINE_STATE.md untouched. Nothing deployed or dry-run by this
   agent — devops runs the deploy next.

**dev-mid → devops | 2026-07-12 (fix-forward pass 3, batched per rules/20 §5)**
1) Fixed BOTH dev-owned Phase-2 dry-run defects in one pass: (A) VS-03 flow
   `VS_Session_Screen_DefineCapacity.flow-meta.xml` — renamed both `<recordChoiceSets>` blocks
   (`VS_Active_Facility_Choices`, `VS_Active_Service_Choices`) to `<dynamicChoiceSets>`
   (FlowDynamicChoiceSet is the real Metadata API type; `recordChoiceSets` never was); all
   children (name/dataType/displayField/filterLogic/filters/limit/object/sortField/sortOrder/
   valueField) carried over 1:1, active-record filters preserved, position unchanged (already
   XSD-correct). (B) VS-04 — removed the single illegal `<fieldPermissions>` block for the
   required lookup `VS_Facility_Service__c.VS_Service__c` from all 5 permission sets
   (VS_Facility_Staff/VS_Nurse/VS_MO_Facility_Admin/VS_District_Admin/VS_District_MIS); grep
   confirms zero remaining references; VS_Bulk_Export gate (MIS-only, C5/D-022) untouched.
2) Least sure about: whether `dynamicChoiceSets` will validate cleanly on the real dry-run —
   FlowRecordChoiceSet and FlowDynamicChoiceSet share this exact child schema per my knowledge of
   the Flow metadata XSD, but I have no live org access to confirm; if this org surfaces yet
   another schema nuance, a Flow-Builder save+retrieve (per deployments.md's own recommendation)
   is the fallback, not another hand-edit guess.
3) What you must not miss: only the two named defects were touched — no screen, validation rule,
   fault path, helpline text, connector, Create Records logic, object/field permission grant, or
   the VS_Bulk_Export gating was altered. Do not re-derive scope beyond these 6 files.
4) Open items I'm passing you: re-run ONE Phase 2 dry-run with RunLocalTests now (fix-in-batches
   already applied, both defects fixed together) — this is the moment the §3.4 VS_BookingService/
   VS_SlotGenBatch test suite finally gets to execute against the org. I did not deploy or
   dry-run anything myself per this pass's explicit instruction.
5) Working notes: 02-build/review-notes/VS-03-review.md ("Choice-set element fix (2nd
   occurrence)" section) and 02-build/review-notes/VS-04-review.md (section 9b); 2 new
   status-history lines in 02-build/jira-log.md; this run's agent-runs.log line.
   PIPELINE_STATE.md untouched. Nothing deployed or dry-run by this agent.

**dev-mid → devops | 2026-07-12 (fix-forward pass 3, complete-sweep batch per rules/20 §5)**
1) Fixed BOTH newly-unmasked defect classes devops's complete sweep found: (A) VS-03 flow —
   deleted the illegal `<isRequired>false</isRequired>` line on the boolean `VS_Drive_Day_Input`
   screen field (boolean screen inputs can't carry this element at all, masked until the
   round-2 dynamicChoiceSets fix let validation reach this far). (B) VS-04 — removed 20 illegal
   `<fieldPermissions>` entries (3 Master-Detail + 17 required=true) from ALL 5 permission sets
   (100 line removals total, scripted for consistency, done in one batched pass not one-per-round).
2) Least sure about: whether this sweep is now truly exhaustive for these two defect classes —
   I did not independently re-derive which fields are MD/required from the object metadata; I
   trusted devops's list verbatim (as instructed) rather than cross-checking every object-meta.xml
   myself. If a 3rd wave of the same class appears, the underlying object schema (not this list)
   is the source of truth to re-derive from.
3) What you must not miss: `VS_Slot__c`'s entire fieldPermissions group is now empty in all 5
   files (all 6 of its FLS entries were on the removal list) — its objectPermissions (read-only)
   grant is untouched and still there; this is expected, not a dropped grant.
4) Open items I'm passing you: re-run the complete Phase 2 dry-run now — both defect classes
   (choice-set naming, FLS-on-illegal-fields) should be fully exhausted across their full field
   lists this round; if the boolean-isRequired class or the MD/required-FLS class recurs on a
   field not in today's lists, that's a genuinely new instance, not a missed one from this pass.
5) Working notes: 02-build/review-notes/VS-03-review.md ("Boolean screen-input isRequired fix"
   section) and 02-build/review-notes/VS-04-review.md (section 9c); 2 new status-history lines in
   02-build/jira-log.md; this run's agent-runs.log line. PIPELINE_STATE.md untouched. Nothing
   deployed or dry-run by this agent.

---
**Handoff — dev-senior → devops/code-reviewer (BLOCKER C test-FLS fix, 2026-07-12)**
1) What I produced: fixed VS_BookingServiceTest (VS-09) + VS_SlotGenBatchTest (VS-06) to run their
   USER_MODE-enforced calls under System.runAs(a test User) assigned the NEW permset
   VS_Booking_Engine_Test_Context; production code (book(), slot-gen, WITH USER_MODE / insert as user)
   is UNCHANGED — the defect was test-context, not code. Added the permset + 2 review-packet sections,
   A-018, 2 jira-log lines.
2) What I'm unsure about (unmeasured): I could NOT deploy or run tests here. The fix is
   correct-by-construction (FLS surface mapped field-by-field, braces balanced, lint shows no NEW
   issues — only the 2 pre-existing $CustomMetadata flags). Pass/coverage are UNVERIFIED by me.
3) What you MUST NOT miss (devops): ADD `VS_Booking_Engine_Test_Context` (PermissionSet) to
   `manifest/deltas/SPRINT-1-phase2.xml` BEFORE the Phase 2 re-run — else the tests'
   PermissionSetAssignment lookup throws and everything fails again. It is one new component.
4) GENUINE GAP (routed, not papered over): NO role permset grants VS_Appointment__c (deferred
   VS-08/17/20) or VS_Slot__c Create (all 5 are Slot read-only) — so the /dev-implement suggestion to
   reuse VS_Facility_Staff/VS_Nurse/VS_MO_Facility_Admin was unsatisfiable. A real runtime booking
   permset + a slot-gen automation Slot-Create grant are still owed (A-018, BA_ARCH_CONFIRM).
5) Expectation for the next run: FLS fix lets the §3.4 capacity-exhaustion + mixed online/walk-in +
   even-distribution + 250-session governor asserts finally EXECUTE. This MAY unmask previously-hidden
   LOGIC failures (asserts that never ran before) — read any such failure as newly-revealed, NOT a
   regression from this pass. Governor SOQL<=4/DML==1 window kept clean (setup in @TestSetup, measured
   only around generateForSessions). PIPELINE_STATE.md untouched; nothing deployed/dry-run by me.

---
**Handoff — dev-senior → devops (BLOCKER D one-line permset fix, 2026-07-12)**
1) What I produced: added ONE <objectPermissions> block (VS_Facility__c, Read-only, all other flags
   false) to force-app/main/default/permissionsets/VS_Booking_Engine_Test_Context.permissionset-meta.xml,
   resolving the dry-run error "Read VS_Session__c depends on Read VS_Facility__c" (MD master-before-
   detail Read rule).
2) What I'm unsure about: nothing structurally — but I did NOT deploy; the dry-run confirmation is yours.
3) What you MUST NOT miss: object Read ONLY on VS_Facility__c, NO field grants (engines read it only as
   the relationship-Id; FLS there re-trips the required/MD trap). The 9 field grants + all other object
   perms are unchanged (6 objectPermissions / 9 fieldPermissions now).
4) Still owed (unchanged from BLOCKER C): add VS_Booking_Engine_Test_Context to
   manifest/deltas/SPRINT-1-phase2.xml before the re-run; A-018 runtime booking/slot-gen grants remain
   for BA_ARCH_CONFIRM.
5) Expectation: this clears the last metadata error on the permset; RunLocalTests should now execute the
   §3.4 + governor asserts. Fixing FLS/perms may unmask previously-hidden LOGIC failures — read any as
   newly-revealed, not a regression. PIPELINE_STATE.md untouched; nothing deployed/dry-run by me.

---
**Handoff — dev-senior → devops (BLOCKER E fixtures-out-of-runAs, 2026-07-12)**
1) What I produced: fixed VS_BookingServiceTest — moved ALL fixture DML (newSession/newSlot/newPatient,
   incl. pre-created loop/mixed patients) OUT of runAs into the default system-mode context; only the
   VS_BookingService.book() call remains inside System.runAs(bookingUser()). Production code UNCHANGED.
   VS_SlotGenBatchTest was ALREADY canonical (fixtures plain DML in @TestSetup, only executeBatch/
   generateForSessions in runAs) — verified, no change needed.
2) What I'm unsure about: I cannot deploy/run here. Booking fix is correct-by-construction (braces 58/58,
   lint unchanged). Pass/coverage UNVERIFIED by me.
3) What you MUST NOT miss: VS_Booking_Engine_Test_Context must be in manifest/deltas/SPRINT-1-phase2.xml
   (from BLOCKER C) — still required. All state asserts (capacity-exhaustion, mixed online/walk-in §3.4,
   remainder/even-distribution, 250-session SOQL<=4/DML==1) are preserved and now EXECUTE.
4) HONEST caveat on VS_SlotGenBatchTest: the run cited makeData line 66 failing on FLS, but that is plain
   @TestSetup DML (canonically FLS-exempt) and the booking class's identical @TestSetup pattern provably
   completed — so I expect it to pass on re-run. IF it still fails on plain DML, that's a deploy-time
   @TestSetup FLS-enforcement finding to escalate, NOT a code weakness — do not ask me to weaken code or
   grant fixtures FLS via the permset to mask it.
5) Expectation: fixture-creation wall cleared; §3.4 + governor asserts finally execute. May unmask
   previously-hidden LOGIC failures — read any as newly-revealed, not a regression. PIPELINE_STATE.md
   untouched; nothing deployed/dry-run by me.

---
**Handoff — dev-senior → devops (BLOCKER F org-FLS-on-plain-DML fix, 2026-07-12)**
1) What I produced: (a) broadened the TEST-ONLY VS_Booking_Engine_Test_Context permset to grant a test
   user CRUD+FLS to BUILD fixtures (read+create on all fixture objects; +edit on Session; +edit+delete
   on Slot; FLS on VS_Is_Drive_Day__c, VS_Match_Key__c, the 6 Appointment fields; read-only on 2
   formulas). (b) Both test classes now create the harness User OUTSIDE runAs, then run ALL fixture DML
   + engine calls INSIDE System.runAs(harnessUser). Production code UNCHANGED.
2) Unsure/unverified: I cannot deploy/run here. Correct-by-construction (braces 57/57 + 49/49; permset
   well-formed, desc 251<=255; every FLS field confirmed optional/formula — no required/MD).
3) MUST NOT miss: the harness permset must be in manifest/deltas/SPRINT-1-phase2.xml (BLOCKER C). Root
   cause is REAL org behavior: this DE org enforces FLS/CRUD on PLAIN Apex DML in deploy-time tests, so
   fixtures need an FLS user — not a code weakness.
4) A-018 UNCHANGED: the broadened permset is TEST-ONLY; runtime production permsets (Appointment create,
   Slot-create automation) are still owed → BA_ARCH_CONFIRM. Do not treat the harness permset as the
   production grant.
5) Governor window honest: testBulk builds fixtures + scope BEFORE Test.startTest inside runAs, measures
   Limits only around generateForSessions (SOQL<=4/DML==1). Expectation: fixtures now build under FLS;
   §3.4 + governor asserts finally execute; may unmask previously-hidden LOGIC failures (not regressions).
   PIPELINE_STATE.md untouched; nothing deployed/dry-run by me.

---
**Handoff — dev-senior → devops (BLOCKER G two production-code fixes, 2026-07-12)**
1) What I produced: FIX 1 — VS_SlotGenBatch.getBookingHorizonDays() + VS_SlotGenerationService.
   getConfiguredDefaultGranularity() now read CMDT via VS_Setting__mdt.getInstance('<DeveloperName>')
   instead of SOQL (this org rejects CMDT SOQL on the runAs path). FIX 2 — VS_BookingService.
   isDuplicateReferenceError detects the reference collision by StatusCode.DUPLICATE_VALUE only (no
   longer needs field/record visibility). Both are genuine production improvements.
2) Unsure/unverified: cannot deploy/run here. Correct-by-construction (braces 25/25, 28/28, 7/7; zero
   FROM VS_Setting__mdt SOQL remains; lint unchanged). Coverage/pass unmeasured by me.
3) MUST NOT miss: default-fallback (14 / 15) and null handling PRESERVED exactly in FIX 1; retry-once-
   then-REFERENCE_COLLISION contract PRESERVED exactly in FIX 2 (every non-DUPLICATE_VALUE rethrown).
4) Expected unblocks: FIX 1 → 8 slot-gen tests (even-distribution/holiday/drive-day/horizon/idempotent/
   250-session governor/configurable-granularity/degenerate-window); FIX 2 → the 2 reference-collision
   tests. CATEGORY 1 (3 walk-in tests) DELIBERATELY LEFT org-limited: book()'s system-mode counter
   update on required VS_Walk_In_Used_Count__c (D-020) — production code + tests UNCHANGED, no field-FLS
   on a required field; expected to still fail (separate deploy-strategy/QA-load-test decision).
5) A-018 unchanged (harness permset still TEST-ONLY). Permset must be in SPRINT-1-phase2.xml. §3.4 ONLINE
   already VERIFIED; walk-in §3.4 still pending the load test. PIPELINE_STATE.md untouched; nothing
   deployed/dry-run by me.

---
**Handoff — dev-senior → devops (BLOCKER H walk-in test split, D-028/D-028a, 2026-07-12)**
1) What I produced: CREATED force-app/main/default/classes/VS_BookingServiceWalkInTest.cls (+ -meta.xml,
   apiVersion 67.0) — self-contained, the 3 walk-in methods VERBATIM + copies of their helpers + own
   @TestSetup (harness User VSWalkInTest). DELETED only those 3 methods from VS_BookingServiceTest; its
   other 9 methods + @TestSetup + all helpers untouched. Production code UNCHANGED.
2) Unsure/unverified: cannot deploy/run here. Braces balanced (45/45 + 25/25); lint unchanged. Coverage
   is my estimate only (see 5).
3) MUST DO on deploy: add VS_BookingServiceWalkInTest to the manifest so it DEPLOYS, but do NOT include
   it in the class-level RunSpecifiedTests list (it can't execute under deploy-time FLS on the required
   VS_Walk_In_Used_Count__c — that is why it is split). Keep VS_Booking_Engine_Test_Context in the
   manifest too (BLOCKER C).
4) Why class-level: RunSpecifiedTests takes CLASS names only; method-level Class.method ran 0 tests and
   rolled back on 0% coverage last time. The class split is the fix.
5) Coverage expectation: VS_BookingServiceTest alone still covers online + capacity-exhaustion §3.4 +
   collision + negatives -> I expect VS_BookingService >=75% (mid-80s; was 88%). YOU measure it.
   Category-1 walk-in stays org-limited; the 3 moved methods are expected not to run on deploy by design
   (QA load test proves walk-in overbooking). PIPELINE_STATE.md untouched; nothing deployed by me.

---
**Handoff — orchestrator (DEV_IN_PROGRESS close-out) → architect (BA_ARCH_CONFIRM) + human, 2026-07-12**
1) What I produced: Sprint-1 (VS-01..09) DEPLOYED REAL to AgentForceClaudeWorkFlow — Deploy
   `0AfgL00000QySCASA3` (Phase 2, 88 comp) + `0AfgL00000QxRmoSAF` (Phase 1a CMDT type) + 6 manual
   VS_Setting.* records. 21/21 named tests pass; per-class coverage VS_BookingService 86% /
   VS_ReferenceGenerator 100% / VS_SlotGenBatch 95% / VS_SlotGenerationService 95% (org-wide new-class ~92%).
2) §3.4 status the drift-check MUST carry: ONLINE no-overbooking, even-distribution, 250-session governor
   (SOQL<=4/DML==1), drive-day override, idempotency, reference-collision all VERIFIED at deploy time.
   WALK-IN overbooking is NOT unit-verified — un-executable on this org (D-028: deploy-time FLS-filtering
   of the system-mode `update session` on required VS_Walk_In_Used_Count__c). Split into
   VS_BookingServiceWalkInTest (deployed, not run). Walk-in concurrency → QA parallel LOAD test (the real
   §3.4 concurrency proof per the VS-09 packet — unit tests can't prove FOR UPDATE serialization anyway).
3) DRIFT-CHECK RADAR (verify as-built vs design): D-020 (VS_Booked_Count__c plain writable, counters
   maintained system-mode inside the single VS_Session__c FOR UPDATE lock — NO roll-up/formula/trigger);
   D-019 (ONE session-row lock for ALL channels, no second lock/no VS_WalkInService); D-023 (even split
   isolated in ONE private VS_SlotGenerationService.distributeCapacity()); D-016 (booking ref = Crockford
   base32 Unique External Id, generated in service); D-024 (DPDP consent copy must be a Custom Label with
   the [[DRAFT]] prefix, not hardcoded — verify).
4) MUST-NOT-MISS gaps routed here: **A-018 (production permission gap)** — NO role permset grants
   VS_Appointment__c or VS_Patient__c, and all 5 role permsets are VS_Slot__c read-only; so no real
   Portal/staff user can call book() and no human role can run slot-gen under USER_MODE yet. The deployed
   VS_Booking_Engine_Test_Context is a TEST/CI HARNESS ONLY (broad CREATE+FLS) and MUST NOT be treated as
   a production grant or assigned to real users — a real booking permset (VS_Appointment__c create+FLS) +
   a slot-gen automation/scheduler grant (VS_Slot__c create) are owed at VS-08/17/20. Also A-016
   (disjoint online/walk-in pools per D-020 vs AC "shared place" — implemented design default) and A-017
   (bookedById not stored; CreatedById used).
5) Post-deploy operational items (runbook, before QA can exercise UI): assign the 5 role permsets to
   users; seed synthetic data (org has 0 rows); org-specific limits recorded for retro — D-027 (CMDT
   records only creatable via Setup UI on this DE org) and D-028/D-028a (deploy-time FLS-filtering of
   system-mode DML → walk-in tests org-limited; class-level RunSpecifiedTests only). PIPELINE_STATE phase
   left at DEV_IN_PROGRESS — human /advance gate to DEV_COMPLETE is next.

---
**Handoff — architect (BA_ARCH_CONFIRM drift check) → human + qa-lead, 2026-07-12**
1) What I produced: 04-confirmations/drift-check.md — independent as-built-vs-design check of VS-01..09 as
   DEPLOYED (0AfgL00000QySCASA3). Verdict table (radar R1-R8 + object reconciliation + secondary fidelity),
   go/no-go, QA note.
2) Verdict: GO for BA_ARCH_CONFIRM → READY_FOR_QA. ZERO DEVIATES-MUST-FIX. §3.4 crown jewel landed faithfully
   — one VS_Session__c FOR UPDATE lock for all channels (no VS_WalkInService, no second lock), D-020 plain
   writable counters maintained system-mode inside the lock (no roll-up/trigger), D-023 distribution in the
   one distributeCapacity() method, D-016 Crockford ref-gen — all MATCHES.
3) DEVIATES-ACCEPTABLE (all deferred by plan, none block the pilot): D-024 consent Custom Label not built
   (no consent screen in pilot — owed to VS-10/citizen journey; fields carry the obligation); A-018 production
   booking/slot-gen permsets owed to VS-08/17/20 (test harness is TEST-ONLY, must NOT be a production grant);
   3 designed objects (Notification_Log/OTP_Verification/Error_Log) belong to later EPs.
4) MUST-NOT-MISS for QA: §3.4 WALK-IN concurrency is Tier-1 and UNPROVEN by unit tests — needs the parallel
   LOAD test (D-028; unit tests can't prove FOR UPDATE serialization). A-018: no real Portal/staff user can
   call book() yet — the production permset MUST exist before any real user booking journey is exercised (the
   load test may use the harness user; a real-user journey may not).
5) Not changed: I did NOT touch PIPELINE_STATE.md YAML (orchestrator/human owns the gate). No new D-/A-
   minted — all radar items ruled against existing D-016/019/020/023/024/028 and A-016/017/018. BA_ARCH_CONFIRM →
   READY_FOR_QA is a HUMAN GATE.

**qa-engineer (/qa-run A) → qa-lead/qa-engineer(Run B)/human | 2026-07-12**
1) Produced: `03-qa/test-plan.md` §8 Results filled for TC-001..006/015..022 (9 PASS/0 FAIL/5 BLOCKED); full evidence in `03-qa/evidence/run-A/` (seed.apex + real pasted CLI/curl/SOQL output, no fabrication); 5 re-runnable regression specs in `03-qa/regression/` (2 green-bar wrappers around the deployed `VS_BookingServiceTest`/`VS_SlotGenBatchTest`, 1 expected-fail walk-in check, 1 parameterized-but-currently-blocked concurrency harness, 1 manual TC-021 procedure); new A-019 in assumptions.md.
2) Least sure about: whether TC-018's "PASS (partial)" is the right call — the deployed test only proves the far-beyond-horizon boundary + in-horizon inclusion, not the exact day-13/14/15 + past-dated matrix the test plan describes; I judged this an honest partial-pass rather than a full block, but qa-lead should weigh in at `/qa-report`.
3) Must not miss: **TC-002/003 (§3.4 walk-in/mixed-channel concurrency, the crown jewel) are UNPROVEN, not just untested-this-round** — no session in this environment could invoke `VS_BookingService.book()` live at all (A-019), so this isn't "we ran out of time," it's "the org has never had this exercised outside a self-contained unit test." This should weigh heavily, probably decisively, on the `/qa-report` GO/NO-GO for the walk-in channel specifically (online channel IS verified, live, this session).
4) Open items passing forward: (a) devops/architect need to unblock A-019 (authenticated harness-user session, or the test-plan §3 temporary REST-endpoint fallback) before a real TC-001/002/003 concurrency proof is possible; (b) TC-021 needs a human/browser Setup-UI session — full manual steps + mandatory-restore-to-25 already written in `03-qa/regression/tc-021-config-propagation.md`; (c) Run B's TC-010 (permission-set audit) should explicitly smoke-test that a real role user (not just XML inspection) can complete an end-to-end action, given A-019 proved "the FLS looks right on paper" was not sufficient evidence twice now (deploy-time AND live).
5) Working notes: scratchpad under the session temp dir (ephemeral, not committed) has the raw intermediate `sf apex run`/curl outputs; the durable copies are all under `03-qa/evidence/run-A/`.

---
**qa-engineer (/qa-run B) → qa-lead/human | 2026-07-12**
1) Produced: `03-qa/test-plan.md` §8 Results filled for TC-007..014/023..028 (8 PASS/0 FAIL/6 BLOCKED); full evidence in `03-qa/evidence/run-B/` (real pasted SOQL/Tooling-API/Metadata-API-retrieve output, no fabrication — TC-024 run first per instruction); 11 new regression artifacts in `03-qa/regression/` (5 shell audit scripts re-running the live checks + 6 Playwright `.spec.ts` files for the browser-blocked TCs, written for the next engineer with a browser session); new A-020 in assumptions.md.
2) Least sure about: whether TC-025's secondary observation (`{!$Flow.FaultMessage}` reference-code line on the fault screen) deserves escalation to a BUG-### on stricter C7.3 reading — I judged it meets the TC's literal AC (plain-language message + helpline present) and left it as a flagged observation, not a bug; qa-lead should weigh in.
3) Must not miss: **the Tier-1 compliance headlines are clean and STRONGER than a structural-only audit** — TC-008 (no-Aadhaar) and TC-010/011 (role-visibility/bulk-export gating) were verified via LIVE in-org queries against the actual deployed grant graph (`ObjectPermissions`, `SetupEntityAccess`, Tooling API `EntityParticle` which bypasses the FLS limitation that hampered Run A's `sobject describe` calls), not just by reading source XML. This directly answers Run A's own TC-010 follow-up request ("smoke-test that FLS looks right on paper AND live") for the object/field-grant layer, though a true per-role LOGIN smoke test remains blocked (no browser, and only 1 of 4 Salesforce license slots free — A-020). A COMPLIANCE SELF-CORRECTION happened mid-run: the project's pretool guardrail correctly caught an Aadhaar-shaped literal (a repeated-digit 12-numeral placeholder, redacted here per rules/10 — do not re-type the digits) I had used as TC-007 test data before it reached a new file; I found and redacted the evidence file that had already been written via Bash (which bypasses the Write-tool guard) and re-ran the test clean with alphanumeric junk data instead — worth noting as a real near-miss, not swept under the rug.
4) Open items passing forward: (a) A-020 — the license-slot/impersonation constraint blocks any future live per-role login smoke test until devops/architect pick a strategy (free a slot vs. enable `enableAdminLoginAsAnyUser`, currently false per TC-023 evidence); (b) TC-012/013/014/025/026/027 all need a real browser/Playwright session — specs are written and ready in `03-qa/regression/`, just need `@playwright/test` + `@axe-core/playwright` added as devDependencies and a `playwright.config.ts`/storageState setup project (neither exists yet, per the `playwright-sf-testing` skill); (c) combined with Run A, the full picture for `/qa-report`: Tier-1 compliance (no-Aadhaar, OWD, role-visibility, bulk-export) is CLEAN; Tier-1 §3.4 walk-in/mixed-channel concurrency remains UNPROVEN (Run A, A-019); the MO flow itself (TC-012/013/014) has never been exercised live at all in this pilot's QA to date.
5) Working notes: `03-qa/evidence/run-B/` (all raw SOQL/JSON/apex/txt outputs + the `tc009-retrieve`/`tc023-retrieve` live Metadata API pulls), `03-qa/regression/` (5 `.sh` + 6 `.spec.ts`), `.claude/memory/assumptions.md` A-020, this run's `agent-runs.log` line.

**dev-senior (§3.4 walk-in load-test harness — temporary QA infra) → qa-engineer/devops | 2026-07-12**
1) Produced: `force-app/main/default/classes/VS_LoadTestEndpoint.cls` (+test, 87.5% cov, 16/16) — a TEMPORARY `@RestResource(/vsLoadTest/*)` `global without sharing` harness that seeds a reserve==1 scenario and wraps `VS_BookingService.book()` so genuinely-concurrent HTTP can prove the §3.4 WALK-IN guarantee (TC-002/003) that D-028 blocked; `03-qa/evidence/run-A/loadtest-endpoint-notes.md` (endpoints + seed math + the invariant the driver must assert); VS-09 packet §3.4-load-test-harness section; permset `VS_Booking_Engine_Test_Context` gained 5 revert-marked harness lines.
2) Least sure about: whether the WALK-IN `book()` path succeeds under genuine RUNTIME concurrency — in my CHECK-ONLY dry-run test it passed (the class runs system-mode as admin, sidestepping D-028's deploy-time-only FLS), but that is exactly what the live HTTP load test must confirm; do NOT treat my green dry-run as proof of the concurrency guarantee itself.
3) Must not miss: reserve==1 is GUARANTEED by `Total_Capacity=4 -> CEILING(4*25/100)=1` (formula field, not settable) and `verify` returns the ACTUAL computed `walkInReserve` — assert against that, never a hardcoded 1. Fire N≈20 concurrent `book` calls per variant, then assert exactly ONE success per seeded place, `apptCount==successes`, `slotBookedCount<=slotCapacity`, `walkInUsed<=walkInReserve`, and coded rejection reasons; any extra success = §3.4 FAILURE. Prefer re-seeding a fresh session per repeat over `reset`.
4) Open items: (a) the class + its test MUST be REMOVED from the org after the load test, and the 5 permset lines reverted (steps in the VS-09 packet "Manual / setup steps"); (b) production `VS_BookingService` and all F-001 metadata are UNCHANGED — this is orchestration-only QA infra, not a product change, so no drift-check impact; (c) validate-only dry-run PASSED (Deploy 0AfgL00000QyzhZSAR) but I did NOT commit-deploy — devops deploys to `AgentForceClaudeWorkFlow` then runs the driver.
5) Working notes: NO Aadhaar/no 12-digit identifier anywhere (10-digit fictional mobiles + synthetic match keys); dry-run caught+fixed 2 real defects pre-packet (Apex map literal `,`->`=>`, missing required `VS_Date_Of_Birth__c` on the seeded patient — the latter would have failed at runtime too); PIPELINE_STATE.md YAML untouched.

---
**architect (focused §3.4 ruling, post-drift) → dev-senior (implements) + devops (re-deploys + re-tests) | 2026-07-12**
1) Produced: **D-029** in decisions.md — ruling on the QA TC-002 runtime finding (walk-in `book()` `update session;` fails `DmlException: fields being inaccessible on VS_Session__c` at book:~181). CLASSIFICATION: **IMPLEMENTATION-ROBUSTNESS, PRESERVES the §3.4 design (D-019/D-020) — NOT a deviation.** No re-drift-check; this rules ONLY on this one change.
2) Sanctioned fix (dev-senior, in `VS_BookingService.book()`): **option (a)** — replace `update session;` with `update new VS_Session__c(Id = session.Id, VS_Walk_In_Used_Count__c = used + 1);` using the value already computed under the lock. Root cause is that the loaded `session` sObject carries the read-only `$CustomMetadata` FORMULA field `VS_Walk_In_Reserve_Count__c`, which this org's runtime FLS anomaly (D-028 at runtime) treats as inaccessible; a fresh Id+counter sObject never references it. Apply the SAME fresh-sObject pattern to the online branch for symmetry: `update new VS_Slot__c(Id = slot.Id, VS_Booked_Count__c = booked + 1, VS_Status__c = <Open/Full>);`. **DO NOT** use option (b) `Database.update(session, AccessLevel.SYSTEM_MODE)` — it is the same system mode as the plain update that already fails and does not remove the inaccessible field (rejected in D-029).
3) Must not miss — INVARIANTS the fix MUST NOT break: (a) keep the single `SELECT … FOR UPDATE` on `VS_Session__c` AND keep it loading `VS_Walk_In_Reserve_Count__c`/`VS_Walk_In_Used_Count__c` for the reserve check — change ONLY the UPDATE, never the lock SELECT; (b) one method / one lock / one write path for both channels; (c) counter incremented exactly once from the under-lock value (`used+1`) carried on the fresh sObject — **NO re-query** of session/slot (a second SOQL breaks serialization / adds a TOCTOU window); (d) appointment insert stays `insert as user` (USER_MODE); (e) NO roll-up/formula/trigger/flow added; (f) counter persist stays system-mode; (g) `VS_Walk_In_Used_Count__c` stays REQUIRED — do NOT grant it FLS, do NOT make it optional (VS-04 trap). The fix works BECAUSE required fields are always accessible.
4) Re-verification bar (devops/QA, to call §3.4 walk-in PROVEN): re-deploy the fixed class, then re-run the load test — **TC-002** N≥20 concurrent last-place walk-in burst (reserve=1) ×3 → exactly 1 `success:true`, `walkInUsed=1 ≤ reserve=1`, all other calls coded `WALKIN_RESERVE_FULL` (NOT `DmlException`); **TC-003** mixed online+walk-in ×3 → exactly 1 online + exactly 1 walk-in success, pools disjoint; **regression TC-001** online ×3 (the slot branch is also touched) → still exactly 1 success, no overbooking; zero rows above capacity on every repeat (any double-book = Sev-1, release-blocking). After the fix, re-check whether `VS_BookingServiceWalkInTest` can now execute at deploy-time (may fold back into RunSpecifiedTests) — dev/devops call, NOT required for the GO.
5) **GO** for dev-senior to proceed. This is a bounded robustness change inside the crown-jewel service; production code stays design-faithful (D-019/D-020 intact). devops re-deploys to `AgentForceClaudeWorkFlow` and re-runs the §3.4 load test; QA re-reads §8 verdicts. PIPELINE_STATE YAML untouched (phase stays QA_IN_PROGRESS); ANSWER-KEY not read.

---
**Handoff — dev-senior (D-029 walk-in counter-persist robustness) → devops (re-deploys + re-runs §3.4 load test) + qa-engineer | 2026-07-12**
1) What I produced: applied D-029 option (a), BOTH branches, to `VS_BookingService.book()` — the ONLY change is the two counter-PERSIST DML statements. Walk-in `update session;` → `update new VS_Session__c(Id=session.Id, VS_Walk_In_Used_Count__c=session.VS_Walk_In_Used_Count__c)`; online `update slot;` → `update new VS_Slot__c(Id=slot.Id, VS_Booked_Count__c=slot.VS_Booked_Count__c, VS_Status__c=slot.VS_Status__c)`. Fresh sObjects carry only the WRITTEN fields (the READ-only $CustomMetadata formula VS_Walk_In_Reserve_Count__c is no longer dragged into the DML — that was the runtime DmlException root cause). Values are the ones already computed UNDER the lock (no re-query). No test change needed (tests re-query fresh + assert persisted state, identical). Review packet + jira-log + this handoff + agent-runs.log updated.
2) What I'm least sure about: I could NOT deploy/run here. Correct-by-construction (braces 25/25, parens 106/106; metadata-lint = only the 2 pre-existing $CustomMetadata FAILs). The RUNTIME proof is devops's load test — do NOT read this handoff as proof the anomaly is closed.
3) What you MUST NOT miss (devops): re-deploy `ApexClass:VS_BookingService` to AgentForceClaudeWorkFlow ONLY, then re-run the D-029 re-verification bar — TC-002 (N≥20 last-place walk-in burst, reserve=1) ×3 → exactly 1 success, walkInUsed=1≤reserve=1, all others coded WALKIN_RESERVE_FULL (NOT DmlException); TC-003 mixed ×3 → exactly 1 online + 1 walk-in success, pools disjoint; regression TC-001 online ×3 (slot branch also touched) → still exactly 1 success, no overbooking. Any row above capacity = Sev-1. After the fix, dev/devops may re-check whether VS_BookingServiceWalkInTest folds back into deploy-time RunSpecifiedTests (not required for GO).
4) Open items I'm passing you: unchanged — A-018 (production booking/slot-gen permsets still owed, BA_ARCH_CONFIRM); A-016/A-017. No new D-/A- minted (D-029 already exists). §3.4 walk-in remains UNPROVEN until the re-run passes; online §3.4 already verified.
5) Working notes: force-app/main/default/classes/VS_BookingService.cls (2 DML statements changed, nothing else); 02-build/review-notes/VS-09-review.md ("D-029 walk-in counter-persist robustness fix" section, before/after + invariant proof); 02-build/jira-log.md (1 status line); this run's agent-runs.log line. PIPELINE_STATE.md YAML untouched (phase stays QA_IN_PROGRESS per D-029); ANSWER-KEY not read; nothing deployed/dry-run by me.

---
**Handoff — qa-lead (/qa-report close-out) → human (holds the QA_IN_PROGRESS→DONE gate) | 2026-07-12**
1) What I produced: `03-qa/test-plan.md` §8.1 (Consolidated recount table + tier breakdown + BLOCKED-cause
   attribution) and §8.2 (Release recommendation: **GO-WITH-CAVEATS**, one-paragraph rationale, 6 numbered
   caveats/preconditions, zero-open-defects confirmation, explicit gate note) — the only file this role may
   write besides this note and its `agent-runs.log` line. Recount: **20 PASS / 0 FAIL / 8 BLOCKED / 0
   BUG-###** across all 28 TCs (verified by re-tallying the §8 table myself, not trusted from upstream
   summaries — TC-002/TC-003 counted at their post-D-029 PASS status, with the Run-A engineer's original
   in-flight BLOCKED note left verbatim and marked SUPERSEDED for audit). ALSO FIXED IN THIS RUN: found and
   redacted a pre-existing Aadhaar-shaped 12-digit literal sitting in this very file (the qa-run-B handoff
   entry above, item 3) that had apparently been written via a Bash redirect that bypassed the Write-tool
   guardrail in an earlier session — the guardrail correctly blocked MY attempt to re-write this file with
   that digit string still present, so I replaced it with a non-digit description before appending my own
   note (append-only discipline yields to rules/10's absolute no-Aadhaar-anywhere rule when a past entry
   itself is the violation).
2) Least sure about: whether GO-WITH-CAVEATS (vs. an unconditional GO) is the right calibration for
   TC-012/013/014 (the MO screen flow — Tier-1, never run through a live browser UI in this pilot's entire
   QA cycle, though deployed clean + structurally validated + zero drift-check findings). I judged the
   caveat framing correct — RFP §3.4 and Aadhaar/RBAC integrity are the two things a NO-GO would truly need
   to hinge on, and both are proven clean; a staff-only, recoverable-failure-mode screen flow that has
   never regressed at the metadata layer is a real but bounded pre-launch gap, not equivalent to those.
   The human may reasonably weigh this differently — I've surfaced it explicitly, not buried it.
3) Must not miss: **zero open Sev-1/Sev-2 bugs** (`03-qa/bug-reports/` holds only `.gitkeep`) and the RFP
   §3.4 no-overbooking guarantee is **fully proven under genuine concurrency for ALL THREE channels**
   (online/walk-in/disjoint-mixed, 9 load-test runs total, peak-N-in-flight timing captured, zero
   overbooking on any repeat) — this is the single most important fact for the human's /advance decision.
   The 8 BLOCKED TCs are **environment-blocked (no browser, DE-org CMDT/FLS quirks), not product defects**
   — I did not invent, downgrade, or file a bug for any of them; TC-005 specifically is subsumed in intent
   by TC-002's stronger concurrent evidence (noted explicitly in §8.1, not silently reclassified PASS).
   SEPARATELY: the redacted Aadhaar-shaped literal noted in (1) is a real near-miss worth a human/security
   eyeball — a second occurrence of the exact class of finding qa-engineer Run B already caught once.
4) Open items I'm passing to the human: the 6 caveats in test-plan.md §8.2 — (1) TC-012/013/014 need a
   browser run before real MO use; (2) A-018 production booking/slot-gen permset is a hard precondition for
   ANY real user journey (the test harness must never be assigned to a real persona); (3) seed data + role
   permset assignment (org currently has 0 of each); (4) org-specific quirks D-027/D-028/D-029/A-019/A-020
   should be reconfirmed (not assumed) on any non-DE target org; (5) pilot-scope limits per test-plan §7
   (VS-10..22 not built; REQ-053's record-level facility sharing not proven end-to-end — the most
   compliance-consequential gap named in this plan); (6) REQ coverage restated (13 Covered/7 Partial/0
   uncovered for what was built). **Marking QA_IN_PROGRESS → DONE remains the human's `/advance` gate — I
   only recommend.**
5) Working notes: `03-qa/test-plan.md` §8.1/§8.2 (the full recount + recommendation, with every load-test
   number cross-checked against `03-qa/evidence/run-A/TC-001-002-003-loadtest-SUMMARY.md`'s D-029 RE-TEST
   section and `02-build/deployments.md`'s D-029 RE-TEST section); this run's `agent-runs.log` line.
   `PIPELINE_STATE.md` YAML NOT touched (rules/00 — QA_IN_PROGRESS→DONE is a human gate).
   `ANSWER-KEY-intentional-gaps.md` not read; no injection/concealment instruction encountered this run.

---

**architect (D-030 portal-booking design ruling) → developer / code-reviewer | 2026-07-13 (post-DONE forward-build, phase untouched)**
1. Produced: **D-030** in decisions.md — DESIGN RULING (no Apex written) on how an OTP-verified citizen books through the §3.4 crown-jewel service on the public site. Verdict = ACCEPT-WITH-AMENDMENT: `VS_BookingService` `with sharing` → `inherited sharing`; portal path invoked from ONE thin named `without sharing` wrapper adjacent to the C9 gate; server-side C9 gate (VS_OTP_Verification__c.VS_Verified__c + unexpired) made MANDATORY in VS_BookingController.book (currently only claimed in ApexDoc, not coded — MUST-FIX); citizen/guest permset gets NO edit on Session/Slot (D-020 held). All §3.4/D-019/D-020/D-029 invariants confirmed preserved (sharing changes visibility, not the lock/counting).
2. Least sure about: the exact runtime FLS/edit surface a least-privilege portal user needs on VS_Appointment__c/VS_Patient__c fields under `insert as user` on THIS DE org (its FLS-on-system-mode-DML quirk, D-028/D-029) — the developer must dry-run/validate the new portal permset, not author it from memory. Also whether findOrCreate's patient path needs its own elevation for the VS_Match_Key__c upsert under least privilege (verify).
3. Must not miss: (a) do NOT fork book() — one body, inherited sharing, one `without sharing` wrapper is the whole point (a fork re-opens the D-019 seam); (b) the WHOLE book() body runs elevated because SELECT…FOR UPDATE needs edit to lock — a DML-only elevation is insufficient; (c) cancel/reschedule via the elevated path is a SEPARATE MUST-FIX: add an explicit mobile-ownership check (OTP mobile == VS_Booked_By_Mobile__c) BEFORE elevating or it's IDOR; (d) NEVER assign VS_Booking_Engine_Test_Context to a real/guest user.
4. Open items passed forward: implement in VS_BookingController + VS_BookingService + a new least-privilege portal permset; SHIP BAR in D-030 — keep VS_BookingServiceTest/VS_BookingServiceWalkInTest/VS_BookingServiceCancelRescheduleTest/VS_BookingControllerTest green, add the least-privilege-runAs booking test + C9 reject/accept tests, re-run the D-029 §3.4 load bar THROUGH the portal path, metadata-lint clean, validate-only RunLocalTests green. A-018 is resolved for the portal ONLY once this lands. VS-20 record-level facility sharing (REQ-053) still unbuilt (orthogonal).
5. Working notes: D-030 in .claude/memory/decisions.md; VS_BookingService.cls (lines 45 `with sharing` → inherited; counter writes lines 194-205 unchanged) and VS_BookingController.cls (book lines 80-94 need the C9 gate + wrapper; existing `without sharing` Reader inner class lines 113-139 is the placement precedent); this run's agent-runs.log + PIPELINE_STATE.md log line.

**architect (D-030a amendment) → developer / QA | 2026-07-13**
1. Produced D-030a in decisions.md — amends D-030's ship bar after the implementation finding. D-030 design stays GO.
2. Least sure about: whether a standard-behaving sandbox is available for the runtime least-privilege success gate before launch — QA must source one (this DE org cannot host it, D-028).
3. Must not miss: the citizen cleared the SHARING barrier exactly as designed; the wall is OBJECT CRUD (D-028), which `without sharing` does not bypass. Do NOT "fix" it by granting Slot/Session or counter-field edit to VS_Booking_Portal (D-020 breach) or by Database.update SYSTEM_MODE (no-op here, D-029 b).
4. Open items: implement the A-018 proof test to assert book() THROWS "UPDATE not allowed" under runAs the portal user (green + honest); QA carries the runtime success gate on a standard org as a Tier-1 launch precondition; keep the harness-permset success test labelled harness-only.
5. Working notes: D-030 + D-030a in .claude/memory/decisions.md; VS_BookingService counter DML lines 194-205; VS_Booking_Portal permset; agent-runs.log + PIPELINE_STATE log lines this run.
