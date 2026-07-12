---
description: Run the BA — produce/refresh requirements brief + open questions (phase DISCOVERY)
---
1. Read PIPELINE_STATE.md; require phase DISCOVERY (else print state and STOP).
2. Launch the ba-analyst subagent. If $ARGUMENTS names specific input docs or sections, scope the pass to those; otherwise full 00-inputs/ pass.
3. On completion print: REQ count by MoSCoW, open-question count by severity, new assumptions logged, and diff summary if the brief already existed.

FINAL VERIFICATION (do not report success until ALL pass — this step is mandatory):
- The expected output file(s) for this command exist and are non-placeholder.
- One run line was appended to .claude/logs/agent-runs.log (format per rules/30 §4).
- One log line was appended to PIPELINE_STATE.md if this run changed phase or completed a work item.
- 02-build/jira-log.md has a status-history line for any ticket whose status changed.
- Any new D-### / A-### referenced in outputs actually exists in .claude/memory/.
If anything is missing, complete it NOW (or have the subagent do so), then report. Never claim done with missing bookkeeping.
