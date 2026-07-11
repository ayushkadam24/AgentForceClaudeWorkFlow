# Deployment Log — POC org (Developer Edition, no source tracking: THIS FILE is the truth)

Append-only. Format:
`date time | scope | manifest | target | deploy ID | dry-run | tests | result | by`

| Date/time | Scope | Manifest | Target | Deploy ID | Dry-run | Tests | Result | By |
|---|---|---|---|---|---|---|---|---|
| 2026-07-11 23:15 | DP-001 (VS-01 SCRUM-13 + VS-02 SCRUM-14, batched per M-1) | manifest/deltas/DP-001-package.xml | POC Developer Edition org (D-025) — no org alias/connection exists in this environment | none (not executed) | NOT RUN against an org — no authorized/connected org in this environment (`sf org list` shows no alias for the POC DE org); structural validation only (see below) | N/A — no Apex in DP-001 (pure objects/fields/CustomMetadata/Flow) | PREPARED, NOT EXECUTED | devops |
| 2026-07-12 09:40 | DP-001 (VS-01 + VS-02) — MANIFEST REGENERATED after VS-02 Option-A rename | manifest/deltas/DP-001-package.xml (regenerated) | POC Developer Edition org (D-025) — still no org alias/connection in this environment | none (not executed) | NOT RUN against an org — no authorized/connected org in this environment; structural validation only (see note below) | N/A — no Apex in DP-001 | PREPARED (unchanged — regeneration only, still not executed) | devops
| 2026-07-12 16:50 | SPRINT-1-ALL: whole build to date, VS-01..VS-09 (all 9 tickets built+reviewed, 95 manifest members) | manifest/package.xml (refreshed full manifest, superseding DP-001 delta for this run) | `AgentForceClaudeWorkFlow` — CONFIRMED Developer Edition org (username `ethanspython396.16ac318df344@agentforce.com`, instance `orgfarm-cb999a8bfb-dev-ed.develop.my.salesforce.com`, Org Id `00DgL00000VkhBNUAZ`) | `0AfgL00000Qwd5FSAR` (first attempt) / `0AfgL00000QwdBhSAJ` (repro attempt) — both FAILED, no successful deploy ID | **FAILED** — `UNKNOWN_EXCEPTION: An unexpected error occurred... ErrorId 1453209052-1089401 (-315522575)` on the full 95-member manifest, reproduced identically on a second independent attempt (different Deploy ID, same error code), with both `--test-level RunLocalTests` and `--test-level NoTestRun` (ruling out Apex test execution as the trigger). Root-caused by bisection (see detail section below) to two real source-side metadata defects; NOT an org-connectivity or org-health issue (a standalone `VS_Facility__c` object deploy succeeded cleanly in the same org during bisection) | Tests: 0 run, 0 passed, 0 failed (deploy never got past metadata validation) | **DRY-RUN-FAILED — DEPLOY NOT ATTEMPTED** (per rules: dry-run must be clean before real deploy; it was not) | devops
| 2026-07-12 20:10 | SPRINT-1-ALL: re-run after dev-mid fix-forward (VS_Bulk_Export description + VS_Setting__mdt deploymentStatus + proactive permission-set description shortening) | manifest/package.xml (unchanged, 95 components — confirmed no regen needed) | `AgentForceClaudeWorkFlow` (same confirmed DE org) | `0AfgL00000QwdreSAB` (dry-run WITH RunLocalTests, FAILED) | **FAILED AGAIN** — `UNKNOWN_EXCEPTION (-315522575)`, same error family. Bisection found 3 MORE real defects the first pass hadn't reached, plus 1 platform/dry-run-mode-specific behavior (see detail section below) | 0 run (never reached test execution) | **DRY-RUN-FAILED (2nd attempt) — DEPLOY NOT ATTEMPTED** | devops

### Step 0 — org safety gate (2026-07-12, first run)

- `sf org list --all`: confirmed `AgentForceClaudeWorkFlow` alias present, type blank (non-DevHub scratch/DE-style row), status **Connected**, Org Id `00DgL00000VkhBNUAZ`, username `ethanspython396.16ac318df344@agentforce.com` (marked default org). This is clearly distinct from every client org in the list (`ECMS Prod`, `ECMS SIT/UAT/TEST/INT/DevPhase2/DM`, `NationalCallCenter`, `VishnuCallCenter` — all on `prutech.com` usernames).
- `sf org display --target-org AgentForceClaudeWorkFlow`: **Instance Url** `https://orgfarm-cb999a8bfb-dev-ed.develop.my.salesforce.com` — the `-dev-ed` + `.develop.my.salesforce.com` pattern is the Developer Edition signature. Username on `agentforce.com`, not any client domain.
- **GO decision**: alias confirmed as the intended DE org per D-025. Proceeded past Step 0. (Re-confirmed same alias/org for the 2026-07-12 20:10 re-run — no re-verification needed, same session context.)

