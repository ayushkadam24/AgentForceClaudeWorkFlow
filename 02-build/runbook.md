# Deployment Runbook — POC org

Owned by the devops agent; sourced from each ticket's review packet ("Manual / setup steps").
A deploy is not DONE until its post-deploy and manual steps are checked and verified.

Format per ticket/batch:

## VS-## — <title>
### Pre-deploy
- [ ] step | verified by/when
### Post-deploy
- [ ] step | verified by/when
### Manual (cannot deploy)
- [ ] step | verified by/when

---

## DP-001 — VS-01 (SCRUM-13) + VS-02 (SCRUM-14): capacity objects + settings config

Source packets: `02-build/review-notes/VS-01-review.md`, `02-build/review-notes/VS-02-review.md`.
Manifest: `manifest/deltas/DP-001-package.xml` (48 components). Deploy-order rationale: M-1
(VS-01's `VS_Session__c` formula fields need VS-02's `VS_Setting__mdt.WalkInReservePct.Value__c`
to resolve — see `02-build/deployments.md` for the full record). Status: PREPARED, NOT EXECUTED.
Superseded for the 2026-07-12 run by the SPRINT-1-ALL batch below (which bundles DP-001's scope
into the full-build package); DP-001 as a standalone delta is no longer the active deploy plan
but its checklist items remain valid record. Now further superseded by SPRINT-1-PHASED (D-026).

### Pre-deploy
- [ ] `sf org login web` to the POC Developer Edition org (D-025); confirm/record the org alias | pending
- [ ] Run `sf project deploy start --dry-run --manifest manifest/deltas/DP-001-package.xml --target-org <alias>` and paste real output into `02-build/deployments.md` | pending
- [ ] Recommend `/dev-review VS-02` before execution (only VS-01 has an independent review verdict so far) | pending — human call
- [ ] M-2 (create-only key flow) — devops recommends this does NOT block DP-001 (edit-path gap only); confirm human agrees with sequencing (deploy first, fix M-2 as a follow-up delta before BA_ARCH_CONFIRM) | pending — human call

### Post-deploy
- [ ] AC2: Save a `VS_Session__c` with `VS_Total_Capacity__c` set; confirm `VS_Walk_In_Reserve_Count__c`/`VS_Bookable_Capacity__c` compute (CEILING against WalkInReservePct=25) | pending
- [ ] AC3: Create a `VS_Facility_Service__c` record; confirm `VS_External_Id__c` auto-populates via `VS_FacilityService_BeforeSave_SetExternalId`; create a duplicate (same facility+service) and confirm the Unique constraint rejects it | pending
- [ ] A-008: confirm the before-save flow behaves correctly on both UI saves and API/bulk inserts, and the Unique-constraint violation is catchable/user-actionable | pending
- [ ] Setup → Custom Metadata Types → VS Setting → Manage Records: spot-check all 6 records (CutOffHours=4, WalkInReservePct=25, DefaultSlotGranularityMins=15, BookingHorizonDays=14, NoShowThresholdCount=3, ReminderOffsetsHours="24,3") | pending
- [ ] Update `02-build/jira-log.md` VS-01/VS-02 status history with a "Deployed to POC" line once executed | pending

### Manual (cannot deploy)
- [ ] A-009: DHO/BA ratify `BookingHorizonDays`/`NoShowThresholdCount`/`ReminderOffsetsHours` (still OQ-005/006/007 Open) before any later ticket relies on them | pending
- [ ] No Page Layout/List View adjustments were deployed for the 5 new objects (VS-01 scope was pure object/field metadata) — human may adjust default layouts in Setup once deployed | pending, non-blocking

---

## SPRINT-1-ALL — VS-01..VS-09 (whole Sprint 1 build to date): first real deploy attempt to DE org

Source: `manifest/package.xml` (full manifest refreshed 2026-07-12, 95 components — supersedes
DP-001 delta for this run, see `02-build/deployments.md`). Target: `AgentForceClaudeWorkFlow`
(confirmed Developer Edition, D-025). Human authorized this attempt in-conversation on 2026-07-12.
**Result after 2 dry-run attempts: STILL FAILING. Real deploy has NOT been attempted either time
(rule: no execution without a clean dry-run). Superseded by SPRINT-1-PHASED (D-026) below — all 5
source blockers found here are now FIXED; the residual is a deploy-MODE issue the phased plan handles.**

