// Agent Theater — cartoon view of the AI delivery-pipeline agents.
// Reads only append-only pipeline artifacts. Never writes to the pipeline. Pure observer.
// (Exception: the Health tab RUNS scripts/health-check.js, which is itself read-only.)

const vscode = require("vscode");
const path = require("path");
const fs = require("fs");
const { exec } = require("child_process");

const PHASES = [
  "NOT_STARTED", "DISCOVERY", "ARCH_DESIGN", "SPRINT_PLANNED", "DEV_IN_PROGRESS",
  "DEV_COMPLETE", "BA_ARCH_CONFIRM", "READY_FOR_QA", "QA_IN_PROGRESS", "DONE"
];

// Human gates per rules/00: phase → the transition awaiting human approval.
const GATES = {
  SPRINT_PLANNED: "DEV_IN_PROGRESS",
  DEV_COMPLETE: "BA_ARCH_CONFIRM",
  BA_ARCH_CONFIRM: "READY_FOR_QA",
  QA_IN_PROGRESS: "DONE"
};

const KNOWN_AGENTS = [
  "ba-analyst", "architect", "pm-planner", "dev-senior", "dev-mid",
  "code-reviewer", "qa-lead", "qa-engineer", "devops", "orchestrator", "human"
];

let panel = null;
let prevStatuses = {};     // for BLOCKED-transition notifications
let statusItem = null;     // status bar: phase + blocked count
let prevHandoffCount = -1; // for baton-pass animation
let pendingBaton = null;   // held until the panel consumes it

function activate(context) {
  context.subscriptions.push(
    vscode.commands.registerCommand("agentTheater.open", () => openPanel(context))
  );

  // Status bar item — visible without opening the panel (activation: onStartupFinished).
  statusItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 100);
  statusItem.command = "agentTheater.open";
  statusItem.text = "🎭 Theater";
  statusItem.tooltip = "Agent Theater — click to open";
  statusItem.show();
  context.subscriptions.push(statusItem);

  const root = findProjectRoot();
  if (root) {
    updateStatusBar(root);
    const t = setInterval(() => updateStatusBar(root), 30000);
    context.subscriptions.push({ dispose: () => clearInterval(t) });
  }
}

function updateStatusBar(root) {
  if (!statusItem) return;
  try {
    applyStatusBar(collectState(root, null));
  } catch { /* keep last known status */ }
}

function openPanel(context) {
  const root = findProjectRoot();
  if (!root) {
    vscode.window.showErrorMessage(
      "Agent Theater: could not find PIPELINE_STATE.md in any open workspace folder. " +
      "Open the pipeline project folder, or set agentTheater.projectRoot in settings."
    );
    return;
  }

  if (panel) { panel.reveal(); pushState(root, null, true); return; }

  lastSnapshotKey = null; // fresh panel = fresh webview; never dedupe its first snapshot

  panel = vscode.window.createWebviewPanel(
    "agentTheater", "Agent Theater", vscode.ViewColumn.Beside,
    {
      enableScripts: true,
      retainContextWhenHidden: true,
      localResourceRoots: [vscode.Uri.file(path.join(context.extensionPath, "media"))]
    }
  );
  panel.onDidDispose(() => { panel = null; }, null, context.subscriptions);

  const mediaUri = (f) =>
    panel.webview.asWebviewUri(vscode.Uri.file(path.join(context.extensionPath, "media", f)));
  panel.webview.html = getHtml(panel.webview, mediaUri);

  panel.webview.onDidReceiveMessage((msg) => {
    if (!msg) return;
    // force=true: webview-requested refreshes must always be answered, even if the
    // snapshot is unchanged — the initial pushState can be dropped while the webview
    // is still loading, and the dedupe key must not swallow the retry.
    if (msg.type === "refresh") pushState(root, null, true);
    if (msg.type === "health") runHealthCheck(root);
  }, null, context.subscriptions);

  const watchGlob =
    "{PIPELINE_STATE.md,.claude/logs/agent-runs.log,02-build/deployments.md,02-build/jira-log.md,01-discovery/open-questions.md,.claude/memory/handoffs.md,03-qa/test-plan.md,03-qa/bug-reports/*}";
  const watcher = vscode.workspace.createFileSystemWatcher(
    new vscode.RelativePattern(root, watchGlob)
  );
  // Debounce: agents often append to several files in one burst — coalesce to one refresh.
  let debounce = null, lastChanged = null;
  const onFileEvent = (uri) => {
    lastChanged = path.basename(uri.fsPath);
    clearTimeout(debounce);
    debounce = setTimeout(() => pushState(root, lastChanged), 400);
  };
  watcher.onDidChange(onFileEvent); watcher.onDidCreate(onFileEvent);
  panel.onDidDispose(() => clearTimeout(debounce), null, context.subscriptions);
  context.subscriptions.push(watcher);

  // Polling fallback — watchers can miss events on some Windows setups.
  const poll = setInterval(() => pushState(root), 15000);
  panel.onDidDispose(() => clearInterval(poll), null, context.subscriptions);

  pushState(root);
}

