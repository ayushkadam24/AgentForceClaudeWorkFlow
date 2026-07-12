# 🎭 Agent Theater

A tiny VS Code extension that shows the Vaccine Scheduler POC pipeline agents as cartoon
characters — who's on stage, who's blocked, where the pipeline stands.

It is a **pure observer**: it only reads the pipeline's append-only artifacts and never
writes anything. No pipeline rules are touched.

## What it reads

| File | Used for |
|---|---|
| `PIPELINE_STATE.md` | YAML → current phase + next command; log lines → per-agent speech bubbles |
| `.claude/logs/agent-runs.log` | per-agent last command + OK/PARTIAL/BLOCKED status |
| `02-build/deployments.md` | last `### STATUS:` line → deploy banner + devops speech bubble |

File watchers auto-refresh the view whenever any of these change (i.e. whenever an agent
finishes a run and writes its bookkeeping).

## Cartoon states

- **ON STAGE** (bobbing, blue glow) — the most recent actor in the logs
- **BLOCKED** (frowning, shaking, red ⚠) — last run result was BLOCKED
- **PARTIAL** (flat mouth, yellow) — last run result was PARTIAL
- **OK** (smiling, green badge) — last run OK
- **ZZZ** (sleeping) — no log entry in the last 12h (configurable: `agentTheater.staleHours`)

## Run it

1. Open **this folder** (`_tools/agent-theater`) in VS Code.
2. Press **F5** ("Run Agent Theater") — a second VS Code window opens with the pipeline
   project loaded.
3. In that window: `Ctrl+Shift+P` → **Agent Theater: Open**.

No `npm install` needed — plain JavaScript, zero dependencies.

To install permanently instead of F5: `Ctrl+Shift+P` → "Developer: Install Extension from
Location..." → pick this folder.

If your pipeline project lives elsewhere, set `agentTheater.projectRoot` in settings to the
folder containing `PIPELINE_STATE.md`.

## Ideas for v2

- Parse `02-build/jira-log.md` → ticket cards flowing between dev agents
- Gate-approval moments: human character steps forward and the track pulses
- Lane A / Lane B split-stage view when parallel lanes are active (rules/40)
- Sound effect / toast when an agent flips to BLOCKED
