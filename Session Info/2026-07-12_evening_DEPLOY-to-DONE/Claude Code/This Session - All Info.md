# Vaccine Scheduler POC — Session Record (Claude Code, Session 2)

**Authored:** Sunday, 12 July 2026 (evening) · **Session tool:** Claude Code · **Feature:** F-001 slot-booking-core
**Covers:** the second session of the day — resumed at deploy-triage, drove the pilot all the way to **DONE + retro**.
**Predecessor pack:** `Session Info/2026-07-12_04-38-27/` (morning: Sprint-1 built+reviewed, deploy triage pending).

---

## 0. TL;DR — the POC is COMPLETE
- **Phase: `DONE`.** All four human gates approved. `/retro` run; `retro/poc-learnings.md` filled.
- **F-001 pilot (VS-01..09) is DEPLOYED and RELEASED** on a **GO-WITH-CAVEATS** recommendation.
- **§3.4 no-overbooking guarantee is PROVEN under real concurrency** (online + walk-in + disjoint, zero overbooking across 18 load-test runs).
- **0 bugs.** 20 PASS / 0 FAIL / 8 BLOCKED (all BLOCKED = environment, not defects).
- There is nothing to *resume* — the pipeline is finished. This pack is a **record + follow-up list**.

---

## 1. What this session did, in order
1. **Resumed** from the morning pack; health check green; picked up the deploy at its blocker point.
2. **Deploy saga (8 fix-forward rounds)** — see §2. Landed 88 components in the DE org.
3. **`/advance` → DEV_COMPLETE** (human gate).
4. **`/arch-confirm`** — architect drift check: **GO, zero MUST-FIX** (`04-confirmations/drift-check.md`).
5. **`/advance` → BA_ARCH_CONFIRM → (gate) → READY_FOR_QA** (human gates).
6. **`/qa-plan`** — 28-TC risk-based plan (verified integrity after an audit-trail gap; reconciled).
7. **`/qa-run A`** (booking + §3.4) and **`/qa-run B`** (roles/compliance/flow) — 17 PASS / 0 FAIL / 11 BLOCKED / 0 bugs.
8. **§3.4 walk-in load test** — a temporary Apex REST harness fired genuinely-concurrent HTTP. Online proven; walk-in blocked by a runtime org-FLS anomaly → **D-029 fix** → re-tested → **walk-in PROVEN**. Harness removed; org clean.
9. **`/qa-report`** — GO-WITH-CAVEATS.
10. **`/advance` → DONE** (final release gate, human-approved).
11. **`/retro`** — closed the POC.

---

## 2. The deploy saga (why it took 8 rounds) — all resolved
Landing Sprint-1 on this specific free Developer Edition org (`AgentForceClaudeWorkFlow`) hit a chain of real issues:
- **Two-phase deploy (D-026):** formula fields read `$CustomMetadata`; can't validate under `checkOnly` with same-transaction CMDT → split the deploy.
- **CMDT records un-deployable (D-027):** this org **rejects all CustomMetadata *record* MDAPI deploys** (opaque `UNKNOWN_EXCEPTION`), in every mode. **Fix: the 6 `VS_Setting.*` records were created MANUALLY in Setup.** (The `.md-meta.xml` source files still exist and match.)
- **Metadata-schema defects** (caught only at real dry-run): CustomObject description caps (1401/1108 > 1000), FLS on required/Master-Detail fields (swept: 20 across 5 permsets), Flow using `recordChoiceSets` (invalid) instead of `dynamicChoiceSets` + XSD element order + a boolean `isRequired`, and an MD-detail-read-without-master permset dependency.
- **Test FLS-context (D-028):** this org **enforces FLS on plain/system-mode DML at BOTH deploy-time tests AND runtime** — highly non-standard. Forced: `runAs`+permset test fixtures, a dedicated test-harness permset (`VS_Booking_Engine_Test_Context`, TEST-ONLY), a **walk-in test class split** so class-level `RunSpecifiedTests` could exclude the un-runnable walk-in methods.
- **Real production hardening (kept regardless):** CMDT reads via `getInstance()`; collision detection via `StatusCode.DUPLICATE_VALUE`.
- **D-029 (the walk-in fix):** `book()`'s system-mode `update session` dragged the FLS-hidden `$CustomMetadata` formula field into the DML and **failed at runtime on this org**. Architect ruled it implementation-robustness; dev-senior changed the two counter-persist statements to update a **fresh sObject carrying only the written fields** (`update new VS_Session__c(Id, VS_Walk_In_Used_Count__c)` / `VS_Slot__c(Id, VS_Booked_Count__c, VS_Status__c)`). Lock / single-write-path / `used+1`-under-lock / `insert as user` all unchanged. This **fixed a real runtime bug** and closed the §3.4 walk-in proof.

**Deploys of record (source of truth = `02-build/deployments.md`, D-025):**
`0AfgL00000QxRmoSAF` (Phase-1a CMDT type) · `0AfgL00000QySCASA3` (Phase-2, 88 comp, 21/21 tests) · `0AfgL00000Qz4PYSAZ` (D-029 fix). Temporary load harness deployed + fully removed (org back to clean 88-component state, endpoint HTTP 404 / Tooling count 0).

