---
description: Run the QA Lead — risk-based test plan + scope split (phase READY_FOR_QA)
---
1. Read PIPELINE_STATE.md; require phase READY_FOR_QA (drift check must be go).
2. Launch the qa-lead subagent to produce 03-qa/test-plan.md with risk tiers, TC-### cases, REQ coverage table, and the run A / run B scope split.
3. On completion print: TC counts by tier, coverage gaps, and the two /qa-run commands to execute next. Set phase QA_IN_PROGRESS.
