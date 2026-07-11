---
description: Implement a ticket — routes VS-## to dev-senior or dev-mid (phase DEV_IN_PROGRESS)
argument-hint: VS-## [ticket id, e.g. /dev-implement VS-03]
---
1. Read PIPELINE_STATE.md; require phase DEV_IN_PROGRESS.
2. Look up $ARGUMENTS in 02-build/sprint-plan.md. No ticket ID given → list open tickets in dependency order and STOP. Unknown ID → STOP.
3. Check the ticket's routing column and launch THAT subagent (dev-senior or dev-mid) with the ticket ID. Never override routing; a mid ticket that turns out complex comes back for re-routing.
4. On completion print: files created/changed, dry-run/test results, review packet path, and the ticket's new status. If all tickets are now In Review or Done, note that DEV_COMPLETE can be declared via /advance.
