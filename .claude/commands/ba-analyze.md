---
description: Run the BA — produce/refresh requirements brief + open questions (phase DISCOVERY)
---
1. Read PIPELINE_STATE.md; require phase DISCOVERY (else print state and STOP).
2. Launch the ba-analyst subagent. If $ARGUMENTS names specific input docs or sections, scope the pass to those; otherwise full 00-inputs/ pass.
3. On completion print: REQ count by MoSCoW, open-question count by severity, new assumptions logged, and diff summary if the brief already existed.
