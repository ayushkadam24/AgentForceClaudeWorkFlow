# Documentation & Artifact Rules (binding for every agent)

1. Every generated artifact starts with a header block:
   feature (F-001), producing agent, date, phase, and the upstream IDs it derives from.
2. ID schemes: REQ-### requirements · OQ-### open questions · D-### decisions · EP-## epics ·
   VS-## tickets · TC-### test cases · BUG-### defects · A-### assumptions.
3. Memory discipline:
   - A decision that constrains later work → one entry in .claude/memory/decisions.md
     (ID, date, decider, decision, rationale, alternatives rejected).
   - An assumption anyone makes → .claude/memory/assumptions.md with owner + how to verify.
   - New domain term → .claude/memory/glossary.md.
   - Phase handoff → append the outgoing agent's 5-line handoff note to .claude/memory/handoffs.md
     (what I produced, what I'm unsure about, what the next role must not miss).
4. Log discipline: one line per agent run in .claude/logs/agent-runs.log:
   `YYYY-MM-DD HH:MM | agent | command | phase | inputs-read | outputs-written | result(OK/PARTIAL/BLOCKED) | note`
5. PIPELINE_STATE.md gets exactly ONE new log line per run; the YAML block only changes per
   the state-machine rules. Nothing else in that file is touched.
6. Markdown artifacts use tables for registers (REQs, OQs, TCs, bugs) and keep one H1 per file.
