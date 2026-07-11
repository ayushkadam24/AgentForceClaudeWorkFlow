---
description: Run the PM — sprint plan + complexity-routed tickets (phase SPRINT_PLANNED)
---
1. Read PIPELINE_STATE.md; require phase SPRINT_PLANNED (set by /advance after design sign-off), or DEV_IN_PROGRESS if $ARGUMENTS = "replan" with a reason.
2. Launch the pm-planner subagent. It writes sprint-plan.md + jira-log.md and mirrors to Jira if the Atlassian MCP is connected.
3. Print: sprint count, tickets per sprint with routing (dev-senior/dev-mid), the REQ coverage table, and any "Needs architect" items.
4. Remind: starting the build is a human gate — run /advance to approve DEV_IN_PROGRESS.