function findProjectRoot() {
  const cfg = vscode.workspace.getConfiguration("agentTheater").get("projectRoot");
  if (cfg && fs.existsSync(path.join(cfg, "PIPELINE_STATE.md"))) return cfg;
  for (const f of vscode.workspace.workspaceFolders || []) {
    if (fs.existsSync(path.join(f.uri.fsPath, "PIPELINE_STATE.md"))) return f.uri.fsPath;
  }
  return null;
}

// mtime-based read cache: files are re-parsed only when they actually changed.
const fileCache = new Map(); // path → { mtimeMs, txt }
function safeRead(p) {
  try {
    const mtimeMs = fs.statSync(p).mtimeMs;
    const hit = fileCache.get(p);
    if (hit && hit.mtimeMs === mtimeMs) return hit.txt;
    const txt = fs.readFileSync(p, "utf8");
    fileCache.set(p, { mtimeMs, txt });
    return txt;
  } catch { return ""; }
}

function normalizeActor(raw) {
  if (!raw) return null;
  const lower = raw.toLowerCase().trim();
  for (const a of KNOWN_AGENTS) if (lower.startsWith(a)) return a;
  for (const a of KNOWN_AGENTS) if (lower.includes(a)) return a;
  return null;
}

function parseTs(dateStr) {
  const m = /^(\d{4})-(\d{2})-(\d{2})(?:\s+(\d{1,2}):(\d{2}))?/.exec((dateStr || "").trim());
  if (!m) return { ts: 0, dateOnly: true };
  const dateOnly = m[4] === undefined;
  const ts = new Date(+m[1], +m[2] - 1, +m[3],
    dateOnly ? 23 : +m[4], dateOnly ? 59 : +m[5]).getTime();
  return { ts, dateOnly };
}

function parsePipelineState(txt) {
  const out = { yaml: {}, events: [] };
  const ym = /^---\s*\n([\s\S]*?)\n---/m.exec(txt);
  if (ym) {
    for (const line of ym[1].split("\n")) {
      const kv = /^(\w+):\s*(.*)$/.exec(line.trim());
      if (kv) out.yaml[kv[1]] = kv[2];
    }
  }
  let seq = 0;
  for (const line of txt.split("\n")) {
    const m = /^-\s+([\d-]+(?:\s+[\d:]+)?)\s*\|\s*([^|]+?)\s*\|\s*(.+)$/.exec(line.trim());
    if (!m) continue;
    const agent = normalizeActor(m[2]);
    if (!agent) continue;
    const t = parseTs(m[1]);
    out.events.push({
      ts: t.ts, dateOnly: t.dateOnly, seq: seq++, source: "state-log", agent,
      command: null, phase: null, result: null, note: m[3].trim()
    });
  }
  return out;
}

