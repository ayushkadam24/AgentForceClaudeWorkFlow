---
description: Run a QA Engineer — execute an assigned TC range via Playwright (phase QA_IN_PROGRESS)
argument-hint: A|B or a TC range like TC-001..TC-020
---
1. Read PIPELINE_STATE.md; require phase QA_IN_PROGRESS. Resolve $ARGUMENTS to a TC range from test-plan.md's scope split (default: the first unexecuted range).
2. Confirm the target org is the POC scratch org (from .claude/memory/decisions.md / sf config); if unclear, STOP and ask.
3. Launch the qa-engineer subagent for that range: execute TCs, capture evidence, write regression specs, file BUG-### reports (mirror to Jira if connected).
4. On completion print: pass/fail/blocked counts, bugs filed with severity, evidence and regression paths.

FINAL VERIFICATION (do not report success until ALL pass — this step is mandatory):
- The expected output file(s) for this command exist and are non-placeholder.
- One run line was appended to .claude/logs/agent-runs.log (format per rules/30 §4).
- One log line was appended to PIPELINE_STATE.md if this run changed phase or completed a work item.
- 02-build/jira-log.md has a status-history line for any ticket whose status changed.
- Any new D-### / A-### referenced in outputs actually exists in .claude/memory/.
If anything is missing, complete it NOW (or have the subagent do so), then report. Never claim done with missing bookkeeping.
