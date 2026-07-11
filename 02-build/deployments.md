# Deployment Log — POC org (Developer Edition, no source tracking: THIS FILE is the truth)

Append-only. Format:
`date time | scope | manifest | target | deploy ID | dry-run | tests | result | by`

| Date/time | Scope | Manifest | Target | Deploy ID | Dry-run | Tests | Result | By |
|---|---|---|---|---|---|---|---|---|
| 2026-07-11 23:15 | DP-001 (VS-01 SCRUM-13 + VS-02 SCRUM-14, batched per M-1) | manifest/deltas/DP-001-package.xml | POC Developer Edition org (D-025) — no org alias/connection exists in this environment | none (not executed) | NOT RUN against an org — no authorized/connected org in this environment (`sf org list` shows no alias for the POC DE org); structural validation only (see below) | N/A — no Apex in DP-001 (pure objects/fields/CustomMetadata/Flow) | PREPARED, NOT EXECUTED | devops |

### DP-001 structural validation performed (no org, no CLI-against-org command run)

- `sf project generate manifest -p <VS-01+VS-02 source paths> -n DP-001-package -d manifest/deltas`
  run locally (no org required) — succeeded, output at `manifest/deltas/DP-001-package.xml`.
- `sf project generate manifest -p force-app -n package -d manifest` run locally to refresh the
  full manifest at `manifest/package.xml` (previously a stale wildcard/Apex-only placeholder —
  replaced with the real component set now on disk, since VS-01+VS-02 are the only metadata built
  so far, the full manifest and the DP-001 delta manifest are currently identical in content).
- Every `<members>` entry in `manifest/deltas/DP-001-package.xml` was cross-checked against the
  actual files under `force-app/main/default/` — **0 mismatches**: 6 CustomObject, 35 CustomField,
  6 CustomMetadata records, 1 Flow = **48 components**, all present on disk under exactly the API
  names listed.
- Cross-ticket contract path verified by direct file inspection (not just packet prose):
  `VS_Session__c.VS_Walk_In_Reserve_Count__c.field-meta.xml` formula references
  `$CustomMetadata.VS_Setting__mdt.WalkInReservePct.Value__c`; confirmed
  `force-app/main/default/objects/VS_Setting__mdt/fields/Value__c.field-meta.xml` exists (API name
  exactly `Value__c`) and `force-app/main/default/customMetadata/VS_Setting.WalkInReservePct.md-meta.xml`
  exists with `fullName="VS_Setting.WalkInReservePct"` and a `Value__c` value of 25. Contract is
  internally consistent on disk.
- **`sf project deploy start --dry-run` was NOT run.** No org is authorized or connected in this
  environment (`sf org list` was checked — no alias/org corresponds to the POC Developer Edition
  org referenced by D-025). The human must run, after `sf org login web` to that DE org:
  ```
  sf project deploy start --dry-run --manifest manifest/deltas/DP-001-package.xml --target-org <DE-org-alias>
  ```
  and paste the real output here before DP-001 status can move from PREPARED to VALIDATED.
- No Apex test run — DP-001 contains no ApexClass/ApexTrigger, so `sf apex run test` is not
  applicable to this package. (VS-09's booking-service tests will matter starting at DP-002 or
  whichever package first carries Apex.)

## DP-001 — Deployment Package record

- **Package ID:** DP-001
- **Date prepared:** 2026-07-11
- **Contents:** VS-01 (SCRUM-13, "Build facility/service/session capacity objects") + VS-02
  (SCRUM-14, "Create VS_Setting__mdt config + seed values"), bundled per the human verdict on
  VS-01's `/dev-review` (M-1 finding): `VS_Session__c`'s formula fields cannot resolve until
  `VS_Setting__mdt`/`WalkInReservePct.Value__c` exist, so VS-01 cannot deploy standalone.
- **Delta manifest:** `manifest/deltas/DP-001-package.xml` (48 components: 6 CustomObject, 35
  CustomField, 6 CustomMetadata, 1 Flow — see full list in the manifest file).
- **Full manifest (refreshed same run):** `manifest/package.xml` — currently identical in content
  to the delta because VS-01+VS-02 are the only metadata built to date.
- **Target:** POC Developer Edition org (D-025) — free, persistent, single fixed org; no source
  tracking, so this log is the sole record of what was deployed and when.
