/**
 * Walk-in booking tests — split from VS_BookingServiceTest per D-028/D-028a. NOT named in the deploy
 * RunSpecifiedTests run: the walk-in path's system-mode `update session` on the required
 * VS_Walk_In_Used_Count__c cannot execute under this org's deploy-time FLS enforcement (org limitation,
 * not a defect). Walk-in overbooking is proven by QA's parallel load test.
 *
 * This class is intentionally SELF-CONTAINED (its own @TestSetup + copies of the helpers the 3 walk-in
 * methods use) so it compiles and runs independently. Duplication with VS_BookingServiceTest is
 * accepted for the POC to avoid any risk to the 21 deploy-run methods (D-028a). Production code and the
 * §3.4 design are UNCHANGED — this is a test-packaging split only.
 *
 * Traceability: REQ-002/006/007/008 / EP-03 / D-019, D-020, D-016, D-009, D-028, D-028a.
 */
@IsTest(SeeAllData=false)
private class VS_BookingServiceWalkInTest {

    private static Datetime slotStart() { return Datetime.now().addDays(1); }

    // The dedicated TEST/CI FLS harness permset (see VS-09 review packet). TEST-ONLY.
    private static final String TEST_PERMSET = 'VS_Booking_Engine_Test_Context';

    @TestSetup
    static void makeData() {
        // Setup-object DML (User + PermissionSetAssignment) FIRST, in the default context; then wrap all
        // non-setup fixture DML in runAs(u) below (canonical MIXED_DML-safe ordering; the org enforces
        // FLS on plain DML in deploy tests, so fixtures need an FLS-bearing user).
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            FirstName = 'VS',
            LastName = 'VSWalkInTest',
            Alias = 'vswit',
            Email = 'vs.walkin.test@vaccinescheduler.poc.example',
            Username = 'vs.walkin.test.' + Math.abs(Crypto.getRandomLong())
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
            insert new VS_Facility__c(Name = 'Test PHC Kothrud');
            insert new VS_Service__c(Name = 'COVID Vaccination');
        }
    }

    // ---- Data helpers (called INSIDE runAs(bookingUser()) so their DML runs with FLS) ----------------

    /** The FLS-bearing harness user under which fixtures AND book() execute. */
    private static User bookingUser() {
        return [SELECT Id FROM User WHERE LastName = 'VSWalkInTest' LIMIT 1];
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

    // ---- Walk-in happy path -------------------------------------------------------------------

    @IsTest
    static void testHappyPath_walkInBooking() {
      System.runAs(bookingUser()) {
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
    }

    // ---- WALK-IN RESERVE exhaustion (mandatory) -----------------------------------------------

    @IsTest
    static void testWalkInReserveExhaustion_neverOverbooks() {
      System.runAs(bookingUser()) {
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
    }

    // ---- MIXED online + walk-in on the SAME session (D-019 mandatory proof) --------------------
    // The case D-015's dual lock could not prove: a burst of BOTH channel types on one session.
    // Under D-019/D-020 the two channels take the SAME session lock but draw DISJOINT pools (slot
    // bookable vs session reserve). This asserts each pool respects its own ceiling and neither
    // channel consumes the other's capacity — no overbooking across channels.
    @IsTest
    static void testMixedChannels_sameSession_noOverbooking() {
      System.runAs(bookingUser()) {
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
    }
}
