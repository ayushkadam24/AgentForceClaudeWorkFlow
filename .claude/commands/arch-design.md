---
description: Run the Architect — technical design + ERD + epics (phase ARCH_DESIGN)
---
1. Read PIPELINE_STATE.md; require phase ARCH_DESIGN. Require 01-discovery/requirements-brief.md to be non-placeholder; else STOP with reason.
2. Launch the architect subagent in Design mode. If $ARGUMENTS is given, treat it as the design aspect to (re)work (e.g., "data model", "slot integrity").
3. On completion print: object count, epic list, decisions logged (D-###), and REQ→design coverage gaps if any.
