---
description: Close the POC — fill retro/poc-learnings.md from the whole run (phase DONE)
---
1. Require phase DONE (or explicit human override noted in the log).
2. Read the full paper trail: PIPELINE_STATE.md log, agent-runs.log, open-questions, decisions, review packets, drift check, test results, bug reports.
3. Fill retro/poc-learnings.md: what each agent got wrong, prompt fixes applied (diff .claude/agents if edited during the run), handoff friction observed, go/no-go evidence.
4. ONLY NOW may the human compare against ANSWER-KEY-intentional-gaps.md — the retro should state which intentional gaps were caught in Discovery and which slipped through. Do not read the key yourself; ask the human to paste the comparison outcome.
