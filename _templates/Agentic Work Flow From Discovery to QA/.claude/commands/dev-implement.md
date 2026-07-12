---
description: Implement a ticket — routes T-## to dev-senior or dev-mid (phase DEV_IN_PROGRESS)
argument-hint: T-## [ticket id, e.g. /dev-implement T-03]
---
1. Read PIPELINE_STATE.md; require phase DEV_IN_PROGRESS.
2. LANE CHECK: if a LANE file exists at the project root, this session may only build tickets whose routing matches its lane (A=dev-senior, B=dev-mid) AND whose dependencies are merged to main (rules/40). Filter accordingly.
3. Look up $ARGUMENTS in 02-build/sprint-plan.md. No ticket ID given → list open tickets in dependency order and STOP. Unknown ID → STOP.
3. Check the ticket's routing column and launch THAT subagent (dev-senior or dev-mid) with the ticket ID. Never override routing; a mid ticket that turns out complex comes back for re-routing.
4. On completion print: files created/changed, dry-run/test results, review packet path, and the ticket's new status. If all tickets are now In Review or Done, note that DEV_COMPLETE can be declared via /advance.

FINAL VERIFICATION (do not report success until ALL pass — this step is mandatory):
- The expected output file(s) for this command exist and are non-placeholder.
- One run line was appended to .claude/logs/agent-runs.log (format per rules/30 §4).
- One log line was appended to PIPELINE_STATE.md if this run changed phase or completed a work item.
- 02-build/jira-log.md has a status-history line for any ticket whose status changed.
- Any new D-### / A-### referenced in outputs actually exists in .claude/memory/.
If anything is missing, complete it NOW (or have the subagent do so), then report. Never claim done with missing bookkeeping.
