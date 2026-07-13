/**
 * VS_BookingServiceCancelRescheduleTest — tests for the VS-11 cancel/reschedule extension of the
 * crown-jewel booking service (VS_BookingService.cancel/reschedule), EP-04, RFP §4.5, REQ-003/015.
 *
 * WHAT THESE TESTS PROVE (and, honestly, WHAT THEY DO NOT):
 *  - They prove the cut-off REJECTION LOGIC (a change inside VS_Setting__mdt.CutOffHours of slot start
 *    is refused with a coded VS_BookingException, no stack trace), the place-FREEING LOGIC (the freed
 *    slot count decrements and a Full slot flips back to Open), and the ATOMIC cancel-old + book-new of
 *    reschedule across and within sessions (final row/counter state asserted).
 *  - They do NOT, by themselves, prove serialization under REAL concurrency. Apex unit tests run in a
 *    SINGLE transaction and cannot spawn parallel transactions, so the reused VS_Session__c FOR UPDATE
 *    lock (and the deadlock-safe ORDER BY Id acquisition for a cross-session reschedule) is not
 *    contended here. Runtime serialization is validated by QA's parallel load test — see the VS-11
 *    review packet. In particular the B-1 fix (the in-lock re-read of the appointment status inside
 *    releasePlaceAndCancel that stops two concurrent cancels of the SAME appointment from
 *    double-freeing the place) cannot be interleaved in a unit transaction; testCancel_alreadyCancelled
 *    locks the sequential no-double-decrement invariant, and the concurrent double-cancel is a QA
 *    load-test case exactly like the §3.4 walk-in burst that proved book().
 *
 * === FLS/deploy-time discipline (D-028/D-028a) ===
 * Mirrors VS_BookingServiceTest: the harness User is created OUTSIDE runAs in @TestSetup; ALL non-setup
 * fixture DML AND the cancel()/reschedule() calls-under-test run INSIDE System.runAs(bookingUser())
 * carrying the VS_Booking_Engine_Test_Context harness permset. Every fixture is ONLINE (Portal/Staff)
 * so no test writes the required VS_Walk_In_Used_Count__c under system-mode DML — the walk-in cancel
 * branch shares book()'s proven walk-in decrement pattern and its dedicated counter-assertion test is
 * org-limited exactly like the VS-09 walk-in tests (deferred to QA runAs/parallel validation).
 *
 * Traceability: REQ-003, REQ-015 / EP-04 / §4.5 / D-010, D-019, D-020, D-029.
 */
@IsTest(SeeAllData=false)
private class VS_BookingServiceCancelRescheduleTest {

    private static Datetime farFuture() { return Datetime.now().addDays(1); }   // well past the 4h cut-off

    // Book/slot-gen FLS harness (VS-09) PLUS the VS-11 harness that adds Appointment Edit and FLS on
    // VS_Cancelled_At__c (the required VS_Status__c cannot carry FLS and needs none — see the permset).
    private static final String TEST_PERMSET = 'VS_Booking_Engine_Test_Context';
    private static final String CANCEL_PERMSET = 'VS_Cancel_Reschedule_Test_Context';

