---
description: Run the Architect drift check — as-built vs design (phase BA_ARCH_CONFIRM)
---
1. Read PIPELINE_STATE.md; require phase BA_ARCH_CONFIRM (entered via human-approved /advance from DEV_COMPLETE).
2. Launch the architect subagent in Drift-check mode over force-app/ + 02-build/.
3. Print the verdict table (MATCHES / DEVIATES-ACCEPTABLE / DEVIATES-MUST-FIX) and the go/no-go recommendation. MUST-FIX items go back to /dev-implement before the QA gate can be approved.

FINAL VERIFICATION (do not report success until ALL pass — this step is mandatory):
- The expected output file(s) for this command exist and are non-placeholder.
- One run line was appended to .claude/logs/agent-runs.log (format per rules/30 §4).
- One log line was appended to PIPELINE_STATE.md if this run changed phase or completed a work item.
- 02-build/jira-log.md has a status-history line for any ticket whose status changed.
- Any new D-### / A-### referenced in outputs actually exists in .claude/memory/.
If anything is missing, complete it NOW (or have the subagent do so), then report. Never claim done with missing bookkeeping.
