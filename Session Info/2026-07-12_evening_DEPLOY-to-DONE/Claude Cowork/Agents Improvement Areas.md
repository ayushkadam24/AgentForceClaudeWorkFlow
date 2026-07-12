# Agents / Skills / Commands — Improvement Areas (Day 2, deploy-focused post-mortem)

Source: the Sprint-1 deploy saga (2 opaque full-manifest failures, 3-round phased deploy, manual
CMDT records, blockers A–H) + QA execution. Items marked [DONE-IN-TEMPLATES] are already baked into
`_templates/*`; applying them to THIS live project is optional (POC is DONE).

## 1. Shift deployability left (biggest win)
- **Org connection = build precondition.** All 9 tickets were built with no org; every deploy defect
  surfaced at once, behind one opaque error. Add to /dev-implement FINAL VERIFICATION: per-ticket
  delta dry-run when an org is connected; without an org, the packet carries the UNVERIFIED banner
  (rules/20 §3 already says this — enforce it in the dev agents' postconditions too). [DONE-IN-TEMPLATES]
- **Ban hand-authored Flow XML.** VS-03 took 3 fix rounds (element NAME, order, boolean isRequired).
  Rule: build flows in Flow Builder against the org and retrieve. [DONE-IN-TEMPLATES via skill §4]

## 2. Make the lint know what we now know
Expand `scripts/metadata-lint.js` to FAIL on:
- description over per-type caps (exists) — CustomPermission/PermissionSet 255, Object/Field 1000
- `<fieldPermissions>` targeting required=true or Master-Detail fields (cost: 21 entries, 2 rounds)
- illegal elements per type (e.g. `<deploymentStatus>` on `__mdt`)
- Flow: non-whitelisted top-level elements (`recordChoiceSets`!), XSD order, boolean `<isRequired>`
Then: lint runs at BUILT gate, not just pre-packet. A FAIL is a defect (rules/20 §2 already binding).

## 3. Stop paying twice for org knowledge
- **`sf-deploy-troubleshooting` skill** created (failure taxonomy + 6-step protocol + org-safety
  gate + ledger discipline). Add to the live project too if it continues. [DONE-IN-TEMPLATES]
- **`org-facts.md` register** (Tickets template): append-only org-quirks base checked BEFORE
  debugging any deploy. Candidate for the live project's memory/. [DONE-IN-TEMPLATES]
- **Canonical USER_MODE test recipe** (harness permset; user created OUTSIDE runAs; fixtures+engine
  INSIDE runAs on FLS-enforcing orgs; CMDT via getInstance; RunSpecifiedTests = CLASS names only)
  → fold into sf-apex-patterns so tests are right the FIRST time (blockers C–H were 6 rounds).

## 4. Process discipline
- **Fix-in-batches enforcement:** after first instance of a defect class, SWEEP the whole class
  (scripted), then one dry-run. The platform shows one error per file per run — looping is a trap.
- **devops:** keep pre-built single- and pair-component bisection manifests; on UNKNOWN_EXCEPTION
  go straight to class-level bisection; 1-record CMDT probe deploy early on any new org.
- **code-reviewer:** add a deployability checklist item (run lint, check caps/FLS legality) —
  all 9 tickets were APPROVED while carrying deploy blockers.
- **Bookkeeping:** agent-runs.log went stale for a day despite stop-guard — verify the guard is
  actually live at session start (fresh-session hook-load rule) and let /health FAIL loudly on it.

## 5. QA phase learnings (from today's runs)
- Browser-dependent TCs (flows, a11y, copy) need a Playwright-equipped environment from the start,
  or plan them as a separate run — 8 of 28 TCs blocked on missing browser.
- The §3.4-style load test belongs in the plan from day 1 (it found a REAL runtime bug, D-029,
  that 21/21 passing unit tests missed). Keep "unit tests prove logic, not concurrency" honesty.
- License-slot limits on DE orgs (A-020) constrain per-role login smoke tests — plan roles early.
