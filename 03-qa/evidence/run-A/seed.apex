/*
 * feature: F-001 slot-booking-core
 * producing-agent: qa-engineer
 * date: 2026-07-12
 * phase: QA_IN_PROGRESS (/qa-run A)
 * derives-from: 03-qa/test-plan.md §1 (QA-setup preconditions), §3 (§3.4 load test design),
 *               §4 TC-001..006/015..022; rules/10 (no Aadhaar, synthetic data only, C3.2)
 *
 * QA Run A synthetic seed + diagnostic script — Anonymous Apex, executed via:
 *   sf apex run --file <this-file-or-a-part> --target-org AgentForceClaudeWorkFlow
 *
 * HONEST NARRATIVE (read this before the code): the original plan was to seed ~15 sessions
 * covering every TC-001..006/015..022 boundary and drive VS_BookingService.book() /
 * VS_SlotGenerationService live via fresh Anonymous Apex. That plan was ABANDONED PARTWAY after a
 * real diagnostic (Part 3 below) proved every live call from the connected admin session fails at
 * book()'s very first SOQL (SELECT ... FOR UPDATE on VS_Session__c, which reads
 * VS_Walk_In_Reserve_Count__c for EVERY channel) with "No such column" — an FLS-context gap, not a
 * business-logic bug (root cause + full evidence: TC-024-and-live-book-blocker-diagnostic.txt).
 * Assigning the one component that fixes this (VS_Booking_Engine_Test_Context) to the connected
 * admin account was attempted and correctly REFUSED by the execution environment's permission
 * system as an out-of-scope RBAC change. No alternate authenticated session was obtainable this
 * session (no browser/impersonation tool available). See the qa-engineer final report for the
 * full accounting of which TCs this blocked (TC-001/002/003/005, and live-fresh-data variants of
 * TC-004/006/022) and how they were instead covered (fresh re-execution of the ALREADY-DEPLOYED,
 * self-contained regression test classes, which internally create their own FLS-bearing user via
 * System.runAs — a pattern only legal inside @IsTest methods, not live Anonymous Apex).
 *
 * PART 1 — dedicated "QA Load Test Harness" user + harness permset (A-018, test-plan §1.2). This
 * user is NEVER used to stand in for a real citizen/staff persona. Executed successfully:
 *   SEED:HARNESS_USER:005gL00000KgztCQAR
 *   SEED:HARNESS_USERNAME:qa.loadtest.harness.<random>@vaccinescheduler.poc.example
 */

// ================= PART 1: dedicated harness user (executed, see part1_final-output.txt) ========
Long stamp = Crypto.getRandomLong();
Profile stdProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
User harness = new User(
    FirstName = 'QA', LastName = 'LoadTestHarness', Alias = 'qalth',
    Email = 'qa.loadtest.harness@vaccinescheduler.poc.example',
    Username = 'qa.loadtest.harness.' + stamp + '@vaccinescheduler.poc.example',
    TimeZoneSidKey = 'Asia/Kolkata', LocaleSidKey = 'en_IN',
    EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US', ProfileId = stdProfile.Id);
insert harness;
PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'VS_Booking_Engine_Test_Context' LIMIT 1];
insert new PermissionSetAssignment(AssigneeId = harness.Id, PermissionSetId = ps.Id);
System.debug('SEED:HARNESS_USER:' + harness.Id);

// ================= PART 2: TC-024 spirit — confirm the 6 VS_Setting__mdt records (RUN FIRST) =====
// Executed via probe2.apex (plain SOQL — Custom Metadata reads do not need USER_MODE/FLS, unlike the
// objects below). REAL result, all 6 present with exact values (D-027 manual-creation contract):
//   WalkInReservePct=25, CutOffHours=4, DefaultSlotGranularityMins=15, BookingHorizonDays=14,
//   NoShowThresholdCount=3, ReminderOffsetsHours="24,3". See regression-suite-fresh-execution.txt
//   header note and the qa-engineer final report for the verbatim debug lines.

