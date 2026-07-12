# What's next after Sprint 1 (F-001 pilot DONE)

**State:** F-001 pilot (VS-01..09) DEPLOYED + RELEASED (GO-WITH-CAVEATS). Phase = DONE.
Sprint 2-4 (VS-10..22) = planned, NOT built. This file = the durable next-step list.

---

## A. Make the delivered pilot actually usable (do these FIRST — the engine is proven but no real user can book yet)
1. **A-018 — build the PRODUCTION booking permission set.** HARD BLOCKER. No role permset grants
   `VS_Appointment__c`/`VS_Patient__c` create+FLS, and slots are read-only for all roles — so no real
   staff/portal user can call `book()`. The TEST harness permset (`VS_Booking_Engine_Test_Context`)
   must NEVER be assigned to a real user. (This is VS-08/17/20 scope, pull it forward.)
2. **Seed synthetic data + assign the 5 role permsets** (`VS_Facility_Staff`/`VS_Nurse`/
   `VS_MO_Facility_Admin`/`VS_District_Admin`/`VS_District_MIS`). Org is at 0 rows, permsets unassigned.
   No Aadhaar in any seed data.
3. **Browser-run TC-012/013/014** — the 3 Tier-1 MO screen-flow tests (never run through a live browser
   this cycle; runnable Playwright specs already in `03-qa/regression/`).
4. **Move verification off the DE org** to a scratch org or sandbox. The DE org's quirks (D-027 CMDT
   records not deployable via API; D-028 FLS on system-mode DML) caused most of Sprint 1's deploy pain.

## B. Harden the pipeline BEFORE Sprint 2 (so you don't re-pay Sprint 1's 8-round deploy tax)
5. **Expand `scripts/metadata-lint.js`**: also flag `fieldPermissions` on required/Master-Detail fields,
   and a permset granting object-read on an MD detail without read on its master. (Both cost deploy rounds.)
6. **No-Aadhaar guard that covers Bash writes** — a git pre-commit / CI grep. The Write-tool guard is
   bypassable via shell redirects (2 near-misses this session, both caught + redacted).
7. **Stop/SubagentStop hook** that enforces the audit trail: no subagent "completes" without its
   `agent-runs.log` line AND an updated `next_command`. (Manual reconciliation ate real time.)
8. **`org-capability-probe` script** — on first connect to any org, test CMDT-record deployability +
   FLS-on-system-mode-DML and record to memory. Discover quirks in 30s, not across 8 rounds.

## C. Continue the build — Sprint 2 (only after A+B)
Per `02-build/sprint-plan.md`:
- **VS-10** — `VS_PatientService.findOrCreate` (exact-match de-dup, D-011/D-017).
- **VS-11** — `VS_BookingService.cancel/reschedule` + cut-off (Tier-1; REUSES the §3.4 session lock — treat as crown-jewel-adjacent, load-test it too).
- **VS-12** — `VS_NoShowBatch` (scheduled, idempotent).
Then Sprint 3 (VS-13..16, citizen Experience site + booking LWC + OTP) and Sprint 4 (VS-17..22, SMS seam,
sharing rules, purge, seed). **VS-20 (facility-scoped sharing rules) is the most consequential unbuilt
compliance gap — REQ-053 record-level "staff sees only their facility" is NOT yet enforced.**

## Recommended order
B (quick, ~1 hr) → A (makes the pilot demonstrable/real) → Sprint 2. Doing B first means Sprint 2
deploys in ~2 rounds instead of 8.

---
Full detail: `Session Info/2026-07-12_evening_DEPLOY-to-DONE/Claude Code/This Session - All Info.md`
+ `retro/poc-learnings.md`. Source of truth for state: `PIPELINE_STATE.md`.