### Step 1 — full manifest refresh (first run)

- `sf project generate manifest --source-dir force-app --name package --output-dir manifest` — succeeded, wrote `manifest/package.xml`.
- All `applications/aura/lwc/flexipages/layouts/tabs/staticresources/contentassets` folders confirmed empty (scaffolding only) — nothing missing from the regenerated manifest.
- **Component count: 95** members total — ApexClass 8 (`VS_BookingException`, `VS_BookingService`, `VS_BookingServiceTest`, `VS_ReferenceGenerator`, `VS_SlotGenBatch`, `VS_SlotGenBatchTest`, `VS_SlotGenException`, `VS_SlotGenerationService`), CustomField 63, CustomMetadata 6 (`VS_Setting.*` records), CustomObject 9 (`VS_Appointment__c`, `VS_Facility_Service__c`, `VS_Facility__c`, `VS_Holiday__c`, `VS_Patient__c`, `VS_Service__c`, `VS_Session__c`, `VS_Setting__mdt`, `VS_Slot__c`), CustomPermission 1 (`VS_Bulk_Export`), Flow 2 (`VS_FacilityService_BeforeSave_SetExternalId`, `VS_Session_Screen_DefineCapacity`), PermissionSet 5, Settings 1 (`Security`). Matches expected Sprint-1 scope exactly.
- Confirmed unchanged for the 20:10 re-run: dev-mid's fixes were description-only content edits + one element removal — no component added/removed/renamed, so no regeneration was needed.

### Step 2/A — dry-run WITH tests (first run) — FAILED, verbatim key lines

```
sf project deploy start --manifest manifest/package.xml --dry-run --test-level RunLocalTests --target-org AgentForceClaudeWorkFlow

 Status: Failed
 Deploy ID: 0AfgL00000Qwd5FSAR
 Target Org: ethanspython396.16ac318df344@agentforce.com

Test Results Summary
Passing: 0
Failing: 0
Total: 0
Dry-run complete.
```

`sf project deploy report --job-id 0AfgL00000Qwd5FSAR --target-org AgentForceClaudeWorkFlow --json`:
```
"errorMessage": "UNKNOWN_EXCEPTION: An unexpected error occurred. Please include this ErrorId if you contact support: 1453209052-1089401 (-315522575)",
"errorStatusCode": "UNKNOWN_EXCEPTION",
"numberComponentErrors": 0,
"numberComponentsDeployed": 0,
"componentFailures": [],
"componentSuccesses": []
```

Repro attempt (independent run, `--json`): same error code, new Deploy ID `0AfgL00000QwdBhSAJ`, `ErrorId 1776318095-521522 (-315522575)`. Reproducible, not a transient blip.

Re-ran with `--test-level NoTestRun` (isolate whether Apex test execution was the trigger): **same `UNKNOWN_EXCEPTION` (-315522575)**, Deploy ID `0AfgL00000QwdV3SAJ` — confirms tests are not the cause; the failure occurs during metadata validation/deploy itself, before tests would run.

### Root-cause bisection — FIRST run (dry-run/NoTestRun only, no force-app/ files touched, no real deploy attempted)

