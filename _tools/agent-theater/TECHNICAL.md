# 🎭 Agent Theater — Technical Documentation

Version 0.1.0 · 2026-07-12 · lives in `_tools/agent-theater/` (outside the pipeline's write-access matrix)

Agent Theater is a zero-dependency VS Code extension that visualizes the AI-assisted Salesforce
delivery pipeline (Vaccine Scheduler POC) as a cast of cartoon characters. It answers, at a glance:
who acted last, who is blocked, where the pipeline stands, whether a human gate is waiting, and how
the deploy saga is going.

---

## 1. Design principles

1. **Pure observer.** The extension only READS pipeline artifacts. It never writes to any pipeline
   file, never changes phase, never touches `force-app/`. The single active thing it can do — the
   🩺 Health button — runs `scripts/health-check.js`, which is itself a read-only audit.
2. **Files are the API.** No hooks into Claude Code. The pipeline's own discipline (append-only
   logs, one-line-per-run, ID schemes from rules/30) makes the artifacts parseable. If the
   bookkeeping is stale, the theater shows stale — that is a feature (it exposes housekeeping debt).
3. **Zero dependencies.** Plain JavaScript, no build step, no npm install. `F5` and it runs.

## 2. Architecture

```
┌────────────────────────── VS Code (Extension Host) ─────────────────────────┐
│ extension.js                                                                │
│  ├─ activate(): registers command, creates STATUS BAR item,                 │
│  │              30s status poll (works without opening the panel)           │
│  ├─ openPanel(): WebviewPanel + FileSystemWatcher + 15s polling fallback    │
│  ├─ collectState(): reads + parses the 6 source files → one JSON snapshot   │
│  ├─ pushState(): snapshot → webview postMessage (+ baton delivery,          │
│  │               + status bar update, + BLOCKED toast notifications)        │
│  └─ runHealthCheck(): child_process exec node scripts/health-check.js       │
└───────────────┬──────────────────────────────────────────────────────────────┘
                │ postMessage({type:"state"|"health"|"error"})
┌───────────────▼───────────────── Webview (sandboxed) ────────────────────────┐
│ media/main.js + media/style.css                                             │
│  ├─ header: phase pill · phase track · gate banner · deploy banner/strip    │
│  ├─ tabs: Stage · Tickets · Timeline · Blockers                             │
│  ├─ SVG cartoon characters (generated in JS, animated in CSS)               │
│  └─ baton-pass animation, health output panel                               │
└──────────────────────────────────────────────────────────────────────────────┘
```

Messages webview → extension: `{type:"refresh"}` and `{type:"health"}` only.

## 3. Data sources & parsing contracts

| File | What is parsed | Contract relied on |
|---|---|---|
| `PIPELINE_STATE.md` | YAML block → phase/next_command/updated_by; log lines → per-agent events | rules/30 §5: one log line per run, `- date \| actor \| message` |
| `.claude/logs/agent-runs.log` | per-agent events with command + OK/PARTIAL/BLOCKED | rules/30 §4 line format |
| `02-build/deployments.md` | main table rows → deploy chips; last `### STATUS:` line → banner + devops bubble | devops ledger format (append-only table + STATUS sections) |
| `02-build/jira-log.md` | register table → ticket cards; status-history lines → kanban column | pm-planner register + `- date \| VS-## \| Old→New \| actor \| note` |
| `01-discovery/open-questions.md` | summary table → open OQ list with severity | BA summary-table format |
| `.claude/memory/handoffs.md` | `**from → to \| date**` headers → baton-pass events | rules/30 §3 handoff notes |

Parsing is defensive: malformed lines are skipped, never fatal. Actor names are normalized
(`"orchestrator (dev-mid + devops)"` → `orchestrator`; start-of-string match wins over substring).

**Timestamp rule:** run-log lines carry `HH:MM`; state-log lines are date-only. Date-only lines are
ranked at 23:59 of their day so a same-day gate approval is not outranked by an earlier timed entry;
they display as a date (no fabricated clock time). Within one file, append order breaks ties.

## 4. State derivation

Per agent, from its latest event: `BLOCKED` → blocked (red, shaking, ⚠) · `PARTIAL` → partial
(yellow, flat mouth) · otherwise → done (green). The most recent actor overall is **ON STAGE**
(blue, bobbing, ★). No event, or last event older than `agentTheater.staleHours` (default 12h) →
sleeping (zzz). DevOps' speech bubble is always overridden by the deploy ledger's last `### STATUS:`.

**Human gates** (from rules/00): `SPRINT_PLANNED→DEV_IN_PROGRESS`, `DEV_COMPLETE→BA_ARCH_CONFIRM`,
`BA_ARCH_CONFIRM→READY_FOR_QA`, `QA_IN_PROGRESS→DONE`. When the current phase is a gate source, the
purple **HUMAN GATE** banner appears, the Human card gets the pulsing spotlight, and the status bar
shows `GATE⛩` on a warning background.

## 5. Features

