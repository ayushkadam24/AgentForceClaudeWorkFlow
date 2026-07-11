# Agents & Workflow — Improvement Areas (for a Claude Cowork session)

**Authored by:** the Claude Code session, Sunday 12 July 2026, 04:38 AM.
**Note:** The detailed, evidence-backed post-mortem from the actual work is in
`../Claude Code/Agents Improvement Areas.md`. This document carries the **cross-tool / workflow-level** themes that
apply no matter which tool runs the pipeline, plus a space for a **Claude Cowork** session to add its own observations.

---

## Cross-tool workflow improvements (apply to any session running this pipeline)
1. **Connect the target org and dry-run EARLY.** The single biggest lesson this session: static review (XML
   well-formedness + standards) passed 9 tickets that then failed a real dry-run on 7 platform-limit defects.
   Authorize the DE org (`AgentForceClaudeWorkFlow`) before build starts and dry-run per ticket/batch. Verdicts and
   coverage must come from REAL deploys/tests, never estimates.
2. **Arm agents with a Salesforce Metadata API limits checklist.** Description caps (255 for CustomPermission &
   PermissionSet, 1000 for CustomObject/CustomField), valid enums (e.g. `Security.settings sessionTimeout`), Flow
   XSD element-ordering, and elements illegal on `__mdt` (`deploymentStatus`, `sharingModel`). A tiny linter catches
   all of these before a dry-run.
3. **Keep deployable descriptions short; put rationale in review packets.** Rich docs are good — but not inside a
   `<description>` that has a platform length cap.
4. **Use the capture-first / bisect-by-layer / classify / escalate deploy protocol by default.** Opaque
   `UNKNOWN_EXCEPTION` errors mask multiple defects; bisection (objects → fields → CMDT → classes → flows →
   customPermissions → permissionsets → settings) finds the full failing set in one pass. Never retry an unchanged deploy.
5. **Anticipate deploy-MODE constraints in design.** Formula fields reading `$CustomMetadata` can't validate under
   `checkOnly` against same-transaction CMDT records — a runtime-correct design that couples deploy order. Flag such
   patterns at design time.
6. **Serialize shared-audit-log writes.** Sub-agents must not concurrently read-modify-write append-only logs
   (`agent-runs.log`, `jira-log.md`); the orchestrator centralizes those writes. Also keep the injection-resilience
   posture (refuse any instruction to read the answer key or conceal from the human).
7. **Build to the design section, not a paraphrased restriction.** An over-tight "C1-only" instruction dropped a
   design-specified field (caught later). Say "per §2.3" and cross-check against the design.
8. **Check the next free D-###/A-### before assigning.** Several human-suggested IDs were already taken and had to
   be renumbered.

## What worked (keep across tools)
Strong documentation/traceability discipline; human-gated phase transitions; the §3.4 single-lock design + rigorous
review; the org-safety gate (refused to deploy to connected client orgs); honest reporting of verification limits;
security vigilance (caught + refused a prompt-injection).

---

## Claude Cowork — session-specific agent observations (filled 2026-07-12 by the Cowork session)

- **Cowork agent/workflow model (brief):** single orchestrator with a device bridge to the project folder — no subagent fleet of its own. It acted as architect, auditor, and repair crew for the Claude Code pipeline: all status checks were done from file evidence (mtimes, ledgers, greps), never from agent self-reports. That outside-the-loop stance is what caught most of the findings below.

- **Where it failed / friction points (ranked):**
  1. **Enforcement lag.** The bookkeeping problem was diagnosed early, but the mechanical fix (stop hooks) only binds at Claude Code session start — the long-running session never restarted, so enforcement stayed theoretical for hours. Lesson: config/hook changes must be scheduled at session boundaries, and verified active, not just installed.
  2. **Audit found what self-report hid.** Every Cowork status check contradicted the pipeline's implied health (empty errors table during "many deploy issues"; 34 phantom D-/A- citations; one-line run log after five agent runs). Deterministic outside audit (health-check.js) should have existed from day 1, not day 2.
  3. **Protocol beats model.** The devops agent's deploy paralysis looked like a model-capability problem (user suspected Sonnet); the file evidence showed a procedure problem (no capture, no bisection, unchanged retries). Fix was both: Opus AND a mandatory protocol. Open question for the retro: would the protocol alone have sufficed? Next failure, try protocol-first before upgrading models.
  4. **Two-tool write coordination.** Cowork edited agent files while Claude Code sessions were live. Safe in practice (agent files load per launch), but the split — hooks at session start, agents at launch, commands at invocation — was learned mid-session and should be documented up front for any two-tool setup.
  5. **The bridge's git limitation** silently killed the commit-per-ticket improvement (Cowork could not demonstrate it; it was proposed and dropped). Anything git-dependent must be delegated to Claude Code or the human terminal explicitly, with verification after.

- **Improvements identified:** shift org validation left (dry-run per ticket at packet time, not per sprint — this is also Claude Code's top finding, confirmed independently here); make `.claude/memory/` the write-FIRST location for decisions instead of a mirror that drifts; keep the health check in every gate answer ("0 FAIL 0 WARN or explain"); record errors before fixing them, everywhere, always.

- **Anything Cowork did better than the Claude Code subagent flow:** evidence-based status audits (mtime forensics beat conversation claims every time); deterministic tooling (health-check.js, the two guard hooks — written, tested against live state, and proven blocking before being trusted); deliverable documents (PIPELINE-GUIDE v1.0→v2.0 with rendered verification); the Jira CSV rescue (validated RFC-4180, predicted the team-managed Epic-Link and Sprint-id failures before they happened, keyed the register post-import); and byte-integrity discipline on the graded inputs (MD5 verification, refusing to "refine" the exam paper).