1. **Org/connectivity sanity check** — deployed `VS_Facility__c` (a plain custom object + 8 fields) alone: **Succeeded** (Deploy ID `0AfgL00000Qwdy5SAB`, `numberComponentsDeployed: 9`, `status: Succeeded`). Confirms the DE org and the deploy pipeline are healthy; the failure is source-side, not org-side.
2. **`VS_Bulk_Export` CustomPermission alone**: **FAILED cleanly** (not UNKNOWN_EXCEPTION) — `"problem": "Value too long for field: Description maximum length is:255"`. Confirmed by direct read: description was a single run-on paragraph (~730+ characters). **Real defect #1.**
3. **Full manifest minus `CustomPermission`**: still failed with the same `UNKNOWN_EXCEPTION` — defect #1 is real but not the sole cause.
4. **Objects+fields+CustomMetadata only**: still `UNKNOWN_EXCEPTION`. Narrowed search to the 9 CustomObject bundle.
5. **`VS_Setting__mdt` (Custom Metadata Type) alone**: **FAILED cleanly** — `"problem": "Cannot specify: deploymentStatus for Custom Metadata Type"`. Confirmed: the file had `<deploymentStatus>Deployed</deploymentStatus>`, illegal on a `__mdt`. **Real defect #2.**
6. **`Security.settings` alone** (dev-mid's flagged "unverified schema" risk): **Succeeded** — schema is valid as written; good news, this risk did not materialize.

**First-run conclusion:** the aggregate `UNKNOWN_EXCEPTION` was the platform choking on defect #2 bundled with other objects. Both defects flagged back to dev-mid for fix-forward; NOT fixed by devops (force-app/ is dev-owned).

### Fix-forward applied by dev-mid (confirmed on disk by devops, read-only)

- `VS_Setting__mdt.object-meta.xml`: `<deploymentStatus>` element removed — confirmed via direct read and a standalone dry-run (Deploy ID `0AfgL00000QwfwfSAB`, `status: Succeeded`).
- `VS_Bulk_Export.customPermission-meta.xml`: description shortened to 231 chars (was ~730+).
- All 5 permission-set descriptions proactively shortened: `VS_District_Admin` 243, `VS_District_MIS` 243, `VS_Facility_Staff` 224, `VS_MO_Facility_Admin` 218, `VS_Nurse` 221 chars — all ≤255. Spot-checked `VS_District_Admin`'s object/field permission blocks: structurally unchanged (no grants/gating altered), description-only edit as claimed.
- `manifest/package.xml` confirmed NOT requiring regeneration (no component added/removed/renamed).

### Step A — dry-run WITH tests (RE-RUN, 2026-07-12 20:10) — FAILED AGAIN, verbatim key lines

```
sf project deploy start --manifest manifest/package.xml --dry-run --test-level RunLocalTests --target-org AgentForceClaudeWorkFlow --json

"errorMessage": "UNKNOWN_EXCEPTION: An unexpected error occurred. Please include this ErrorId if you contact support: 299824955-584671 (-315522575)",
"errorStatusCode": "UNKNOWN_EXCEPTION",
"id": "0AfgL00000QwdreSAB",
"numberComponentErrors": 0,
"numberComponentsDeployed": 0,
"status": "Failed",
"success": false
```

Same error family reproduced despite both original blockers being confirmed fixed — meaning the first pass's analysis was correct but incomplete (the opaque exception was masking more defects than the two found). Re-bisected further (dry-run/`NoTestRun` only, no force-app edits):

1. **Group A** (`VS_Appointment__c`, `VS_Facility_Service__c`, `VS_Facility__c`, `VS_Holiday__c`, `VS_Patient__c` + fields, no CMDT): surfaced **clean, non-opaque component errors** this time (progress):
   - `VS_Appointment__c`: `"problem": "Value too long for field: Description maximum length is:1000"` — confirmed by direct read: description is **1401 chars** (CustomObject cap is 1000, not 255). **Real defect #3.**
   - `VS_Patient__c`: same problem — confirmed **1108 chars**. **Real defect #4.**
   - `VS_Facility_Service__c.VS_Service__c`: `"referenceTo value of 'VS_Service__c' does not resolve to a valid sObject type"` — **bisection artifact, not a real defect** (`VS_Service__c` object simply wasn't included in this partial test manifest; resolves fine in the real full manifest).
   - Full object-description sweep (all 9 objects) confirmed **only these 2** exceed the 1000-char CustomObject limit; the other 7 are 285–764 chars, within limit.

2. **Flows alone** (`VS_FacilityService_BeforeSave_SetExternalId` + `VS_Session_Screen_DefineCapacity`, no dependent objects): also clean errors:
   - `VS_FacilityService_BeforeSave_SetExternalId`: `"We can't find the object specified in the Start element..."` — **bisection artifact** (parent object not in this partial manifest; resolves fine in the full manifest).
   - `VS_Session_Screen_DefineCapacity`: **`"problem": "Error parsing file: Element {http://soap.sforce.com/2006/04/metadata}recordChoiceSets invalid at this location in type Flow"`** — a genuine **XML element-ordering/schema-sequence violation**. The flow's top-level child elements are not in Metadata API XSD-required sequence order (`status` before `start`; `variables` before `recordChoiceSets`; `formulas`/`recordLookups`/`recordCreates` scattered after `screens` instead of grouped per schema). `<recordChoiceSets>` appears twice (lines 30, 49) positioned after `<start>`/`<variables>`, which the schema rejects. **Real defect #5.**

3. **`VS_Session__c` + `VS_Setting__mdt` together** (2 objects only, both otherwise clean/known-good in isolation): **reproduces `UNKNOWN_EXCEPTION`** even in this minimal 2-object pairing (error code `1832326563-521540 (-315522575)`). `VS_Session__c` **alone** (referencing a non-existent `VS_Setting__mdt` in that partial manifest) gives a normal clean error (`"Field VS_Setting__mdt does not exist. Check spelling."`) — NOT `UNKNOWN_EXCEPTION`. `VS_Setting__mdt` **alone** succeeds cleanly. Only the **pairing** crashes opaquely.
   **Analysis:** `VS_Session__c.VS_Walk_In_Reserve_Count__c`/`VS_Bookable_Capacity__c` are formula fields reading `$CustomMetadata.VS_Setting__mdt.WalkInReservePct.VS_Value__c` (the VS-01/VS-02 D-025 contract — field/record/type names all verified correct on disk). This looks like a **known Salesforce Metadata API `--dry-run`/`checkOnly=true` limitation**: formula fields referencing `$CustomMetadata` cannot always be compile-validated when the CMDT type + records are being **created in the same transaction** — check-only mode doesn't commit CMDT records before formula compilation, and instead of a graceful error, this org/API version throws a generic `UNKNOWN_EXCEPTION`. Reproduced identically across every full/near-full bisection in both runs, independent of defects #1–#5.
   **This is NOT a force-app source defect** in the same sense as #1–#5 — it is a deploy-strategy/ordering issue. **Recommended resolution path (human/dev decision, NOT applied by devops without authorization):** (a) split into two deploy phases — Phase 1: `VS_Setting__mdt` (type + 6 records) + everything not referencing it; Phase 2: `VS_Session__c` (and anything else with `$CustomMetadata`-reading formulas) once the CMDT exists in the org — or (b) attempt a real (non-`checkOnly`) deploy once #3/#4/#5 are fixed, since real deploys commit records progressively and may not hit this check-only-specific limitation. Neither option was executed this session.

### Step B — REAL DEPLOY: NOT ATTEMPTED (either run)

Per instruction ("If it FAILS... STOP — do not deploy"), and because neither dry-run passed clean, **no real deploy was run in either attempt**. All commands used `--dry-run`/`checkOnly: true`; **zero components were created in the org** in this session.

### STATUS: DRY-RUN-FAILED (2nd attempt) — BLOCKED pending 3 more source fixes + 1 deploy-strategy decision

- **Blocker 3 (NEW):** `force-app/main/default/objects/VS_Appointment__c/VS_Appointment__c.object-meta.xml` — object `<description>` is 1401 chars, exceeds the 1000-char CustomObject limit; must be shortened.
- **Blocker 4 (NEW):** `force-app/main/default/objects/VS_Patient__c/VS_Patient__c.object-meta.xml` — object `<description>` is 1108 chars, same limit, same fix needed.
- **Blocker 5 (NEW):** `force-app/main/default/flows/VS_Session_Screen_DefineCapacity.flow-meta.xml` — top-level element order violates the Flow metadata XSD sequence (`recordChoiceSets` at lines 30/49 appears after `start`/`variables`; `status` appears before `start`; `formulas`/`recordLookups`/`recordCreates` scattered after `screens`). Needs top-level elements reordered per the Flow schema (safest fix: re-open/re-save in Flow Builder against a connected org, which normalizes order automatically, then re-export; or manually reorder to the XSD sequence).
- **Deploy-strategy decision needed (not a force-app bug):** `VS_Session__c` + `VS_Setting__mdt` in the same check-only transaction reproducibly throws `UNKNOWN_EXCEPTION`, independent of #1–#5. Recommend a two-phase deploy OR a human-authorized real (non-dry-run) deploy attempt once #3–#5 are fixed, to test whether the limitation is check-only-specific.
- All 3 new blockers are dev-owned fixes (devops does not edit `force-app/`). **Once all 3 are fixed AND the deploy-strategy question is resolved, re-run the full dry-run WITH tests before any real-deploy attempt.**

## Errors & resolutions (append-only)

| Date | Scope | Error (component + first line) | Root cause | Fix | Seen before? |
|---|---|---|---|---|---|
| 2026-07-12 | SPRINT-1-ALL dry-run (1st attempt) | `VS_Bulk_Export.customPermission-meta.xml` — "Value too long for field: Description maximum length is:255" | Description authored as a single ~730+ char paragraph, exceeds the 255-char CustomPermission limit | FIXED by dev-mid (confirmed on disk): shortened to 231 chars | First occurrence |
| 2026-07-12 | SPRINT-1-ALL dry-run (1st attempt) | `VS_Setting__mdt.object-meta.xml` — "Cannot specify: deploymentStatus for Custom Metadata Type" | `<deploymentStatus>` element present in a `__mdt` definition; only legal on standard CustomObjects, not Custom Metadata Types — likely copy/pasted from a normal custom-object template | FIXED by dev-mid (confirmed on disk): element removed; standalone dry-run now Succeeds | First occurrence |
| 2026-07-12 | SPRINT-1-ALL dry-run (1st attempt) | Full 95-component manifest — `UNKNOWN_EXCEPTION: An unexpected error occurred... (-315522575)` (generic, no component detail) | Platform-side unhandled exception when the illegal-`deploymentStatus` CMDT was deployed alongside multiple other CustomObjects | Resolved by fixing the row above — but a DIFFERENT recurrence of the same error code appeared on re-run (see below), caused by other defects | First occurrence of this specific trigger |
| 2026-07-12 | SPRINT-1-ALL dry-run (2nd attempt, re-run) | `VS_Appointment__c.object-meta.xml` — "Value too long for field: Description maximum length is:1000" | Object description authored at 1401 chars, over the 1000-char CustomObject cap | NOT YET APPLIED (force-app/ is dev-owned) — shorten to ≤1000 chars | New defect, but **same defect CLASS (description-length overflow) as `VS_Bulk_Export` above — 2nd occurrence** |
| 2026-07-12 | SPRINT-1-ALL dry-run (2nd attempt, re-run) | `VS_Patient__c.object-meta.xml` — "Value too long for field: Description maximum length is:1000" | Object description authored at 1108 chars, over the 1000-char CustomObject cap | NOT YET APPLIED (force-app/ is dev-owned) — shorten to ≤1000 chars | **3rd occurrence of the description-length-overflow defect class (CustomPermission 255-cap, now 2x CustomObject 1000-cap). Flag for retro: recommend a pre-Ready-for-Review lint step that checks every `<description>` against its metadata type's known Metadata API length cap.** |
| 2026-07-12 | SPRINT-1-ALL dry-run (2nd attempt, re-run) | `VS_Session_Screen_DefineCapacity.flow-meta.xml` — "Error parsing file: Element {...}recordChoiceSets invalid at this location in type Flow" | Top-level Flow XML elements not in Metadata API XSD-required sequence order (likely hand-edited rather than saved via Flow Builder, which auto-normalizes order) | NOT YET APPLIED (force-app/ is dev-owned) — reorder top-level elements per Flow schema, or re-save via Flow Builder | First occurrence |
| 2026-07-12 | SPRINT-1-ALL dry-run (both attempts) | Full manifest / `VS_Session__c`+`VS_Setting__mdt` pairing — `UNKNOWN_EXCEPTION (-315522575)` persists even in a clean 2-object isolation test, independent of all 5 fixed/pending source defects | Suspected known Salesforce `checkOnly=true` limitation: formula fields reading `$CustomMetadata` cannot compile-validate against CMDT records created in the same transaction; a real (non-check-only) deploy commits progressively and may not hit this. NOT confirmed as a force-app defect — a deploy-ordering/strategy question for human decision | Not applied — pending human decision: two-phase deploy vs. authorized real-deploy test | **Recurrence of the exact error code (-315522575) across BOTH dry-run attempts, isolated to this specific pairing both times. This is the 2nd session where an aggregate `UNKNOWN_EXCEPTION` masked/mixed genuine defects with an apparent platform behavioral limitation — flag strongly for retro (recommend devops always keep single- and pair-component bisection manifests ready, and recommend dev-side smoke-testing each new CMDT-referencing formula field against a real deploy, not just dry-run, before Ready-for-Review).** |
