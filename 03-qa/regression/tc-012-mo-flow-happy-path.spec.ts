// TC-012 — MO flow (VS-03) happy path
// feature: F-001 slot-booking-core | producing-agent: qa-engineer | date: 2026-07-12
// phase: QA_IN_PROGRESS (/qa-run B) | derives-from: 03-qa/test-plan.md TC-012 (REQ-010/011/012, Tier 1)
//
// STATUS THIS RUN: BLOCKED — no browser/Playwright session obtainable in this QA environment
// (A-019 / Run A finding, reconfirmed this run: this environment has CLI/Tooling-API access only,
// no interactive browser). This spec is written so the NEXT engineer with a real browser session can
// run it as-is (or close to it) once `@playwright/test` is added as a devDependency and a
// playwright.config.ts + storageState setup project exist per the playwright-sf-testing skill.
//
// PRECONDITION: TC-024 run first (WalkInReservePct=25 confirmed this run — see
// 03-qa/evidence/run-B/TC-024-cmdt-audit.json). A user assigned ONLY `VS_MO_Facility_Admin`
// (NOT the test harness permset, per A-018) must exist and be logged in via storageState.
// At least one active VS_Facility__c + VS_Service__c + active VS_Facility_Service__c junction must
// be seeded (reuse 03-qa/evidence/run-A/seed.apex or top up).
//
// Login & session per skill: `sf org open --url-only -o AgentForceClaudeWorkFlow` to mint a session
// URL for the MO test user (or a Connected App OAuth flow — never script the login form with real
// credentials), then persist via storageState (playwright/.auth/state.json, gitignored).

import { test, expect } from '@playwright/test';

test.describe('TC-012: MO flow happy path — VS_Session__c creation with correct capacity math', () => {
  test('MO creates a session; Walk-In Reserve / Bookable Capacity formulas compute against WalkInReservePct=25', async ({
    page
  }) => {
    // Arrange: navigate to the VS_Session_Screen_DefineCapacity flow (Lightning App Page tab or
    // Global Quick Action — exact placement is a manual post-deploy Setup step per the VS-03 packet).
    await page.goto('/lightning/n/VS_Session_Screen_DefineCapacity'); // adjust to actual tab API name once placed

    // Act: fill the screen flow fields using stable labels (per skill selector strategy — getByLabel,
    // never auto-generated ids).
    await page.getByLabel(/Facility/i).click();
    await page.getByText(/Diag Facility|Seed Facility/i).first().click(); // adjust to real seeded facility name
    await page.getByLabel(/Service/i).click();
    await page.getByText(/Diag Service|Seed Service/i).first().click();

    const sessionDate = new Date();
    sessionDate.setDate(sessionDate.getDate() + 2); // avoid TC-024/CutOffHours edge, avoid today
    const dateStr = sessionDate.toISOString().slice(0, 10);
    await page.getByLabel(/Session Date/i).fill(dateStr);
    await page.getByLabel(/Start Time/i).fill(`${dateStr}T09:00`);
    await page.getByLabel(/End Time/i).fill(`${dateStr}T10:00`);
    await page.getByLabel(/Total Capacity/i).fill('80');
    // Drive Day left unchecked for the happy path (TC-017 covers drive-day override separately)

    await page.getByRole('button', { name: /Next|Finish/i }).click();

    // Assert: success screen + record state
    await expect(page.getByText(/Session Not Saved/i)).toHaveCount(0); // must NOT hit the fault screen
    await expect(page.getByText(/success|created/i)).toBeVisible();

    // Verify VS_Walk_In_Reserve_Count__c / VS_Bookable_Capacity__c formulas: at capacity=80,
    // WalkInReservePct=25 -> reserve=CEILING(80*0.25)=20, bookable=60. Verify via `sf data query`
    // in an afterEach/companion script (formula fields are read-only, platform-computed — not
    // independently settable in the UI, so a record query is the authoritative assert, not a
    // screen read).

    await page.screenshot({ path: '03-qa/evidence/TC-012-happy-path-success.png', fullPage: true });
  });
});
