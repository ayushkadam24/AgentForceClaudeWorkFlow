# TC-021 — Config propagation (WalkInReservePct 25→30→25) — MANUAL, BLOCKED programmatically

feature: F-001 slot-booking-core | producing-agent: qa-engineer | date: 2026-07-12
phase: QA_IN_PROGRESS (/qa-run A) | derives-from: 03-qa/test-plan.md TC-021, D-027

## Why this is manual-only

Two programmatic write paths were attempted for real against `VS_Setting__mdt.WalkInReservePct`
(record Id `m00gL00001Ejq3V`) and both were correctly rejected by the platform:

```
PATCH /services/data/v60.0/sobjects/VS_Setting__mdt/m00gL00001Ejq3V
  -> HTTP 400 {"message":"entity type cannot be updated: VS Setting","errorCode":"CANNOT_INSERT_UPDATE_ACTIVATE_ENTITY"}

PATCH /services/data/v60.0/tooling/sobjects/VS_Setting__mdt/m00gL00001Ejq3V
  -> HTTP 404 {"errorCode":"NOT_FOUND","message":"The requested resource does not exist"}
```

(raw responses: `03-qa/evidence/run-A/TC-021-rest-attempt.json`,
`03-qa/evidence/run-A/TC-021-tooling-attempt.json`)

This is consistent with D-027 (this DE org rejects ALL CustomMetadata **record** writes via the
Metadata API in every mode tried at deploy time) extending to the standard/Tooling REST write paths
too — Custom Metadata records on this org are writable **only** via the Setup UI
(Custom Metadata Types → VS Setting → Manage Records → Edit), which requires an interactive browser
session. No browser/Playwright tool was available to this qa-engineer session, so TC-021 is marked
**BLOCKED**, not silently skipped.

## Manual steps (for whoever next has a browser session on `AgentForceClaudeWorkFlow`)

1. Setup → Custom Metadata Types → **VS Setting** → Manage Records.
2. Open **WalkInReservePct**, note current `VS_Value__c = 25`. Edit → set to `30`. Save.
3. Re-open a session with a known `VS_Total_Capacity__c` (or query one via Apex) and confirm
   `VS_Walk_In_Reserve_Count__c` recalculates immediately with **zero code redeploy** —
   e.g. `CEILING(80 * 30 / 100) = 24` (was `20` at 25%). Query via anonymous Apex:
   ```apex
   System.debug([SELECT VS_Total_Capacity__c, VS_Walk_In_Reserve_Count__c, VS_Bookable_Capacity__c
                 FROM VS_Session__c WHERE Id = :sessionId]);
   ```
4. **MANDATORY RESTORE:** edit `WalkInReservePct` back to `VS_Value__c = 25`. Save. Re-confirm the
   same session recalculates back to the original reserve. Every other TC in this plan (and Run B's
   TC-012) assumes `WalkInReservePct = 25` — leaving it at 30 would silently invalidate every other
   capacity-boundary test in the suite.
5. Paste real before/after values into a fresh `03-qa/evidence/run-A/TC-021-manual-<date>.txt` and
   flip this TC's Result row from BLOCKED to PASS/FAIL in `03-qa/test-plan.md` §8 once done.
