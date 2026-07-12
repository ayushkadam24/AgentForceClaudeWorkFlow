/**
 * VS_BookingServiceTest — tests for the VS-09 crown-jewel booking service (VS_BookingService +
 * VS_ReferenceGenerator + VS_BookingException), EP-03, RFP §3.4.
 *
 * WHAT THESE TESTS PROVE (and, honestly, WHAT THEY DO NOT):
 *  - They prove the capacity-CEILING LOGIC: under the single VS_Session__c FOR UPDATE lock, a
 *    check-then-insert correctly REJECTS the over-limit booking, never lets VS_Booked_Count__c exceed
 *    VS_Capacity__c or VS_Walk_In_Used_Count__c exceed VS_Walk_In_Reserve_Count__c, flips a full slot
 *    to 'Full', and keeps the two channel pools disjoint.
 *  - They do NOT, by themselves, prove serialization under REAL concurrency. Apex unit tests run in a
 *    SINGLE transaction and cannot spawn truly parallel transactions, so the FOR UPDATE lock is not
 *    contended here. Real no-overbooking-under-concurrency is validated by a parallel load test on the
 *    DE org (N simultaneous book() calls for the last seat) — see 02-build/review-notes/VS-09-review.md.
 *
 * === FLS/USER_MODE TEST PATTERN (BLOCKER C→F, dev-senior 2026-07-12) ===
 * ROOT CAUSE (BLOCKER F): this DE org ENFORCES FLS/CRUD on PLAIN Apex DML during deploy-time
 * RunLocalTests (not the usual system-mode bypass), and the deploying admin has no FLS on the freshly
 * Metadata-API-deployed OPTIONAL VS_ fields. So neither the deploying admin nor a bare test user can
 * build fixtures; the running context needs REAL FLS. Pattern applied:
 *  - The harness User is created (setup DML) OUTSIDE runAs in @TestSetup; ALL non-setup fixture DML AND
 *    the book() call-under-test run INSIDE System.runAs(bookingUser()). That user carries the
 *    VS_Booking_Engine_Test_Context harness permset, which grants the CRUD+FLS to build fixtures and to
 *    run the USER_MODE booking path. (Setup DML outside + non-setup inside runAs avoids MIXED_DML.)
 * Production code is UNCHANGED; the harness permset is TEST-ONLY and does NOT resolve the A-018 runtime
 * production-permset gap (still routed to BA_ARCH_CONFIRM).
 *
 * Meaningful state asserts throughout (final row counts + counters, not merely "no exception").
 * @TestSetup builds a synthetic spine (no Aadhaar, rules/10); no SeeAllData.
 *
 * Traceability: REQ-002/006/007/008 / EP-03 / D-019, D-020, D-016, D-009.
 */
@IsTest(SeeAllData=false)
private class VS_BookingServiceTest {

    private static Datetime slotStart() { return Datetime.now().addDays(1); }

    // Dedicated TEST/CI FLS harness permset (see VS-09 review packet, BLOCKER C/F). TEST-ONLY — it does
    // NOT resolve the A-018 runtime gap (no role permset grants Appointment create; that stays routed).
    private static final String TEST_PERMSET = 'VS_Booking_Engine_Test_Context';