### Pre-deploy
- [x] Org safety gate: `sf org list --all` + `sf org display --target-org AgentForceClaudeWorkFlow` confirm Developer Edition (`*.develop.my.salesforce.com`, `-dev-ed`), distinct from all client sandbox/prod orgs in the list | verified by devops, 2026-07-12
- [x] Full manifest regenerated from force-app, 95 components confirmed against source (8 ApexClass, 63 CustomField, 6 CustomMetadata, 9 CustomObject, 1 CustomPermission, 2 Flow, 5 PermissionSet, 1 Settings) | verified by devops, 2026-07-12
- [x] Dry-run #1 with `--test-level RunLocalTests` executed against the real DE org | run by devops, 2026-07-12 — **FAILED** (`UNKNOWN_EXCEPTION`, Deploy IDs `0AfgL00000Qwd5FSAR` / `0AfgL00000QwdBhSAJ`)
- [x] **BLOCKER 1 FIXED** — `VS_Bulk_Export.customPermission-meta.xml` description shortened (231 chars) | verified on disk by devops, 2026-07-12
- [x] **BLOCKER 2 FIXED** — `VS_Setting__mdt.object-meta.xml` illegal `<deploymentStatus>` element removed | verified on disk + standalone dry-run Succeeded by devops, 2026-07-12
- [x] Dry-run #2 re-run with `--test-level RunLocalTests` after fixes | run by devops, 2026-07-12 — **FAILED AGAIN** (`UNKNOWN_EXCEPTION`, Deploy ID `0AfgL00000QwdreSAB`) — bisection found 3 more real defects + 1 deploy-strategy issue
- [x] **BLOCKER 3 (was NEW)** — `VS_Appointment__c.object-meta.xml` `<description>` 1401→696 chars (≤1000 cap) | FIXED by dev-mid, verified on disk by devops, 2026-07-12
- [x] **BLOCKER 4 (was NEW)** — `VS_Patient__c.object-meta.xml` `<description>` 1108→845 chars (≤1000 cap) | FIXED by dev-mid, verified on disk by devops, 2026-07-12
- [x] **BLOCKER 5 (was NEW)** — `VS_Session_Screen_DefineCapacity.flow-meta.xml` top-level elements reordered per Flow XSD | FIXED by dev-mid, 2026-07-12 (Flow parse-error gone; final proof deferred to Phase 2 dry-run)
- [x] **DEPLOY-STRATEGY DECISION** — resolved by human as **D-026 two-phase deploy** (CMDT first, then dependents). See SPRINT-1-PHASED below. | decided by human, 2026-07-12

### Post-deploy
- [ ] NOT REACHED via this batch — see SPRINT-1-PHASED for the active plan | superseded

### Manual (cannot deploy)
- [ ] Carried into SPRINT-1-PHASED below | superseded

---

## SPRINT-1-PHASED — D-026 two-phase Sprint-1 deploy (ACTIVE plan)

Source: `manifest/deltas/SPRINT-1-phase1.xml` (9 comp) + `manifest/deltas/SPRINT-1-phase2.xml` (86 comp);
union == `manifest/package.xml` (95, script-reconciled, zero overlap). Target: `AgentForceClaudeWorkFlow`
(confirmed DE, D-025). Human authorized the two-phase real deploy via D-026. Full record + verbatim
output + bisection in `02-build/deployments.md` (SPRINT-1-PHASED section).

