---
description: Run the QA Lead close-out — consolidate results into a GO/NO-GO (phase QA_IN_PROGRESS)
---
1. Read PIPELINE_STATE.md; require phase QA_IN_PROGRESS with at least one /qa-run executed.
2. Launch qa-lead in close-out mode: consolidate TC results + bug reports into test-plan.md's Results section with a GO / NO-GO release recommendation.
3. Print the recommendation and open Sev-1/Sev-2 bugs. NO-GO → bugs route back to /dev-implement. GO → remind that marking DONE is a human gate via /advance.

FINAL VERIFICATION (do not report success until ALL pass — this step is mandatory):
- The expected output file(s) for this command exist and are non-placeholder.
- One run line was appended to .claude/logs/agent-runs.log (format per rules/30 §4).
- One log line was appended to PIPELINE_STATE.md if this run changed phase or completed a work item.
- 02-build/jira-log.md has a status-history line for any ticket whose status changed.
- Any new D-### / A-### referenced in outputs actually exists in .claude/memory/.
If anything is missing, complete it NOW (or have the subagent do so), then report. Never claim done with missing bookkeeping.
