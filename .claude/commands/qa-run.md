---
description: Run a QA Engineer — execute an assigned TC range via Playwright (phase QA_IN_PROGRESS)
argument-hint: A|B or a TC range like TC-001..TC-020
---
1. Read PIPELINE_STATE.md; require phase QA_IN_PROGRESS. Resolve $ARGUMENTS to a TC range from test-plan.md's scope split (default: the first unexecuted range).
2. Confirm the target org is the POC scratch org (from .claude/memory/decisions.md / sf config); if unclear, STOP and ask.
3. Launch the qa-engineer subagent for that range: execute TCs, capture evidence, write regression specs, file BUG-### reports (mirror to Jira if connected).
4. On completion print: pass/fail/blocked counts, bugs filed with severity, evidence and regression paths.