function parseRunLog(txt) {
  const events = [];
  let seq = 0;
  for (const line of txt.split("\n")) {
    if (!line.trim() || line.trim().startsWith("#")) continue;
    const parts = line.split("|").map((s) => s.trim());
    if (parts.length < 3) continue;
    const agent = normalizeActor(parts[1]);
    if (!agent) continue;
    const result = parts.find((p) => /^(OK|PARTIAL|BLOCKED)$/i.test(p)) || null;
    const t = parseTs(parts[0]);
    events.push({
      ts: t.ts, dateOnly: t.dateOnly, seq: seq++, source: "run-log", agent,
      command: parts[2] || null, phase: parts[3] || null,
      result: result ? result.toUpperCase() : null,
      note: parts[parts.length - 1] || ""
    });
  }
  return events;
}

function parseDeployStatus(txt) {
  const matches = [...txt.matchAll(/^###\s+STATUS:\s*(.+)$/gm)];
  return matches.length ? matches[matches.length - 1][1].trim() : null;
}

/** deployments.md main table rows → deploy-history chips. */
function parseDeploys(txt) {
  const deploys = [];
  for (const line of txt.split("\n")) {
    if (!/^\|\s*\d{4}-\d{2}-\d{2}/.test(line.trim())) continue;
    const cells = line.split("|").map((s) => s.trim());
    // | date | scope | manifest | target | deployId | dryrun | tests | result | by |
    if (cells.length < 10) continue;
    const result = cells[8] || "";
    const cls = /DEPLOYED|SUCCE/i.test(result) ? "ok"
      : /FAILED|BLOCKED/i.test(result) ? "fail"
      : "warn"; // PREPARED / PARTIAL / ESCALATED
    deploys.push({
      date: cells[1], scope: (cells[2] || "").slice(0, 90),
      result: result.slice(0, 160), cls
    });
  }
  return deploys;
}

/** jira-log.md → ticket register + latest status from the status-history lines. */
function parseTickets(txt) {
  const tickets = {};
  // Register rows: | VS-01 | Title | EP-01 | dev-mid | M | 1 | SCRUM-13 |
  for (const line of txt.split("\n")) {
    const m = /^\|\s*(VS-\d{2})\s*\|([^|]+)\|\s*(EP-\d{2})\s*\|([^|]+)\|([^|]+)\|([^|]+)\|([^|]*)\|/.exec(line.trim());
    if (!m) continue;
    tickets[m[1]] = {
      id: m[1], title: m[2].trim(), ep: m[3], routing: m[4].trim(),
      estimate: m[5].trim(), sprint: m[6].trim(), jira: m[7].trim(),
      status: "Backlog", lastNote: "", lastDate: ""
    };
  }
  // Status history: - date | VS-## | Old→New | actor | note   (also "fix applied" lines, no →)
  for (const line of txt.split("\n")) {
    const m = /^-\s*([\d-]+)\s*\|\s*(VS-\d{2}|ALL)\s*\|\s*([^|]+)\|\s*([^|]+)\|\s*(.*)$/.exec(line.trim());
    if (!m || m[2] === "ALL") continue;
    const t = tickets[m[2]];
    if (!t) continue;
    const transition = m[3].trim();
    if (transition.includes("→")) {
      let status = transition.split("→").pop().trim();
      status = status.replace(/\(.*?\)/g, "").trim(); // "Approved (with batched fixes)" → "Approved"
      if (/^Backlog/i.test(status)) status = "Backlog";
      if (status && !/^n\/a$/i.test(status)) t.status = status;
    } else if (/fix applied/i.test(transition)) {
      t.status = t.status === "Approved" ? "Approved" : t.status; // fixes don't regress status
      t.fixCount = (t.fixCount || 0) + 1;
    }
    t.lastNote = (m[5] || "").slice(0, 160);
    t.lastDate = m[1];
  }
  return Object.values(tickets);
}

/** handoffs.md — headers like "**from → to | date**" or "**Handoff — from → to (...)**". */
function parseHandoffs(txt) {
  const hs = [];
  for (const raw of txt.split("\n")) {
    const line = raw.trim();
    if (!line.includes("→")) continue;
    if (!/^(\*\*|##)/.test(line)) continue;
    const idx = line.indexOf("→");
    const from = normalizeActor(line.slice(0, idx));
    const to = normalizeActor(line.slice(idx + 1));
    if (from) hs.push({ from, to: to || "human" });
  }
  return hs;
}

/** 03-qa/test-plan.md → TC register (§4) merged with results (§8) + release verdict. */
function parseTestPlan(txt) {
  const tcs = {};
  for (const line of txt.split("\n")) {
    const t = line.trim();
    // register row: | TC-001 | Title | 1 | REQ(s) | Type | A | Precondition |
    let m = /^\|\s*(TC-\d{3})\s*\|([^|]+)\|\s*([123])\s*\|([^|]*)\|([^|]*)\|\s*([AB])\s*\|/.exec(t);
    if (m) {
      tcs[m[1]] = {
        id: m[1], title: m[2].replace(/\*\*/g, "").trim().slice(0, 140),
        tier: +m[3], reqs: m[4].trim().slice(0, 60), run: m[6],
        status: "NOT RUN", note: ""
      };
      continue;
    }
    // results row: | TC-004 | **PASS** | evidence | notes |
    m = /^\|\s*(TC-\d{3})\s*\|\s*\**\s*(PASS|FAIL|BLOCKED|PARTIAL|NOT RUN)\**[^|]*\|([^|]*)\|(.*)$/i.exec(t);
    if (m && tcs[m[1]]) {
      tcs[m[1]].status = m[2].toUpperCase();
      tcs[m[1]].note = (m[4] || "").replace(/\*\*/g, "").replace(/\|+\s*$/, "").trim().slice(0, 180);
    }
  }
  const verdict = /GO-WITH-CAVEATS/.test(txt) ? "GO-WITH-CAVEATS"
    : /\bNO-GO\b/.test(txt) ? "NO-GO"
    : /RELEASE RECOMMENDATION/i.test(txt) ? "SEE §8" : null;
  return { tcs: Object.values(tcs), verdict };
}

/** 03-qa/bug-reports/ → bug file list. */
function listBugs(root) {
  try {
    return fs.readdirSync(path.join(root, "03-qa", "bug-reports"))
      .filter((f) => /^BUG-|\.md$/i.test(f) && !f.startsWith("."));
  } catch { return []; }
}

/** open-questions.md summary table → open items. */
function parseOpenQuestions(txt) {
  const oqs = [];
  for (const line of txt.split("\n")) {
    const m = /^\|\s*(OQ-\d{3})\s*\|([^|]+)\|([^|]+)\|([^|]+)\|([^|]+)\|\s*([^|]+?)\s*\|/.exec(line.trim());
    if (!m) continue;
    const sevM = /blocks-\w+|clarification/.exec(m[3]);
    oqs.push({
      id: m[1], q: m[2].trim().slice(0, 120),
      sev: sevM ? sevM[0] : "", owner: m[4].trim().slice(0, 40),
      status: m[6].trim()
    });
  }
  return oqs;
}

function collectState(root, changedFile) {
  const stateTxt = safeRead(path.join(root, "PIPELINE_STATE.md"));
  const runTxt = safeRead(path.join(root, ".claude", "logs", "agent-runs.log"));
  const deployTxt = safeRead(path.join(root, "02-build", "deployments.md"));
  const jiraTxt = safeRead(path.join(root, "02-build", "jira-log.md"));
  const oqTxt = safeRead(path.join(root, "01-discovery", "open-questions.md"));
  const handoffTxt = safeRead(path.join(root, ".claude", "memory", "handoffs.md"));
  const testPlanTxt = safeRead(path.join(root, "03-qa", "test-plan.md"));

  const ps = parsePipelineState(stateTxt);
  const runEvents = parseRunLog(runTxt);
  const all = [...ps.events, ...runEvents]
    .sort((a, b) => a.ts - b.ts || a.seq - b.seq);

  const latest = {};
  for (const ev of all) {
    const cur = latest[ev.agent];
    if (!cur || ev.ts > cur.ts || (ev.ts === cur.ts && ev.seq >= cur.seq)) latest[ev.agent] = ev;
  }
  const star = all.length ? all[all.length - 1] : null;

  const staleHours =
    vscode.workspace.getConfiguration("agentTheater").get("staleHours") || 12;
  const staleMs = staleHours * 3600 * 1000;
  const now = Date.now();

  const deployStatus = parseDeployStatus(deployTxt);
  const phase = ps.yaml.phase || null;
  const gate = GATES[phase] ? { from: phase, to: GATES[phase] } : null;

  const agents = {};
  for (const a of KNOWN_AGENTS) {
    const ev = latest[a] || null;
    let status = "idle";
    if (ev) {
      if (ev.result === "BLOCKED") status = "blocked";
      else if (ev.result === "PARTIAL") status = "partial";
      else status = "done";
      if (star && star.agent === a) status = "active";
      if (now - ev.ts > staleMs && status !== "blocked") status = "sleeping";
    } else status = "sleeping";
    // Gate spotlight: while waiting at a human gate, the Human is the story.
    if (a === "human" && gate) status = "active";
    let note = ev ? ev.note : "";
    if (a === "devops" && deployStatus) note = deployStatus;
    agents[a] = {
      status,
      note: (note || "").slice(0, 220),
      command: ev ? ev.command : null,
      when: ev
        ? (ev.dateOnly ? new Date(ev.ts).toLocaleDateString() : new Date(ev.ts).toLocaleString())
        : null
    };
  }

  // BLOCKED-transition notifications (skip the very first snapshot).
  if (Object.keys(prevStatuses).length) {
    for (const a of KNOWN_AGENTS) {
      if (agents[a].status === "blocked" && prevStatuses[a] !== "blocked") {
        vscode.window.showWarningMessage(
          `Agent Theater: ${a} is BLOCKED — ${agents[a].note.slice(0, 120)}`);
      }
    }
  }
  prevStatuses = Object.fromEntries(KNOWN_AGENTS.map((a) => [a, agents[a].status]));

  // Baton pass: detect a NEW handoff in handoffs.md. Held in pendingBaton until the
  // panel consumes it (so the status-bar poll can't swallow the animation).
  const handoffs = parseHandoffs(handoffTxt);
  if (prevHandoffCount >= 0 && handoffs.length > prevHandoffCount && handoffs.length) {
    pendingBaton = handoffs[handoffs.length - 1];
  }
  prevHandoffCount = handoffs.length;
  const baton = null; // panel delivery happens in pushState via pendingBaton

  const oqs = parseOpenQuestions(oqTxt);
  const openOQs = oqs.filter((o) => /open/i.test(o.status));
  const agentIssues = KNOWN_AGENTS
    .filter((a) => agents[a].status === "blocked" || agents[a].status === "partial")
    .map((a) => ({ agent: a, status: agents[a].status, note: agents[a].note }));

  return {
    root,
    generatedAt: new Date().toLocaleTimeString(),
    changedFile: changedFile || null,
    phase, phases: PHASES, yaml: ps.yaml, gate,
    deployStatus,
    deploys: parseDeploys(deployTxt),
    tickets: parseTickets(jiraTxt),
    star: star ? star.agent : null,
    agents,
    // Timeline: full merged event list (notes trimmed to keep the message light).
    events: all.map((e) => ({
      ts: e.ts, dateOnly: e.dateOnly, agent: e.agent, command: e.command,
      result: e.result, note: (e.note || "").slice(0, 200),
      when: e.dateOnly ? new Date(e.ts).toLocaleDateString() : new Date(e.ts).toLocaleString()
    })),
    blockers: {
      deployStatus, agentIssues, openOQs,
      oqOpenCount: openOQs.length, oqTotal: oqs.length
    },
    baton,
    handoffCount: handoffs.length,
    qa: { ...parseTestPlan(testPlanTxt), bugs: listBugs(root) }
  };
}

let lastSnapshotKey = null;
function pushState(root, changedFile, force) {
  if (!panel) return;
  try {
    const data = collectState(root, changedFile);
    data.baton = pendingBaton;
    pendingBaton = null;
    applyStatusBar(data);
    // Skip identical snapshots (polling produces many) — unless forced or a baton must be delivered.
    const key = JSON.stringify({ ...data, generatedAt: 0, changedFile: 0 });
    if (!force && !data.baton && key === lastSnapshotKey) return;
    lastSnapshotKey = key;
    panel.webview.postMessage({ type: "state", data });
  } catch (e) {
    panel.webview.postMessage({ type: "error", message: String(e) });
  }
}

function applyStatusBar(s) {
  if (!statusItem) return;
  const blocked = s.blockers.agentIssues.filter((i) => i.status === "blocked").length;
  const partial = s.blockers.agentIssues.length - blocked;
  statusItem.text =
    `🎭 ${s.phase || "?"}` +
    (s.gate ? " · GATE⛩" : "") +
    (blocked ? ` $(error)${blocked}` : "") +
    (partial ? ` $(warning)${partial}` : "");
  statusItem.tooltip =
    `Agent Theater — phase ${s.phase || "?"}` +
    (s.gate ? `\nHUMAN GATE waiting: ${s.gate.from} → ${s.gate.to}` : "") +
    `\nblocked: ${blocked} · partial: ${partial}` +
    (s.deployStatus ? `\ndeploy: ${s.deployStatus.slice(0, 100)}` : "") +
    `\n(click to open the theater)`;
  statusItem.backgroundColor = blocked
    ? new vscode.ThemeColor("statusBarItem.errorBackground")
    : s.gate
    ? new vscode.ThemeColor("statusBarItem.warningBackground")
    : undefined;
}

function runHealthCheck(root) {
  if (!panel) return;
  const script = path.join(root, "scripts", "health-check.js");
  if (!fs.existsSync(script)) {
    panel.webview.postMessage({ type: "health", ok: false, output: "scripts/health-check.js not found" });
    return;
  }
  exec(`node "${script}"`, { cwd: root, timeout: 60000, maxBuffer: 1024 * 1024 },
    (err, stdout, stderr) => {
      if (!panel) return;
      const output = ((stdout || "") + (stderr ? "\n" + stderr : "")).trim();
      panel.webview.postMessage({
        type: "health",
        ok: !err,
        exitCode: err ? (err.code === undefined ? -1 : err.code) : 0,
        output: output.slice(-4000) || "(no output)"
      });
    });
}

function getHtml(webview, mediaUri) {
  const nonce = Math.random().toString(36).slice(2);
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta http-equiv="Content-Security-Policy"
  content="default-src 'none'; style-src ${webview.cspSource}; script-src 'nonce-${nonce}';">
<link rel="stylesheet" href="${mediaUri("style.css")}">
<title>Agent Theater</title>
</head>
<body>
  <header>
    <h1>🎭 Agent Theater</h1>
    <div id="meta"></div>
    <button id="health-btn" title="Run scripts/health-check.js">🩺 Health</button>
    <button id="refresh" title="Re-read pipeline files">⟳ Refresh</button>
  </header>
  <div id="phase-track"></div>
  <div id="gate-banner" class="hidden"></div>
  <div id="deploy-banner" class="hidden"></div>
  <div id="deploy-strip"></div>
  <nav id="tabs">
    <button class="tab active" data-tab="stage">Stage</button>
    <button class="tab" data-tab="tickets">Tickets</button>
    <button class="tab" data-tab="timeline">Timeline</button>
    <button class="tab" data-tab="qa">QA</button>
    <button class="tab" data-tab="blockers">Blockers</button>
  </nav>
  <main>
    <div id="tab-stage" class="tabpane"></div>
    <div id="tab-tickets" class="tabpane hidden"></div>
    <div id="tab-timeline" class="tabpane hidden"></div>
    <div id="tab-qa" class="tabpane hidden"></div>
    <div id="tab-blockers" class="tabpane hidden"></div>
  </main>
  <div id="health-out" class="hidden"></div>
  <footer id="foot"></footer>
  <script nonce="${nonce}" src="${mediaUri("main.js")}"></script>
</body>
</html>`;
}

function deactivate() {}

module.exports = { activate, deactivate };
