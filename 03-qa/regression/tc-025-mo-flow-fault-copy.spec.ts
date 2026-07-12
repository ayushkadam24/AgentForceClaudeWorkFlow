// TC-025 — MO flow copy/labels: fault screen shows plain-language message + facility helpline (C7.3)
// feature: F-001 slot-booking-core | producing-agent: qa-engineer | date: 2026-07-12
// phase: QA_IN_PROGRESS (/qa-run B) | derives-from: 03-qa/test-plan.md TC-025 (Tier 3, C7.3)
//
// STATUS THIS RUN: BLOCKED — no browser/Playwright session obtainable (A-019).
//
// STATIC PROXY THIS RUN: read the deployed VS_Session_Fault_Screen field text directly from
// force-app/main/default/flows/VS_Session_Screen_DefineCapacity.flow-meta.xml (line 250):
//   "We could not save this session. Please check the details and try again in a few minutes.
//    If the problem continues, contact the facility helpline: {!VS_Helpline_Display}.
//    Reference for support staff: {!$Flow.FaultMessage}"
// FINDING (worth a human/architect eyeball, not filed as a bug): the message IS plain-language and
// DOES include the facility helpline number as required — but it also appends the raw
// {!$Flow.FaultMessage} system value as a "Reference for support staff" line. This is a common,
// reasonable UX pattern (an error-reference code for support triage), not a full stack trace dump,
// but it does mean SOME internal system detail reaches the screen. Flagging for a human call on
// whether "Reference for support staff: <raw fault message>" satisfies "not a raw error/stack trace"
// as strictly as C7.3 intends, or should be replaced with an opaque incident ID. Not filed as
// BUG-### because the plain-language message + helpline requirement (the TC's literal AC) IS met;
// this is a secondary observation.

import { test, expect } from '@playwright/test';

test.describe('TC-025: MO flow fault screen copy', () => {
  test('a forced fault (e.g. FLS/CRUD DML failure) shows plain-language text + helpline, not a raw stack trace', async ({
    page
  }) => {
    // Arrange: trigger a fault path, e.g. log in as a user with read-only VS_Session__c access
    // (any of the 4 non-MO production permsets) and attempt the flow, or simulate a DML failure.
    await page.goto('/lightning/n/VS_Session_Screen_DefineCapacity');
    // ... fill valid inputs, submit as a user expected to fail the Create Records DML ...
    await page.getByRole('button', { name: /Next|Finish/i }).click();

    await expect(page.getByText(/We could not save this session/i)).toBeVisible();
    await expect(page.getByText(/contact the facility helpline/i)).toBeVisible();
    // Assert NO raw Apex/DML exception class name (e.g. "System.DmlException") appears as the
    // PRIMARY visible message (the secondary "Reference for support staff" line noted above is a
    // known, flagged nuance, not asserted against here).
    await expect(page.getByText(/System\.\w+Exception/)).toHaveCount(0);

    await page.screenshot({ path: '03-qa/evidence/TC-025-fault-screen-copy.png' });
  });
});