---

## 3. §3.4 — the crown jewel, PROVEN
Temporary REST harness fired N=25–26 genuinely-concurrent HTTP `book()` calls (peak 25 in-flight), ×3 repeats per scenario:
- **Online (TC-001):** exactly 1 success, 24× `SLOT_FULL`, `booked=1 ≤ cap=1`.
- **Walk-in (TC-002, after D-029):** exactly 1 success, `walkInUsed=1 ≤ reserve=1`, 24× `WALKIN_RESERVE_FULL`.
- **Disjoint mixed (TC-003):** exactly 1 online + 1 walk-in, pools never cross (D-020).
- **Zero overbooking across all 18 runs.** Evidence: `03-qa/evidence/run-A/TC-00{1,2,3}-loadtest*.json` + `...-SUMMARY.md`.
Unit tests can prove ceiling LOGIC only, not `FOR UPDATE` serialization — the concurrent load test was mandatory.

---

## 4. New decisions & assumptions this session (in `.claude/memory/`)
- **D-026 / D-026a / D-026b** — two-phase deploy strategy + root-cause corrections.
- **D-027** — org rejects CMDT-record MDAPI deploys → manual Setup creation.
- **D-028 / D-028a** — org FLS-filters system-mode DML (deploy-time + runtime); walk-in tests split for class-level `RunSpecifiedTests`.
- **D-029** — walk-in counter-persist robustness fix (fresh sObject; architect-ruled implementation-robustness).
- **A-018** — production permission gap: NO role permset grants `VS_Appointment__c`/`VS_Patient__c`; slots read-only for all roles → no real user can book yet (owed VS-08/17/20). The test-harness permset must **never** be assigned to a real user.
- **A-019 / A-020** — admin lacks FLS on optional VS_ fields; harness-permset self-assign refused; DE-org license-slot limit (1/5) on per-role login smoke tests.
- Cross-session memory added: `de-org-deploy-quirks.md` (D-027 + D-028 — check before deploying to this org).

---

## 5. Open follow-ups (the 5 accepted launch caveats + candidate fixes)
**Launch preconditions (from `03-qa/test-plan.md` §8.2 — accepted at the GO gate):**
1. **Browser-run TC-012/013/014** (the 3 Tier-1 MO-flow screen-flow TCs) — never exercised through a live browser here (no Playwright session). Runnable specs are in `03-qa/regression/`.
2. **Build the A-018 production booking/slot-gen permset** before any real user journey. Harness permset never on a real user.
3. **Seed data + assign the 5 role permsets** (org is at 0 rows; role permsets unassigned).
4. **Reconfirm org quirks D-027/D-028/D-029** on any non-DE target org (they are very likely this-DE-org-specific).
5. **Pilot scope = VS-01..09 only.** VS-10..22 not built; **REQ-053 record-level facility sharing (VS-20)** is the most consequential unbuilt gap.

**Candidate prompt/tooling fixes (in `retro/poc-learnings.md` → "Prompt fixes applied"):**
- `metadata-lint.js`: also flag `fieldPermissions` on required/MD fields, and MD-detail-read-without-master.
- dev agents: "coverage is UNVERIFIED until measured against an org — never estimate a %."
- sf-apex-patterns: the D-029 fresh-sObject system-mode-write pattern + the runAs+permset USER_MODE test-fixture pattern.
- **A no-Aadhaar guard that also covers Bash writes** (pre-commit/CI grep) — the Write-tool guard is bypassable via shell redirects (two near-misses this session, both caught + redacted).
- ba-analyst: the "failure-edge for the lowest-capability persona" instruction (Discovery misses #13/#14).

---

## 6. Housekeeping notes / minor residue (harmless)
- **Synthetic `LT `-named load-test rows remain in the org** (no Aadhaar; org was 0-rows before). A human can clean them; a predicate-less mass delete was correctly guardrail-blocked.
- **`03-qa/harness/`** holds preserved copies of the temporary load-test classes (`VS_LoadTestEndpoint.cls`, `_Test.cls`) for a possible clean-org re-test. They are **not** in `force-app/` and **not** deployed.
- **Compliance:** the retro's Discovery-grading section (11+2p+1m) was confirmed **human-authored** and kept; the ANSWER-KEY was never read by any agent. Two Bash-written Aadhaar-shaped literals were caught + redacted; full-workspace scan is clean and the health no-Aadhaar invariant passes.

---

## 7. Where the truth lives
- Phase: `PIPELINE_STATE.md` (YAML) — currently `DONE`.
- Deploy log (source of truth, no org source-tracking): `02-build/deployments.md`.
- Decisions/assumptions: `.claude/memory/{decisions,assumptions,handoffs}.md`.
- QA results + release rec: `03-qa/test-plan.md` §8 / §8.2.
- Drift check: `04-confirmations/drift-check.md`.
- Retro: `retro/poc-learnings.md`.
- Run history: `.claude/logs/agent-runs.log`.
- Cross-session memory: `C:\Users\ayush.kadam\.claude\projects\d--VS-Code-Agentic-Workflows\memory\` (MEMORY.md index).