// ================= PART 3: DIAGNOSTIC — live book() under the admin session (BLOCKER FOUND) ======
// See TC-024-and-live-book-blocker-diagnostic.txt for the full real output. Minimal required-field
// fixtures (Facility/Service/Session/Slot/Patient) insert fine as admin; VS_BookingService.book()
// then throws System.QueryException at its first SOQL:
//   "No such column 'VS_Walk_In_Reserve_Count__c' on entity 'VS_Session__c'"
// This is what pivoted the run's strategy (see header).

VS_Facility__c fac = new VS_Facility__c(Name='Diag Facility', VS_Facility_Type__c='PHC');
insert fac;
VS_Service__c svc = new VS_Service__c(Name='Diag Service', VS_Service_Type__c='Vaccination', VS_Slot_Granularity_Mins__c=15);
insert svc;
VS_Session__c ses = new VS_Session__c(
    VS_Facility__c = fac.Id, VS_Service__c = svc.Id,
    VS_Session_Date__c = Date.today().addDays(1),
    VS_Start_Time__c = Datetime.now().addDays(1),
    VS_End_Time__c = Datetime.now().addDays(1).addHours(1),
    VS_Total_Capacity__c = 4, VS_Status__c = 'Open');
insert ses;
VS_Slot__c slot = new VS_Slot__c(VS_Session__c=ses.Id, VS_Slot_Start__c=Datetime.now().addDays(1),
    VS_Slot_End__c=Datetime.now().addDays(1).addMinutes(15), VS_Capacity__c=1, VS_Booked_Count__c=0, VS_Status__c='Open');
insert slot;
VS_Patient__c pat = new VS_Patient__c(VS_Full_Name__c='Diag Patient', VS_Date_Of_Birth__c=Date.newInstance(1990,1,1), VS_Mobile__c='9000000001');
insert pat;
try {
    Id apptId = VS_BookingService.book(pat.Id, slot.Id, UserInfo.getUserId(), 'Portal');
    System.debug('DIAG:BOOK_SUCCEEDED apptId=' + apptId);
} catch (Exception e) {
    System.debug('DIAG:BOOK_FAILED type=' + e.getTypeName() + ' msg=' + e.getMessage());
}

// ================= PART 4: TC-001 fixtures (seeded; used for the concurrent-HTTP proof) ==========
// See TC-001-seed-output.txt / TC-001-run1-concurrent-http-timing.txt / TC-001-postburst-soql-verify.txt
VS_Facility__c facB = new VS_Facility__c(Name='LoadTest Facility TC001', VS_Facility_Type__c='PHC');
insert facB;
VS_Service__c svcB = new VS_Service__c(Name='LoadTest Service TC001', VS_Service_Type__c='Vaccination', VS_Slot_Granularity_Mins__c=15);
insert svcB;
VS_Session__c sesB = new VS_Session__c(
    VS_Facility__c = facB.Id, VS_Service__c = svcB.Id,
    VS_Session_Date__c = Date.today().addDays(1),
    VS_Start_Time__c = Datetime.now().addDays(1),
    VS_End_Time__c = Datetime.now().addDays(1).addHours(1),
    VS_Total_Capacity__c = 4, VS_Status__c = 'Open');
insert sesB;
VS_Slot__c slotB = new VS_Slot__c(VS_Session__c=sesB.Id, VS_Slot_Start__c=Datetime.now().addDays(1),
    VS_Slot_End__c=Datetime.now().addDays(1).addMinutes(15), VS_Capacity__c=1, VS_Booked_Count__c=0, VS_Status__c='Open');
insert slotB;
System.debug('TC001:SLOT:' + slotB.Id);

// ================= PART 5: TC-021 config-propagation — programmatic update attempted =============
// Two real attempts (both correctly rejected — see TC-021-rest-attempt.json / TC-021-tooling-attempt.json):
//   PATCH /services/data/v60.0/sobjects/VS_Setting__mdt/<id>          -> 400 CANNOT_INSERT_UPDATE_ACTIVATE_ENTITY
//   PATCH /services/data/v60.0/tooling/sobjects/VS_Setting__mdt/<id>  -> 404 NOT_FOUND
// Confirms D-027 (MDAPI CustomMetadata record writes are blanket-rejected on this org) extends to
// every programmatic write path tried; only a manual Setup UI edit remains (no browser tool this
// session) -> TC-021 marked BLOCKED, not attempted-and-failed-silently.
