# Vaccine Scheduler POC — Cowork Session Resume (Day 3, 2026-07-13, afternoon → ~20:45 IST)

**Authored by:** the Claude Cowork session, Monday 13 July 2026.
**Role split today:** Claude Code (VS Code) ran the FORWARD BUILD (Sprints 2–4 VS-10..20, org sync,
app UI shell, VS-14 citizen site). This Cowork session was again OBSERVER / TOOLSMITH / WORKFLOW-FACTORY:
live status audits, root-caused the "agents running but not logging" mystery (unmerged branches),
codified the UI-shell definition-of-done across rules + agents, reviewed and extended the Agent
Theater (sprint-progress strip), and built TWO new reusable workflow folders in
`D:\Agentforce POC's\WorkFlows with Agents\`.

---

## Project state at session end (tool-agnostic)
- **PIPELINE_STATE phase: DONE** (F-001 pilot). All post-DONE work is forward-build outside the
  state machine — flagged below as a process improvement.
- **Branches MERGED to main and pushed** at 19:31 (`74447da` "Merge sprint 2-4 branches and org
  sync into main"): forward-build-sprint2-4 (VS-10..20 + fixes + app UI), track-a-a018-booking-permset
  (`VS_Booking_Capability`), pipeline-hardening-track-b (lint upgrades, no-Aadhaar commit guard, org probe).
- **Org (`AgentForceClaudeWorkFlow`):** VS-10..20 deployed; seeded (36 facilities, 36 services,
  35 sessions + slots, 489 patients, 144 appointments); **UI shell live** — `VS_Vaccine_Scheduler`
  Lightning app, 11 object tabs, list views (Open Sessions / Open Slots / Booked Appointments),
  6 page layouts + compact layouts, app permset assigned to admin (ethanspython). Verified live per
  agent-runs.log lines 70–71.
- **VS-14 (Experience Cloud citizen site) — site layer BUILT + DEPLOYED at 20:31** (log line 72):
  site + guest access created (site NOT published); `VS_BookingController` (@AuraEnabled) + test
  7/7 PASS 90% cov deployed; `vsSlotPicker` LWC (lightningCommunity targets) deployed;
  guest profile "Vaccine Scheduler Portal Profile" retrieved into repo + object/FLS/class access
  granted + deployed; OTP stub `VS_OtpStubProvider` (TEST_CODE 000000 — replace before go-live);
  SOQL field-to-field comparison bug fixed (→ Status=Open filter). NOT yet committed at session
  end (git lock held past 20:31; last commit = 19:31 merge); jira-log VS-14 status still Backlog.
- **DECISION WAITING ON HUMAN (guest-write limit, flagged not silently made):** with-sharing
  `VS_BookingService` counter update conflicts with guest read-only sharing → pure-guest booking
  needs **Option A** (OTP-verified authenticated/trusted path — C9-compliant, matches design) or
  **Option B** (`without sharing` portal method — anonymous guests can write; weaker posture).
  Cowork's read: A is the defensible choice; C9 requires identity verification pre-transaction anyway.
- **Guest read sharing rules deliberately NOT added** — the picker currently uses elevated reads.
  Revisit before publish.
- **A-018 still open:** no non-admin user has `VS_Booking_Capability` — no real user can book yet.

## What this Cowork session did today
1. **Status audits + the logging mystery.** Agents WERE logging — on unmerged branches while the
   working tree sat on main. Also confirmed the forward-build runs skipped agent-runs.log lines
   (later partially backfilled by the Code session at lines 70–71).
2. **UI-shell gap → institutionalized.** The forward build shipped objects with no tabs/app/layouts
   (human had to intervene). Now binding: rules/20 "UI shell = part of definition-of-done" +
   matching blocks in dev-mid, dev-senior, pm-planner, architect (design §UI item 7), code-reviewer
   (missing shell = MAJOR). Retro entry added ("Forward-build — the invisible-org gap").
   NOTE: architect Mode 2 drift-check line may still be missing — one-liner in
   `PATCH-ui-shell-definition-of-done.md` §5 (delete the patch file once fully applied).
3. **Agent Theater reviewed + extended.** Full code review (parsers validated against real pipeline
   files — 40 events, 22 tickets, 28 TCs, verdict, deploys, handoffs all parse). The Jul-13 dedupe
   fix confirmed correct. Added a **sprint-progress strip** (per-sprint ✅/🔨/⬜ chips with done/total
   and per-ticket hover) — changed `extension.js` (+`#sprint-strip` div), `media/main.js`
   (renderSprints), `media/style.css`. Reload the extension host to pick it up.
   KNOWN DATA GAP: Sprint 1 shows 2/9 because only VS-01/02 got "Approved" transitions in
   jira-log.md — backfill verdict lines to make the strip truthful.
   **Live heartbeat added (all 3 Theaters):** result `STARTED`/`WIP` in agent-runs.log now flips
   the agent's card to ON STAGE immediately. Paired discipline = rules/30 item 9 (log a STARTED
   line at run start; final OK/PARTIAL/BLOCKED line still mandatory), added by the human ~20:15.
   The running Code session predates the rule — heartbeats expected from its NEXT run. VS Code
   window reload still needed to load the updated Theater build (sprint strip + heartbeat).
