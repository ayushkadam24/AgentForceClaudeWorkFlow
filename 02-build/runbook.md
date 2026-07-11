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

_Known standing manual items:_
- [ ] A-007: per-facility public-group membership is maintained manually in the POC | pending first facility setup
