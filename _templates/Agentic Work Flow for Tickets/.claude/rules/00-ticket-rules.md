# Ticket Pipeline Rules (binding for every agent)

## States & who moves them
NEW → SOLUTIONED (ticket-architect) → BUILT (ticket-developer) → TESTED (ticket-tester) →
PACKAGED (ticket-developer) → DONE (human only). BLOCKED at any step, with reason + owner.
Every transition = one row in TICKETS.md status history + updated register row.

## Write access
- ticket-architect: 02-solution.md + register/status + memory appends
- ticket-developer: src/, 03-build-notes.md, package/, deploy-steps.md + register/status
- ticket-tester: test classes under src/, 04-test-evidence.md + register/status
- 01-ticket.md is READ-ONLY after paste (it is the requirement source)
- Nobody runs org-touching commands. PACKAGE-ONLY policy (CLAUDE.md) is absolute.

## Per-ticket quality gates
1. SOLUTIONED requires: approach + impacted-metadata list + risks + open questions (may be empty,
   must be considered) + test strategy.
2. BUILT requires: metadata-lint PASS on src/ (a lint FAIL is a defect, fix before claiming BUILT).
3. TESTED requires: test classes with meaningful asserts (state, not no-exception) + a manual
   verification script; everything marked "NOT RUN — expected results" until human executes.
4. PACKAGED requires: delta package.xml listing EXACTLY the src/ contents (reconcile: 0 missing,
   0 extra) + deploy-steps.md with explicit --target-org placeholder + post-deploy checks +
   rollback note (destructiveChanges.xml if the ticket removes anything).

## Cross-ticket discipline
- Check TICKETS.md for related/conflicting tickets BEFORE solutioning (same objects/classes).
- Reusable learnings → .claude/memory/org-facts.md or decisions.md, cited by later tickets.
- One folder per ticket, named `<JIRA-KEY>-<slug>`; never edit another ticket's folder.

## Honesty
- No fabricated Jira updates: this workshop is file-local; the human syncs Jira.
- Ambiguity → open question in 02-solution.md; never silently decide scope.