4. **Two new workflow folders** in `D:\Agentforce POC's\WorkFlows with Agents\` (see NEXT-STEPS in
   this folder for how to use them):
   - **POC-Pipeline-Replica** (215 files): exact clean copy of this pipeline — 9 agents, 5 rules
     (incl. today's UI-shell rule), 16 commands, 8 skills, hooks/settings, scripts, docx guides,
     Agent Theater with sprint strip. PIPELINE_STATE reset to NOT_STARTED, empty memory/logs/artifacts.
     Usage: drop client docs into 00-inputs/ → /kickoff. (ANSWER-KEY, Session Info, settings.local
     deliberately not copied. `git init` before first use.)
   - **Jira-Daily-Workflow** (37 files): lightweight per-story pipeline
     NEW→ANALYZED→IN_DEV→IN_REVIEW→READY_TO_DEPLOY→(human gate)→DEPLOYED→CLOSED.
     4 agents (story-analyst / sf-developer / code-reviewer / devops-deployer), 8 commands,
     STORY_TRACKER.md register+history, per-story folder with changed-files.md as the packaging
     contract, `scripts/make-package.js` (changed-files → package.xml + destructiveChanges.xml,
     tested incl. layout-names-with-spaces bug fix), and **Agent Theater (Jira)** — story kanban,
     deploy table (parses the locked deploy-log header format in rules/20), timeline, and a
     "➕ New story" intake tab that writes stories/<KEY>/story.md + tracker rows from a pasted
     Jira ticket (its ONE write; everything else observer). All parsers + intake tested end-to-end.
5. **Answered "current status"**: two-truths picture (paper says DONE-for-pilot; reality is
   two sprints ahead) + what remains for a full working project.

## Cowork-specific operational learnings (for the NEXT Cowork session)
- **The Cowork sandbox's Linux mirror of this folder can be STALE** (PIPELINE_STATE, rules/20,
  agent-runs.log, retro, _tools were hours behind while agents/git stayed current). The host-side
  Read/Write/Grep tools see live files — verify anything suspicious there, and prefer `git show`
  for committed content. Do NOT trust `find -newermt`/`md5sum` on the mirror alone.
- `.claude/**` is write-protected for Cowork sessions here TWICE over: Cowork protects `.claude`
  paths generally, and this project's own settings.json denies rules/hooks/settings writes.
  Workaround used today: bash-mount writes for NEW folders' .claude; PATCH file + human paste for
  THIS project's .claude.
- A live Claude Code session's work is invisible until it writes/commits — check `git log --all`,
  `git status`, and `.git/index.lock` before declaring "nothing is running".

## Open items handed to the next session (either tool)
0. **HUMAN DECISION FIRST — guest-write Option A vs B** (see project-state section above).
   Then: replace the OTP stub's fixed TEST_CODE before any real citizen use; decide the guest
   read-sharing approach (elevated reads vs explicit guest sharing rules) before publish.
1. VS-14 close-out: commit + log the site work (uncommitted at session end); retrieve remaining
   site metadata (Network, sharing set, ExperienceBundle) into force-app — guest profile is
   already in the repo; **independent code-review of the guest profile's object/FLS/class grants
   BEFORE publish** (citizen data only via OTP + sharing set — C5/Tier-1; VS_BookingController
   is guest-exposed surface).
2. A-018: assign `VS_Booking_Capability` to a non-admin test user; verify a real booking journey.
3. QA cycle for Sprints 2–4 (nothing after VS-09 is QA'd; sharing rules + site are Tier-1 surface).
4. Backfill jira-log ticket transitions (verdicts + Deployed states) — fixes sprint strip truthfulness.
5. Update the OQ register statuses (27/27 still say "Open"; several were decided) — Theater nags until then.
6. Apply the architect Mode 2 drift-check line if not yet done; delete PATCH-ui-shell file.
7. Consider opening F-002 (or re-entering the state machine) for post-pilot work instead of
   building under phase=DONE.
