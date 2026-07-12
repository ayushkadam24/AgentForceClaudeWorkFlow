// TC-013 — MO flow (VS-03) fault/validation paths
// feature: F-001 slot-booking-core | producing-agent: qa-engineer | date: 2026-07-12
// phase: QA_IN_PROGRESS (/qa-run B) | derives-from: 03-qa/test-plan.md TC-013 (REQ-010/011/012, Tier 1)
//
// STATUS THIS RUN: BLOCKED — no browser/Playwright session obtainable (A-019). See TC-012 spec header
// for the same login/precondition notes; not repeated here.
//
// ***STATIC PROXY THIS RUN (not a live UI run — clearly marked)***: the flow's actual in-flow
// validationRule elements were confirmed to exist exactly as this TC expects by reading the deployed
// flow metadata directly (force-app/main/default/flows/VS_Session_Screen_DefineCapacity.flow-meta.xml,
// lines 176-213):
//   - VS_Session_Date_Input:  {!VS_Session_Date_Input} >= TODAY()
//       -> "Session date cannot be in the past. Please choose today or a future date."
//   - VS_Start_Time_Input:    DATEVALUE({!VS_Start_Time_Input}) = {!VS_Session_Date_Input}
//       -> "Start time must fall on the selected session date..."
//   - VS_End_Time_Input:      AND(End > Start, DATEVALUE(End) = SessionDate)
//       -> "End time must be after the start time and must fall on the selected session date..."
//   - VS_Total_Capacity_Input: {!VS_Total_Capacity_Input} > 0
//       -> "Enter a total capacity greater than 0 so slots can be generated for this session."
// All 4 messages are plain-language, tell the user what to DO (rules/20 "Validation rules: error
// messages tell the USER what to do, not what the system did"), not internal state. This is a
// structural confirmation that the fault/validation SURFACE exists as designed — it does NOT prove
// the screen actually renders/blocks submission live, which requires the browser run below.
//
// Drive-Day checkbox -> VS_Is_Drive_Day__c: confirmed the screen field VS_Drive_Day_Input is wired to
// set VS_Session__c.VS_Is_Drive_Day__c on the Create Records element (VS_Create_Session, line 51+) —
// structural wiring present, not live-verified.

import { test, expect } from '@playwright/test';

test.describe('TC-013: MO flow fault/validation paths', () => {
  test('capacity <= 0 is blocked with a plain-language message', async ({ page }) => {
    await page.goto('/lightning/n/VS_Session_Screen_DefineCapacity');
    // ... fill Facility/Service/Date/Start/End as in TC-012 ...
    await page.getByLabel(/Total Capacity/i).fill('0');
    await page.getByRole('button', { name: /Next|Finish/i }).click();
    await expect(
      page.getByText('Enter a total capacity greater than 0 so slots can be generated for this session.')
    ).toBeVisible();
    await page.screenshot({ path: '03-qa/evidence/TC-013-capacity-zero-blocked.png' });
  });

  test('end time <= start time is blocked with a plain-language message', async ({ page }) => {
    await page.goto('/lightning/n/VS_Session_Screen_DefineCapacity');
    const d = new Date();
    d.setDate(d.getDate() + 2);
    const dateStr = d.toISOString().slice(0, 10);
    await page.getByLabel(/Session Date/i).fill(dateStr);
    await page.getByLabel(/Start Time/i).fill(`${dateStr}T10:00`);
    await page.getByLabel(/End Time/i).fill(`${dateStr}T09:00`); // before start
    await page.getByRole('button', { name: /Next|Finish/i }).click();
    await expect(
      page.getByText(/End time must be after the start time/i)
    ).toBeVisible();
    await page.screenshot({ path: '03-qa/evidence/TC-013-end-before-start-blocked.png' });
  });

  test('past-dated session is blocked with a plain-language message', async ({ page }) => {
    await page.goto('/lightning/n/VS_Session_Screen_DefineCapacity');
    const d = new Date();
    d.setDate(d.getDate() - 1);
    const dateStr = d.toISOString().slice(0, 10);
    await page.getByLabel(/Session Date/i).fill(dateStr);
    await page.getByRole('button', { name: /Next|Finish/i }).click();
    await expect(
      page.getByText('Session date cannot be in the past. Please choose today or a future date.')
    ).toBeVisible();
    await page.screenshot({ path: '03-qa/evidence/TC-013-past-date-blocked.png' });
  });

  test('Drive Day checkbox sets VS_Is_Drive_Day__c=true on the created session', async ({ page }) => {
    await page.goto('/lightning/n/VS_Session_Screen_DefineCapacity');
    // ... fill valid Facility/Service/Date/Start/End/Capacity ...
    await page.getByLabel(/Drive Day/i).check();
    await page.getByRole('button', { name: /Next|Finish/i }).click();
    await expect(page.getByText(/success|created/i)).toBeVisible();
    // Verify VS_Is_Drive_Day__c=true via `sf data query` on the newly created session Id — the
    // formula/checkbox value is not independently re-displayed on the success screen.
    await page.screenshot({ path: '03-qa/evidence/TC-013-drive-day-created.png' });
  });
});
