---
description: Run the QA Lead — risk-based test plan + scope split (phase READY_FOR_QA)
---
1. Read PIPELINE_STATE.md; require phase READY_FOR_QA (drift check must be go).
2. Launch the qa-lead subagent to produce 03-qa/test-plan.md with risk tiers, TC-### cases, REQ coverage table, and the run A / run B scope split.
3. On completion print: TC counts by tier, coverage gaps, and the two /qa-run commands to execute next. Set phase QA_IN_PROGRESS.

FINAL VERIFICATION (do not report success until ALL pass — this step is mandatory):
- The expected output file(s) for this command exist and are non-placeholder.
- One run line was appended to .claude/logs/agent-runs.log (format per rules/30 §4).
- One log line was appended to PIPELINE_STATE.md if this run changed phase or completed a work item.
- 02-build/jira-log.md has a status-history line for any ticket whose status changed.
- Any new D-### / A-### referenced in outputs actually exists in .claude/memory/.
If anything is missing, complete it NOW (or have the subagent do so), then report. Never claim done with missing bookkeeping.
