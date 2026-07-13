/**
 * VS_BookingControllerManageTest — the VS-16 citizen self-service management surface on
 * VS_BookingController: findMyAppointments / cancelMyAppointment / rescheduleMyAppointment (EP-06).
 *
 * WHAT THESE TESTS PROVE (honestly) — the security-critical asserts are ALL unit-provable and MUST pass:
 *  - VIEW is OTP-gated and returns ONLY the caller's own upcoming rows (never another mobile's) and
 *    excludes cancelled bookings.
 *  - The C9 gate rejects any manage action with no verified OTP for the mobile.
 *  - THE IDOR GUARD (D-030 residual MUST-FIX): a DIFFERENT mobile holding its OWN valid OTP CANNOT
 *    cancel or reschedule another mobile's appointment — the coded NOT_APPOINTMENT_OWNER rejection fires
 *    BEFORE any elevated write and the target appointment is provably UNCHANGED.
 *  - The cancel/reschedule HAPPY PATH (as the CI harness user, which holds the D-020-forbidden Slot/Appt
 *    edit grants) frees/moves the place correctly.
 *  - The least-privilege portal user's cancel elevation CLEARS sharing/FLS and reaches the §3.4 counter
 *    DML, whose sole residual on this DE org is the documented D-028 object-CRUD wall (runtime-safe on a
 *    standard org) — the crown jewel is not weakened.
 *
 * D-028 discipline mirrors VS_BookingControllerTest / VS_BookingServiceCancelRescheduleTest: acting users
 * are created OUTSIDE runAs in @TestSetup with permsets; every fixture write AND every call-under-test
 * runs INSIDE System.runAs(...). Appointments are seeded via VS_BookingService.book (Portal) as the
 * harness user and stamped with VS_Booked_By_Mobile__c (the ownership field), exactly as the live book()
 * path does post-booking.
 *
 * Traceability: REQ-002/003/005/006/015/056/057/060 / EP-06 / D-030, D-030a, D-019, D-020, D-028.
 */
@IsTest(SeeAllData=false)
private class VS_BookingControllerManageTest {

    private static final String OTP_CODE = VS_OtpStubProvider.TEST_CODE;   // '000000'
    private static final String MOBILE_A = '9000000101';
    private static final String MOBILE_B = '9000000102';                   // the "attacker" mobile (IDOR)
    private static final String MOBILE_PORTAL = '9000000105';
    private static final String MOBILE_NO_OTP = '9000000109';

    private static Datetime farFuture() { return Datetime.now().addDays(2); }   // upcoming + past cut-off

    @TestSetup
    static void makeData() {
        User harness = newUser('VSManage', 'vsmg');
        User portal = newUser('VSMgPortal', 'vmpt');
        insert new List<User>{ harness, portal };
        assign(harness.Id, new Set<String>{
            'VS_Booking_Engine_Test_Context', 'VS_Cancel_Reschedule_Test_Context',
            'VS_Otp_Test_Context', 'VS_Patient_Service_Test_Context'});
        assign(portal.Id, new Set<String>{ 'VS_Booking_Portal' });

        System.runAs(harness) {
            VS_FacilityTriggerHandler.bypass = true;
            VS_AppointmentTriggerHandler.bypass = true;
            insert new VS_Facility__c(Name = 'Test PHC Kothrud', VS_Facility_Type__c = 'PHC', VS_Is_Active__c = true);
            insert new VS_Service__c(Name = 'COVID Vaccination', VS_Service_Type__c = 'Vaccination',
                VS_Slot_Granularity_Mins__c = 15, VS_Is_Active__c = true);
        }
    }

    // ---- fixtures ----------------------------------------------------------------------------

