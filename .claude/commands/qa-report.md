---
description: Run the QA Lead close-out — consolidate results into a GO/NO-GO (phase QA_IN_PROGRESS)
---
1. Read PIPELINE_STATE.md; require phase QA_IN_PROGRESS with at least one /qa-run executed.
2. Launch qa-lead in close-out mode: consolidate TC results + bug reports into test-plan.md's Results section with a GO / NO-GO release recommendation.
3. Print the recommendation and open Sev-1/Sev-2 bugs. NO-GO → bugs route back to /dev-implement. GO → remind that marking DONE is a human gate via /advance.
