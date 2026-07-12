// TC-026 — MO flow accessibility spot-check (staff-UI proxy, NOT REQ-056 satisfaction — see test-plan §2)
// feature: F-001 slot-booking-core | producing-agent: qa-engineer | date: 2026-07-12
// phase: QA_IN_PROGRESS (/qa-run B) | derives-from: 03-qa/test-plan.md TC-026 (Tier 3, C6 proxy)
//
// STATUS THIS RUN: BLOCKED — no browser/Playwright session obtainable (A-019). No static proxy is
// meaningful for keyboard/screen-reader/axe/zoom checks (they are inherently runtime/rendering
// checks; nothing in the flow's XML metadata can substitute for them). Left as scaffolding only.
//
// Requires @axe-core/playwright as a devDependency (not yet in package.json — add when a browser
// session is available and this spec is first run for real).

import { test, expect } from '@playwright/test';
// import AxeBuilder from '@axe-core/playwright';

test.describe('TC-026: MO flow accessibility spot-check', () => {
  test('keyboard-only operation: Tab order reaches every field, Enter/Space activates buttons, focus always visible', async ({
    page
  }) => {
    await page.goto('/lightning/n/VS_Session_Screen_DefineCapacity');
    // Tab through every field in document order; assert each is reachable and focus-visible.
    await page.keyboard.press('Tab');
    await expect(page.getByLabel(/Facility/i)).toBeFocused();
    await page.keyboard.press('Tab');
    await expect(page.getByLabel(/Service/i)).toBeFocused();
    // ... continue through Session Date / Start / End / Total Capacity / Drive Day / Next button ...
    // Activate the Next/Finish button via keyboard only (Enter, not a mouse click).
    await page.keyboard.press('Enter');
  });

  test('axe-core scan: no serious/critical violations on the session-details screen', async ({ page }) => {
    await page.goto('/lightning/n/VS_Session_Screen_DefineCapacity');
    // const results = await new AxeBuilder({ page }).analyze();
    // const serious = results.violations.filter(v => ['serious', 'critical'].includes(v.impact ?? ''));
    // expect(serious).toEqual([]);
  });

  test('200% zoom usability: no field/button becomes unreachable or overlapping at 200% zoom', async ({
    page
  }) => {
    await page.goto('/lightning/n/VS_Session_Screen_DefineCapacity');
    await page.setViewportSize({ width: 640, height: 480 }); // approximates 200% zoom on a 1280x960 baseline
    await expect(page.getByLabel(/Facility/i)).toBeVisible();
    await expect(page.getByRole('button', { name: /Next|Finish/i })).toBeVisible();
    await page.screenshot({ path: '03-qa/evidence/TC-026-200pct-zoom.png' });
  });
});
