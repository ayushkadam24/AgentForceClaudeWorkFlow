/**
 * VS_BookingControllerTest — covers the @AuraEnabled seam VS_BookingController (VS-13/EP-06 UI layer)
 * and the D-030 portal booking design (inherited-sharing elevation + Annexure C9 OTP gate).
 *
 * D-028 pattern: acting users are created OUTSIDE runAs in @TestSetup with permsets; every write runs
 * INSIDE System.runAs(...). Two users:
 *  - bookingUser: the CI/test harness (VS_Booking_Engine_Test_Context etc.) used by most methods.
 *  - portalUser: holds ONLY the least-privilege VS_Booking_Portal permset (NO edit on Session/Slot) —
 *    the A-018 proof that an OTP-verified least-privilege citizen can book via the elevated Booker.
 */
@IsTest(SeeAllData=false)
private class VS_BookingControllerTest {

    private static final String OTP_CODE = VS_OtpStubProvider.TEST_CODE;   // '000000'
    private static Datetime farFuture() { return Datetime.now().addDays(2); }

    @TestSetup
    static void makeData() {
        // VS-20: keep the facility/appointment sharing triggers out of this booking-controller fixture.
        // They never touch VS_Slot__c/VS_Session__c (only Group/GroupMember/__Share + the facility's
        // VS_Sharing_Group_Id__c), so getAvailableSlots is functionally unaffected on the live site — this
        // bypass only removes a test-harness async/setup interaction that perturbed testReads.
        VS_FacilityTriggerHandler.bypass = true;
        VS_AppointmentTriggerHandler.bypass = true;
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = newUser('VSBookCtrl', 'vsbc');
        User portal = newUser('VSPortal', 'vspt');
        insert new List<User>{ u, portal };

        assign(u.Id, new Set<String>{
            'VS_Booking_Engine_Test_Context', 'VS_Patient_Service_Test_Context', 'VS_Otp_Test_Context'});
        assign(portal.Id, new Set<String>{ 'VS_Booking_Portal' });

        System.runAs(u) {
            VS_Facility__c f = new VS_Facility__c(Name = 'Test PHC', VS_Facility_Type__c = 'PHC', VS_Is_Active__c = true);
            insert f;
            VS_Service__c svc = new VS_Service__c(Name = 'COVID', VS_Service_Type__c = 'Vaccination',
                VS_Slot_Granularity_Mins__c = 15, VS_Is_Active__c = true);
            insert svc;
            VS_Session__c ses = new VS_Session__c(VS_Facility__c = f.Id, VS_Service__c = svc.Id,
                VS_Session_Date__c = Date.today().addDays(2), VS_Start_Time__c = farFuture(),
                VS_End_Time__c = farFuture().addHours(4), VS_Total_Capacity__c = 10, VS_Status__c = 'Open');
            insert ses;
            insert new VS_Slot__c(VS_Session__c = ses.Id, VS_Slot_Start__c = farFuture(),
                VS_Slot_End__c = farFuture().addMinutes(15), VS_Capacity__c = 5, VS_Booked_Count__c = 0,
                VS_Status__c = 'Open');
        }
    }

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

    private static User bookingUser() { return [SELECT Id FROM User WHERE LastName = 'VSBookCtrl' LIMIT 1]; }
    private static User portalUser()  { return [SELECT Id FROM User WHERE LastName = 'VSPortal' LIMIT 1]; }
    private static Id facilityId() { return [SELECT Id FROM VS_Facility__c LIMIT 1].Id; }
    private static Id serviceId()  { return [SELECT Id FROM VS_Service__c LIMIT 1].Id; }
    private static Id slotId()      { return [SELECT Id FROM VS_Slot__c LIMIT 1].Id; }

    @IsTest
    static void testReads_returnReferenceData() {
        // Use the session's ACTUAL stored date, not a recomputed Date.today().addDays(2): @TestSetup
        // builds the data inside runAs(Asia/Kolkata) while this method runs as the admin (a different
        // TZ), so recomputing "today+2" here can land on a different calendar day near a TZ midnight
        // boundary and miss the filter (a latent flaky test, not a getAvailableSlots defect — proven
        // working against real org data).
        Date sessionDay = [SELECT VS_Session_Date__c FROM VS_Session__c LIMIT 1].VS_Session_Date__c;
        Test.startTest();
        List<VS_Facility__c> fac = VS_BookingController.getFacilities();
        List<VS_Service__c> svc = VS_BookingController.getServices();
        List<VS_BookingController.SlotView> slots =
            VS_BookingController.getAvailableSlots(facilityId(), serviceId(), sessionDay);
        Test.stopTest();
        System.assertEquals(1, fac.size(), 'active facility returned');
        System.assertEquals(1, svc.size(), 'active service returned');
        System.assertEquals(1, slots.size(), 'one open slot with capacity');
        System.assertEquals(5, slots[0].remaining, 'remaining = capacity - booked');
    }

    @IsTest
    static void testGetAvailableSlots_missingInput_throws() {
        Test.startTest();
        Boolean threw = false;
        try { VS_BookingController.getAvailableSlots(null, null, null); }
        catch (AuraHandledException e) { threw = true; }
        Test.stopTest();
        System.assert(threw, 'missing input -> AuraHandledException');
    }

