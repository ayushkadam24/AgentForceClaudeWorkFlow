---
description: DevOps — prepare, validate and (on your approval) execute + record a deployment
argument-hint: T-## | "sprint-1" | "all" | "drift-check"
---
1. Read PIPELINE_STATE.md; require DEV_IN_PROGRESS or later.
2. Launch the devops subagent with $ARGUMENTS:
   - T-## → delta manifest for that ticket's components; "sprint-1"/"all" → batch manifest;
   - "drift-check" → org-vs-source drift report only, no deploy.
3. The agent prepares the manifest, dry-run validates, runs relevant Apex tests, then STOPS and
   shows you the exact deploy command and validation evidence.
4. Only after your explicit "yes": it executes, records deploy ID + result in
   02-build/deployments.md, updates the ticket in jira-log.md (Deployed-to-POC note), and logs the run.

FINAL VERIFICATION (do not report success until ALL pass — this step is mandatory):
- The expected output file(s) for this command exist and are non-placeholder.
- One run line was appended to .claude/logs/agent-runs.log (format per rules/30 §4).
- One log line was appended to PIPELINE_STATE.md if this run changed phase or completed a work item.
- 02-build/jira-log.md has a status-history line for any ticket whose status changed.
- Any new D-### / A-### referenced in outputs actually exists in .claude/memory/.
If anything is missing, complete it NOW (or have the subagent do so), then report. Never claim done with missing bookkeeping.
