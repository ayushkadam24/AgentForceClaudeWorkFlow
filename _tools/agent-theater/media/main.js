// Agent Theater webview — stage, tickets, timeline scrubber, QA, blockers, health.
(function () {
  const vscodeApi = acquireVsCodeApi();

  const ROSTER = [
    { id: "ba-analyst",    label: "BA Analyst",    emoji: "📋", color: "#4e8cff" },
    { id: "architect",     label: "Architect",     emoji: "📐", color: "#9b6bff" },
    { id: "pm-planner",    label: "PM Planner",    emoji: "🗂️", color: "#ff9f43" },
    { id: "dev-senior",    label: "Dev Senior",    emoji: "👷", color: "#2ecc71" },
    { id: "dev-mid",       label: "Dev Mid",       emoji: "🔧", color: "#27ae9b" },
    { id: "code-reviewer", label: "Code Reviewer", emoji: "🔍", color: "#e056a2" },
    { id: "qa-lead",       label: "QA Lead",       emoji: "📊", color: "#c0a532" },
    { id: "qa-engineer",   label: "QA Engineer",   emoji: "🧪", color: "#b8862b" },
    { id: "devops",        label: "DevOps",        emoji: "🚀", color: "#e74c3c" },
    { id: "orchestrator",  label: "Orchestrator",  emoji: "🎛️", color: "#7f8c9b" },
    { id: "human",         label: "Human",         emoji: "🧑‍⚖️", color: "#5d6d7e" }
  ];
  const BY_ID = Object.fromEntries(ROSTER.map((r) => [r.id, r]));

  const STATUS_META = {
    active:   { label: "ON STAGE",  cls: "active" },
    blocked:  { label: "BLOCKED",   cls: "blocked" },
    partial:  { label: "PARTIAL",   cls: "partial" },
    done:     { label: "OK",        cls: "done" },
    idle:     { label: "IDLE",      cls: "idle" },
    sleeping: { label: "ZZZ",       cls: "sleeping" }
  };

  const TICKET_STATUS_CLS = {
    "Backlog": "t-backlog", "In Progress": "t-progress",
    "Ready for Review": "t-review", "Approved": "t-approved",
    "Done": "t-approved", "Deployed": "t-approved"
  };

  let DATA = null;          // latest live snapshot
  let timelineIdx = null;   // null = live

  function esc(s) {
    return String(s || "").replace(/[&<>"']/g, (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  }

  function charSVG(agent, status) {
    const eyes =
      status === "sleeping"
        ? '<path d="M44 36 h10 M66 36 h10" stroke="#333" stroke-width="2.5" stroke-linecap="round"/>'
        : status === "blocked"
        ? '<circle cx="49" cy="36" r="4" fill="#333"/><circle cx="71" cy="36" r="4" fill="#333"/>'
        : '<circle cx="49" cy="36" r="3" fill="#333"/><circle cx="71" cy="36" r="3" fill="#333"/>';
    const mouth =
      status === "blocked"
        ? '<path d="M50 52 q10 -8 20 0" stroke="#333" stroke-width="2.5" fill="none" stroke-linecap="round"/>'
        : status === "partial"
        ? '<path d="M50 50 h20" stroke="#333" stroke-width="2.5" stroke-linecap="round"/>'
        : status === "sleeping"
        ? '<circle cx="60" cy="51" r="4" fill="none" stroke="#333" stroke-width="2"/>'
        : '<path d="M50 47 q10 9 20 0" stroke="#333" stroke-width="2.5" fill="none" stroke-linecap="round"/>';
    const brows =
      status === "blocked"
        ? '<path d="M43 27 l12 4 M77 27 l-12 4" stroke="#333" stroke-width="2.5" stroke-linecap="round"/>'
        : "";
    const zzz = status === "sleeping" ? '<text x="92" y="20" font-size="14" class="zzz">z z</text>' : "";
    const alert = status === "blocked" ? '<text x="90" y="22" font-size="18">⚠️</text>' : "";
    return `
<svg viewBox="0 0 120 140" class="char ${status}" aria-hidden="true">
  <ellipse cx="60" cy="132" rx="34" ry="6" fill="rgba(0,0,0,0.25)"/>
  <path d="M38 78 L82 78 L92 128 L28 128 Z" fill="${agent.color}" stroke="rgba(0,0,0,0.25)" stroke-width="2"/>
  <line x1="38" y1="86" x2="20" y2="108" stroke="${agent.color}" stroke-width="9" stroke-linecap="round"/>
  <line x1="82" y1="86" x2="100" y2="108" stroke="${agent.color}" stroke-width="9" stroke-linecap="round"/>
  <circle cx="60" cy="40" r="28" fill="#ffd9b3" stroke="rgba(0,0,0,0.25)" stroke-width="2"/>
  <path d="M32 34 a28 28 0 0 1 56 0 q-14 -12 -28 -12 q-14 0 -28 12" fill="${agent.color}" opacity="0.85"/>
  ${brows}${eyes}${mouth}
  <text x="12" y="130" font-size="20">${agent.emoji}</text>
  ${zzz}${alert}
</svg>`;
  }

  function agentCard(agent, st, isStar, spotlight) {
    const meta = STATUS_META[st.status] || STATUS_META.idle;
    return `
<div class="card ${meta.cls}${spotlight ? " spotlight" : ""}" data-agent="${agent.id}" title="${esc(st.note)}">
  <div class="badge ${meta.cls}">${meta.label}</div>${isStar ? '<span class="star">★</span>' : ""}
  ${charSVG(agent, st.status)}
  <div class="name">${esc(agent.label)}</div>
  ${st.command ? `<div class="cmd"><code>${esc(st.command)}</code></div>` : ""}
  ${st.note ? `<div class="bubble">${esc(st.note)}</div>` : ""}
  ${st.when ? `<div class="when">${esc(st.when)}</div>` : ""}
</div>`;
  }

  function renderStage(agents, star, gate) {
    return ROSTER.map((agent) => {
      const st = agents[agent.id] || { status: "sleeping", note: "", command: null, when: null };
      const spotlight = gate && agent.id === "human";
      return agentCard(agent, st, star === agent.id, spotlight);
    }).join("");
  }

  function renderTickets(tickets) {
    if (!tickets || !tickets.length) return '<div class="empty">No tickets parsed from 02-build/jira-log.md</div>';
    const cols = ["Backlog", "In Progress", "Ready for Review", "Approved"];
    const other = tickets.filter((t) => !cols.includes(t.status));
    const colHtml = cols.map((c) => {
      const items = tickets.filter((t) => t.status === c);
      return `
<div class="kcol">
  <div class="kcol-head ${TICKET_STATUS_CLS[c] || ""}">${esc(c)} <span class="kcount">${items.length}</span></div>
  ${items.map(ticketCard).join("") || '<div class="kempty">—</div>'}
</div>`;
    }).join("");
    const otherHtml = other.length
      ? `<div class="kcol"><div class="kcol-head">Other</div>${other.map(ticketCard).join("")}</div>` : "";
    return `<div class="kanban">${colHtml}${otherHtml}</div>`;
  }

  function ticketCard(t) {
    const dev = BY_ID[t.routing] || { color: "#7f8c9b", emoji: "❔" };
    const jewel = t.id === "VS-09" ? " 👑" : "";
    return `
<div class="tcard ${TICKET_STATUS_CLS[t.status] || ""}" title="${esc(t.lastNote)}">
  <div class="tid">${esc(t.id)}${jewel} <span class="tep">${esc(t.ep)}</span>
    <span class="tsprint">S${esc(t.sprint)}</span></div>
  <div class="ttitle">${esc(t.title)}</div>
  <div class="tmeta"><span class="tdev" style="border-color:${dev.color}">${dev.emoji} ${esc(t.routing)}</span>
    ${t.jira ? `<span class="tjira">${esc(t.jira)}</span>` : ""}
    ${t.fixCount ? `<span class="tfix">${t.fixCount} fix${t.fixCount > 1 ? "es" : ""}</span>` : ""}</div>
</div>`;
  }

  // ---- Sprint rollup: group tickets by sprint, classify done/active/pending ----
  const TERMINAL_TICKET = { "Approved": 1, "Done": 1, "Deployed": 1 };
  function renderSprints(tickets) {
    if (!tickets || !tickets.length) return "";
    const by = {};
    for (const t of tickets) {
      const k = String(t.sprint || "?").trim() || "?";
      (by[k] = by[k] || []).push(t);
    }
    const keys = Object.keys(by).sort(
      (a, b) => (parseInt(a, 10) || 99) - (parseInt(b, 10) || 99));
    return keys.map((k) => {
      const items = by[k];
      const done = items.filter((t) => TERMINAL_TICKET[t.status]).length;
      const started = items.some((t) => t.status !== "Backlog");
      const cls = done === items.length ? "sp-done" : started ? "sp-active" : "sp-pending";
      const icon = cls === "sp-done" ? "✅" : cls === "sp-active" ? "🔨" : "⬜";
      const label = cls === "sp-done" ? "complete" : cls === "sp-active" ? "in progress" : "not started";
      const tip = `Sprint ${k} — ${label} (${done}/${items.length} tickets done)\n` +
        items.map((t) => `${t.id} · ${t.status}`).join("\n");
      return `<span class="spchip ${cls}" title="${esc(tip)}">${icon} Sprint ${esc(k)} <b>${done}/${items.length}</b></span>`;
    }).join("") + '<span class="dlabel">sprint progress (from jira-log ticket statuses)</span>';
  }

  function computeAgentsAt(events, uptoIdx) {
    const latest = {};
    for (let i = 0; i < uptoIdx; i++) {
      const ev = events[i];
      latest[ev.agent] = ev;
    }
    const agents = {};
    let starAgent = uptoIdx > 0 ? events[uptoIdx - 1].agent : null;
    for (const r of ROSTER) {
      const ev = latest[r.id];
      let status = "sleeping";
      if (ev) {
        status = ev.result === "BLOCKED" ? "blocked"
          : ev.result === "PARTIAL" ? "partial" : "done";
        if (r.id === starAgent) status = "active";
      }
      agents[r.id] = {
        status,
        note: ev ? ev.note : "",
        command: ev ? ev.command : null,
        when: ev ? ev.when : null
      };
    }
    return { agents, starAgent };
  }

  function renderTimeline() {
    const evs = DATA.events || [];
    const n = evs.length;
    const idx = timelineIdx === null ? n : timelineIdx;
    const cur = idx > 0 ? evs[idx - 1] : null;
    const { agents, starAgent } = idx === n && timelineIdx === null
      ? { agents: DATA.agents, starAgent: DATA.star }
      : computeAgentsAt(evs, idx);
    return `
<div class="tl-controls">
  <input type="range" id="tl-slider" min="0" max="${n}" value="${idx}">
  <div class="tl-label">${idx === n ? "LIVE" : `event ${idx}/${n}`}
    ${cur ? ` — <b>${esc(cur.agent)}</b> ${cur.command ? `<code>${esc(cur.command)}</code>` : ""} <span class="tl-when">${esc(cur.when)}</span>` : ""}</div>
  ${cur ? `<div class="tl-note">${esc(cur.note)}</div>` : ""}
</div>
<div class="stage-grid">${renderStage(agents, starAgent, null)}</div>`;
  }

  // ---- QA tab: verdict + TC board grouped by tier ----
  const TC_STATUS_CLS = {
    "PASS": "q-pass", "FAIL": "q-fail", "BLOCKED": "q-blocked",
    "PARTIAL": "q-partial", "NOT RUN": "q-notrun"
  };
  function renderQA(qa) {
    if (!qa || !qa.tcs || !qa.tcs.length)
      return '<div class="empty">No test cases parsed from 03-qa/test-plan.md yet (run /qa-plan)</div>';
    const counts = {};
    for (const tc of qa.tcs) counts[tc.status] = (counts[tc.status] || 0) + 1;
    const summary = Object.entries(counts)
      .map(([s, n]) => `<span class="qsum ${TC_STATUS_CLS[s] || ""}">${n} ${esc(s)}</span>`).join(" ");
    const verdict = qa.verdict
      ? `<div class="banner ${qa.verdict.startsWith("GO") ? "good" : "bad"}">🏁 <b>Release recommendation:</b> ${esc(qa.verdict)}</div>`
      : "";
    const bugs = `<div class="qbugs">🐛 bug reports: <b>${(qa.bugs || []).length}</b>${(qa.bugs || []).length ? " — " + qa.bugs.map(esc).join(", ") : ""}</div>`;
    const tiers = [1, 2, 3].map((tier) => {
      const items = qa.tcs.filter((t) => t.tier === tier);
      if (!items.length) return "";
      return `
<h3>Tier ${tier} ${tier === 1 ? "(block release on failure)" : ""}</h3>
<div class="qgrid">${items.map((t) => `
  <div class="qcard ${TC_STATUS_CLS[t.status] || ""}" title="${esc(t.note || t.title)}">
    <div class="qid">${esc(t.id)} <span class="qrun">run ${esc(t.run)}</span>
      <span class="qstat">${esc(t.status)}</span></div>
    <div class="qtitle">${esc(t.title)}</div>
    ${t.reqs ? `<div class="qreqs">${esc(t.reqs)}</div>` : ""}
  </div>`).join("")}</div>`;
    }).join("");
    return verdict + `<div class="qsummary">${summary}</div>` + bugs + tiers;
  }

  function renderBlockers(b) {
    if (!b) return "";
    const issues = (b.agentIssues || []).map((i) =>
      `<div class="bk-item bk-${i.status}"><b>${esc(i.agent)}</b> <span class="bk-tag">${esc(i.status.toUpperCase())}</span><div>${esc(i.note)}</div></div>`
    ).join("") || '<div class="empty">No agents blocked or partial 🎉</div>';
    const oqRows = (b.openOQs || []).map((o) =>
      `<tr><td>${esc(o.id)}</td><td>${esc(o.q)}</td><td><span class="sev sev-${esc(o.sev).replace("blocks-", "")}">${esc(o.sev)}</span></td><td>${esc(o.owner)}</td></tr>`
    ).join("");
    return `
<h3>Agent issues</h3>${issues}
${b.deployStatus ? `<h3>Deploy ledger</h3><div class="bk-item bk-partial">${esc(b.deployStatus)}</div>` : ""}
<h3>Open questions (${b.oqOpenCount}/${b.oqTotal} open)</h3>
${oqRows ? `<table class="oq"><thead><tr><th>ID</th><th>Question</th><th>Severity</th><th>Owner</th></tr></thead><tbody>${oqRows}</tbody></table>` : '<div class="empty">None open</div>'}`;
  }

  function render(data) {
    DATA = data;

    document.getElementById("meta").innerHTML =
      `<span class="phase-pill">${esc(data.phase || "?")}</span>` +
      (data.yaml.next_command ? ` next: <code>${esc(data.yaml.next_command)}</code>` : "") +
      (data.yaml.updated_by ? ` · updated by <b>${esc(data.yaml.updated_by)}</b>` : "");

    const cur = data.phases.indexOf(data.phase);
    document.getElementById("phase-track").innerHTML = data.phases
      .map((p, i) => {
        const cls = i < cur ? "ph done" : i === cur ? "ph current" : "ph";
        return `<span class="${cls}" title="${esc(p)}">${esc(p.replace(/_/g, " "))}</span>`;
      })
      .join('<span class="ph-arrow">→</span>');

    const gateB = document.getElementById("gate-banner");
    if (data.gate) {
      gateB.classList.remove("hidden");
      gateB.className = "banner gate";
      gateB.innerHTML =
        `🧑‍⚖️ <b>HUMAN GATE:</b> the pipeline is waiting for your approval — ` +
        `<b>${esc(data.gate.from)} → ${esc(data.gate.to)}</b>` +
        (data.yaml.next_command ? ` (via <code>${esc(data.yaml.next_command)}</code> / <code>/advance</code>)` : "");
    } else gateB.classList.add("hidden");

    const banner = document.getElementById("deploy-banner");
    if (data.deployStatus) {
      banner.classList.remove("hidden");
      banner.innerHTML = `🚀 <b>Deploy ledger:</b> ${esc(data.deployStatus)}`;
      banner.className = /BLOCKED|FAILED/i.test(data.deployStatus)
        ? "banner bad" : /PARTIAL/i.test(data.deployStatus)
        ? "banner warn" : "banner good";
    } else banner.classList.add("hidden");

    document.getElementById("deploy-strip").innerHTML = (data.deploys || []).map((d) => {
      const icon = d.cls === "ok" ? "✅" : d.cls === "fail" ? "❌" : "🟡";
      return `<span class="dchip d-${d.cls}" title="${esc(d.date)} — ${esc(d.scope)}
${esc(d.result)}">${icon}</span>`;
    }).join("") + ((data.deploys || []).length ? '<span class="dlabel">deploy attempts</span>' : "");

    const sprintStrip = document.getElementById("sprint-strip");
    if (sprintStrip) sprintStrip.innerHTML = renderSprints(data.tickets);

    document.getElementById("tab-stage").innerHTML =
      `<div class="stage-grid">${renderStage(data.agents, data.star, data.gate)}</div>`;
    document.getElementById("tab-tickets").innerHTML = renderTickets(data.tickets);
    document.getElementById("tab-timeline").innerHTML = renderTimeline();
    document.getElementById("tab-qa").innerHTML = renderQA(data.qa);
    document.getElementById("tab-blockers").innerHTML = renderBlockers(data.blockers);
    wireSlider();
    // Persist across webview reloads / VS Code restarts (retainContextWhenHidden ≠ restart-proof).
    vscodeApi.setState({ data: { ...data, baton: null }, activeTab: currentTab() });

    const foot = document.getElementById("foot");
    foot.textContent =
      `watching ${data.root} · last read ${data.generatedAt}` +
      (data.changedFile ? ` · triggered by ${data.changedFile}` : "");
    foot.classList.remove("flash");
    void foot.offsetWidth;
    foot.classList.add("flash");

    if (data.baton) launchBaton(data.baton);
  }

  // Baton-pass: an envelope flies from the outgoing agent's card to the receiver's.
  function launchBaton(b) {
    const fromEl = document.querySelector(`#tab-stage .card[data-agent="${b.from}"]`);
    const toEl = document.querySelector(`#tab-stage .card[data-agent="${b.to}"]`);
    if (!fromEl || !toEl) return;
    const f = fromEl.getBoundingClientRect();
    const t = toEl.getBoundingClientRect();
    const el = document.createElement("div");
    el.className = "baton";
    el.textContent = "📨";
    el.style.left = (f.left + f.width / 2 - 13) + "px";
    el.style.top = (f.top + f.height / 3) + "px";
    document.body.appendChild(el);
    fromEl.classList.add("baton-glow");
    toEl.classList.add("baton-glow");
    requestAnimationFrame(() => requestAnimationFrame(() => {
      el.style.transform =
        `translate(${(t.left + t.width / 2) - (f.left + f.width / 2)}px, ` +
        `${(t.top + t.height / 3) - (f.top + f.height / 3)}px) rotate(360deg) scale(1.2)`;
    }));
    setTimeout(() => {
      el.remove();
      fromEl.classList.remove("baton-glow");
      toEl.classList.remove("baton-glow");
    }, 1700);
  }

  function wireSlider() {
    const s = document.getElementById("tl-slider");
    if (!s) return;
    s.addEventListener("input", () => {
      const v = parseInt(s.value, 10);
      timelineIdx = v >= (DATA.events || []).length ? null : v;
      document.getElementById("tab-timeline").innerHTML = renderTimeline();
      wireSlider();
      const s2 = document.getElementById("tl-slider");
      if (s2) s2.focus();
    });
  }

  // Tabs
  function currentTab() {
    const a = document.querySelector(".tab.active");
    return a ? a.dataset.tab : "stage";
  }
  function selectTab(name) {
    document.querySelectorAll(".tab").forEach((t) =>
      t.classList.toggle("active", t.dataset.tab === name));
    document.querySelectorAll(".tabpane").forEach((p) =>
      p.classList.toggle("hidden", p.id !== "tab-" + name));
  }
  document.getElementById("tabs").addEventListener("click", (e) => {
    const btn = e.target.closest(".tab");
    if (!btn) return;
    selectTab(btn.dataset.tab);
    const st = vscodeApi.getState() || {};
    vscodeApi.setState({ ...st, activeTab: btn.dataset.tab });
  });

  document.getElementById("health-btn").addEventListener("click", () => {
    const out = document.getElementById("health-out");
    out.classList.remove("hidden");
    out.innerHTML = '<div class="health-head">🩺 running scripts/health-check.js…</div>';
    vscodeApi.postMessage({ type: "health" });
  });

  window.addEventListener("message", (e) => {
    const msg = e.data;
    if (msg.type === "state") render(msg.data);
    if (msg.type === "error")
      document.getElementById("tab-stage").innerHTML = `<div class="error">${esc(msg.message)}</div>`;
    if (msg.type === "health") {
      const out = document.getElementById("health-out");
      out.classList.remove("hidden");
      out.innerHTML =
        `<div class="health-head ${msg.ok ? "h-ok" : "h-fail"}">🩺 health-check ${msg.ok ? "PASS" : "FAIL"} (exit ${msg.exitCode})
         <button id="health-close">✕</button></div><pre>${esc(msg.output)}</pre>`;
      document.getElementById("health-close").addEventListener("click", () =>
        out.classList.add("hidden"));
    }
  });

  document.getElementById("refresh").addEventListener("click", () =>
    vscodeApi.postMessage({ type: "refresh" }));

  // Instant restore from persisted state (before the first fresh snapshot arrives).
  const saved = vscodeApi.getState();
  if (saved && saved.data) {
    render(saved.data);
    if (saved.activeTab) selectTab(saved.activeTab);
  }
  vscodeApi.postMessage({ type: "refresh" });
})();