- **Deploy-order rationale (M-1):** `VS_Session__c.VS_Walk_In_Reserve_Count__c` and
  `VS_Bookable_Capacity__c` formulas reference `$CustomMetadata.VS_Setting__mdt.WalkInReservePct.Value__c`
  (VS-02's deliverable). Deploying VS-01 alone would fail Metadata API formula validation. DP-001
  therefore bundles both tickets into one `sf project deploy start` pass.
- **STATUS: PREPARED — NOT EXECUTED.** No deploy has been run against any org. No deploy ID exists.
  Nothing in `force-app/` was modified to produce this package (manifests only, generated from
  source, never hand-edited).

### PRE-DEPLOY CHECKLIST — gates the human must clear before executing DP-001

- [ ] **VS-02 has not yet had its `/dev-review`.** Only VS-01 has an independent code-review verdict
      (APPROVE-WITH-FIXES, 2026-07-11). VS-02's review packet (`02-build/review-notes/VS-02-review.md`)
      is dev-authored only — recommend running `/dev-review VS-02` before executing DP-001, even
      though VS-02 is pure declarative Custom Metadata with low review risk.
- [ ] **M-2 (integrity gap, still OPEN on disk as of this run):**
      `VS_FacilityService_BeforeSave_SetExternalId` is confirmed **`recordTriggerType: Create`**
      only (verified by reading the flow XML directly this run — not yet fixed to
      `CreateAndUpdate`). This means editing `VS_Service__c` on an existing
      `VS_Facility_Service__c` row leaves a stale `VS_External_Id__c` composite key and the unique
      constraint silently stops catching duplicate (facility, service) pairs on the edit path.
      **devops recommendation: this does NOT need to block DP-001.** M-2 is an *edit-path* gap —
      it does not affect create-time uniqueness (AC3, which DP-001 exists to prove) and does not
      touch the VS-01↔VS-02 formula contract that is DP-001's actual purpose. Blocking DP-001 on
      M-2 would delay proving the crown-jewel-adjacent capacity model in the DE org for a defect
      that only manifests on a later edit. **Recommended sequencing: deploy DP-001 first (prove
      AC2/AC3/create-path), fix M-2 as a follow-up delta package before BA_ARCH_CONFIRM** (per the
      human verdict's own instruction that M-2 must be applied "before BA_ARCH_CONFIRM," not
      "before any deploy"). Flagging for the human to override if a stricter reading is preferred.
- [ ] **N-1 (nit, docs):** VS-01-review.md field tally to be corrected (12 fields on
      `VS_Session__c`, 33 total, not 11/32) when M-2 is fixed — does not block DP-001, no metadata
      impact.
- [ ] Human has run `sf org login web` to the POC Developer Edition org and confirmed an alias.
- [ ] Human has run the dry-run command above and pasted real output into this file.

### POST-DEPLOY manual verification (cannot be automated/deployed — see runbook.md for checkboxes)

- **AC2:** Save a `VS_Session__c` with `VS_Total_Capacity__c` set; confirm
  `VS_Walk_In_Reserve_Count__c` and `VS_Bookable_Capacity__c` compute per the CEILING formula
  against `WalkInReservePct` = 25.
- **AC3:** Create one `VS_Facility_Service__c` record; confirm `VS_External_Id__c` auto-populates
  via the before-save flow; then attempt a second record for the same facility+service and confirm
  the Unique constraint rejects it.
- **A-008 (verify):** the before-save flow's field assignment executes correctly on both UI saves
  and API/bulk inserts, and the resulting Unique-constraint violation is catchable/user-actionable.
- **A-009 (flag, not a deploy gate):** `BookingHorizonDays`=14, `NoShowThresholdCount`=3,
  `ReminderOffsetsHours`="24,3" are BA-suggested defaults (OQ-006/007/005), still status Open —
  DHO/BA should ratify before these are relied on by later consuming Apex/Flow.
- Setup → Custom Metadata Types → VS Setting → Manage Records: spot-check all 6 records show
  expected values post-deploy.

### Drift-check reconciliation note (per D-025 — DE has no source tracking)

Once DP-001 is executed, the log entry above (deploy ID, timestamp) becomes the authoritative
record of "what should be in the org." A subsequent `/deploy drift-check` run must
`sf project retrieve start --manifest manifest/package.xml` to a temp directory (never over
`force-app/`) and diff against source; any difference not explained by a later logged deployment
in this file is org-side drift (a manual Setup click) and gets reported, never silently absorbed.

## Errors & resolutions (append-only)

| Date | Scope | Error (component + first line) | Root cause | Fix | Seen before? |
|---|---|---|---|---|---|
