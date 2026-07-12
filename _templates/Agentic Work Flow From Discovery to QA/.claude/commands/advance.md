---
description: Human gate — summarize current phase output and propose the single next transition
---
1. Read PIPELINE_STATE.md; identify current phase and the ONE next phase in the sequence.
2. Run `node scripts/health-check.js` and `node scripts/metadata-lint.js`; include both outputs in the gate summary — a gate proposal on a FAILing health check must say so in the first line.
3. Summarize what the current phase produced (files + key numbers) and any open risks/blockers from open-questions.md, review packets, or bug reports relevant to this gate.
4. State plainly: "Proposed transition: X → Y. This is a human gate: SPRINT_PLANNED→DEV_IN_PROGRESS, DEV_COMPLETE→BA_ARCH_CONFIRM, BA_ARCH_CONFIRM→READY_FOR_QA, QA_IN_PROGRESS→DONE." 
5. WAIT for explicit approval. Only after the human says yes: update PIPELINE_STATE.md one step, log line "Gate approved by human", and print the command that starts the next phase.
6. Never chain transitions. One /advance = at most one step.
