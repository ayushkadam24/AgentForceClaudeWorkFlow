// TC-014 — MO flow negative: mismatched facility+service pair is NOT blocked (known gap A-010)
// feature: F-001 slot-booking-core | producing-agent: qa-engineer | date: 2026-07-12
// phase: QA_IN_PROGRESS (/qa-run B) | derives-from: 03-qa/test-plan.md TC-014 (REQ-010/011, A-010)
//
// STATUS THIS RUN: BLOCKED — no browser/Playwright session obtainable (A-019).
//
// STATIC PROXY THIS RUN: confirmed structurally that VS_Session_Screen_DefineCapacity's Facility and
// Service dynamicChoiceSets (VS_Active_Facility_Choices / VS_Active_Service_Choices) are two
// INDEPENDENT active-record lists with no cross-filter against VS_Facility_Service__c (A-010,
// dev-mid's own flagged assumption, never resolved by BA_ARCH_CONFIRM as a MUST-FIX — drift-check
// left it DEVIATES-ACCEPTABLE). This confirms the code path this TC targets still exists as
// documented; the live behavioral confirmation (submit succeeds anyway, no new block appeared since
// A-010 was raised) requires the browser run below.

import { test, expect } from '@playwright/test';

test.describe('TC-014: mismatched facility+service is not blocked (confirms unchanged behavior, not a new regression)', () => {
  test('a facility+service pair with no active VS_Facility_Service__c offering still saves successfully', async ({
    page
  }) => {
    await page.goto('/lightning/n/VS_Session_Screen_DefineCapacity');
    await page.getByLabel(/Facility/i).click();
    await page.getByText(/Facility A/i).first().click(); // pick a facility with NO active offering for the service below
    await page.getByLabel(/Service/i).click();
    await page.getByText(/Service B \(not offered at Facility A\)/i).first().click();

    const d = new Date();
    d.setDate(d.getDate() + 2);
    const dateStr = d.toISOString().slice(0, 10);
    await page.getByLabel(/Session Date/i).fill(dateStr);
    await page.getByLabel(/Start Time/i).fill(`${dateStr}T09:00`);
    await page.getByLabel(/End Time/i).fill(`${dateStr}T10:00`);
    await page.getByLabel(/Total Capacity/i).fill('10');
    await page.getByRole('button', { name: /Next|Finish/i }).click();

    // Expected (per A-010's documented, accepted-as-is behavior): the flow does NOT block this —
    // no cross-check against VS_Facility_Service__c exists. If a NEW block appears here that did not
    // exist when A-010 was raised, that is a change worth flagging to architect/BA (could be a
    // silent regression OR a welcome fix — either way, not something to assume without investigation).
    await expect(page.getByText(/success|created/i)).toBeVisible();
    await page.screenshot({ path: '03-qa/evidence/TC-014-mismatched-facility-service-not-blocked.png' });
  });
});
