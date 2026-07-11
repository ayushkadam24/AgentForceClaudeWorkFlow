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
but its checklist items remain valid record.

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
(rule: no execution without a clean dry-run). Status: BLOCKED — 3 new source fixes needed plus 1
deploy-strategy decision, on top of the first 2 fixes which ARE confirmed applied.**

### Pre-deploy
- [x] Org safety gate: `sf org list --all` + `sf org display --target-org AgentForceClaudeWorkFlow` confirm Developer Edition (`*.develop.my.salesforce.com`, `-dev-ed`), distinct from all client sandbox/prod orgs in the list | verified by devops, 2026-07-12
- [x] Full manifest regenerated from force-app, 95 components confirmed against source (8 ApexClass, 63 CustomField, 6 CustomMetadata, 9 CustomObject, 1 CustomPermission, 2 Flow, 5 PermissionSet, 1 Settings) | verified by devops, 2026-07-12
- [x] Dry-run #1 with `--test-level RunLocalTests` executed against the real DE org | run by devops, 2026-07-12 — **FAILED** (`UNKNOWN_EXCEPTION`, Deploy IDs `0AfgL00000Qwd5FSAR` / `0AfgL00000QwdBhSAJ`)
- [x] **BLOCKER 1 FIXED** — `VS_Bulk_Export.customPermission-meta.xml` description shortened (231 chars) | verified on disk by devops, 2026-07-12
- [x] **BLOCKER 2 FIXED** — `VS_Setting__mdt.object-meta.xml` illegal `<deploymentStatus>` element removed | verified on disk + standalone dry-run Succeeded by devops, 2026-07-12
- [x] Dry-run #2 re-run with `--test-level RunLocalTests` after fixes | run by devops, 2026-07-12 — **FAILED AGAIN** (`UNKNOWN_EXCEPTION`, Deploy ID `0AfgL00000QwdreSAB`) — bisection found 3 more real defects + 1 deploy-strategy issue
- [ ] **BLOCKER 3 (NEW)** — fix `force-app/main/default/objects/VS_Appointment__c/VS_Appointment__c.object-meta.xml`: `<description>` is 1401 chars, exceeds the 1000-char CustomObject limit; shorten. Owner: dev-mid (VS-08). | pending — dev fix required
- [ ] **BLOCKER 4 (NEW)** — fix `force-app/main/default/objects/VS_Patient__c/VS_Patient__c.object-meta.xml`: `<description>` is 1108 chars, same limit; shorten. Owner: dev-mid (VS-07). | pending — dev fix required
- [ ] **BLOCKER 5 (NEW)** — fix `force-app/main/default/flows/VS_Session_Screen_DefineCapacity.flow-meta.xml`: top-level element order violates the Flow metadata XSD sequence (`recordChoiceSets` at lines 30/49 appears after `start`/`variables`; `status` before `start`; `formulas`/`recordLookups`/`recordCreates` scattered after `screens`) — error: "Element recordChoiceSets invalid at this location in type Flow". Reorder elements per schema, or re-save via Flow Builder. Owner: dev-mid (VS-03). | pending — dev fix required
- [ ] **DEPLOY-STRATEGY DECISION (not a force-app bug)** — `VS_Session__c` + `VS_Setting__mdt` in the same check-only transaction reproducibly throws `UNKNOWN_EXCEPTION` even in complete isolation (both objects individually clean); suspected Salesforce `checkOnly=true` limitation with formula fields reading `$CustomMetadata` created in the same transaction. Options: (a) two-phase deploy — CMDT first, `VS_Session__c` second; (b) human-authorized real (non-dry-run) deploy attempt once blockers 3–5 are fixed, to test if a real deploy avoids the check-only-specific issue. **Human/architect decision needed before re-attempting.** | pending — human call
- [ ] Once blockers 3–5 are fixed and the deploy-strategy question is resolved, re-run the full dry-run with `--test-level RunLocalTests` before any real-deploy attempt | pending
- [ ] Re-confirm `sf apex run test` / coverage results only after a clean dry-run (not yet reached — 0 tests have run against this org across both attempts) | pending

### Post-deploy
- [ ] NOT REACHED — real deploy has not been attempted in either dry-run cycle. All post-deploy verification (AC2/AC3 from DP-001, §3.4 slot-integrity concurrency spot-check on `VS_BookingService`, `VS_SlotGenBatch` batch run smoke-test, 5 permission-set assignment sanity check, `VS_Bulk_Export` gating check on `VS_District_MIS` only, per-class code coverage for `VS_BookingService`/`VS_SlotGenerationService`) remains pending until a successful deploy exists | pending

### Manual (cannot deploy)
- [ ] Security → Session Settings: confirm org-wide Session Timeout = 15 Minutes was NOT yet applied (dry-run only, no real deploy) — once a real deploy succeeds, spot-check in Setup that `sessionTimeout=FifteenMinutes`/`lockSessionsToDomain=true`/`forceRelogin=true` took effect (schema itself confirmed valid by devops's isolated dry-run, org-side effect still unconfirmed) | pending
- [ ] A-007: per-facility public-group membership — still a standing manual item, not yet reached (no deploy) | pending
- [ ] A-009: DHO/BA ratification of tunable defaults — still standing, not yet reached | pending

---

_Known standing manual items:_
- [ ] A-007: per-facility public-group membership is maintained manually in the POC | pending first facility setup
