/**
 * VS_SlotGenBatchTest — tests for the VS-06 slot-generation engine (VS_SlotGenBatch +
 * VS_SlotGenerationService + VS_SlotGenException), EP-02.
 *
 * Covers every VS-06 acceptance criterion with MEANINGFUL state asserts (not "no exception"):
 *  - even distribution: sum(VS_Slot__c.VS_Capacity__c) == VS_Session__c.VS_Bookable_Capacity__c,
 *    remainder to the EARLIEST slots (D-023/A-005);
 *  - holiday skip: a normal session on a holiday date generates NO slots (D-018);
 *  - drive-day override: a drive-day session on a holiday date DOES generate slots (D-018);
 *  - booking horizon: sessions beyond BookingHorizonDays generate no slots (REQ-013);
 *  - idempotency: re-running the batch does not double-generate;
 *  - NEGATIVE: buildSlots throws VS_SlotGenException on invalid granularity / window;
 *  - BULK (REQ-062): 250 sessions in one service call issue a CONSTANT number of SOQL/DML
 *    statements (no SOQL/DML-in-loop) and stay within governor limits.
 *
 * === FLS/USER_MODE TEST PATTERN (BLOCKER C→F, dev-senior 2026-07-12) ===
 * ROOT CAUSE (BLOCKER F): this DE org ENFORCES FLS/CRUD on PLAIN Apex DML during deploy-time
 * RunLocalTests (not the usual system-mode bypass), and the deploying admin has no FLS on the freshly
 * Metadata-API-deployed OPTIONAL VS_ fields (e.g. VS_Is_Drive_Day__c) — so plain-DML fixtures fail at
 * setup. Pattern applied: the harness User is created (setup DML) OUTSIDE runAs; ALL non-setup fixture
 * DML AND the batch/generateForSessions engine calls run INSIDE System.runAs(slotGenUser()), which
 * carries the VS_Booking_Engine_Test_Context harness permset (create/read on fixture objects +
 * VS_Slot__c create + FLS on VS_Is_Drive_Day__c and the formula reads). Setup DML outside + non-setup
 * inside runAs avoids MIXED_DML. Production code is UNCHANGED; the permset is TEST-ONLY and does NOT
 * resolve the A-018 runtime gap (BA_ARCH_CONFIRM).
 *
 * GOVERNOR-WINDOW INTEGRITY: the 250-session test captures Limits.getQueries()/getDmlStatements() ONLY
 * around the generateForSessions call; the User setup (@TestSetup), the fixtures, and the runAs entry
 * are all OUTSIDE that measured window, so the SOQL<=4/DML==1 budget measures only the engine call.
 *
 * No SeeAllData; synthetic data only (rules/10, no Aadhaar). @TestSetup builds the shared spine;
 * the 250-session bulk case builds its own isolated data.
 */
@IsTest(SeeAllData=false)
private class VS_SlotGenBatchTest {

    // Distinct session dates so each test can fetch its session by date after @TestSetup.
    private static Date normalDate()  { return Date.today().addDays(2); }   // normal, in-horizon
    private static Date holidayDate() { return Date.today().addDays(3); }   // normal on a holiday
    private static Date driveDate()   { return Date.today().addDays(4); }   // drive-day on a holiday
    private static Date beyondDate()  { return Date.today().addDays(30); }  // beyond the 14-day horizon

    // Dedicated TEST/CI FLS harness permset (see VS-06 review packet, BLOCKER C/F). TEST-ONLY — it does
    // NOT resolve the A-018 runtime gap (no role permset grants VS_Slot__c create; that stays routed).
    private static final String TEST_PERMSET = 'VS_Booking_Engine_Test_Context';

    private static Datetime at(Date d, Integer hour) {
        return Datetime.newInstance(d, Time.newInstance(hour, 0, 0, 0));
    }