| Feature | Where | Behavior |
|---|---|---|
| Stage | tab 1 | 11 cartoon cards (9 agents + orchestrator + human), status badge, last command, speech bubble, timestamp |
| Ticket board | tab 2 | kanban: Backlog / In Progress / Ready for Review / Approved; card = VS-##, EP, sprint, routed dev, SCRUM key, fix-forward count; VS-09 wears 👑 |
| Timeline scrubber | tab 3 | slider replays every logged event chronologically; far right = LIVE |
| Blockers | tab 4 | blocked/partial agents, deploy STATUS, open OQ register with severity colors |
| Phase track | header | 10-phase state machine, done/current/future |
| Deploy strip | header | one chip per ledger row: ✅ ok · ❌ failed · 🟡 prepared/partial; hover = scope + result |
| Gate banner | header | purple pulse when a human gate is waiting |
| Status bar item | VS Code bottom bar | `🎭 <phase> · GATE⛩ · ⛔n ⚠n`; red bg if blocked, orange if gate; click opens panel; live without opening the panel |
| Baton pass | stage | new entry in `handoffs.md` → 📨 flies from sender card to receiver card, both glow gold |
| Health | header button | runs `scripts/health-check.js`, shows PASS/FAIL + output inline |
| Notifications | VS Code toast | warning toast whenever an agent newly flips to BLOCKED |
| Refresh | watchers + 15s poll + button | footer "last read" pulses blue on every refresh |

## 6. Setup

### Prerequisites
- VS Code ≥ 1.85 · Node.js on PATH (only needed for the Health button)
- The pipeline project folder (contains `PIPELINE_STATE.md`)

### Option A — Run from source (recommended during development)
1. `File → Open Folder` → select `_tools/agent-theater` (the folder itself, as workspace root).
2. Press **F5** → launch config "Run Agent Theater" opens an **[Extension Development Host]**
   window with `D:\VS Code\Agentic Workflows` pre-loaded.
3. In that window: `Ctrl+Shift+P` → **Agent Theater: Open**.
4. After changing extension code: **Ctrl+R** in the dev-host window reloads it.

⚠ Do NOT press F5 in the pipeline-project window — there F5 belongs to the Salesforce extensions
(Apex Replay Debugger, "log must be generated with…" error).

### Option B — Install into your main VS Code
1. `Ctrl+Shift+P` → **Developer: Install Extension from Location...**
2. In the FOLDER picker, select `_tools/agent-theater` (single-click the folder → Select Folder —
   do not navigate inside it; a file dialog cannot select folders).
3. Reload the window. The 🎭 status bar item appears on startup; open the panel from it or via
   `Ctrl+Shift+P` → Agent Theater: Open.

### Settings
| Setting | Default | Meaning |
|---|---|---|
| `agentTheater.projectRoot` | (auto) | absolute path to the folder containing `PIPELINE_STATE.md`, if not in the open workspace |
| `agentTheater.staleHours` | 12 | hours without a log entry before an agent sleeps |

## 7. Usage tips

- **"Is the pipeline waiting on me?"** — glance at the status bar: `GATE⛩` on orange = yes.
- **Replay a sprint for a demo** — Timeline tab, drag from 0 and narrate; every fix-forward and
  gate shows up in order.
- **Deploy post-mortems** — hover the ❌ chips left-to-right; the tooltip carries scope + error.
- **Test the baton** — append `**qa-lead → qa-engineer | <today>**` to
  `.claude/memory/handoffs.md`, watch the 📨 fly, then remove the line.
- **Sleeping agents that shouldn't be** — usually means `agent-runs.log` bookkeeping is stale;
  run the pipeline's housekeeping (the theater deliberately doesn't lie about it).

## 8. Troubleshooting

| Symptom | Cause → fix |
|---|---|
| "Agent Theater: Open" missing from palette | extension not loaded — F5 route: open dev-host window; install route: reinstall from location + reload |
| F5 shows Apex "log must be generated…" error | you pressed F5 in the SFDX project window — open `_tools/agent-theater` as workspace root instead |
| "could not find PIPELINE_STATE.md" | dev-host opened without the project folder → set `agentTheater.projectRoot` |
| Panel shows old UI (no tabs/gate banner) | dev host running stale code → **Ctrl+R** in the dev-host window |
| Health button says script not found / node error | `scripts/health-check.js` missing or Node not on PATH |
| Card times look "in the future" | timestamps come verbatim from log lines — agents' clocks, not the extension |
| No baton animation | fires only on NEW handoffs while the panel is open (per-session detection; no replay of history) |

## 9. Extending

- **New agent:** add to `KNOWN_AGENTS` (extension.js) + `ROSTER` (main.js — id, label, emoji, color).
- **New file source:** add a `safeRead` + parser in `collectState`, add the file to `watchGlob`,
  render in `main.js`. Keep parsers line-based and defensive.
- **v2 candidates:** traceability explorer (REQ→EP→VS→TC chain), lane A/B split stage (rules/40),
  QA burn-up once TC-###/BUG-### appear in `03-qa/`, gate-approval writeback (would end
  pure-observer status — decide deliberately).

## 10. File map

```
_tools/agent-theater/
├── package.json          manifest: command, settings, onStartupFinished activation
├── extension.js          host: parsers, state, watchers, status bar, health, baton detection
├── media/
│   ├── main.js           webview: rendering, tabs, timeline, baton animation
│   └── style.css         theme-aware styles + all animations
├── .vscode/launch.json   F5 config (opens the pipeline folder in the dev host)
├── README.md             quick start
└── TECHNICAL.md          this document
```
