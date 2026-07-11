# Resume Runbook — start here tomorrow

Everything below assumes tonight's git push included the 2026-07-12 .claude improvements
(metadata-limits reference, scripts/metadata-lint.js, rules/20+30 additions, agent patches,
/advance health step, CLAUDE.md config-boundaries note).

## Step 0 — tonight, before closing
    git add -A
    git commit -m "checkpoint: sprint-1 built+reviewed, deploy triage pending; .claude v2 improvements"
    git push
Then exit Claude Code (/exit) and delete the Cowork session. Nothing of value lives in either
conversation — the files are the memory.

## Step 1 — resume Claude Code (the pipeline)
1. Open "D:\VS Code\Agentic Workflows" in VS Code → start a FRESH claude session.
   (Fresh matters: the Stop/SubagentStop bookkeeping hooks only load at session start.)
2. First message — paste exactly:

   Read, in order:
   "Session Info/2026-07-12_04-38-27/Claude Code/This Session - All Info.md" and
   "Session Info/2026-07-12_04-38-27/Claude Cowork/This Session - All Info.md".
   Then run /status, node scripts/health-check.js and node scripts/metadata-lint.js.
   First do housekeeping until the health check reports 0 FAIL 0 WARN (backfill
   agent-runs.log, PIPELINE_STATE log lines, D-005..D-025 + A-003..A-017 into
   .claude/memory/, jira-log status lines VS-01..09, runbook completion).
   Then resume the deploy at the recorded blocker point: fix VS-07/VS-08 object
   descriptions (>1000 — move rationale to packets), VS-03 flow element order,
   decide the two-phase CMDT deploy strategy (metadata-lint flags the two
   $CustomMetadata formulas), then dry-run → real deploy → sf apex run test
   --code-coverage → record verdicts from REAL results → Bucket B items into
   .claude/memory/handoffs.md → update ledgers/runbook → STOP before /advance.

3. Verify enforcement is finally live: after its first work run, check that
   .claude/logs/agent-runs.log grew. If an agent finishes without logging, the stop-guard
   is not loaded — you are not in a fresh session.
4. Your gates for the day: approve /advance → DEV_COMPLETE, then /arch-confirm (drift check
   incl. Bucket B rulings), then /advance → READY_FOR_QA, /qa-plan, /qa-run A|B, /qa-report.

## Step 2 — resume Claude Cowork (the auditor/toolsmith), optional but recommended
1. New Cowork session → connect the same folder ("Add folder" in the desktop app).
2. First message — paste:

   Read "Session Info/2026-07-12_04-38-27/Claude Cowork/This Session - All Info.md"
   (especially the operational-notes section) and the RESUME-TOMORROW.md beside it.
   You are resuming as the pipeline's outside auditor and toolsmith. Verify current
   state from file evidence (health check + metadata lint via device_bash), report
   status, and stand by for improvement work. Do not open
   ANSWER-KEY-intentional-gaps.md — grading is complete and recorded in retro/.

## Known traps (do not rediscover these)
- git through the Cowork device bridge is broken — git runs in your terminal or Claude Code only.
- Hooks bind Claude Code, not Cowork's shell. Hook/CLAUDE.md edits need a session restart.
- Jira project key is SCRUM (not VS): VS-nn = SCRUM-(nn+12), epics EP-01..08 = SCRUM-5..12.
  Atlassian MCP still not connected (D-004) — jira-log.md is ticket truth.
- The DE org is the ONLY deploy target; the pretool guardrail blocks prod-looking targets.
- Deploy failures: capture → record in deployments.md Errors table → bisect → classify —
  never retry an unchanged deploy (devops protocol, now default).