### Pre-deploy
- [x] Org safety gate re-confirmed (`sf org list`): `AgentForceClaudeWorkFlow` Connected, Org Id `00DgL00000VkhBNUAZ`, `-dev-ed`/`.develop.my.salesforce.com` signature | verified by devops, 2026-07-12 11:22
- [x] Blockers 1–5 confirmed fixed on disk; `node scripts/metadata-lint.js` shows only the 2 known `$CustomMetadata` flags (one a false positive on the plain-Number `VS_Value__c`) | verified by devops, 2026-07-12
- [x] Phase 1 + Phase 2 delta manifests generated and reconciled against the full manifest (9 + 86 = 95, no drop/overlap/dupe) | verified by devops, 2026-07-12
- [x] **Phase 1 dry-run** (`SPRINT-1-phase1.xml`, no test level — no Apex) | run by devops, 2026-07-12 11:22 — **FAILED** `UNKNOWN_EXCEPTION (-315522575)` (Deploy ID `0AfgL00000QxbfhSAB`). Bisection: type+fields alone SUCCEED (`0AfgL00000QxbpNSAR`); the 6 CMDT records under `checkOnly` (type not yet committed) are the trigger — a deploy-MODE limitation, NOT a source defect
- [x] **D-026a approved** — Phase 1 split into 1a (real-deploy proven-clean type+fields) + 1b (dry-run records against committed type, then real) | human, 2026-07-12
- [x] **Phase 1a REAL deploy** (`SPRINT-1-phase1a.xml`, no --dry-run) — `VS_Setting__mdt` + `VS_Value__c` + `VS_Value_Text__c` | run by devops, 2026-07-12 11:40 — **SUCCEEDED**, Deploy ID `0AfgL00000QxRmoSAF`, 3 comp REAL in org
- [x] **Phase 1b DRY-RUN** (`SPRINT-1-phase1b.xml`, 6 records, type NOW committed) | run by devops, 2026-07-12 11:42 — **FAILED** `UNKNOWN_EXCEPTION (-315522575)`, Deploy ID `0AfgL00000QxeSHSAZ`, componentsTotal:0. Type presence did NOT make records dry-runnable — this DE org cannot checkOnly-validate CMDT records at all
- [x] **Phase 1b REAL deploy** (`SPRINT-1-phase1b.xml`, no --dry-run, human-approved D-026b) | run by devops, 2026-07-12 11:55 — **FAILED** `UNKNOWN_EXCEPTION (-315522575)`, Deploy `0AfgL00000QxclSSAR`, 0 deployed. Bisected: single record (`0AfgL00000QxYLGSA3`) + brand-new nil-free diagnostic record (`0AfgL00000QxbnmSAB`) also fail identically → org-level MDAPI-CMDT-record limitation (**D-027**), NOT a source defect
- [x] Org-state verified (anon Apex): `VS_Setting__mdt` type queryable (1a committed), record count = 0 | devops, 2026-07-12 12:00
- [x] **D-027 CLEARED** — human manually created all 6 `VS_Setting.*` records in Setup; coordinator verified via anon Apex (count=6, exact values, number/text split correct) | 2026-07-12
- [ ] Drift-check retrieve the 6 manually-created records into the record of truth (D-025 no source tracking) | pending — devops drift-check
- [x] **Phase 2 dry-run** (`SPRINT-1-phase2.xml`, `--test-level RunLocalTests`) | run by devops, 2026-07-12 12:20 — **FAILED (clean/non-opaque)** Deploy `0AfgL00000Qxf0ASAR`: 80 validated, 6 errors. **`$CustomMetadata` formula fields COMPILED** (two-phase objective achieved). 0 tests ran (validation failed first). 2 dev-owned defects surfaced (below)
- [x] **BLOCKER A (VS-03) round 1 FIXED** — `recordChoiceSets`->`dynamicChoiceSets` (dev-mid); re-run confirms that error gone | 2026-07-12 12:45
- [x] **BLOCKER B (VS-04) round 1 PARTIAL** — VS_Service__c FLS removed (dev-mid); that error gone, but same class remains on other MD/required fields | 2026-07-12 12:45
- [x] **Phase 2 dry-run RE-RUN** (`0AfgL00000QxjN7SAJ`) — FAILED, 80 validated / 6 errors / 0 tests. `$CustomMetadata` formulas still compile. Next layer of the 2 classes unmasked | devops, 2026-07-12 12:45
- [x] **BLOCKER A2 (VS-03) FIXED** — `<isRequired>false</isRequired>` removed from `VS_Drive_Day_Input` (dev-mid) | 2026-07-12
- [x] **BLOCKER B2 (VS-04) FIXED** — all 20 illegal MD/required-field `<fieldPermissions>` removed from 5 permsets (dev-mid, grep-confirmed 0 remaining) | 2026-07-12
- [x] **Phase 2 FINAL dry-run** (`0AfgL00000QxkkbSAB`) — **METADATA CLEAN 86/86, 0 errors**; RunLocalTests ran: 24/23-fail/1-pass | devops, 2026-07-12 12:58
- [x] **Phase 2 REAL deploy** (`0AfgL00000QxljtSAB`, RunLocalTests) — 86/86 validated, 0 component errors, but **23/24 tests FAILED → ROLLED BACK (nothing committed)** | devops, 2026-07-12 13:02
- [x] **BLOCKER C (VS-09 + VS-06) FIXED** — tests now create User+permset+`System.runAs`; dev-senior added CI permset `VS_Booking_Engine_Test_Context` (prod-permset gap logged A-018 -> BA_ARCH_CONFIRM) | 2026-07-12
- [x] Manifest updated 86 -> **87** (added `VS_Booking_Engine_Test_Context`); full package.xml refreshed to 96; reconciled (9+87=96=full, no dupes) | devops, 2026-07-12
- [x] **Phase 2 dry-run** (`0AfgL00000QxpifSAB`, 87 comp) — FAILED on 1 metadata error (permset MD-master dependency); 0 tests ran | devops, 2026-07-12 13:20
- [x] **BLOCKER D FIXED** — VS_Facility__c Read added to test permset (dev-senior); MD dependency resolved | 2026-07-12
- [x] **Phase 2 dry-run** (`0AfgL00000QxqbVSAR`, 87 comp) — **METADATA 100% CLEAN 87/87, 0 errors**; RunLocalTests ran: 24/23-fail/1-pass | devops, 2026-07-12 13:40
- [x] **BLOCKER E applied** (dev-senior) — Booking fixtures moved out of runAs; diagnostic dry-run `0AfgL00000QxuonSAB` (87/87 clean) shows failures MOVED (Session/Slot plain inserts now pass) | 2026-07-12 14:05
- [x] **BLOCKER F applied** (dev-senior) — fixtures now runAs an FLS-bearing harness permset; dry-run `0AfgL00000Qxy7dSAB` (87/87 clean): 24 run / 13 fail / **11 PASS**, fixtures build, coverage real | 2026-07-12 14:30
- [x] **§3.4 ONLINE VERIFIED** — `testCapacityExhaustion_online_neverOverbooks` PASSED (no-overbooking ceiling held); `testHappyPath_onlineBooking` + all negatives pass | 2026-07-12 14:30
- [x] Coverage now real: VS_BookingService **88%**, VS_ReferenceGenerator **100%** (both meet rules/20 85%); VS_SlotGenerationService 73% / VS_SlotGenBatch 35% (suppressed by cat-3 CMDT-read failures) | 2026-07-12 14:30
- [x] **BLOCKER G applied** (dev-senior, 2 code fixes: getInstance config read + StatusCode dup-detect) — dry-run `0AfgL00000Qy0PZSAZ` (87/87 clean): 24 run / **21 PASS** / 3 fail, no regression | 2026-07-12 14:55
- [x] **Coverage ALL >=85%**: VS_BookingService 94%, VS_ReferenceGenerator 100%, VS_SlotGenBatch 95%, VS_SlotGenerationService 95% (org-wide ~95%) | 2026-07-12 14:55
- [x] **§3.4 + slot-gen VERIFIED**: online capacity ceiling, even-distribution, 250-session governor (SOQL<=4/DML==1), drive-day override, idempotency, collision-retry + coded-exception all PASS | 2026-07-12 14:55
- [ ] **ONLY REMAINING: 3 walk-in tests** fail at `book:182` (system-mode `update session` on required counter field; org FLS-filters plain deploy-time DML — VS-04 trap; production-safe). Deliberately unchanged | org-limit — human deploy-strategy call
- [x] **HUMAN DECISION (D-028)** — real deploy via RunSpecifiedTests naming the 21 passing tests; 3 walk-in tests = documented org limit routed to QA load test | human, 2026-07-12
- [x] **Phase 2 real deploy ATTEMPT** (`0AfgL00000QyQv7SAF`, RunSpecifiedTests method-level) — **FAILED/ROLLED BACK**: method-level `--tests Class.method` ran 0 tests (deploy API takes CLASS names only) → 0% coverage gate → rollback | devops, 2026-07-12 15:15
- [x] **BLOCKER H DONE** (dev-senior) — 3 walk-in methods moved to `VS_BookingServiceWalkInTest.cls`; `VS_BookingServiceTest` keeps 9 passing methods; production code untouched | 2026-07-12
- [x] Manifest 87 → **88** (added VS_BookingServiceWalkInTest); package.xml → 97; reconciled clean | devops, 2026-07-12
- [x] **PHASE 2 REAL DEPLOY SUCCEEDED** — `sf project deploy start ... --test-level RunSpecifiedTests --tests VS_BookingServiceTest --tests VS_SlotGenBatchTest` → **Deploy `0AfgL00000QySCASA3`, 88/88, 21/21 pass, 0 fail**; coverage VS_BookingService 86% / VS_ReferenceGenerator 100% / VS_SlotGenBatch 95% / VS_SlotGenerationService 95% (org-wide ~92%, all ≥75%) | devops, 2026-07-12 15:40
- [x] **In-org verified** — 88 componentSuccesses (incl. both formula fields); anon Apex: 8 objects exist, 6 prod classes present, 6 permsets, VS_Bulk_Export, 6 CMDT records | devops, 2026-07-12 15:40
- [x] **SPRINT-1 BUILD DEPLOYED COMPLETE** — full 97-member manifest real in AgentForceClaudeWorkFlow (Phase 1a `0AfgL00000QxRmoSAF` + 6 manual records + Phase 2 `0AfgL00000QySCASA3`). §3.4 online + slot-gen verified; walk-in §3.4 → QA parallel load test (D-028) | devops, 2026-07-12