    @TestSetup
    static void makeData() {
        // Setup-object DML (User + PermissionSetAssignment) FIRST, in the default context; then wrap all
        // non-setup fixture DML in runAs(u) — the canonical MIXED_DML-safe ordering, and the org's
        // deploy-time FLS enforcement means fixtures must be built by an FLS-bearing user anyway.
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            FirstName = 'VS',
            LastName = 'VSSlotGenTest',
            Alias = 'vssgt',
            Email = 'vs.slotgen.test@vaccinescheduler.poc.example',
            Username = 'vs.slotgen.test.' + Math.abs(Crypto.getRandomLong())
                + '@vaccinescheduler.poc.example',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id);
        insert u;
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :TEST_PERMSET LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        System.runAs(u) {
            VS_Facility__c fac = new VS_Facility__c(Name = 'Test PHC Kothrud');
            insert fac;

            VS_Service__c svc = new VS_Service__c(Name = 'COVID Vaccination');
            insert svc; // VS_Service_Type__c (Vaccination) + VS_Slot_Granularity_Mins__c (15) default in

            List<VS_Session__c> sessions = new List<VS_Session__c>{
                newSession(fac.Id, svc.Id, normalDate(),  9, 13, 80, false), // 240min/15=16 slots, bookable 60
                newSession(fac.Id, svc.Id, holidayDate(), 9, 11, 40, false), // on a holiday, not a drive day
                newSession(fac.Id, svc.Id, driveDate(),   9, 11, 40, true),  // on a holiday, drive day (override)
                newSession(fac.Id, svc.Id, beyondDate(),  9, 11, 40, false)  // beyond horizon
            };
            insert sessions;

            insert new List<VS_Holiday__c>{
                new VS_Holiday__c(VS_Facility__c = fac.Id, VS_Holiday_Date__c = holidayDate()),
                new VS_Holiday__c(VS_Facility__c = fac.Id, VS_Holiday_Date__c = driveDate())
            };
        }
    }

    /** The FLS-bearing harness user under which fixtures AND the engine calls execute (BLOCKER F). */
    private static User slotGenUser() {
        return [SELECT Id FROM User WHERE LastName = 'VSSlotGenTest' LIMIT 1];
    }

    private static VS_Session__c newSession(
            Id facId, Id svcId, Date d, Integer startHour, Integer endHour,
            Integer total, Boolean driveDay) {
        return new VS_Session__c(
            VS_Facility__c     = facId,
            VS_Service__c      = svcId,
            VS_Session_Date__c = d,
            VS_Start_Time__c   = at(d, startHour),
            VS_End_Time__c     = at(d, endHour),
            VS_Total_Capacity__c = total,
            VS_Status__c       = 'Open',
            VS_Is_Drive_Day__c = driveDay);
    }

    private static VS_Session__c fetchSession(Date d) {
        return [
            SELECT Id, VS_Session_Date__c, VS_Start_Time__c, VS_End_Time__c,
                   VS_Bookable_Capacity__c, VS_Is_Drive_Day__c, VS_Facility__c, VS_Service__c
            FROM VS_Session__c WHERE VS_Session_Date__c = :d LIMIT 1];
    }

    private static List<VS_Slot__c> fetchSlots(Id sessionId) {
        return [
            SELECT Id, VS_Slot_Start__c, VS_Slot_End__c, VS_Capacity__c,
                   VS_Booked_Count__c, VS_Status__c
            FROM VS_Slot__c WHERE VS_Session__c = :sessionId
            ORDER BY VS_Slot_Start__c ASC];
    }

    // --- AC1: even distribution, remainder to earliest, sum == bookable capacity ---
    @IsTest
    static void testEvenDistribution_sumsToBookableExactly() {
      System.runAs(slotGenUser()) {
        VS_Session__c ses = fetchSession(normalDate());
        Integer bookable = ses.VS_Bookable_Capacity__c.intValue();
        System.assertEquals(60, bookable, 'Precondition: 80 total, 25% reserve -> 60 bookable');

        Test.startTest();
        Database.executeBatch(new VS_SlotGenBatch(), 200);
        Test.stopTest();

        List<VS_Slot__c> slots = fetchSlots(ses.Id);
        System.assertEquals(16, slots.size(), '240-min window / 15-min granularity = 16 slots');

        Integer sum = 0;
        for (VS_Slot__c sl : slots) {
            sum += sl.VS_Capacity__c.intValue();
            System.assertEquals(0, sl.VS_Booked_Count__c.intValue(), 'Booked count starts at 0');
            System.assertEquals('Open', sl.VS_Status__c, 'Generated slots are Open');
        }
        System.assertEquals(bookable, sum,
            'INVARIANT: sum(slot capacity) must equal session bookable capacity EXACTLY (D-023/A-005)');

        // Remainder (60 mod 16 = 12) goes to the 12 EARLIEST slots -> 4 each; the rest get 3.
        for (Integer i = 0; i < slots.size(); i++) {
            Integer expected = (i < 12) ? 4 : 3;
            System.assertEquals(expected, slots[i].VS_Capacity__c.intValue(),
                'Remainder must land on the earliest slots (index ' + i + ')');
        }

        // Contiguous 15-min windows starting at the session start.
        System.assertEquals(ses.VS_Start_Time__c, slots[0].VS_Slot_Start__c, 'First slot starts at session start');
        System.assertEquals(slots[0].VS_Slot_Start__c.addMinutes(15), slots[0].VS_Slot_End__c, 'Slot is 15 min long');
        System.assertEquals(slots[0].VS_Slot_End__c, slots[1].VS_Slot_Start__c, 'Slots are contiguous');
        System.assertEquals(ses.VS_End_Time__c, slots[15].VS_Slot_End__c, 'Last slot ends at session end');
      }
    }

    // --- AC2: normal session on a holiday date -> no slots (D-018) ---
    @IsTest
    static void testHolidaySkip_generatesNoSlots() {
      System.runAs(slotGenUser()) {
        VS_Session__c ses = fetchSession(holidayDate());

        Test.startTest();
        Database.executeBatch(new VS_SlotGenBatch(), 200);
        Test.stopTest();

        System.assertEquals(0, fetchSlots(ses.Id).size(),
            'A normal session on a holiday-closed date must generate NO slots (D-018)');
      }
    }

    // --- AC3: drive-day session overrides a holiday closure (D-018) ---
    @IsTest
    static void testDriveDayOverridesHoliday_generatesSlots() {
      System.runAs(slotGenUser()) {
        VS_Session__c ses = fetchSession(driveDate());
        Integer bookable = ses.VS_Bookable_Capacity__c.intValue(); // 40 total, reserve 10 -> 30

        Test.startTest();
        Database.executeBatch(new VS_SlotGenBatch(), 200);
        Test.stopTest();

        List<VS_Slot__c> slots = fetchSlots(ses.Id);
        System.assertEquals(8, slots.size(),
            'Drive-day session on a holiday still generates its slots (120min/15=8) (D-018)');
        Integer sum = 0;
        for (VS_Slot__c sl : slots) { sum += sl.VS_Capacity__c.intValue(); }
        System.assertEquals(bookable, sum, 'Drive-day slots still sum to bookable capacity exactly');
      }
    }

    // --- AC4: booking horizon boundary (REQ-013) ---
    @IsTest
    static void testBookingHorizon_excludesBeyondHorizon() {
      System.runAs(slotGenUser()) {
        VS_Session__c beyond = fetchSession(beyondDate());
        VS_Session__c inHorizon = fetchSession(normalDate());

        Test.startTest();
        Database.executeBatch(new VS_SlotGenBatch(), 200);
        Test.stopTest();

        System.assertEquals(0, fetchSlots(beyond.Id).size(),
            'Session beyond BookingHorizonDays (14) must generate no slots (REQ-013)');
        System.assert(fetchSlots(inHorizon.Id).size() > 0,
            'In-horizon session still generates slots (boundary sanity)');
      }
    }

    // --- Idempotency: re-running the batch does not double-generate ---
    @IsTest
    static void testReRun_isIdempotent() {
      System.runAs(slotGenUser()) {
        Id normalId = fetchSession(normalDate()).Id;

        Test.startTest();
        Database.executeBatch(new VS_SlotGenBatch(), 200);
        Test.stopTest();
        Integer firstRun = fetchSlots(normalId).size();
        System.assertEquals(16, firstRun, 'First run generates 16 slots');

        // Second run: already-slotted sessions are excluded by the start() query.
        Database.executeBatch(new VS_SlotGenBatch(), 200);
        System.assertEquals(firstRun, fetchSlots(normalId).size(),
            'Re-run must not double-generate slots (idempotent, no SOQL/DML in loop)');
      }
    }

    // --- NEGATIVE: buildSlots throws VS_SlotGenException on invalid input ---
    // buildSlots() is pure in-memory (no DML/SOQL), but the fetchSession/fixtures read/insert VS_ data,
    // so the whole body runs under runAs(slotGenUser()) for FLS.
    @IsTest
    static void testBuildSlots_invalidGranularity_throws() {
      System.runAs(slotGenUser()) {
        VS_Session__c ses = fetchSession(normalDate());
        Boolean thrown = false;
        try {
            VS_SlotGenerationService.buildSlots(ses, 0);
        } catch (VS_SlotGenException e) {
            thrown = true;
            System.assertEquals('INVALID_GRANULARITY', e.getMessage(), 'Coded message expected');
        }
        System.assert(thrown, 'Zero/negative granularity must raise VS_SlotGenException');
      }
    }

    @IsTest
    static void testBuildSlots_invalidWindow_throws() {
      System.runAs(slotGenUser()) {
        // Degenerate session: end == start -> no valid slot window.
        VS_Facility__c fac = [SELECT Id FROM VS_Facility__c LIMIT 1];
        VS_Service__c svc = [SELECT Id FROM VS_Service__c LIMIT 1];
        Date d = Date.today().addDays(5);
        VS_Session__c bad = newSession(fac.Id, svc.Id, d, 9, 9, 40, false); // start == end
        insert bad;
        VS_Session__c fetched = fetchSession(d);

        Boolean thrown = false;
        try {
            VS_SlotGenerationService.buildSlots(fetched, 15);
        } catch (VS_SlotGenException e) {
            thrown = true;
            System.assertEquals('INVALID_WINDOW', e.getMessage(), 'Coded message expected');
        }
        System.assert(thrown, 'A window that cannot fit one slot must raise VS_SlotGenException');
      }
    }

    // --- BULK (REQ-062): 250 sessions -> constant SOQL/DML, no in-loop statements ---
    @IsTest
    static void testBulk_250Sessions_isGovernorSafe() {
      System.runAs(slotGenUser()) {
        // Fixtures built as the harness user, BEFORE Test.startTest -> never in the measured window.
        VS_Facility__c fac = new VS_Facility__c(Name = 'Bulk PHC');
        insert fac;
        VS_Service__c svc = new VS_Service__c(Name = 'Bulk Vaccination');
        insert svc;

        Date d = Date.today().addDays(2);
        List<VS_Session__c> sessions = new List<VS_Session__c>();
        for (Integer i = 0; i < 250; i++) {
            sessions.add(newSession(fac.Id, svc.Id, d, 9, 11, 80, false)); // 8 slots each, bookable 60
        }
        insert sessions;

        // Re-query with the field set VS_SlotGenBatch.start() supplies.
        List<VS_Session__c> scope = [
            SELECT Id, VS_Session_Date__c, VS_Start_Time__c, VS_End_Time__c,
                   VS_Bookable_Capacity__c, VS_Is_Drive_Day__c, VS_Facility__c, VS_Service__c
            FROM VS_Session__c WHERE VS_Facility__c = :fac.Id];
        System.assertEquals(250, scope.size(), 'All 250 bulk sessions queried');

        Test.startTest();
        // Measure ONLY the batch service call: qBefore/dBefore captured immediately before it and
        // qAfter/dAfter immediately after, so neither fixtures, the runAs entry, nor setup are counted.
        Integer qBefore = Limits.getQueries();
        Integer dBefore = Limits.getDmlStatements();
        Integer created = VS_SlotGenerationService.generateForSessions(scope);
        Integer queriesUsed = Limits.getQueries() - qBefore;
        Integer dmlUsed = Limits.getDmlStatements() - dBefore;
        Test.stopTest();

        System.assertEquals(250 * 8, created, '250 sessions x 8 slots = 2000 slots generated');
        System.assert(queriesUsed <= 4,
            'SOQL must be CONSTANT (services + holidays + config), not per-session. Used=' + queriesUsed);
        System.assertEquals(1, dmlUsed, 'Exactly ONE DML statement for the whole scope (no DML-in-loop)');

        // Spot-check the invariant still holds under bulk.
        Id sampleId = scope[0].Id;
        Integer sum = 0;
        for (VS_Slot__c sl : [SELECT VS_Capacity__c FROM VS_Slot__c WHERE VS_Session__c = :sampleId]) {
            sum += sl.VS_Capacity__c.intValue();
        }
        System.assertEquals(60, sum, 'Bulk-generated slots still sum to bookable capacity exactly');
      }
    }

    // --- MINOR-1: configurable (NON-15) granularity over a NON-multiple window (D-008) ---
    // Proves D-008 "configurable, not hardcoded" is actually EXERCISED: a 30-min granularity over a
    // 250-min window (09:00-13:10) -> floor(250/30)=8 slots, the trailing 10-min partial DROPPED, and
    // the sum invariant sum(slot cap)==bookable still holds.
    @IsTest
    static void testConfigurableGranularity_nonMultipleWindow_dropsTrailingPartial() {
      System.runAs(slotGenUser()) {
        VS_Facility__c fac = new VS_Facility__c(Name = 'Granularity PHC');
        insert fac;
        // NON-default 30-min per-service granularity (not the 15 default every other test uses).
        VS_Service__c svc = new VS_Service__c(Name = 'Granularity Svc', VS_Slot_Granularity_Mins__c = 30);
        insert svc;
        Date d = Date.today().addDays(2);
        VS_Session__c ses = new VS_Session__c(
            VS_Facility__c     = fac.Id,
            VS_Service__c      = svc.Id,
            VS_Session_Date__c = d,
            VS_Start_Time__c   = at(d, 9),
            VS_End_Time__c     = Datetime.newInstance(d, Time.newInstance(13, 10, 0, 0)), // 09:00-13:10 = 250 min
            VS_Total_Capacity__c = 80,   // 25% reserve -> bookable 60
            VS_Status__c       = 'Open',
            VS_Is_Drive_Day__c = false);
        insert ses;

        Test.startTest();
        Database.executeBatch(new VS_SlotGenBatch(), 200);
        Test.stopTest();

        VS_Session__c reloaded = [
            SELECT VS_Start_Time__c, VS_End_Time__c, VS_Bookable_Capacity__c
            FROM VS_Session__c WHERE Id = :ses.Id];
        List<VS_Slot__c> slots = fetchSlots(ses.Id);

        System.assertEquals(8, slots.size(),
            '250-min window / 30-min granularity = floor 8 slots (configurable, not the 15 default)');
        System.assertEquals(slots[0].VS_Slot_Start__c.addMinutes(30), slots[0].VS_Slot_End__c,
            'Each slot honours the configured 30-min granularity, not 15');
        // Trailing partial dropped: 8*30 = 240 min -> last slot ends at 13:00, NOT the 13:10 session end.
        System.assertEquals(at(d, 13), slots[7].VS_Slot_End__c,
            'Last slot ends at 13:00; the trailing 10-min partial interval is DROPPED');
        System.assert(slots[7].VS_Slot_End__c < reloaded.VS_End_Time__c,
            'Last slot end precedes the session end (partial interval not emitted)');

        Integer sum = 0;
        for (VS_Slot__c sl : slots) { sum += sl.VS_Capacity__c.intValue(); }
        System.assertEquals(reloaded.VS_Bookable_Capacity__c.intValue(), sum,
            'INVARIANT: sum(slot cap) == session bookable EXACTLY at 30-min granularity (D-023/A-005)');
      }
    }

    // --- MINOR-2: capacity < slotCount edge (bookable 5, 8 slots) ---
    // distributeCapacity gives the first 5 slots capacity 1 and the trailing 3 capacity 0; the sum
    // still equals bookable (5) EXACTLY.
    // PRODUCT FLAG (BA_ARCH_CONFIRM): whether 0-capacity Open slots SHOULD be emitted at all is a
    // PRODUCT decision, not a code defect. This test LOCKS the CURRENT behavior (they ARE emitted) and
    // flags it — it deliberately does NOT change the emit behavior.
    @IsTest
    static void testCapacityLessThanSlotCount_trailingSlotsGetZeroCapacity() {
      System.runAs(slotGenUser()) {
        VS_Facility__c fac = new VS_Facility__c(Name = 'LowCap PHC');
        insert fac;
        VS_Service__c svc = new VS_Service__c(Name = 'LowCap Svc'); // 15-min default granularity
        insert svc;
        Date d = Date.today().addDays(2);
        // Total 7 @ 25% reserve = CEILING(1.75)=2 -> bookable 5; window 09:00-11:00 @ 15 min -> 8 slots.
        VS_Session__c ses = newSession(fac.Id, svc.Id, d, 9, 11, 7, false);
        insert ses;
        VS_Session__c fetched = [
            SELECT Id, VS_Start_Time__c, VS_End_Time__c, VS_Bookable_Capacity__c
            FROM VS_Session__c WHERE Id = :ses.Id];
        System.assertEquals(5, fetched.VS_Bookable_Capacity__c.intValue(),
            'Precondition: total 7 @ 25% reserve -> bookable 5 (< the 8 slots)');

        Test.startTest();
        List<VS_Slot__c> slots = VS_SlotGenerationService.buildSlots(fetched, 15);
        Test.stopTest();

        System.assertEquals(8, slots.size(), '120-min window / 15-min = 8 slots');
        Integer sum = 0;
        for (Integer i = 0; i < slots.size(); i++) {
            Integer cap = slots[i].VS_Capacity__c.intValue();
            sum += cap;
            Integer expected = (i < 5) ? 1 : 0; // earliest 5 get 1, trailing 3 get 0
            System.assertEquals(expected, cap,
                'First 5 slots get capacity 1, trailing 3 get capacity 0 (index ' + i + ')');
        }
        System.assertEquals(5, sum,
            'INVARIANT: sum(slot cap) == bookable (5) EXACTLY even when capacity < slotCount');
      }
    }

    // --- MINOR-3: in-batch degenerate-window SKIP branch (generateForSessions continue) ---
    // A degenerate session (end == start -> computeSlotCount <= 0) fed THROUGH the generateForSessions
    // path must be SILENTLY SKIPPED (no slots, NO exception at the batch level) — unlike buildSlots(),
    // which THROWS for the same input. Covers the currently-unexercised `continue` branch.
    @IsTest
    static void testGenerateForSessions_degenerateWindow_skippedNotThrown() {
      System.runAs(slotGenUser()) {
        VS_Facility__c fac = new VS_Facility__c(Name = 'Degenerate PHC');
        insert fac;
        VS_Service__c svc = new VS_Service__c(Name = 'Degenerate Svc');
        insert svc;
        Date d = Date.today().addDays(2);
        VS_Session__c bad = newSession(fac.Id, svc.Id, d, 9, 9, 40, false); // end == start -> degenerate
        insert bad;
        VS_Session__c fetched = [
            SELECT Id, VS_Session_Date__c, VS_Start_Time__c, VS_End_Time__c,
                   VS_Bookable_Capacity__c, VS_Is_Drive_Day__c, VS_Facility__c, VS_Service__c
            FROM VS_Session__c WHERE Id = :bad.Id];

        Test.startTest();
        Integer created = VS_SlotGenerationService.generateForSessions(new List<VS_Session__c>{ fetched });
        Test.stopTest();

        System.assertEquals(0, created,
            'Degenerate-window session is SKIPPED by generateForSessions -> zero slots (no exception)');
        System.assertEquals(0, fetchSlots(bad.Id).size(),
            'No slot rows exist for the skipped degenerate session');
      }
    }

    // --- Empty/no-op guard ---
    // Empty/null input returns 0 at the top of generateForSessions BEFORE any USER_MODE SOQL/DML, so
    // no FLS context is required — kept without runAs to prove that early-return path directly.
    @IsTest
    static void testGenerateForSessions_emptyInput_returnsZero() {
        Test.startTest();
        System.assertEquals(0, VS_SlotGenerationService.generateForSessions(new List<VS_Session__c>()),
            'Empty input generates nothing');
        System.assertEquals(0, VS_SlotGenerationService.generateForSessions(null),
            'Null input generates nothing');
        Test.stopTest();
    }
}
