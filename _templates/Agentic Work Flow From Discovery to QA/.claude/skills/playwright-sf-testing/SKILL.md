---
name: playwright-sf-testing
description: How to drive and test the Salesforce scratch org UI with Playwright — login, selectors, spec structure, evidence. Used by qa-engineer in QA_IN_PROGRESS.
---

# Playwright against Salesforce

## Login & session
- Get a session URL via CLI: `sf org open --url-only -o <poc-scratch-alias>` and start from it —
  never script the login form with real credentials.
- Persist auth with storageState (`playwright/.auth/state.json`, gitignored) in a setup project;
  specs reuse it. Session timeout is 15 min on shared-device profiles — plan test order accordingly.

## Selector strategy (Lightning DOM is hostile — in order of preference)
1. getByRole / getByLabel / getByText on stable labels (field labels, button names).
2. data-* attributes our own LWCs expose (ask devs to add `data-testid` — it's a valid review ask).
3. NEVER: auto-generated ids, deep shadow-DOM CSS chains, nth-child positional selectors.
- Lightning renders async: await expect(...).toBeVisible() — no page.waitForTimeout / hard sleeps.

## Spec structure
- One TC per spec file `03-qa/regression/tc-###.spec.ts`; header comment: TC id, REQ/VS links, precondition.
- Arrange (navigate/seed via UI or sf data commands) → Act → Assert (visible outcome + record
  state where checkable) → evidence screenshot to `03-qa/evidence/TC-###-<step>.png`.
- Test data: synthetic citizens only (Annexure C3.2); use unique suffixes so re-runs don't collide.

## The <CRITICAL_REQ> concurrency TC
Two parallel browser contexts target the same last-place slot and submit as simultaneously as
possible; assert exactly ONE confirmation and one SLOT_FULL message, then verify booked count
== capacity (UI or `sf data query`). Repeat 3×. Any double-book = Sev-1 BUG, release-blocking.

## Accessibility TCs (Annexure C6)
Keyboard-only booking journey (Tab order, Enter/Space activation, focus visible), axe scan via
@axe-core/playwright on booking/reschedule/cancel/certificate pages (no serious/critical violations),
200% zoom usability, slot states readable without color.