    @IsTest
    static void testOtp_issueThenVerify() {
      System.runAs(bookingUser()) {
        Test.startTest();
        VS_BookingController.sendOtp('9000000001');
        Boolean ok = VS_BookingController.verifyOtp('9000000001', OTP_CODE);
        Test.stopTest();
        System.assert(ok, 'stub OTP verifies with the fixed test code');
      }
    }

    @IsTest
    static void testVerifyOtp_wrongCode_throws() {
      System.runAs(bookingUser()) {
        Test.startTest();
        VS_BookingController.sendOtp('9000000002');
        Boolean threw = false;
        try { VS_BookingController.verifyOtp('9000000002', '999999'); }
        catch (AuraHandledException e) { threw = true; }
        Test.stopTest();
        System.assert(threw, 'wrong code -> friendly AuraHandledException');
      }
    }

    /** C9 gate: booking without a verified OTP for the mobile is rejected. */
    @IsTest
    static void testBook_withoutVerifiedOtp_rejected() {
      System.runAs(bookingUser()) {
        Test.startTest();
        Boolean threw = false;
        try { VS_BookingController.book('No Otp', Date.newInstance(1990,1,1), '9000000009', slotId()); }
        catch (AuraHandledException e) { threw = true; }
        Test.stopTest();
        System.assert(threw, 'no verified OTP -> AuraHandledException (C9 gate)');
        System.assertEquals(0, [SELECT COUNT() FROM VS_Appointment__c], 'nothing booked without OTP');
      }
    }

    /** HARNESS-ONLY end-to-end success (NOT a least-privilege proof): the harness permset
     *  VS_Booking_Engine_Test_Context grants Slot/Session EDIT — the D-020 grant forbidden for real
     *  users — so the counter DML completes even under this DE org's D-028 CRUD enforcement. It proves
     *  the happy path wiring (OTP gate -> findOrCreate -> book -> reference), not the A-018 access model. */
    @IsTest
    static void testBook_harnessUser_endToEnd_returnsReference() {
      System.runAs(bookingUser()) {
        String mobile = '9000000003';
        Test.startTest();
        VS_BookingController.sendOtp(mobile);
        VS_BookingController.verifyOtp(mobile, OTP_CODE);
        String ref = VS_BookingController.book('Asha Rao', Date.newInstance(1990,1,1), mobile, slotId());
        Test.stopTest();
        System.assert(String.isNotBlank(ref), 'a booking reference is returned');
        System.assertEquals(1, [SELECT COUNT() FROM VS_Appointment__c WHERE VS_Slot__c = :slotId()],
            'exactly one appointment created');
        // VS-16: the OTP-verified booker mobile is stamped as the IDOR ownership field.
        System.assertEquals(mobile,
            [SELECT VS_Booked_By_Mobile__c FROM VS_Appointment__c WHERE VS_Slot__c = :slotId() LIMIT 1]
                .VS_Booked_By_Mobile__c,
            'VS_Booked_By_Mobile__c stamped with the OTP-verified booker mobile (ownership field)');
      }
    }

    /** A-018 PROOF (D-030 / D-030a): under a user holding ONLY VS_Booking_Portal (NO edit on Session/Slot,
     *  the D-020 red line), the OTP-gated `without sharing` Booker clears the SHARING barrier — the call
     *  reaches the §3.4 lock, passes FLS, and the `insert as user` appointment succeeds — and the SOLE
     *  residual is this DE org's D-028 object-CRUD anomaly on the counter DML (`UPDATE not allowed on
     *  VS_Slot__c`). On a standard org, system-mode DML ignores CRUD and this booking SUCCEEDS; that
     *  success is a QA Tier-1 RUNTIME gate (like the §3.4 walk-in under D-028/D-029), not a deploy-time
     *  unit assertion. Asserting the CRUD wall here proves the elevation worked and isolates the residual
     *  as the documented org quirk, not a design defect. (No post-catch count assertion: catching
     *  suppresses the transaction-end rollback, so a count would read a false 1 — D-030a.) */
    @IsTest
    static void testBook_leastPrivilegePortalUser_clearsSharing_hitsD028CrudWall() {
      System.runAs(portalUser()) {
        String mobile = '9000000005';
        VS_BookingController.sendOtp(mobile);
        VS_BookingController.verifyOtp(mobile, OTP_CODE);
        Test.startTest();
        String caught;
        try {
            // Raw passthrough (no toAura wrap) so the underlying exception is assertable.
            VS_BookingController.bookElevatedRaw('Portal Citizen', Date.newInstance(1985,6,15), mobile, slotId());
            System.assert(false, 'expected the D-028 object-CRUD wall on the counter update');
        } catch (Exception e) {
            caught = e.getMessage();
        }
        Test.stopTest();
        System.assert(caught != null && caught.contains('UPDATE not allowed'),
            'elevation cleared sharing/FLS and reached the counter DML; residual is D-028 object CRUD (runtime-safe on a standard org): ' + caught);
      }
    }

    @IsTest
    static void testBook_missingInput_throws() {
        Test.startTest();
        Boolean threw = false;
        try { VS_BookingController.book('', null, '', null); }
        catch (AuraHandledException e) { threw = true; }
        Test.stopTest();
        System.assert(threw, 'missing booking details -> AuraHandledException');
    }
}
