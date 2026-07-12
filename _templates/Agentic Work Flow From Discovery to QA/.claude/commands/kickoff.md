---
description: Start the pipeline — verify NOT_STARTED, launch Discovery via ba-analyst
---
1. Read PIPELINE_STATE.md. If phase is not NOT_STARTED, print the state and STOP.
2. Verify all five documents exist under 00-inputs/ (rfp, discovery-notes, current-state, stakeholders, compliance). If any is missing, list what's missing and STOP.
3. Set phase to DISCOVERY (updated_by: human, one log line: "Kickoff approved").
4. Launch the ba-analyst subagent to produce the requirements brief and open-questions register per its instructions.
5. When it finishes, print: paths of files it wrote, count of REQs and open questions, and the suggested next step (/advance).
