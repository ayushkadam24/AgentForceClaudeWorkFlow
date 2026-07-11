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
 * Meaningful state asserts throughout (final row counts + counters, not merely "no exception").
 * @TestSetup builds a synthetic spine (no Aadhaar, rules/10); no SeeAllData.
 *
 * Traceability: REQ-002/006/007/008 / EP-03 / D-019, D-020, D-016, D-009.
 */
@IsTest(SeeAllData=false)
private class VS_BookingServiceTest {

    private static Datetime slotStart() { return Datetime.now().addDays(1); }

    @TestSetup
    static void makeData() {
        VS_Facility__c fac = new VS_Facility__c(Name = 'Test PHC Kothrud');
        insert fac;
        VS_Service__c svc = new VS_Service__c(Name = 'COVID Vaccination');
        insert svc;
    }

    // ---- Data helpers -------------------------------------------------------------------------

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

    @IsTest
    static void testHappyPath_walkInBooking() {
        VS_Session__c ses = newSession(4, 'Open'); // reserve = CEILING(4*25/100) = 1
        VS_Slot__c slot = newSlot(ses.Id, 5);
        System.assertEquals(1, reloadSession(ses.Id).VS_Walk_In_Reserve_Count__c.intValue(),
            'Precondition: total 4 @ 25% -> reserve 1 (VS_Setting__mdt.WalkInReservePct must be seeded)');
        Id patientId = newPatient('Bharat WalkIn');

        Test.startTest();
        Id apptId = VS_BookingService.book(patientId, slot.Id, UserInfo.getUserId(), 'WalkIn');
        Test.stopTest();

        VS_Appointment__c appt = [SELECT VS_Status__c, VS_Booked_Channel__c FROM VS_Appointment__c WHERE Id = :apptId];
        System.assertEquals('WalkIn', appt.VS_Status__c, 'Walk-in status is WalkIn');
        System.assertEquals('WalkIn', appt.VS_Booked_Channel__c, 'Walk-in channel recorded');

        System.assertEquals(1, reloadSession(ses.Id).VS_Walk_In_Used_Count__c.intValue(),
            'Walk-in reserve used incremented by 1');
        System.assertEquals(0, reloadSlot(slot.Id).VS_Booked_Count__c.intValue(),
            'Walk-in must NOT consume the slot bookable count (disjoint pools, D-020)');
    }

    // ---- CAPACITY-EXHAUSTION (mandatory): drive to full, over-limit throws SLOT_FULL ----------