    private static User newUser(String last, String alias) {
        return new User(FirstName = 'VS', LastName = last, Alias = alias,
            Email = 'vs.' + alias + '@vaccinescheduler.poc.example',
            Username = 'vs.' + alias + '.' + Math.abs(Crypto.getRandomLong()) + '@vaccinescheduler.poc.example',
            TimeZoneSidKey = 'Asia/Kolkata', LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id);
    }
    private static void assign(Id userId, Set<String> permsetNames) {
        List<PermissionSetAssignment> asg = new List<PermissionSetAssignment>();
        for (PermissionSet ps : [SELECT Id FROM PermissionSet WHERE Name IN :permsetNames]) {
            asg.add(new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = ps.Id));
        }
        insert asg;
    }
    private static User harnessUser() { return [SELECT Id FROM User WHERE LastName = 'VSManage' LIMIT 1]; }
    private static User portalUser()  { return [SELECT Id FROM User WHERE LastName = 'VSMgPortal' LIMIT 1]; }
    private static Id facilityId() { return [SELECT Id FROM VS_Facility__c LIMIT 1].Id; }
    private static Id serviceId()  { return [SELECT Id FROM VS_Service__c LIMIT 1].Id; }

    private static void bypassTriggers() {
        VS_FacilityTriggerHandler.bypass = true;
        VS_AppointmentTriggerHandler.bypass = true;
    }

    private static VS_Session__c newSession() {
        VS_Session__c s = new VS_Session__c(VS_Facility__c = facilityId(), VS_Service__c = serviceId(),
            VS_Session_Date__c = Date.today().addDays(2), VS_Start_Time__c = farFuture(),
            VS_End_Time__c = farFuture().addHours(4), VS_Total_Capacity__c = 20, VS_Status__c = 'Open');
        insert s;
        return s;
    }
    private static VS_Slot__c newSlot(Id sessionId, Integer capacity) {
        VS_Slot__c sl = new VS_Slot__c(VS_Session__c = sessionId, VS_Slot_Start__c = farFuture(),
            VS_Slot_End__c = farFuture().addMinutes(15), VS_Capacity__c = capacity,
            VS_Booked_Count__c = 0, VS_Status__c = 'Open');
        insert sl;
        return sl;
    }

    private static Integer patientSeq = 0;

    /** Seed an appointment OWNED by ownerMobile (patient mobile AND booker mobile), as the live path does.
     *  Each patient is DISTINCT (unique VS_Match_Key__c) so multiple bookings can share the same owner
     *  mobile — the ownership link is the mobile, not one patient row. */
    private static Id bookOwned(String ownerMobile, Id slotId) {
        patientSeq++;
        String uniqueName = 'Owner ' + ownerMobile + ' ' + patientSeq;
        VS_Patient__c pt = new VS_Patient__c(VS_Full_Name__c = uniqueName,
            VS_Date_Of_Birth__c = Date.newInstance(1990, 1, 1), VS_Mobile__c = ownerMobile,
            VS_Match_Key__c = uniqueName.toLowerCase() + '|1990-01-01|' + ownerMobile);
        insert pt;
        Id apptId = VS_BookingService.book(pt.Id, slotId, UserInfo.getUserId(), 'Portal');
        update new VS_Appointment__c(Id = apptId, VS_Booked_By_Mobile__c = ownerMobile);
        return apptId;
    }

    private static void verifyOtpFor(String mobile) {
        VS_BookingController.sendOtp(mobile);
        VS_BookingController.verifyOtp(mobile, OTP_CODE);
    }
    private static VS_Appointment__c reloadAppt(Id apptId) {
        return [SELECT Id, VS_Status__c, VS_Booked_By_Mobile__c FROM VS_Appointment__c WHERE Id = :apptId];
    }
    private static Integer bookedCount(Id slotId) {
        return [SELECT VS_Booked_Count__c FROM VS_Slot__c WHERE Id = :slotId].VS_Booked_Count__c.intValue();
    }

    // ---- VIEW: OTP-gated, caller-only, upcoming-only ------------------------------------------

    @IsTest
    static void testFindMyAppointments_returnsOnlyCallerUpcomingRows() {
      System.runAs(harnessUser()) {
        bypassTriggers();
        VS_Slot__c slot = newSlot(newSession().Id, 10);
        Id a1 = bookOwned(MOBILE_A, slot.Id);
        Id a2 = bookOwned(MOBILE_A, slot.Id);
        Id b1 = bookOwned(MOBILE_B, slot.Id);           // another citizen's booking — must NOT surface
        Id a3 = bookOwned(MOBILE_A, slot.Id);
        VS_BookingService.cancel(a3, UserInfo.getUserId());  // cancelled A row — status filter must drop it

        verifyOtpFor(MOBILE_A);
        Test.startTest();
        List<VS_BookingController.AppointmentView> mine = VS_BookingController.findMyAppointments(MOBILE_A);
        Test.stopTest();

        System.assertEquals(2, mine.size(), 'only A1+A2: B1 (other mobile) and A3 (cancelled) are excluded');
        Set<Id> ids = new Set<Id>();
        for (VS_BookingController.AppointmentView v : mine) {
            ids.add(v.id);
            System.assert(String.isNotBlank(v.reference), 'DTO carries the booking reference');
            System.assertEquals('Test PHC Kothrud', v.facilityName, 'DTO carries the facility name');
            System.assertEquals('COVID Vaccination', v.serviceName, 'DTO carries the service name');
            System.assertNotEquals(null, v.slotStart, 'DTO carries the slot start');
            System.assertEquals('Booked', v.status, 'DTO carries the status code');
        }
        System.assert(ids.contains(a1) && ids.contains(a2), 'both of A\'s upcoming bookings are returned');
        System.assert(!ids.contains(b1), 'IDOR-safe read: another mobile\'s booking is never returned');
        System.assert(!ids.contains(a3), 'cancelled booking is excluded (status filter)');
      }
    }

    @IsTest
    static void testFindMyAppointments_withoutOtp_rejected() {
      System.runAs(harnessUser()) {
        bypassTriggers();
        Test.startTest();
        Boolean threw = false;
        try { VS_BookingController.findMyAppointments(MOBILE_NO_OTP); }
        catch (AuraHandledException e) { threw = true; }
        Test.stopTest();
        System.assert(threw, 'view without a verified OTP -> AuraHandledException (C9 gate)');
      }
    }

    // ---- CANCEL: happy path (harness user holds the D-020 edit grants) -------------------------

    @IsTest
    static void testCancelMyAppointment_happyPath_freesPlace() {
      System.runAs(harnessUser()) {
        bypassTriggers();
        VS_Slot__c slot = newSlot(newSession().Id, 1);       // capacity 1 -> booking flips it Full
        Id apptId = bookOwned(MOBILE_A, slot.Id);
        System.assertEquals('Full', [SELECT VS_Status__c FROM VS_Slot__c WHERE Id = :slot.Id].VS_Status__c,
            'Precondition: slot Full at ceiling');
        verifyOtpFor(MOBILE_A);

        Test.startTest();
        VS_BookingController.cancelMyAppointment(apptId, MOBILE_A);
        Test.stopTest();

        System.assertEquals('Cancelled', reloadAppt(apptId).VS_Status__c, 'appointment flips to Cancelled');
        System.assertEquals(0, bookedCount(slot.Id), 'the freed place decrements the slot count');
        System.assertEquals('Open', [SELECT VS_Status__c FROM VS_Slot__c WHERE Id = :slot.Id].VS_Status__c,
            'slot flips Full->Open so the place is reusable');
      }
    }

    @IsTest
    static void testCancelMyAppointment_withoutOtp_rejected() {
      System.runAs(harnessUser()) {
        bypassTriggers();
        Id apptId = bookOwned(MOBILE_A, newSlot(newSession().Id, 5).Id);
        Test.startTest();
        Boolean threw = false;
        try { VS_BookingController.cancelMyAppointment(apptId, MOBILE_A); }   // no OTP issued/verified
        catch (AuraHandledException e) { threw = true; }
        Test.stopTest();
        System.assert(threw, 'cancel without a verified OTP -> AuraHandledException (C9 gate)');
        System.assertEquals('Booked', reloadAppt(apptId).VS_Status__c, 'the appointment is untouched');
      }
    }

    // ---- CANCEL: IDOR — a different mobile with ITS OWN valid OTP cannot cancel (CRITICAL) -----

    @IsTest
    static void testCancelMyAppointment_idor_differentMobile_rejected() {
      System.runAs(harnessUser()) {
        bypassTriggers();
        VS_Slot__c slot = newSlot(newSession().Id, 1);
        Id apptId = bookOwned(MOBILE_A, slot.Id);            // owned by A
        verifyOtpFor(MOBILE_B);                              // B holds a genuine, valid OTP of its OWN

        Test.startTest();
        String caught;
        try {
            VS_BookingController.cancelMyAppointment(apptId, MOBILE_B);   // B attacks A's booking by Id
            System.assert(false, 'a non-owner mobile must not be able to cancel');
        } catch (AuraHandledException e) {
            caught = e.getMessage();
        }
        Test.stopTest();

        System.assert(caught != null && caught.contains(VS_BookingException.NOT_APPOINTMENT_OWNER),
            'IDOR guard rejects a non-owner with the coded reason: ' + caught);
        System.assertEquals('Booked', reloadAppt(apptId).VS_Status__c,
            'IDOR: the victim\'s appointment is UNCHANGED (not cancelled by the attacker)');
        System.assertEquals(1, bookedCount(slot.Id), 'IDOR: no place was freed by the rejected attack');
      }
    }

    // ---- RESCHEDULE: happy path + ownership carried onto the moved booking ---------------------

    @IsTest
    static void testRescheduleMyAppointment_happyPath_movesPlace() {
      System.runAs(harnessUser()) {
        bypassTriggers();
        VS_Session__c ses = newSession();
        VS_Slot__c slot1 = newSlot(ses.Id, 5);
        VS_Slot__c slot2 = newSlot(ses.Id, 5);
        Id apptId = bookOwned(MOBILE_A, slot1.Id);
        verifyOtpFor(MOBILE_A);

        Test.startTest();
        String ref = VS_BookingController.rescheduleMyAppointment(apptId, slot2.Id, MOBILE_A);
        Test.stopTest();

        System.assert(String.isNotBlank(ref), 'a new booking reference is returned');
        System.assertEquals('Cancelled', reloadAppt(apptId).VS_Status__c, 'old appointment Cancelled');
        System.assertEquals(0, bookedCount(slot1.Id), 'source slot place freed');
        System.assertEquals(1, bookedCount(slot2.Id), 'destination slot place taken');
        VS_Appointment__c moved = [SELECT Id, VS_Booked_By_Mobile__c FROM VS_Appointment__c
            WHERE VS_Slot__c = :slot2.Id AND VS_Status__c = 'Booked' LIMIT 1];
        System.assertEquals(MOBILE_A, moved.VS_Booked_By_Mobile__c,
            'ownership is carried onto the moved booking (the citizen can still manage it)');
      }
    }

    // ---- RESCHEDULE: IDOR — a different mobile cannot move another's booking (CRITICAL) --------

    @IsTest
    static void testRescheduleMyAppointment_idor_differentMobile_rejected() {
      System.runAs(harnessUser()) {
        bypassTriggers();
        VS_Session__c ses = newSession();
        VS_Slot__c slot1 = newSlot(ses.Id, 5);
        VS_Slot__c slot2 = newSlot(ses.Id, 5);
        Id apptId = bookOwned(MOBILE_A, slot1.Id);
        verifyOtpFor(MOBILE_B);

        Test.startTest();
        String caught;
        try {
            VS_BookingController.rescheduleMyAppointment(apptId, slot2.Id, MOBILE_B);
            System.assert(false, 'a non-owner mobile must not be able to reschedule');
        } catch (AuraHandledException e) {
            caught = e.getMessage();
        }
        Test.stopTest();

        System.assert(caught != null && caught.contains(VS_BookingException.NOT_APPOINTMENT_OWNER),
            'IDOR guard rejects a non-owner reschedule with the coded reason: ' + caught);
        System.assertEquals('Booked', reloadAppt(apptId).VS_Status__c, 'the victim booking is unchanged');
        System.assertEquals(1, bookedCount(slot1.Id), 'source slot unchanged by the rejected attack');
        System.assertEquals(0, bookedCount(slot2.Id), 'destination slot unchanged by the rejected attack');
      }
    }

    // ---- input validation --------------------------------------------------------------------

    @IsTest
    static void testCancelMyAppointment_missingInput_throws() {
        Test.startTest();
        Boolean threw = false;
        try { VS_BookingController.cancelMyAppointment(null, null); }
        catch (AuraHandledException e) { threw = true; }
        Test.stopTest();
        System.assert(threw, 'missing input -> AuraHandledException');
    }

    @IsTest
    static void testRescheduleMyAppointment_missingInput_throws() {
        Test.startTest();
        Boolean threw = false;
        try { VS_BookingController.rescheduleMyAppointment(null, null, ''); }
        catch (AuraHandledException e) { threw = true; }
        Test.stopTest();
        System.assert(threw, 'missing input -> AuraHandledException');
    }

    // ==== ELEVATION-FIDELITY of the citizen cancel path (empirically pinned; see the VS-16 packet) ======
    // FINDING (deploy-verified by the coordinator's run, then isolated by the two tests below): the
    // OTP + mobile-ownership guards run in PortalManager (`without sharing`) and CORRECTLY authorize; BUT
    // VS_BookingService.cancel's OWN read (loadCancellableAppointment) enforces SHARING. VS_Appointment__c
    // is OWD Private, so:
    //   * if the portal user does NOT own the record  -> the service read returns 0 rows ->
    //     VS_BookingException(APPOINTMENT_NOT_FOUND), reached BEFORE the §3.4 counter DML. This is
    //     ORG-INDEPENDENT (OWD-Private sharing enforces identically everywhere) — NOT the D-028 FLS gate.
    //   * if the portal user OWNS the record (the common citizen journey — the booker owns their booking)
    //     -> the service read succeeds and the elevation reaches the §3.4 counter DML, whose residual on
    //     THIS DE org is the documented D-028 object-CRUD wall (success on a standard org).
    // The mobile-authorized-but-not-record-owner case (D-030's family-member intent) is BLOCKED by the
    // non-elevated service read — a D-030 elevation-fidelity gap raised to the architect (OQ-031). We do
    // NOT touch VS_BookingService (the §3.4 crown jewel). The two tests below pin BOTH behaviours honestly.

    /** Isolation proof of the gap: the mobile-authorized guards PASS (PortalManager `without sharing`
     *  sees the Private appt), but VS_BookingService.cancel's with-sharing read does NOT see a record the
     *  portal user doesn't own -> APPOINTMENT_NOT_FOUND, reached BEFORE any counter DML. Org-independent. */
    @IsTest
    static void testCancel_mobileAuthorizedNonOwner_serviceReadNotElevated() {
        Id apptId;
        System.runAs(harnessUser()) {
            bypassTriggers();
            // Owned (OwnerId) by the HARNESS user; booker mobile = the portal mobile so the IDOR/mobile
            // guard passes but the portal user is NOT the record owner.
            apptId = bookOwned(MOBILE_PORTAL, newSlot(newSession().Id, 5).Id);
        }
        System.runAs(portalUser()) {
            verifyOtpFor(MOBILE_PORTAL);
            Test.startTest();
            String caught;
            try {
                VS_BookingController.cancelMyAppointmentElevatedRaw(apptId, MOBILE_PORTAL);
                System.assert(false, 'expected the service read to not see the non-owned Private appt');
            } catch (Exception e) {
                caught = e.getMessage();
            }
            Test.stopTest();
            System.assert(caught != null && caught.contains(VS_BookingException.APPOINTMENT_NOT_FOUND),
                'OTP + mobile-ownership passed, but VS_BookingService.cancel enforces sharing on its own '
                + 'read of the OWD-Private appointment the portal user does not own -> APPOINTMENT_NOT_FOUND '
                + '(org-independent; D-030 elevation-fidelity gap, OQ-031): ' + caught);
            // NOTE: we deliberately do NOT reload the appt here as the portal user — it cannot see the
            // non-owned OWD-Private row (that invisibility is the whole point). The APPOINTMENT_NOT_FOUND
            // above already proves the path stopped BEFORE the counter DML, so nothing was mutated.
        }
    }

    /** The common citizen journey: the portal user OWNS their booking, so the service read succeeds and
     *  the elevation REACHES the §3.4 counter DML — whose residual on this DE org is the D-028 object-CRUD
     *  wall (UPDATE not allowed on VS_Slot__c), success on a standard org. Mirrors the book() A-018 proof.
     *  (book() cannot commit a portal-owned appt on this DE org — its counter DML walls first — so we seed
     *  as the harness user and transfer OwnerId to the portal user to model "the booker owns their booking".) */
    @IsTest
    static void testCancel_recordOwnerLeastPriv_reachesCounterDml_hitsD028Wall() {
        Id apptId;
        System.runAs(harnessUser()) {
            bypassTriggers();
            apptId = bookOwned(MOBILE_PORTAL, newSlot(newSession().Id, 1).Id);
            update new VS_Appointment__c(Id = apptId, OwnerId = portalUser().Id);   // booker owns their booking
        }
        System.runAs(portalUser()) {
            verifyOtpFor(MOBILE_PORTAL);
            Test.startTest();
            String caught;
            try {
                VS_BookingController.cancelMyAppointmentElevatedRaw(apptId, MOBILE_PORTAL);
                System.assert(false, 'expected the D-028 object-CRUD wall on the counter update');
            } catch (Exception e) {
                caught = e.getMessage();
            }
            Test.stopTest();
            System.assert(caught != null && caught.contains('UPDATE not allowed'),
                'owner + OTP + mobile-ownership passed and the elevation reached the §3.4 counter DML; '
                + 'residual is the D-028 object-CRUD wall (runtime-safe on a standard org): ' + caught);
        }
    }
}