    @TestSetup
    static void makeData() {
        // Setup-object DML (User + PermissionSetAssignment) FIRST in the default context; then wrap all
        // non-setup fixture DML in runAs(u) (canonical MIXED_DML-safe ordering; the org enforces FLS on
        // plain DML in deploy tests, so fixtures need an FLS-bearing user).
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            FirstName = 'VS',
            LastName = 'VSCancelTest',
            Alias = 'vscxt',
            Email = 'vs.cancel.test@vaccinescheduler.poc.example',
            Username = 'vs.cancel.test.' + Math.abs(Crypto.getRandomLong())
                + '@vaccinescheduler.poc.example',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id);
        insert u;
        Map<String, PermissionSet> psByName = new Map<String, PermissionSet>();
        for (PermissionSet ps : [SELECT Id, Name FROM PermissionSet
                                 WHERE Name IN (:TEST_PERMSET, :CANCEL_PERMSET)]) {
            psByName.put(ps.Name, ps);
        }
        insert new List<PermissionSetAssignment>{
            new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = psByName.get(TEST_PERMSET).Id),
            new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = psByName.get(CANCEL_PERMSET).Id)
        };

        System.runAs(u) {
            insert new VS_Facility__c(Name = 'Test PHC Kothrud');
            insert new VS_Service__c(Name = 'COVID Vaccination');
        }
    }

    // ---- Fixtures (called INSIDE runAs(bookingUser()) so their DML runs with FLS) ------------------

    private static User bookingUser() {
        return [SELECT Id FROM User WHERE LastName = 'VSCancelTest' LIMIT 1];
    }

    private static Id facilityId() { return [SELECT Id FROM VS_Facility__c LIMIT 1].Id; }
    private static Id serviceId()  { return [SELECT Id FROM VS_Service__c LIMIT 1].Id; }

    private static Id newPatient(String name) {
        VS_Patient__c pt = new VS_Patient__c(
            VS_Full_Name__c = name,
            VS_Date_Of_Birth__c = Date.newInstance(1990, 1, 1),
            VS_Mobile__c = '9000000000',
            VS_Match_Key__c = name + '|1990-01-01|9000000000'
        );
        insert pt;
        return pt.Id;
    }

    private static VS_Session__c newSession(Integer total, String status) {
        VS_Session__c s = new VS_Session__c(
            VS_Facility__c = facilityId(),
            VS_Service__c = serviceId(),
            VS_Session_Date__c = Date.today().addDays(1),
            VS_Start_Time__c = farFuture(),
            VS_End_Time__c = farFuture().addHours(4),
            VS_Total_Capacity__c = total,
            VS_Status__c = status
        );
        insert s;
        return s;
    }

    /** Slot whose start is far past the cut-off (cancel/reschedule allowed). */
    private static VS_Slot__c newSlot(Id sessionId, Integer capacity) {
        return newSlotAt(sessionId, capacity, farFuture());
    }

    /** Slot with an explicit start — used to place a slot INSIDE the cut-off window. */
    private static VS_Slot__c newSlotAt(Id sessionId, Integer capacity, Datetime start) {
        VS_Slot__c sl = new VS_Slot__c(
            VS_Session__c = sessionId,
            VS_Slot_Start__c = start,
            VS_Slot_End__c = start.addMinutes(15),
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

    private static VS_Appointment__c reloadAppt(Id apptId) {
        return [SELECT Id, VS_Status__c, VS_Cancelled_At__c, VS_Slot__c, VS_Session__c
                FROM VS_Appointment__c WHERE Id = :apptId];
    }

    private static Integer apptCount(Id slotId) {
        return [SELECT COUNT() FROM VS_Appointment__c WHERE VS_Slot__c = :slotId];
    }

    // ---- CANCEL: past cut-off frees the place and reopens a full slot -------------------------

    @IsTest
    static void testCancel_pastCutOff_online_releasesPlaceAndOpensSlot() {
      System.runAs(bookingUser()) {
        VS_Session__c ses = newSession(20, 'Open');
        VS_Slot__c slot = newSlot(ses.Id, 1);                    // capacity 1 -> booking flips it Full
        Id apptId = VS_BookingService.book(newPatient('Cancel Me'), slot.Id, UserInfo.getUserId(), 'Portal');
        System.assertEquals('Full', reloadSlot(slot.Id).VS_Status__c, 'Precondition: slot is Full at ceiling');

        Test.startTest();
        VS_BookingService.cancel(apptId, UserInfo.getUserId());
        Test.stopTest();

        VS_Appointment__c appt = reloadAppt(apptId);
        System.assertEquals('Cancelled', appt.VS_Status__c, 'Appointment flips to Cancelled');
        System.assertNotEquals(null, appt.VS_Cancelled_At__c, 'VS_Cancelled_At__c is stamped on cancel');

        VS_Slot__c after = reloadSlot(slot.Id);
        System.assertEquals(0, after.VS_Booked_Count__c.intValue(), 'Freed place decrements the slot count to 0');
        System.assertEquals('Open', after.VS_Status__c, 'Slot flips Full->Open so the place is reusable (§4.5)');
      }
    }

    // ---- CANCEL: inside the cut-off window is rejected (NEGATIVE, AC-5) ------------------------

    @IsTest
    static void testCancel_withinCutOff_rejected() {
      System.runAs(bookingUser()) {
        VS_Session__c ses = newSession(20, 'Open');
        // Slot starts in 1 hour — inside the 4-hour CutOffHours window (VS_Setting__mdt).
        VS_Slot__c slot = newSlotAt(ses.Id, 5, Datetime.now().addHours(1));
        Id apptId = VS_BookingService.book(newPatient('Too Late'), slot.Id, UserInfo.getUserId(), 'Portal');

        Test.startTest();
        String caught;
        try {
            VS_BookingService.cancel(apptId, UserInfo.getUserId());
            System.assert(false, 'A cancel inside the cut-off window must throw');
        } catch (VS_BookingException e) {
            caught = e.getMessage();
        }
        Test.stopTest();

        System.assertEquals(VS_BookingException.WITHIN_CUTOFF, caught,
            'Cancel inside the cut-off -> WITHIN_CUTOFF (coded, user-actionable — not a stack trace)');
        System.assertEquals('Booked', reloadAppt(apptId).VS_Status__c, 'Appointment is untouched by the rejected cancel');
        System.assertEquals(1, reloadSlot(slot.Id).VS_Booked_Count__c.intValue(),
            'Slot count is untouched — no place was freed inside the cut-off');
      }
    }

    // ---- CANCEL: an already-cancelled appointment is rejected ---------------------------------

    @IsTest
    static void testCancel_alreadyCancelled_rejected() {
      System.runAs(bookingUser()) {
        VS_Session__c ses = newSession(20, 'Open');
        VS_Slot__c slot = newSlot(ses.Id, 5);
        Id apptId = VS_BookingService.book(newPatient('Once Only'), slot.Id, UserInfo.getUserId(), 'Portal');

        Test.startTest();
        VS_BookingService.cancel(apptId, UserInfo.getUserId());
        String caught;
        try {
            VS_BookingService.cancel(apptId, UserInfo.getUserId());
            System.assert(false, 'Cancelling an already-cancelled appointment must throw');
        } catch (VS_BookingException e) {
            caught = e.getMessage();
        }
        Test.stopTest();

        System.assertEquals(VS_BookingException.ALREADY_CANCELLED, caught, 'Second cancel -> ALREADY_CANCELLED');
        System.assertEquals(0, reloadSlot(slot.Id).VS_Booked_Count__c.intValue(),
            'The place stays freed exactly once — the second attempt does not double-decrement');
      }
    }

    // ---- CANCEL: null input throws before any DML ---------------------------------------------

    @IsTest
    static void testCancel_nullInput_throws() {
        Test.startTest();
        String caught;
        try {
            VS_BookingService.cancel(null, UserInfo.getUserId());
            System.assert(false, 'Null appointmentId must throw');
        } catch (VS_BookingException e) {
            caught = e.getMessage();
        }
        Test.stopTest();
        System.assertEquals(VS_BookingException.INVALID_INPUT, caught, 'Null input -> INVALID_INPUT');
    }

    // ---- RESCHEDULE: across sessions (S1 != S2) — one FOR UPDATE ordered by Id (AC-3) ----------

    @IsTest
    static void testReschedule_crossSession_movesPlaceAtomically() {
      System.runAs(bookingUser()) {
        VS_Session__c s1 = newSession(20, 'Open');
        VS_Session__c s2 = newSession(20, 'Open');
        VS_Slot__c slot1 = newSlot(s1.Id, 5);
        VS_Slot__c slot2 = newSlot(s2.Id, 5);
        Id oldAppt = VS_BookingService.book(newPatient('Mover'), slot1.Id, UserInfo.getUserId(), 'Portal');
        System.assertEquals(1, reloadSlot(slot1.Id).VS_Booked_Count__c.intValue(), 'Precondition: source slot holds 1');

        Test.startTest();
        Id newAppt = VS_BookingService.reschedule(oldAppt, slot2.Id, UserInfo.getUserId(), 'Portal');
        Test.stopTest();

        System.assertNotEquals(null, newAppt, 'A new appointment Id is returned');
        System.assertNotEquals(oldAppt, newAppt, 'Reschedule creates a NEW appointment (cancel-old + book-new)');

        System.assertEquals('Cancelled', reloadAppt(oldAppt).VS_Status__c, 'The old appointment is Cancelled');
        VS_Appointment__c moved = reloadAppt(newAppt);
        System.assertEquals('Booked', moved.VS_Status__c, 'The new appointment is Booked');
        System.assertEquals(slot2.Id, moved.VS_Slot__c, 'The new appointment sits on the destination slot');
        System.assertEquals(s2.Id, moved.VS_Session__c, 'The new appointment belongs to the destination session');

        System.assertEquals(0, reloadSlot(slot1.Id).VS_Booked_Count__c.intValue(), 'Source slot place is freed');
        System.assertEquals(1, reloadSlot(slot2.Id).VS_Booked_Count__c.intValue(), 'Destination slot place is taken');
      }
    }

    // ---- RESCHEDULE: within the SAME session — a single lock (AC-4) ----------------------------

    @IsTest
    static void testReschedule_sameSession_singleLock_movesPlace() {
      System.runAs(bookingUser()) {
        VS_Session__c ses = newSession(20, 'Open');
        VS_Slot__c slot1 = newSlot(ses.Id, 5);
        VS_Slot__c slot2 = newSlot(ses.Id, 5);
        Id oldAppt = VS_BookingService.book(newPatient('Shuffle'), slot1.Id, UserInfo.getUserId(), 'Portal');

        Test.startTest();
        Id newAppt = VS_BookingService.reschedule(oldAppt, slot2.Id, UserInfo.getUserId(), 'Staff');
        Test.stopTest();

        System.assertEquals('Cancelled', reloadAppt(oldAppt).VS_Status__c, 'Old appointment Cancelled');
        VS_Appointment__c moved = reloadAppt(newAppt);
        System.assertEquals('Booked', moved.VS_Status__c, 'New appointment Booked');
        System.assertEquals(ses.Id, moved.VS_Session__c, 'Still the same session (single-lock path)');
        System.assertEquals(0, reloadSlot(slot1.Id).VS_Booked_Count__c.intValue(), 'Source slot freed');
        System.assertEquals(1, reloadSlot(slot2.Id).VS_Booked_Count__c.intValue(), 'Destination slot taken');
      }
    }

    // ---- RESCHEDULE: inside the cut-off is rejected -------------------------------------------

    @IsTest
    static void testReschedule_withinCutOff_rejected() {
      System.runAs(bookingUser()) {
        VS_Session__c ses = newSession(20, 'Open');
        VS_Slot__c soon = newSlotAt(ses.Id, 5, Datetime.now().addHours(1));   // inside the cut-off
        VS_Slot__c dest = newSlot(ses.Id, 5);
        Id apptId = VS_BookingService.book(newPatient('Late Mover'), soon.Id, UserInfo.getUserId(), 'Portal');

        Test.startTest();
        String caught;
        try {
            VS_BookingService.reschedule(apptId, dest.Id, UserInfo.getUserId(), 'Portal');
            System.assert(false, 'A reschedule inside the cut-off window must throw');
        } catch (VS_BookingException e) {
            caught = e.getMessage();
        }
        Test.stopTest();

        System.assertEquals(VS_BookingException.WITHIN_CUTOFF, caught, 'Reschedule inside cut-off -> WITHIN_CUTOFF');
        System.assertEquals('Booked', reloadAppt(apptId).VS_Status__c, 'Original appointment untouched');
        System.assertEquals(0, reloadSlot(dest.Id).VS_Booked_Count__c.intValue(), 'Destination slot untouched');
      }
    }

    // ---- RESCHEDULE: destination full -> SLOT_FULL, savepoint keeps the original intact (atomicity) ---

    @IsTest
    static void testReschedule_destinationFull_rollsBack_originalSurvives() {
      System.runAs(bookingUser()) {
        VS_Session__c s1 = newSession(20, 'Open');
        VS_Session__c s2 = newSession(20, 'Open');
        VS_Slot__c source = newSlot(s1.Id, 5);
        VS_Slot__c full = newSlot(s2.Id, 1);
        Id keep = VS_BookingService.book(newPatient('Original'), source.Id, UserInfo.getUserId(), 'Portal');
        VS_BookingService.book(newPatient('Occupier'), full.Id, UserInfo.getUserId(), 'Portal'); // fills dest

        Test.startTest();
        String caught;
        try {
            VS_BookingService.reschedule(keep, full.Id, UserInfo.getUserId(), 'Portal');
            System.assert(false, 'Rescheduling onto a full slot must throw');
        } catch (VS_BookingException e) {
            caught = e.getMessage();
        }
        Test.stopTest();

        System.assertEquals(VS_BookingException.SLOT_FULL, caught, 'Full destination -> SLOT_FULL from book()');
        // Savepoint rollback: the cancel-old must NOT have committed — the original is still Booked.
        System.assertEquals('Booked', reloadAppt(keep).VS_Status__c,
            'ATOMICITY: the original appointment survives when the new booking is rejected');
        System.assertEquals(1, reloadSlot(source.Id).VS_Booked_Count__c.intValue(),
            'Source slot place is NOT freed on a rolled-back reschedule');
        System.assertEquals(1, reloadSlot(full.Id).VS_Booked_Count__c.intValue(),
            'Destination slot is unchanged (still exactly at its ceiling of 1)');
      }
    }

    // ---- RESCHEDULE: destination slot does not exist -----------------------------------------

    @IsTest
    static void testReschedule_destinationSlotNotFound_throws() {
      System.runAs(bookingUser()) {
        VS_Session__c ses = newSession(20, 'Open');
        VS_Slot__c source = newSlot(ses.Id, 5);
        Id apptId = VS_BookingService.book(newPatient('No Dest'), source.Id, UserInfo.getUserId(), 'Portal');
        VS_Slot__c doomed = newSlot(ses.Id, 5);
        Id ghost = doomed.Id;
        delete doomed;

        Test.startTest();
        String caught;
        try {
            VS_BookingService.reschedule(apptId, ghost, UserInfo.getUserId(), 'Portal');
            System.assert(false, 'A missing destination slot must throw');
        } catch (VS_BookingException e) {
            caught = e.getMessage();
        }
        Test.stopTest();

        System.assertEquals(VS_BookingException.SLOT_NOT_FOUND, caught, 'Missing destination -> SLOT_NOT_FOUND');
        System.assertEquals('Booked', reloadAppt(apptId).VS_Status__c, 'Original untouched — the source lookup happened before any write');
      }
    }

    // ---- RESCHEDULE: invalid channel / null input --------------------------------------------

    @IsTest
    static void testReschedule_invalidInputs_throw() {
      System.runAs(bookingUser()) {
        VS_Session__c ses = newSession(20, 'Open');
        VS_Slot__c slot = newSlot(ses.Id, 5);
        Id apptId = VS_BookingService.book(newPatient('Bad Args'), slot.Id, UserInfo.getUserId(), 'Portal');

        Test.startTest();
        String nullCaught;
        try {
            VS_BookingService.reschedule(null, slot.Id, UserInfo.getUserId(), 'Portal');
            System.assert(false, 'Null appointmentId must throw');
        } catch (VS_BookingException e) { nullCaught = e.getMessage(); }

        String chanCaught;
        try {
            VS_BookingService.reschedule(apptId, slot.Id, UserInfo.getUserId(), 'Telepathy');
            System.assert(false, 'Unknown channel must throw');
        } catch (VS_BookingException e) { chanCaught = e.getMessage(); }
        Test.stopTest();

        System.assertEquals(VS_BookingException.INVALID_INPUT, nullCaught, 'Null input -> INVALID_INPUT');
        System.assertEquals(VS_BookingException.INVALID_CHANNEL, chanCaught, 'Unknown channel -> INVALID_CHANNEL');
        System.assertEquals('Booked', reloadAppt(apptId).VS_Status__c, 'The appointment is untouched by rejected input');
      }
    }
}
