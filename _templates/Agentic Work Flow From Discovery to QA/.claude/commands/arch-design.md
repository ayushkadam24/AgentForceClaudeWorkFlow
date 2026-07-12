---
description: Run the Architect — technical design + ERD + epics (phase ARCH_DESIGN)
---
1. Read PIPELINE_STATE.md; require phase ARCH_DESIGN. Require 01-discovery/requirements-brief.md to be non-placeholder; else STOP with reason.
2. Launch the architect subagent in Design mode. If $ARGUMENTS is given, treat it as the design aspect to (re)work (e.g., "data model", "slot integrity").
3. On completion print: object count, epic list, decisions logged (D-###), and REQ→design coverage gaps if any.

FINAL VERIFICATION (do not report success until ALL pass — this step is mandatory):
- The expected output file(s) for this command exist and are non-placeholder.
- One run line was appended to .claude/logs/agent-runs.log (format per rules/30 §4).
- One log line was appended to PIPELINE_STATE.md if this run changed phase or completed a work item.
- 02-build/jira-log.md has a status-history line for any ticket whose status changed.
- Any new D-### / A-### referenced in outputs actually exists in .claude/memory/.
If anything is missing, complete it NOW (or have the subagent do so), then report. Never claim done with missing bookkeeping.
