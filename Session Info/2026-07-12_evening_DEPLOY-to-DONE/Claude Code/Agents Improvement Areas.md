# Agents Improvement Areas — Claude Code session 2 (deploy → DONE), 2026-07-12 evening

Observed while RUNNING the pipeline (complements the Cowork-side file, which carries the
deploy-focused post-mortem; overlaps marked ↔). Full retro: `retro/poc-learnings.md`.

## Per-agent
- **dev-mid / dev-senior:** built 9 tickets with zero org contact — every deploy defect was
  discovered weeks-equivalent late, in one pile. Make per-ticket delta dry-run (org connected) or
  UNVERIFIED banner (no org) a postcondition INSIDE the agent files, not only rules/20. (↔ Cowork §1)
- **dev-mid:** hand-authored Flow XML cost 3 fix rounds (element name, XSD order, boolean
  isRequired). Agent instruction: flows are built in Flow Builder + retrieved, never hand-written.
- **code-reviewer:** APPROVED all 9 tickets while they carried deploy blockers (description caps,
  illegal FLS, invalid flow elements). Add a "deployability" checklist section to the review packet
  format: metadata-lint output pasted, caps checked, FLS legality checked. (↔ Cowork §4)
- **devops:** the 6-step troubleshooting protocol + bisection worked — keep. Additions: 1-record
  CMDT probe deploy on any new org (detects D-027-class limitations in one round); pre-built
  single/pair bisection manifests; on UNKNOWN_EXCEPTION skip straight to class-level bisection.
- **qa-lead:** ran /qa-plan without self-logging its run line (orchestrator had to audit-reconcile
  and backfill). FINAL VERIFICATION postconditions must include the log line — bookkeeping proved
  skippable under load again. Same class as the stale agent-runs.log from the morning.
- **qa-engineer:** excellent evidence discipline (verbatim JSON per TC) — keep. But 8/28 TCs were
  browser-blocked: the qa-plan should declare environment prerequisites (browser/Playwright,
  license slots for per-role logins) as a §0 gate so blocks are known before execution starts.
- **orchestrator:** caught the injected fake log line, the audit gap, and both Aadhaar-shaped
  near-misses — the guard+audit layers are earning their keep; keep hooks loading verified at
  session start (fresh session after hook edits).

## Cross-cutting
- **One-defect-per-round trap** appeared twice (dry-run rounds; permset FLS). "Fix ALL instances of
  the class, then one re-run" is now rules/20 §5 — enforce with a sweep script, not agent memory.
- **Unit tests ≠ concurrency proof:** 21/21 green tests missed the D-029 runtime bug; the REST
  load harness found it. Any future §3.4-class guarantee needs a load test planned from day 1,
  and the "logic-only" honesty line kept in every test packet. (↔ Cowork §5)
- **Org-quirk knowledge must persist:** D-027/D-028/D-029 exist only in ledger prose + retro.
  Adopt the org-facts.md register + sf-deploy-troubleshooting skill (already in `_templates/`)
  into any continuing work on this repo. (↔ Cowork §3)
- **Bookkeeping as gate condition:** stop-guard + /health caught staleness only when humans looked.
  /advance already runs /health — make a FAIL block the gate proposal outright.
