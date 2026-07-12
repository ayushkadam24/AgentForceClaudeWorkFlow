// TC-027 — Cosmetic sanity: standard Salesforce record/list-view pages render without layout breakage
// feature: F-001 slot-booking-core | producing-agent: qa-engineer | date: 2026-07-12
// phase: QA_IN_PROGRESS (/qa-run B) | derives-from: 03-qa/test-plan.md TC-027 (Tier 3)
//
// STATUS THIS RUN: BLOCKED — no browser/Playwright session obtainable (A-019), and no role test
// users exist to log in as this run (§1.2 precondition unmet — 0 role permsets assigned to any
// standing user this session, see TC-010 evidence: only the harness permset has any assignment).
// No static proxy is meaningful for rendered-layout checks.

import { test, expect } from '@playwright/test';

const OBJECTS = ['VS_Facility__c', 'VS_Service__c', 'VS_Session__c', 'VS_Slot__c'] as const;

test.describe('TC-027: cosmetic sanity of standard list/record pages per permitted role', () => {
  for (const obj of OBJECTS) {
    test(`${obj} list view renders without layout breakage`, async ({ page }) => {
      await page.goto(`/lightning/o/${obj}/list`);
      await expect(page.locator('table, [role="grid"]')).toBeVisible();
      await page.screenshot({ path: `03-qa/evidence/TC-027-${obj}-list.png`, fullPage: true });
    });

    test(`${obj} record page renders without layout breakage`, async ({ page }) => {
      // Navigate to a known seeded record Id (populate from seed.apex output before running).
      await page.goto(`/lightning/o/${obj}/list`);
      await page.locator('table a, [role="grid"] a').first().click();
      await expect(page.locator('records-lwc-highlights-panel, .slds-page-header')).toBeVisible();
      await page.screenshot({ path: `03-qa/evidence/TC-027-${obj}-record.png`, fullPage: true });
    });
  }
});