    @IsTest
    static void testCapacityExhaustion_online_neverOverbooks() {
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

    // ---- WALK-IN RESERVE exhaustion (mandatory) -----------------------------------------------

    @IsTest
    static void testWalkInReserveExhaustion_neverOverbooks() {
        VS_Session__c ses = newSession(4, 'Open'); // reserve = 1
        VS_Slot__c slot = newSlot(ses.Id, 5);

        Test.startTest();
        VS_BookingService.book(newPatient('WalkIn One'), slot.Id, UserInfo.getUserId(), 'WalkIn');
        String caught;
        try {
            VS_BookingService.book(newPatient('WalkIn Two'), slot.Id, UserInfo.getUserId(), 'WalkIn');
            System.assert(false, 'The over-reserve walk-in must throw');
        } catch (VS_BookingException e) {
            caught = e.getMessage();
        }
        Test.stopTest();

        System.assertEquals(VS_BookingException.WALKIN_RESERVE_FULL, caught,
            'Over-reserve walk-in throws WALKIN_RESERVE_FULL');
        VS_Session__c after = reloadSession(ses.Id);
        System.assertEquals(1, after.VS_Walk_In_Used_Count__c.intValue(),
            'INVARIANT: VS_Walk_In_Used_Count__c never exceeds VS_Walk_In_Reserve_Count__c');
        System.assertEquals(after.VS_Walk_In_Reserve_Count__c.intValue(), after.VS_Walk_In_Used_Count__c.intValue(),
            'Used exactly reached the reserve ceiling, not beyond');
    }

    // ---- MIXED online + walk-in on the SAME session (D-019 mandatory proof) --------------------
    // The case D-015's dual lock could not prove: a burst of BOTH channel types on one session.
    // Under D-019/D-020 the two channels take the SAME session lock but draw DISJOINT pools (slot
    // bookable vs session reserve). This asserts each pool respects its own ceiling and neither
    // channel consumes the other's capacity — no overbooking across channels.
    @IsTest
    static void testMixedChannels_sameSession_noOverbooking() {
        VS_Session__c ses = newSession(4, 'Open'); // reserve = 1
        VS_Slot__c slot = newSlot(ses.Id, 1);      // slot bookable ceiling = 1
        System.assertEquals(1, reloadSession(ses.Id).VS_Walk_In_Reserve_Count__c.intValue(),
            'Precondition: one place in each pool (slot cap 1, reserve 1)');

        Test.startTest();
        // First of each channel should succeed (one place per pool).
        Id onlineOk = VS_BookingService.book(newPatient('Mix Online OK'), slot.Id, UserInfo.getUserId(), 'Portal');
        Id walkInOk = VS_BookingService.book(newPatient('Mix WalkIn OK'), slot.Id, UserInfo.getUserId(), 'WalkIn');

        // Second of each channel should be rejected against its own exhausted pool.
        String onlineErr;
        try {
            VS_BookingService.book(newPatient('Mix Online X'), slot.Id, UserInfo.getUserId(), 'Staff');
            System.assert(false, 'Second online booking must throw');
        } catch (VS_BookingException e) { onlineErr = e.getMessage(); }

        String walkInErr;
        try {
            VS_BookingService.book(newPatient('Mix WalkIn X'), slot.Id, UserInfo.getUserId(), 'WalkIn');
            System.assert(false, 'Second walk-in must throw');
        } catch (VS_BookingException e) { walkInErr = e.getMessage(); }
        Test.stopTest();

        System.assertNotEquals(null, onlineOk, 'First online booking succeeded');
        System.assertNotEquals(null, walkInOk, 'First walk-in booking succeeded');
        System.assertEquals(VS_BookingException.SLOT_FULL, onlineErr, 'Second online -> SLOT_FULL');
        System.assertEquals(VS_BookingException.WALKIN_RESERVE_FULL, walkInErr, 'Second walk-in -> WALKIN_RESERVE_FULL');

        VS_Slot__c slotAfter = reloadSlot(slot.Id);
        VS_Session__c sesAfter = reloadSession(ses.Id);
        System.assertEquals(1, slotAfter.VS_Booked_Count__c.intValue(),
            'INVARIANT: slot booked count never exceeds its ceiling of 1');
        System.assertEquals(1, sesAfter.VS_Walk_In_Used_Count__c.intValue(),
            'INVARIANT: walk-in used never exceeds the reserve of 1');
        System.assertEquals(2, apptCount(slot.Id),
            'Exactly two bookings total (one per pool) — no cross-channel overbooking');
    }

    // ---- Booking reference: unique + populated + Crockford charset ----------------------------

    @IsTest
    static void testBookingReference_uniqueAndPopulatedAndTypeable() {
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

    // ---- REFERENCE COLLISION (m-1): regenerate-and-retry-once, then coded exception -----------
    // These deliberately provoke the Unique-External-Id (VS_Booking_Reference__c) collision path via
    // the VS_ReferenceGenerator.forceNextReference test seam, rather than waiting on a 1-in-32^8 clash.

    @IsTest
    static void testReferenceCollision_regeneratesAndRetriesOnce_bookingSucceeds() {
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

    @IsTest
    static void testReferenceCollision_twiceInARow_throwsCodedException() {
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

    // ---- NEGATIVE tests (meaningful row-count asserts) ----------------------------------------

    @IsTest
    static void testNegative_invalidSlotId_throwsAndCreatesNothing() {
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

    @IsTest
    static void testNegative_closedSession_throwsSessionNotOpen() {
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

    @IsTest
    static void testNegative_invalidChannel_throws() {
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

    @IsTest
    static void testNegative_nullInput_throws() {
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
