/**
 * VS_NoShowBatchTest — tests for the VS-12 no-show sweep (VS_NoShowBatch), EP-06.
 *
 * Proves every acceptance criterion with MEANINGFUL final-state asserts (not merely "no exception"):
 *  - AC-1 transition: a Booked appointment on an ended slot -> 'NoShow' and patient no-show count +1;
 *    future-slot and already-CheckedIn appointments are left untouched.
 *  - AC-2 idempotency: after the first run the start()-equivalent scope is EMPTY (NoShow rows are out of
 *    scope), and feeding execute() that empty scope does NOT double-increment.
 *  - AC-3 bulk (200+): a single execute() over 200 due appointments across 40 patients issues a CONSTANT
 *    1 SOQL + 2 DML (no SOQL/DML-in-loop), and every patient ends at the correct aggregated count.
 *  - Aggregation: three due appointments for one patient increment that patient by 3 in ONE patient DML.
 *  - Schedulable path + null-patient branch + empty/null-scope no-op (defensive/negative).
 *
 * === FLS/USER_MODE TEST PATTERN (D-028) ===
 * This DE org enforces FLS/CRUD on plain Apex DML during deploy-time test runs, and the batch itself
 * runs WITH USER_MODE / AccessLevel.USER_MODE. So the harness User is created (setup DML) OUTSIDE runAs
 * in @TestSetup, and ALL non-setup fixture DML AND the batch invocations run INSIDE
 * System.runAs(batchUser()), which carries the VS_NoShow_Batch_Test_Context harness permset (edit on
 * VS_Appointment__c + VS_Patient__c and FLS on VS_Status__c[required]/VS_Patient__c.VS_No_Show_Count__c).
 * Setup DML outside + non-setup inside runAs avoids MIXED_DML. The permset is TEST-ONLY and does NOT
 * grant a real scheduling user the runtime access (that gap is flagged in the review packet).
 *
 * No SeeAllData; synthetic data only (rules/10, no Aadhaar).
 *
 * Traceability: REQ-017, VS-12 AC-1/2/3 / EP-06 / D-020, D-028, D-029.
 */
@IsTest(SeeAllData=false)
private class VS_NoShowBatchTest {

    private static final String TEST_PERMSET = 'VS_NoShow_Batch_Test_Context';

