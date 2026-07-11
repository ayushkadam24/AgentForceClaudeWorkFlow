---
description: Run the PM — sprint plan + complexity-routed tickets (phase SPRINT_PLANNED)
---
1. Read PIPELINE_STATE.md; require phase SPRINT_PLANNED (set by /advance after design sign-off), or DEV_IN_PROGRESS if $ARGUMENTS = "replan" with a reason.
2. Launch the pm-planner subagent. It writes sprint-plan.md + jira-log.md and mirrors to Jira if the Atlassian MCP is connected.
3. Print: sprint count, tickets per sprint with routing (dev-senior/dev-mid), the REQ coverage table, and any "Needs architect" items.
4. Remind: starting the build is a human gate — run /advance to approve DEV_IN_PROGRESS.

FINAL VERIFICATION (do not report success until ALL pass — this step is mandatory):
- The expected output file(s) for this command exist and are non-placeholder.
- One run line was appended to .claude/logs/agent-runs.log (format per rules/30 §4).
- One log line was appended to PIPELINE_STATE.md if this run changed phase or completed a work item.
- 02-build/jira-log.md has a status-history line for any ticket whose status changed.
- Any new D-### / A-### referenced in outputs actually exists in .claude/memory/.
If anything is missing, complete it NOW (or have the subagent do so), then report. Never claim done with missing bookkeeping.