    @TestSetup
    static void makeData() {
        // Setup-object DML (User + PermissionSetAssignment) FIRST, in the default context. Doing it
        // before any non-setup DML — and then wrapping all fixture DML in runAs(u) below — is the
        // canonical MIXED_DML-safe ordering.
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            FirstName = 'VS',
            LastName = 'VSBookingTest',
            Alias = 'vsbkt',
            Email = 'vs.booking.test@vaccinescheduler.poc.example',
            Username = 'vs.booking.test.' + Math.abs(Crypto.getRandomLong())
                + '@vaccinescheduler.poc.example',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id);
        insert u;
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :TEST_PERMSET LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        // Non-setup spine as the harness user (org enforces FLS on plain DML — see class header).
        System.runAs(u) {
            insert new VS_Facility__c(Name = 'Test PHC Kothrud');
            insert new VS_Service__c(Name = 'COVID Vaccination');
        }
    }

    // ---- Data helpers (called INSIDE runAs(bookingUser()) so their DML runs with FLS) ----------------

    /** The FLS-bearing harness user under which fixtures AND book() execute (BLOCKER F). */
    private static User bookingUser() {
        return [SELECT Id FROM User WHERE LastName = 'VSBookingTest' LIMIT 1];
    }

    private static Id facilityId() { return [SELECT Id FROM VS_Facility__c LIMIT 1].Id; }
    private static Id serviceId()  { return [SELECT Id FROM VS_Service__c LIMIT 1].Id; }

    /** Creates a patient with a unique match key so nothing trips the D-017 unique constraint. */
    private static Id newPatient(String name) {
        VS_Patient__c p = new VS_Patient__c(
            VS_Full_Name__c = name,
            VS_Date_Of_Birth__c = Date.newInstance(1990, 1, 1),
            VS_Mobile__c = '9000000000',
            VS_Match_Key__c = name + '|1990-01-01|9000000000'
        );
        insert p;
        return p.Id;
    }

    /** total drives the walk-in reserve formula: reserve = CEILING(total * 25 / 100). total=4 -> 1. */
    private static VS_Session__c newSession(Integer total, String status) {
        VS_Session__c s = new VS_Session__c(
            VS_Facility__c = facilityId(),
            VS_Service__c = serviceId(),
            VS_Session_Date__c = Date.today().addDays(1),
            VS_Start_Time__c = slotStart(),
            VS_End_Time__c = slotStart().addHours(4),
            VS_Total_Capacity__c = total,
            VS_Status__c = status
        );
        insert s;
        return s;
    }

    private static VS_Slot__c newSlot(Id sessionId, Integer capacity) {
        VS_Slot__c sl = new VS_Slot__c(
            VS_Session__c = sessionId,
            VS_Slot_Start__c = slotStart(),
            VS_Slot_End__c = slotStart().addMinutes(15),
            VS_Capacity__c = capacity,
            VS_Booked_Count__c = 0,
            VS_Status__c = 'Open'
        );
        insert sl;
        return sl;
    }

    private static VS_Slot__c reloadSlot(Id slotId) {
        return [SELECT Id, VS_Capacity__c, VS_Booked_Count__c, VS_Status__c
                FROM VS_Slot__c WHERE Id = :slotId];
    }

    private static VS_Session__c reloadSession(Id sessionId) {
        return [SELECT Id, VS_Walk_In_Reserve_Count__c, VS_Walk_In_Used_Count__c
                FROM VS_Session__c WHERE Id = :sessionId];
    }

    private static Integer apptCount(Id slotId) {
        return [SELECT COUNT() FROM VS_Appointment__c WHERE VS_Slot__c = :slotId];
    }

    // ---- Happy paths --------------------------------------------------------------------------

    @IsTest
    static void testHappyPath_onlineBooking() {
      System.runAs(bookingUser()) {
        VS_Session__c ses = newSession(4, 'Open');
        VS_Slot__c slot = newSlot(ses.Id, 5);
        Id patientId = newPatient('Asha Online');

        Test.startTest();
        Id apptId = VS_BookingService.book(patientId, slot.Id, UserInfo.getUserId(), 'Portal');
        Test.stopTest();

        System.assertNotEquals(null, apptId, 'An appointment Id must be returned');
        VS_Appointment__c appt = [
            SELECT VS_Status__c, VS_Booked_Channel__c, VS_Booking_Reference__c,
                   VS_Patient__c, VS_Slot__c, VS_Session__c, VS_Facility__c, VS_Service__c
            FROM VS_Appointment__c WHERE Id = :apptId];
        System.assertEquals('Booked', appt.VS_Status__c, 'Online booking status is Booked');
        System.assertEquals('Portal', appt.VS_Booked_Channel__c, 'Channel recorded');
        System.assertEquals(patientId, appt.VS_Patient__c, 'Patient linked');
        System.assertEquals(ses.Id, appt.VS_Session__c, 'Session denormalized onto appointment');
        System.assertEquals(facilityId(), appt.VS_Facility__c, 'Facility denormalized (sharing/reporting)');
        System.assertEquals(serviceId(), appt.VS_Service__c, 'Service denormalized (sharing/reporting)');

        VS_Slot__c after = reloadSlot(slot.Id);
        System.assertEquals(1, after.VS_Booked_Count__c.intValue(), 'Slot booked count incremented by 1');
        System.assertEquals('Open', after.VS_Status__c, 'Slot still Open (1 of 5 taken)');

        VS_Session__c sesAfter = reloadSession(ses.Id);
        System.assertEquals(0, sesAfter.VS_Walk_In_Used_Count__c.intValue(),
            'Online booking must NOT touch the walk-in reserve pool');
      }
    }

    // NOTE (D-028/D-028a): the walk-in tests (testHappyPath_walkInBooking,
    // testWalkInReserveExhaustion_neverOverbooks, testMixedChannels_sameSession_noOverbooking) were
    // MOVED to VS_BookingServiceWalkInTest — they cannot execute under this org's deploy-time FLS
    // enforcement (system-mode counter update on required VS_Walk_In_Used_Count__c). Splitting them out
    // lets the class-level deploy RunSpecifiedTests run only the executable methods.

    // ---- CAPACITY-EXHAUSTION (mandatory): drive to full, over-limit throws SLOT_FULL ----------

    @IsTest
    static void testCapacityExhaustion_online_neverOverbooks() {
      System.runAs(bookingUser()) {
        VS_Session__c ses = newSession(20, 'Open');
        Integer capacity = 2;
        VS_Slot__c slot = newSlot(ses.Id, capacity);

        Test.startTest();
        // Fill the slot exactly to capacity.
        for (Integer i = 0; i < capacity; i++) {
            VS_BookingService.book(newPatient('Filler ' + i), slot.Id, UserInfo.getUserId(), 'Portal');
        }
        // One more attempt for the last-place-already-gone case.
        String caught;
        try {
            VS_BookingService.book(newPatient('Overflow'), slot.Id, UserInfo.getUserId(), 'Portal');
            System.assert(false, 'The over-capacity booking must throw');
        } catch (VS_BookingException e) {
            caught = e.getMessage();
        }
        Test.stopTest();

        System.assertEquals(VS_BookingException.SLOT_FULL, caught, 'Over-limit booking throws SLOT_FULL');
        VS_Slot__c after = reloadSlot(slot.Id);
        System.assertEquals(capacity, after.VS_Booked_Count__c.intValue(),
            'INVARIANT: VS_Booked_Count__c never exceeds VS_Capacity__c');
        System.assertEquals('Full', after.VS_Status__c, 'Slot flips to Full at the ceiling');
        System.assertEquals(capacity, apptCount(slot.Id),
            'Exactly VS_Capacity__c appointments exist — no extra row from the rejected attempt');
      }
    }

    // (Walk-in reserve exhaustion + mixed online/walk-in §3.4 proof MOVED to
    // VS_BookingServiceWalkInTest per D-028/D-028a — see the note above.)

    // ---- Booking reference: unique + populated + Crockford charset ----------------------------

    @IsTest
    static void testBookingReference_uniqueAndPopulatedAndTypeable() {
      System.runAs(bookingUser()) {
        VS_Session__c ses = newSession(20, 'Open');
        VS_Slot__c slot = newSlot(ses.Id, 5);

        Test.startTest();
        Id a1 = VS_BookingService.book(newPatient('Ref One'), slot.Id, UserInfo.getUserId(), 'Portal');
        Id a2 = VS_BookingService.book(newPatient('Ref Two'), slot.Id, UserInfo.getUserId(), 'Portal');
        Test.stopTest();

        Map<Id, VS_Appointment__c> byId = new Map<Id, VS_Appointment__c>([
            SELECT VS_Booking_Reference__c FROM VS_Appointment__c WHERE Id IN (:a1, :a2)]);
        String r1 = byId.get(a1).VS_Booking_Reference__c;
        String r2 = byId.get(a2).VS_Booking_Reference__c;

        System.assertNotEquals(null, r1, 'Booking reference populated');
        System.assertEquals(8, r1.length(), 'Booking reference is 8 chars (D-016)');
        System.assertNotEquals(r1, r2, 'Two bookings get distinct references');
        System.assert(Pattern.matches('[0-9A-HJKMNP-TV-Z]{8}', r1),
            'Reference uses only the Crockford base32 alphabet (no I, L, O, U): ' + r1);
      }
    }

    // ---- REFERENCE COLLISION (m-1): regenerate-and-retry-once, then coded exception -----------
    // These deliberately provoke the Unique-External-Id (VS_Booking_Reference__c) collision path via
    // the VS_ReferenceGenerator.forceNextReference test seam (a static, DML-free seam — safe inside runAs).

    @IsTest
    static void testReferenceCollision_regeneratesAndRetriesOnce_bookingSucceeds() {
      System.runAs(bookingUser()) {
        VS_Session__c ses = newSession(20, 'Open');
        VS_Slot__c slot = newSlot(ses.Id, 5);

        Test.startTest();
        // First booking CLAIMS a known reference (forces the generator to emit it once).
        VS_ReferenceGenerator.forceNextReference('ABCDEFGH');
        Id first = VS_BookingService.book(newPatient('Ref Holder'), slot.Id, UserInfo.getUserId(), 'Portal');
        // Second booking: force the SAME reference for its FIRST insert -> DUPLICATE_VALUE. The service
        // must regenerate (queue now empty -> Crypto random) and retry ONCE, succeeding.
        VS_ReferenceGenerator.forceNextReference('ABCDEFGH');
        Id second = VS_BookingService.book(newPatient('Ref Collider'), slot.Id, UserInfo.getUserId(), 'Portal');
        Test.stopTest();

        Map<Id, VS_Appointment__c> byId = new Map<Id, VS_Appointment__c>([
            SELECT VS_Booking_Reference__c FROM VS_Appointment__c WHERE Id IN (:first, :second)]);
        String firstRef = byId.get(first).VS_Booking_Reference__c;
        String secondRef = byId.get(second).VS_Booking_Reference__c;

        System.assertNotEquals(null, second, 'Second booking still succeeds after regenerate + retry');
        System.assertEquals('ABCDEFGH', firstRef, 'First booking holds the seeded reference');
        System.assertNotEquals(firstRef, secondRef,
            'The retry produced a DISTINCT reference (not the colliding one)');
        System.assertEquals(8, secondRef.length(), 'Regenerated reference is still 8 chars (D-016)');
        System.assert(Pattern.matches('[0-9A-HJKMNP-TV-Z]{8}', secondRef),
            'Regenerated reference is still Crockford base32 (Crypto random): ' + secondRef);
        System.assertEquals(2, apptCount(slot.Id), 'Both bookings persisted (retry did not drop one)');
      }
    }

    @IsTest
    static void testReferenceCollision_twiceInARow_throwsCodedException() {
      System.runAs(bookingUser()) {
        VS_Session__c ses = newSession(20, 'Open');
        VS_Slot__c slot = newSlot(ses.Id, 5);

        Test.startTest();
        // First booking claims the reference.
        VS_ReferenceGenerator.forceNextReference('ABCDEFGH');
        Id first = VS_BookingService.book(newPatient('Ref Holder'), slot.Id, UserInfo.getUserId(), 'Portal');
        // Force the SAME reference for BOTH the initial insert AND the single retry -> a SECOND
        // collision, which must surface as the coded VS_BookingException (never a raw DmlException).
        VS_ReferenceGenerator.forceNextReference('ABCDEFGH');
        VS_ReferenceGenerator.forceNextReference('ABCDEFGH');
        String caught;
        try {
            VS_BookingService.book(newPatient('Double Collider'), slot.Id, UserInfo.getUserId(), 'Portal');
            System.assert(false, 'A second consecutive collision must throw');
        } catch (VS_BookingException e) {
            caught = e.getMessage();
        }
        Test.stopTest();

        System.assertEquals(VS_BookingException.REFERENCE_COLLISION, caught,
            'Two collisions in a row -> coded REFERENCE_COLLISION (not a leaked DmlException)');
        System.assertNotEquals(null, first, 'The first booking still succeeded');
        System.assertEquals(1, apptCount(slot.Id),
            'Only the first booking persisted — the double-collision attempt created no row');
      }
    }

    // ---- NEGATIVE tests (meaningful row-count asserts) ----------------------------------------

    @IsTest
    static void testNegative_invalidSlotId_throwsAndCreatesNothing() {
      System.runAs(bookingUser()) {
        VS_Session__c ses = newSession(4, 'Open');
        VS_Slot__c slot = newSlot(ses.Id, 5);        // a real slot, to prove nothing gets created
        Integer before = [SELECT COUNT() FROM VS_Appointment__c];
        // A real slot Id that we then delete -> a valid-format Id that resolves to no row.
        VS_Slot__c doomed = newSlot(ses.Id, 5);
        Id ghostSlot = doomed.Id;
        delete doomed;

        Test.startTest();
        String caught;
        try {
            VS_BookingService.book(newPatient('No Slot'), ghostSlot, UserInfo.getUserId(), 'Portal');
            System.assert(false, 'Booking against a non-existent slot must throw');
        } catch (VS_BookingException e) {
            caught = e.getMessage();
        }
        Test.stopTest();

        System.assertEquals(VS_BookingException.SLOT_NOT_FOUND, caught, 'Missing slot -> SLOT_NOT_FOUND');
        System.assertEquals(before, [SELECT COUNT() FROM VS_Appointment__c],
            'No appointment row is created when booking fails');
        System.assertEquals(0, reloadSlot(slot.Id).VS_Booked_Count__c.intValue(),
            'The real slot is untouched by the failed booking');
      }
    }

    @IsTest
    static void testNegative_closedSession_throwsSessionNotOpen() {
      System.runAs(bookingUser()) {
        VS_Session__c ses = newSession(4, 'Closed');
        VS_Slot__c slot = newSlot(ses.Id, 5);

        Test.startTest();
        String caught;
        try {
            VS_BookingService.book(newPatient('Closed Ses'), slot.Id, UserInfo.getUserId(), 'Portal');
            System.assert(false, 'Booking into a closed session must throw');
        } catch (VS_BookingException e) {
            caught = e.getMessage();
        }
        Test.stopTest();

        System.assertEquals(VS_BookingException.SESSION_NOT_OPEN, caught, 'Closed session -> SESSION_NOT_OPEN');
        System.assertEquals(0, apptCount(slot.Id), 'No appointment created for a closed session');
      }
    }

    @IsTest
    static void testNegative_invalidChannel_throws() {
      System.runAs(bookingUser()) {
        VS_Session__c ses = newSession(4, 'Open');
        VS_Slot__c slot = newSlot(ses.Id, 5);

        Test.startTest();
        String caught;
        try {
            VS_BookingService.book(newPatient('Bad Chan'), slot.Id, UserInfo.getUserId(), 'Telepathy');
            System.assert(false, 'An unknown channel must throw');
        } catch (VS_BookingException e) {
            caught = e.getMessage();
        }
        Test.stopTest();

        System.assertEquals(VS_BookingException.INVALID_CHANNEL, caught, 'Unknown channel -> INVALID_CHANNEL');
        System.assertEquals(0, apptCount(slot.Id), 'No appointment created for an invalid channel');
      }
    }

    @IsTest
    static void testNegative_nullInput_throws() {
        // No runAs / no fixtures: book() validates null input and throws BEFORE any DML/SOQL.
        Test.startTest();
        String caught;
        try {
            VS_BookingService.book(null, null, UserInfo.getUserId(), 'Portal');
            System.assert(false, 'Null required input must throw');
        } catch (VS_BookingException e) {
            caught = e.getMessage();
        }
        Test.stopTest();
        System.assertEquals(VS_BookingException.INVALID_INPUT, caught, 'Null input -> INVALID_INPUT');
    }
}