    @TestSetup
    static void makeData() {
        // Setup-object DML (User + PermissionSetAssignment) FIRST in the default context; all non-setup
        // fixture DML is wrapped in runAs(u) below — the canonical MIXED_DML-safe ordering, and required
        // anyway because the org enforces FLS on plain DML in deploy tests (D-028).
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            FirstName = 'VS',
            LastName = 'VSNoShowTest',
            Alias = 'vsnst',
            Email = 'vs.noshow.test@vaccinescheduler.poc.example',
            Username = 'vs.noshow.test.' + Math.abs(Crypto.getRandomLong())
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
            insert new VS_Facility__c(Name = 'Test PHC No-Show');
            insert new VS_Service__c(Name = 'COVID Vaccination');
        }
    }

    // ---- Fixture helpers (all called INSIDE runAs(batchUser()) so their DML carries FLS) ----------

    private static User batchUser() {
        return [SELECT Id FROM User WHERE LastName = 'VSNoShowTest' LIMIT 1];
    }
    private static Id facilityId() { return [SELECT Id FROM VS_Facility__c LIMIT 1].Id; }
    private static Id serviceId()  { return [SELECT Id FROM VS_Service__c LIMIT 1].Id; }

    private static Id newPatient(String name) {
        VS_Patient__c pt = new VS_Patient__c(
            VS_Full_Name__c = name,
            VS_Date_Of_Birth__c = Date.newInstance(1990, 1, 1),
            VS_Mobile__c = '9000000000',
            VS_Match_Key__c = name + '|' + Math.abs(Crypto.getRandomLong()));
        insert pt;
        return pt.Id;
    }

    private static VS_Session__c newSession() {
        VS_Session__c s = new VS_Session__c(
            VS_Facility__c = facilityId(),
            VS_Service__c = serviceId(),
            VS_Session_Date__c = Date.today(),
            VS_Start_Time__c = Datetime.now().addHours(-6),
            VS_End_Time__c = Datetime.now().addHours(-2),
            VS_Total_Capacity__c = 400,
            VS_Status__c = 'Open');
        insert s;
        return s;
    }

    /** A slot whose window ENDS at endDt (use a past endDt for a "due" slot). */
    private static VS_Slot__c newSlot(Id sessionId, Datetime endDt, Integer capacity) {
        VS_Slot__c sl = new VS_Slot__c(
            VS_Session__c = sessionId,
            VS_Slot_Start__c = endDt.addMinutes(-15),
            VS_Slot_End__c = endDt,
            VS_Capacity__c = capacity,
            VS_Booked_Count__c = 0,
            VS_Status__c = 'Open');
        insert sl;
        return sl;
    }

    private static VS_Appointment__c newAppt(Id slotId, Id patientId, String status) {
        VS_Appointment__c a = new VS_Appointment__c(
            VS_Slot__c = slotId,
            VS_Patient__c = patientId,
            VS_Status__c = status);
        insert a;
        return a;
    }

    private static Decimal patientCount(Id patientId) {
        return [SELECT VS_No_Show_Count__c FROM VS_Patient__c WHERE Id = :patientId].VS_No_Show_Count__c;
    }
    private static String apptStatus(Id apptId) {
        return [SELECT VS_Status__c FROM VS_Appointment__c WHERE Id = :apptId].VS_Status__c;
    }

    // The start()-equivalent scope query (mirrors VS_NoShowBatch.start() WHERE clause exactly).
    private static List<VS_Appointment__c> dueScope() {
        Datetime nowDt = Datetime.now();
        return [
            SELECT Id, VS_Patient__c
            FROM VS_Appointment__c
            WHERE VS_Status__c = 'Booked'
              AND VS_Slot__r.VS_Slot_End__c != null
              AND VS_Slot__r.VS_Slot_End__c < :nowDt];
    }

    // ---- AC-1: transition + increment; future / checked-in left alone ----------------------------

    @IsTest
    static void testMarksDueBookedAsNoShow_andIncrementsPatient() {
      System.runAs(batchUser()) {
        VS_Session__c ses = newSession();
        VS_Slot__c pastSlot = newSlot(ses.Id, Datetime.now().addHours(-1), 50);
        VS_Slot__c futureSlot = newSlot(ses.Id, Datetime.now().addHours(3), 50);

        Id pDue = newPatient('Due Patient');
        Id pFuture = newPatient('Future Patient');
        Id pChecked = newPatient('Checked Patient');

        VS_Appointment__c dueAppt = newAppt(pastSlot.Id, pDue, 'Booked');
        VS_Appointment__c futureAppt = newAppt(futureSlot.Id, pFuture, 'Booked');
        VS_Appointment__c checkedAppt = newAppt(pastSlot.Id, pChecked, 'CheckedIn');

        Test.startTest();
        Database.executeBatch(new VS_NoShowBatch(), 200);
        Test.stopTest();

        System.assertEquals('NoShow', apptStatus(dueAppt.Id),
            'A Booked appointment on an ended slot must become NoShow');
        System.assertEquals(1, patientCount(pDue).intValue(),
            'The no-show patient count is incremented by exactly 1');
        System.assertEquals('Booked', apptStatus(futureAppt.Id),
            'An appointment whose slot has not ended stays Booked');
        System.assertEquals(0, patientCount(pFuture).intValue(),
            'Future-slot patient is not incremented');
        System.assertEquals('CheckedIn', apptStatus(checkedAppt.Id),
            'A checked-in appointment is out of scope and untouched');
        System.assertEquals(0, patientCount(pChecked).intValue(),
            'Checked-in patient is not incremented');
      }
    }

    // ---- AC-2: idempotent re-run does not double-increment ----------------------------------------

    @IsTest
    static void testIdempotentReRun_noDoubleIncrement() {
      System.runAs(batchUser()) {
        VS_Session__c ses = newSession();
        VS_Slot__c pastSlot = newSlot(ses.Id, Datetime.now().addHours(-1), 10);
        Id p = newPatient('Idem Patient');
        VS_Appointment__c appt = newAppt(pastSlot.Id, p, 'Booked');

        Test.startTest();
        Database.executeBatch(new VS_NoShowBatch(), 200);
        Test.stopTest();

        System.assertEquals('NoShow', apptStatus(appt.Id), 'First run flips the row to NoShow');
        System.assertEquals(1, patientCount(p).intValue(), 'First run increments the count to 1');

        // Idempotency mechanism: after run 1 the start scope is EMPTY (NoShow is excluded), so a second
        // pass has nothing to process and cannot double-increment.
        List<VS_Appointment__c> reScope = dueScope();
        System.assertEquals(0, reScope.size(),
            'AC-2: no Booked-past rows remain — NoShow rows are excluded from the batch scope');
        new VS_NoShowBatch().execute(null, reScope);
        System.assertEquals(1, patientCount(p).intValue(),
            'AC-2: re-running the batch does NOT double-increment the no-show count');
      }
    }

    // ---- Aggregation: many due appointments for one patient -> ONE patient DML, count += N ---------

    @IsTest
    static void testAggregatesMultiplePerPatient_singleIncrementBatch() {
      System.runAs(batchUser()) {
        VS_Session__c ses = newSession();
        VS_Slot__c pastSlot = newSlot(ses.Id, Datetime.now().addHours(-1), 50);
        Id p = newPatient('Multi Patient');

        List<VS_Appointment__c> appts = new List<VS_Appointment__c>();
        for (Integer i = 0; i < 3; i++) {
            appts.add(new VS_Appointment__c(VS_Slot__c = pastSlot.Id, VS_Patient__c = p, VS_Status__c = 'Booked'));
        }
        insert appts;

        Test.startTest();
        Database.executeBatch(new VS_NoShowBatch(), 200);
        Test.stopTest();

        System.assertEquals(3, patientCount(p).intValue(),
            'Three due appointments for one patient aggregate to a single +3 increment');
        for (VS_Appointment__c a : [SELECT VS_Status__c FROM VS_Appointment__c WHERE VS_Patient__c = :p]) {
            System.assertEquals('NoShow', a.VS_Status__c, 'Every due appointment is flipped to NoShow');
        }
      }
    }

    // ---- AC-3: 200 due appointments -> constant 1 SOQL + 2 DML in one execute() --------------------

    @IsTest
    static void testBulk200_constantSoqlDml_noGovernorBreach() {
      System.runAs(batchUser()) {
        final Integer numPatients = 40;
        final Integer perPatient = 5;   // 40 x 5 = 200 due appointments

        VS_Session__c ses = newSession();
        VS_Slot__c pastSlot = newSlot(ses.Id, Datetime.now().addHours(-1), 400);

        Set<Id> patientIds = new Set<Id>();
        List<VS_Appointment__c> appts = new List<VS_Appointment__c>();
        for (Integer i = 0; i < numPatients; i++) {
            Id pid = newPatient('Bulk ' + i);
            patientIds.add(pid);
            for (Integer j = 0; j < perPatient; j++) {
                appts.add(new VS_Appointment__c(
                    VS_Slot__c = pastSlot.Id, VS_Patient__c = pid, VS_Status__c = 'Booked'));
            }
        }
        insert appts;

        List<VS_Appointment__c> scope = dueScope();
        System.assertEquals(200, scope.size(), 'Fixture built exactly 200 due appointments');

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        Integer dmlBefore = Limits.getDmlStatements();
        new VS_NoShowBatch().execute(null, scope);
        Integer queriesUsed = Limits.getQueries() - queriesBefore;
        Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
        Test.stopTest();

        System.assertEquals(1, queriesUsed,
            'AC-3: exactly ONE SOQL for 200 appointments / 40 patients — no SOQL in a loop');
        System.assertEquals(2, dmlUsed,
            'AC-3: exactly TWO DML (appointments + patients) — no DML in a loop, one patient batch');

        Integer noShowRows = [
            SELECT COUNT() FROM VS_Appointment__c
            WHERE VS_Slot__c = :pastSlot.Id AND VS_Status__c = 'NoShow'];
        System.assertEquals(200, noShowRows, 'All 200 appointments transitioned to NoShow');
        for (VS_Patient__c pt : [SELECT VS_No_Show_Count__c FROM VS_Patient__c WHERE Id IN :patientIds]) {
            System.assertEquals(perPatient, pt.VS_No_Show_Count__c.intValue(),
                'Each patient is incremented by exactly its due-appointment count');
        }
      }
    }

    // ---- Schedulable path + null-patient branch ---------------------------------------------------

    @IsTest
    static void testSchedulableEntry_handlesNullPatientAppointment() {
      System.runAs(batchUser()) {
        VS_Session__c ses = newSession();
        VS_Slot__c pastSlot = newSlot(ses.Id, Datetime.now().addHours(-1), 10);
        VS_Appointment__c noPatientAppt = newAppt(pastSlot.Id, null, 'Booked');   // patient is optional
        Id p = newPatient('Sched Patient');
        VS_Appointment__c withPatientAppt = newAppt(pastSlot.Id, p, 'Booked');

        Test.startTest();
        // Schedulable entry -> Database.executeBatch; runs synchronously at stopTest.
        new VS_NoShowBatch(0).execute((SchedulableContext) null);   // 0 -> guarded to default size
        Test.stopTest();

        System.assertEquals('NoShow', apptStatus(noPatientAppt.Id),
            'A due appointment with no patient still transitions to NoShow');
        System.assertEquals('NoShow', apptStatus(withPatientAppt.Id),
            'A due appointment with a patient transitions to NoShow');
        System.assertEquals(1, patientCount(p).intValue(),
            'The patient is incremented; the null-patient row did not cause an error');
      }
    }

    // ---- Defensive/negative: null and empty scope are safe no-ops ---------------------------------

    @IsTest
    static void testExecute_nullAndEmptyScope_noOp() {
      System.runAs(batchUser()) {
        VS_Session__c ses = newSession();
        VS_Slot__c pastSlot = newSlot(ses.Id, Datetime.now().addHours(-1), 10);
        Id p = newPatient('Untouched Patient');
        VS_Appointment__c appt = newAppt(pastSlot.Id, p, 'Booked');

        Test.startTest();
        VS_NoShowBatch batch = new VS_NoShowBatch();
        batch.execute(null, null);
        batch.execute(null, new List<VS_Appointment__c>());
        Test.stopTest();

        System.assertEquals('Booked', apptStatus(appt.Id),
            'A no-op execute leaves the appointment untouched');
        System.assertEquals(0, patientCount(p).intValue(),
            'A no-op execute does not increment any patient');
      }
    }
}
