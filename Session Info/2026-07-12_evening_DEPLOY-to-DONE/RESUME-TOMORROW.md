# Resume Runbook — start here next session

**The POC is DONE.** All 4 gates approved, F-001 pilot released GO-WITH-CAVEATS, /retro complete.
There is no pipeline state to resume — this runbook is follow-up work, not recovery.

## Step 0 — tonight, before closing
    git add -A
    git commit -m "POC complete: F-001 released GO-WITH-CAVEATS; retro + session packs + agent-theater + templates"
    git push
The files are the memory; neither conversation holds anything the packs don't.

## Step 1 — read first (any fresh session)
1. `Session Info/2026-07-12_evening_DEPLOY-to-DONE/Claude Code/This Session - All Info.md`
2. `Session Info/2026-07-12_evening_DEPLOY-to-DONE/Claude Cowork/This Session - All Info.md`
3. `retro/poc-learnings.md` + both `Agents Improvement Areas.md` files
Then `/status` + `node scripts/health-check.js` to confirm the DONE baseline is clean.

## Track A — productionizing the pilot (the 5 accepted release caveats)
1. Run browser TCs TC-012/013/014 (MO capacity flow) — needs Playwright/browser env; specs are
   pre-written in 03-qa/. Must pass before any real MO uses the flow.
2. Build the A-018 production booking/slot-gen permission set. The TEST harness permset
   (VS_Booking_Engine_Test_Context) must NEVER be assigned to a real user.
3. Seed data + assign role permsets (org has 0 rows; A-020 license-slot limit applies).
4. Any migration off the DE org: re-confirm quirks D-027 (CMDT records), D-028 (FLS on DML in
   deploy tests), D-029 behavior on the target org before trusting the deploy plan.
5. Scope reminder: VS-10..22 unbuilt; REQ-053 record-level facility sharing (VS-20) is the most
   consequential gap if real multi-facility users arrive.

## Track B — Sprint 2 (if the POC continues)
Re-enter the state machine at SPRINT_PLANNED semantics: /pm-plan already has VS-10..22 forward-
planned in 02-build/sprint-plan.md; human gate → DEV_IN_PROGRESS; build order respects the
Depends-on lines in jira-log.md. Fold both Agents Improvement Areas files into rules/agents FIRST
(cheap now, expensive later).

## Track C — tooling & templates
1. Move `_templates/Agentic Work Flow From Discovery to QA` and `_templates/Agentic Work Flow for
   Tickets` to `D:\Agentforce POC's\WorkFlows with Agents\`. On first real use of Template 1,
   complete its SETUP.md (tokens, client docs, rules/10 rewrite, org alias).
2. Agent Theater (`_tools/agent-theater/`): F5 from that folder as workspace root → dev-host →
   "Agent Theater: Open". Docs: README.md + TECHNICAL.md. v2 ideas in TECHNICAL.md §9.
3. `_to_delete/` contains a superseded duplicate session folder — empty it when convenient
   (the device-bridge mount cannot delete; do it in Explorer).

## Housekeeping notes
- Fresh Claude Code sessions load hooks/CLAUDE.md at start — restart after editing them.
- agent-runs.log must stay one-line-per-run; /health FAILs loudly on staleness — treat that as a gate.