### Post-deploy (now unblocked — pending)
- [ ] Assign the 5 role permission sets to test users; confirm VS_Bulk_Export granted ONLY via VS_District_MIS (C5/D-022) | pending
- [ ] Seed synthetic facilities/services/sessions (org has 0 rows) via org-setup.sh; then AC2/AC3 spot-checks | pending
- [ ] QA parallel LOAD test on the walk-in/mixed §3.4 concurrency (the 3 org-limited unit tests' real proof, D-028) | pending — QA
- [ ] Grant the deploying admin FLS on VS_ fields (or assign a role permset) so admin-context anon Apex/queries see the fields (org FLS-filtering, D-028) | pending, non-blocking
- [ ] Real coverage so far (from `0AfgL00000QxljtSAB`, tests blocked at FLS): VS_BookingService 5%, VS_SlotGenerationService 0%, VS_SlotGenBatch 0%, VS_ReferenceGenerator 33% — replaces "~90% ESTIMATED"; not assessable until tests run under FLS context | recorded, 2026-07-12
- [ ] **Phase 2 real deploy** (on clean Phase 2 dry-run + human GO), `--test-level RunLocalTests` — capture component + per-class coverage | pending

### Post-deploy (pending first successful deploy)
- [ ] AC2: `VS_Session__c` save computes `VS_Walk_In_Reserve_Count__c`/`VS_Bookable_Capacity__c` (CEILING vs WalkInReservePct=25) | pending
- [ ] AC3: `VS_Facility_Service__c` `VS_External_Id__c` auto-populates; duplicate rejected by Unique constraint | pending
- [ ] §3.4 slot-integrity: `VS_BookingService` capacity-exhaustion + mixed online/walk-in tests pass under RunLocalTests; record per-class coverage for `VS_BookingService`/`VS_SlotGenerationService` (≥85% target) | pending
- [ ] `VS_SlotGenBatch` batch-run smoke test | pending
- [ ] Setup → Custom Metadata Types → VS Setting: spot-check all 6 records committed by Phase 1 | pending
- [ ] Assign the 5 permission sets to test users; confirm `VS_Bulk_Export` custom permission is granted ONLY via `VS_District_MIS` (C5/D-022) | pending
- [ ] Update `02-build/jira-log.md` VS-01..VS-09 status history with a "Deployed to POC" line | pending

### Manual (cannot deploy)
- [ ] Security → Session Settings: after a real deploy, confirm `sessionTimeout=FifteenMinutes` / `lockSessionsToDomain` / `forceRelogin` took effect (schema confirmed valid by isolated dry-run earlier) | pending
- [ ] A-007: per-facility public-group membership maintained manually | pending
- [ ] A-009: DHO/BA ratification of tunable defaults (BookingHorizonDays/NoShowThresholdCount/ReminderOffsetsHours) | pending

---

_Known standing manual items:_
- [ ] A-007: per-facility public-group membership is maintained manually in the POC | pending first facility setup
