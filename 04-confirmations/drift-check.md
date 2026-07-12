<!--
feature:         F-001 slot-booking-core
producing-agent: architect (design authority — independent drift check)
date:            2026-07-12
phase:           BA_ARCH_CONFIRM
derives-from:    01-discovery/technical-design.md (§2–§7), .claude/memory/decisions.md (D-016/D-019/D-020/D-023/D-024/D-028),
                 .claude/memory/assumptions.md (A-005/A-016/A-017/A-018), 02-build/deployments.md (Deploy 0AfgL00000QySCASA3),
                 02-build/review-notes/VS-0[1-9]-review.md, force-app/main/default/**
scope:           F-001 pilot VS-01..VS-09 as DEPLOYED to AgentForceClaudeWorkFlow (DE org, D-025)
-->

# F-001 Drift Check — As-Built vs Technical Design (VS-01..09)

Independent design-authority comparison of the deployed build (force-app/ + Deploy `0AfgL00000QySCASA3`,
88 Phase-2 components + `0AfgL00000QxRmoSAF` CMDT type + 6 manual `VS_Setting.*` records) against the
design of record `01-discovery/technical-design.md`. Verdicts: **MATCHES** / **DEVIATES-ACCEPTABLE**
(deferred by plan or immaterial to the pilot) / **DEVIATES-MUST-FIX** (blocks the gate).

## 1. Radar verdicts (the eight items the check exists for)

| # | Design element | Verdict | Evidence |
|---|---|---|---|
| R1 | **D-019 / §3.4 — ONE `SELECT…FOR UPDATE` on `VS_Session__c` for ALL channels; no second lock, no `VS_WalkInService`, no unlocked counter write path** | **MATCHES** | `VS_BookingService.cls:117-123` single `FROM VS_Session__c … FOR UPDATE`; both slot-ceiling (`:154-161`) and walk-in-reserve (`:141-149`) checks + counter writes are inside that lock; `update` at `:181-185` still under lock; grep confirms **no `VS_WalkInService`** class exists |
| R2 | **D-020 — `VS_Booked_Count__c` / `VS_Walk_In_Used_Count__c` are plain writable Number fields maintained system-mode inside the lock; NOT roll-up/formula/trigger** | **MATCHES** | `VS_Slot__c/fields/VS_Booked_Count__c` `<type>Number</type>` default 0 (desc cites D-020 "NOT a Roll-Up… NOT a formula"); `VS_Session__c/fields/VS_Walk_In_Used_Count__c` `<type>Number</type>` default 0; incremented only in `VS_BookingService.book()` `:148/:157`; no trigger on either object (deploy manifest carries zero ApexTrigger) |
| R3 | **D-023 — even distribution isolated in ONE private method; sum(slot cap)==bookable** | **MATCHES** | `VS_SlotGenerationService.distributeCapacity(...)` `:164-176` is the sole split (base + remainder to earliest slots); called only from `buildSlots` `:134`; `testEvenDistribution_sumsToBookableExactly` PASS + `testBulk_250Sessions_isGovernorSafe` PASS (deploy `0AfgL00000Qy0PZSAZ`) |
| R4 | **D-016 — booking reference = random non-guessable Crockford base32, Unique External Id, generated in the service** | **MATCHES** | `VS_ReferenceGenerator.cls:25-62` 8-char Crockford (I/L/O/U excluded) via `Crypto.getRandomInteger()`; `VS_Appointment__c/fields/VS_Booking_Reference__c` `Text(8) externalId=true unique=true caseSensitive=false`; generated at `VS_BookingService.cls:171`; collision retry `:200-218`; both collision tests PASS |
| R5 | **D-024 — DPDP consent COPY is a Custom Label with the `[[DRAFT — pending department approval]]` prefix, not hardcoded** | **DEVIATES-ACCEPTABLE** | Consent **fields** exist (`VS_Patient__c.VS_Consent_Given__c` + `VS_Consent_Timestamp__c`, VS-07) and their descriptions explicitly document the D-024 label obligation. The consent **copy/label itself is NOT built** — `force-app/main/default/labels/` does not exist. Correct: no registration screen renders consent copy in the VS-01..09 pilot (that screen is VS-10/citizen journey, EP-05/06). The label is legitimately **owed to the ticket that builds the consent screen** and must exist (with the DRAFT prefix) before that screen ships. Not a pilot-scope drift |
| R6 | **A-018 — `VS_Booking_Engine_Test_Context` is a TEST/CI harness only (broad CREATE+FLS); production booking + slot-gen-automation grants owed to later tickets** | **DEVIATES-ACCEPTABLE** | Permset `<description>` self-declares "TEST/CI FLS harness… TEST-ONLY; does NOT resolve the A-018 runtime permset gap". Design-acceptable **only** as a test artifact — it MUST NOT be assigned to real users or treated as a production grant. Real grants (`VS_Appointment__c` create+FLS for staff/portal; `VS_Slot__c` create for the slot-gen scheduler) are correctly owed to VS-08/17/20 (EP-05/06/08 later sprints), NOT a defect in VS-01..09. **Shipping the pilot with this gap is DEVIATES-ACCEPTABLE (deferred by plan)** because no production user journey (Portal/staff booking UI) is in the pilot scope — see §4 for the hard QA precondition |
| R7 | **A-016 / §3.4 walk-in — disjoint online (slot) vs walk-in (session reserve) capacity pools per D-020 (an AC said "shared place")** | **MATCHES (design)** | As-built implements the DESIGN default: online draws `VS_Slot__c.VS_Capacity__c` (`book:151-161`), walk-in draws `VS_Session__c.VS_Walk_In_Reserve_Count__c` (`book:141-149`), disjoint but under the one session lock. This is exactly D-009/D-020. The VS-09 AC "shared place" wording is **reconciled by D-020** (disjoint pools was the ratified design). Remains an open confirmation to DHO (A-016) — if DHS truly means one merged last place, that is a future data-model change, not a build defect |
| R8 | **Walk-in overbooking UNVERIFIED by unit tests (org limit D-028) → routed to QA parallel load test** | **MATCHES (acceptable strategy)** | The design (§4.4) and the VS-09 packet always designated a **parallel load test** as the real §3.4 concurrency proof — an Apex unit test runs one transaction and cannot prove `FOR UPDATE` serialization. The 3 walk-in methods are split into `VS_BookingServiceWalkInTest` (deployed, not run) because this DE org FLS-filters the system-mode counter `update` on required `VS_Walk_In_Used_Count__c` (D-028), an org test-execution quirk, not a code defect. Verification strategy is sound; it becomes a **QA Tier-1 release gate** (see §4) |

## 2. Object model / unplanned-drift reconciliation

Design §2.2 lists an 11-object F-001 build set; the **pilot** VS-01..09 built the capacity/booking spine only.

| Design object | As-built | Verdict |
|---|---|---|
| VS_Facility__c, VS_Service__c, VS_Facility_Service__c, VS_Session__c, VS_Slot__c, VS_Holiday__c, VS_Patient__c, VS_Appointment__c (8) | Built + deployed | **MATCHES** |
| VS_Setting__mdt (+ VS_Value__c/VS_Value_Text__c, 6 records) | Built; type+fields deployed, 6 records manual (D-027 org limit) | **MATCHES** |
| VS_Notification_Log__c, VS_OTP_Verification__c, VS_Error_Log__c (3) | **Not built** | **DEVIATES-ACCEPTABLE** — designed as F-001 objects but belong to EP-06/EP-07 + error-handling (later sprints), out of the VS-01..09 pilot; deferred by the sprint plan, not silently dropped |

**Components built beyond the object catalogue — all legitimate, none scope-creep:**
- `VS_FacilityService_BeforeSave_SetExternalId` flow — fix-forward for A-008 (a formula field cannot also be `unique/externalId`); it populates the composite-uniqueness key `VS_External_Id__c` that design §2.3 required. **MATCHES** design intent by a corrected mechanism.
- `VS_BookingException` / `VS_SlotGenException` — the custom exceptions design §4/§5 call for. **MATCHES**.
- `VS_BookingServiceWalkInTest` — test-class split (D-028a) so class-level `RunSpecifiedTests` can exclude the org-unrunnable walk-in methods; the walk-in tests stay in source for QA. **MATCHES** (deploy-mechanic, no design change).
- `VS_Booking_Engine_Test_Context` — test harness (R6/A-018).
- `VS_Patient__c.VS_No_Show_Count__c` — added in the review batch (A-013 resolved); design §2.3 places it on Patient. **MATCHES**.

**Designed automation deferred (consistent with EP mapping, not drift):** confirmation record-triggered flow `VS_Appointment_AfterSave_LogConfirmation` (EP-07), `VS_PatientService.findOrCreate` (VS-10), `VS_NoShowBatch`/cancel/reschedule (EP-04), OTP/SMS seams (EP-06/07). All out of VS-01..09 scope. **DEVIATES-ACCEPTABLE**.

## 3. Secondary design-fidelity checks

| Design element | Verdict | Evidence |
|---|---|---|
| §2.4 relationships — MD Facility→Session, MD Session→Slot, MD Facility→Facility_Service; Lookup Service→Session, Slot→Appointment, Patient→Appointment | **MATCHES** | Objects/fields on disk match §2.4; Appointment lookups are `deleteConstraint=Restrict`, Slot reparentable (VS-08 packet) |
| §2.5 person data on `VS_Patient__c` only; C1-minimal; **no Aadhaar anywhere** | **MATCHES** | Patient carries exactly the six C1.1 attributes + match key + consent + derived no-show count; structural grep for Aadhaar clean across all VS-07/08 packets (REQ-044) |
| §2.3 `VS_Walk_In_Reserve_Count__c` / `VS_Bookable_Capacity__c` = `$CustomMetadata` formulas, no automation | **MATCHES** | `VS_Walk_In_Reserve_Count__c` `<formula>CEILING(VS_Total_Capacity__c * $CustomMetadata.VS_Setting__mdt.WalkInReservePct.VS_Value__c / 100)</formula>`; compiled against the 6 manual records at deploy time |
| §6 security — OWD Private on Patient/Appointment; `with sharing` + `WITH USER_MODE`/`insert as user`; `VS_Bulk_Export` gated to `VS_District_MIS`; session timeout ≤15 min | **MATCHES** | Services `with sharing`; appointment insert `insert as user` (`book:202`); slot-gen `insert as user`; `VS_Bulk_Export` enabled only in `VS_District_MIS` (VS-04 packet, D-022); `Security.settings` sessionTimeout=FifteenMinutes deployed |
| Deploy-mode design review — `$CustomMetadata` formula cannot be validated under `checkOnly` with same-transaction CMDT | **MATCHES design guidance** | Resolved exactly as the metadata-deploy-limits skill prescribes: two-phase deploy (D-026), CMDT records committed first (manually, D-027 org limit); formulas then compiled clean in Phase 2 |
| §3.4 §4.6 governor posture — bulk-safe, no SOQL/DML in loops | **MATCHES** | Slot-gen 3 SOQL + 1 DML for 250 sessions (`testBulk_250Sessions_isGovernorSafe` PASS); `book()` single-session, one lock; coverage VS_BookingService 86% / VS_ReferenceGenerator 100% / VS_SlotGenBatch 95% / VS_SlotGenerationService 95% |

## 4. Go / No-Go recommendation

**RECOMMENDATION: GO** — advance BA_ARCH_CONFIRM → READY_FOR_QA (human gate).

Rationale: **zero DEVIATES-MUST-FIX findings.** The §3.4 crown-jewel design landed faithfully — one
`VS_Session__c` `FOR UPDATE` lock for all channels, plain writable counters maintained system-mode inside
that lock, no roll-up/trigger, no second lock, no `VS_WalkInService`. D-023, D-016, D-020 all match the
as-built exactly. Every DEVIATES item is **DEVIATES-ACCEPTABLE, deferred by the sprint plan** (consent
Custom Label, the 3 later-sprint objects, the production permsets, the deferred automation) — none blocks
the pilot QA gate, because no production citizen/staff journey UI is in the VS-01..09 scope. The build is
design-faithful and ready for QA verification.

## 5. For QA (hand to qa-lead)

1. **§3.4 walk-in concurrency is TIER-1, release-blocking, and NOT yet proven.** Online overbooking is
   verified; walk-in/mixed-channel overbooking is **only** provable by a **parallel load test** firing many
   concurrent `book(...,'WalkIn')` (and mixed online+walk-in) calls at one session seeded with one remaining
   reserve place — exactly one succeeds, the rest get `WALKIN_RESERVE_FULL`, `VS_Walk_In_Used_Count__c ≤
   VS_Walk_In_Reserve_Count__c` always, zero extra rows. This is the real §3.4 proof (D-028); do not accept
   the deployed unit-test pass as walk-in coverage.
2. **A-018 production permset is a hard precondition for any real user journey.** `VS_Booking_Engine_Test_Context`
   is a TEST/CI harness — it MUST NOT be assigned to a real Portal/staff user or treated as a production grant.
   Before exercising a real booking journey as a non-admin user, a production booking permset
   (`VS_Appointment__c` create+FLS) and a slot-gen automation grant (`VS_Slot__c` create) must exist (VS-08/17/20).
   The load test in item 1 may run under the harness user (its purpose), but a real-user booking journey may not.
3. **Open confirmations to carry (not blockers):** A-016 (disjoint vs merged "shared place" pools — DHO to
   confirm; as-built matches D-020), A-017 (`bookedById` not stored → `CreatedById`), A-010 (session flow does
   not scope Service to facility offerings), A-015 (past-dated sessions generate no slots). All are design-level
   confirmations for the department, none affect the §3.4 or no-Aadhaar Tier-1 scope.
4. **No-Aadhaar (Tier-1) and role-based visibility (Annexure C5)** remain QA-verifiable and structurally clean
   at this gate; re-run the no-Aadhaar structural check as a release gate per rules/10.
