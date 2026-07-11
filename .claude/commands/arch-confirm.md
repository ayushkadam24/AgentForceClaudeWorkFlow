---
description: Run the Architect drift check — as-built vs design (phase BA_ARCH_CONFIRM)
---
1. Read PIPELINE_STATE.md; require phase BA_ARCH_CONFIRM (entered via human-approved /advance from DEV_COMPLETE).
2. Launch the architect subagent in Drift-check mode over force-app/ + 02-build/.
3. Print the verdict table (MATCHES / DEVIATES-ACCEPTABLE / DEVIATES-MUST-FIX) and the go/no-go recommendation. MUST-FIX items go back to /dev-implement before the QA gate can be approved.
