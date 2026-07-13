/**
 * VS_PatientServiceTest — tests for VS-10 patient identity / exact-match de-dup (VS_PatientService +
 * VS_PatientException), EP-05, D-011/D-017, REQ-004/046.
 *
 * COVERS THE 4 ACs:
 *  1. Exact normalized triple -> existing Id, no new row (testExactMatch_returnsSameId_noNewRow).
 *  2. Any one field differing -> a NEW patient, never a silent merge (testDifferingField_createsNew).
 *  3. Race-safe by the DB unique constraint, NOT a prior SOQL check: a duplicate insert is caught and
 *     resolved to the existing row (testRaceSafe_duplicateInsertResolvesToExisting).
 *  4. Consent not true -> THROW, create nothing; on create, stamp consent + timestamp
 *     (testConsentFalse_throws_createsNothing, testCreatesNewPatient_stampsConsent).
 *
 * === FLS/USER_MODE TEST PATTERN (D-028) ===
 * This DE org enforces FLS/CRUD on PLAIN Apex DML during deploy-time test runs, so fixtures and the
 * USER_MODE code path need a running context that actually holds FLS. The harness User is created as
 * SETUP-object DML in @TestSetup (default context, MIXED_DML-safe); ALL non-setup patient DML and the
 * findOrCreate() call-under-test run INSIDE System.runAs(patientUser()), a user carrying the TEST-ONLY
 * VS_Patient_Service_Test_Context permset (Create+Read on VS_Patient__c + FLS on the de-dup/consent/
 * optional fields). Production code is unchanged.
 *
 * Honest limitation: an Apex unit test runs in ONE transaction and cannot spawn parallel transactions,
 * so the AC-3 test proves the catch-then-requery LOGIC of the loser path; the runtime race-serialization
 * itself is guaranteed by the VS_Match_Key__c DB unique constraint (D-017).
 *
 * Meaningful asserts on final state (row counts + stamped fields), not merely "no exception". No
 * SeeAllData; synthetic, non-Aadhaar data (rules/10).
 *
 * Traceability: REQ-004, REQ-046 / EP-05 / D-011, D-017, D-028.
 */
@IsTest(SeeAllData=false)
private class VS_PatientServiceTest {

    private static final String TEST_PERMSET = 'VS_Patient_Service_Test_Context';

    @TestSetup
    static void makeData() {
        // Setup-object DML (User + PermissionSetAssignment) in the default context — before any
        // non-setup DML — is the canonical MIXED_DML-safe ordering.
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            FirstName = 'VS',
            LastName = 'VSPatientTest',
            Alias = 'vspat',
            Email = 'vs.patient.test@vaccinescheduler.poc.example',
            Username = 'vs.patient.test.' + Math.abs(Crypto.getRandomLong())
                + '@vaccinescheduler.poc.example',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id);
        insert u;
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :TEST_PERMSET LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
    }

    /** The FLS-bearing harness user under which all fixtures AND findOrCreate() execute (D-028). */
    private static User patientUser() {
        return [SELECT Id FROM User WHERE LastName = 'VSPatientTest' LIMIT 1];
    }

    /** Unsaved patient carrying only the three required match-key inputs. */
    private static VS_Patient__c shell(String name, Date dob, String mobile) {
        return new VS_Patient__c(
            VS_Full_Name__c = name, VS_Date_Of_Birth__c = dob, VS_Mobile__c = mobile);
    }

    private static Integer patientCount() {
        return [SELECT COUNT() FROM VS_Patient__c];
    }

    // ---- AC create + AC-4 positive: creates a row and stamps consent -------------------------------
    @IsTest
    static void testCreatesNewPatient_stampsConsent() {
        System.runAs(patientUser()) {
            Test.startTest();
            Id id = VS_PatientService.findOrCreate(
                shell('John Doe', Date.newInstance(1990, 1, 1), '9000000001'), true);
            Test.stopTest();

            System.assertNotEquals(null, id, 'findOrCreate should return the created patient Id');
            System.assertEquals(1, patientCount(), 'exactly one patient row should exist');
            VS_Patient__c saved = [
                SELECT VS_Match_Key__c, VS_Consent_Given__c, VS_Consent_Timestamp__c
                FROM VS_Patient__c WHERE Id = :id];
            System.assertEquals('john doe|1990-01-01|9000000001', saved.VS_Match_Key__c,
                'match key must be the normalized name|ISO-DOB|digits-mobile triple');
            System.assertEquals(true, saved.VS_Consent_Given__c, 'consent flag must be stamped true');
            System.assertNotEquals(null, saved.VS_Consent_Timestamp__c,
                'consent timestamp must be stamped on create (REQ-046)');
        }
    }

    // ---- AC-1: identical normalized triple returns the SAME Id, no new row -------------------------
    @IsTest
    static void testExactMatch_returnsSameId_noNewRow() {
        System.runAs(patientUser()) {
            Id first = VS_PatientService.findOrCreate(
                shell('John Doe', Date.newInstance(1990, 1, 1), '9000000001'), true);

            Test.startTest();
            // Same identity, but differently CASED / SPACED / FORMATTED — normalization must collapse
            // these to the same key so no duplicate is created.
            Id second = VS_PatientService.findOrCreate(
                shell('  JOHN   doe  ', Date.newInstance(1990, 1, 1), ' 90000 00001 '), true);
            Test.stopTest();

            System.assertEquals(first, second, 'an exact normalized match must return the existing Id');
            System.assertEquals(1, patientCount(), 'no second row may be created for the same identity');
        }
    }

    // ---- AC-2: any single differing field creates a NEW patient (no silent merge) ------------------
    @IsTest
    static void testDifferingField_createsNew() {
        System.runAs(patientUser()) {
            Id base = VS_PatientService.findOrCreate(
                shell('John Doe', Date.newInstance(1990, 1, 1), '9000000001'), true);

            Test.startTest();
            Id diffName = VS_PatientService.findOrCreate(
                shell('Jane Doe', Date.newInstance(1990, 1, 1), '9000000001'), true);
            Id diffDob = VS_PatientService.findOrCreate(
                shell('John Doe', Date.newInstance(1991, 1, 1), '9000000001'), true);
            Id diffMobile = VS_PatientService.findOrCreate(
                shell('John Doe', Date.newInstance(1990, 1, 1), '9000000002'), true);
            Test.stopTest();

            Set<Id> ids = new Set<Id>{ base, diffName, diffDob, diffMobile };
            System.assertEquals(4, ids.size(), 'each differing field must yield a distinct patient Id');
            System.assertEquals(4, patientCount(), 'four separate rows must exist (duplicates accepted)');
        }
    }

    // ---- AC-3: duplicate insert is caught and resolved to the existing row (race loser path) -------
    @IsTest
    static void testRaceSafe_duplicateInsertResolvesToExisting() {
        System.runAs(patientUser()) {
            // Seed a row directly so the SAME key already exists in the DB (simulating the race WINNER
            // having committed). buildMatchKey (@TestVisible) keeps the seed key consistent with the
            // service's algorithm.
            String key = VS_PatientService.buildMatchKey(
                'Ravi Kumar', Date.newInstance(1985, 6, 15), '9111111111');
            VS_Patient__c seeded = new VS_Patient__c(
                VS_Full_Name__c = 'Ravi Kumar',
                VS_Date_Of_Birth__c = Date.newInstance(1985, 6, 15),
                VS_Mobile__c = '9111111111',
                VS_Match_Key__c = key,
                VS_Consent_Given__c = true,
                VS_Consent_Timestamp__c = System.now());
            insert seeded;

            Test.startTest();
            // The service's insert hits the unique constraint (DUPLICATE_VALUE) and must resolve to the
            // seeded row via re-query — NOT rely on a prior SOQL existence check.
            Id resolved = VS_PatientService.findOrCreate(
                shell('Ravi Kumar', Date.newInstance(1985, 6, 15), '9111111111'), true);
            Test.stopTest();

            System.assertEquals(seeded.Id, resolved,
                'a duplicate-key insert must resolve to the pre-existing row Id (D-017)');
            System.assertEquals(1, patientCount(), 'the race loser must NOT create a second row');
        }
    }

    // ---- AC-4 negative: consent not true throws and creates nothing --------------------------------
    @IsTest
    static void testConsentFalse_throws_createsNothing() {
        System.runAs(patientUser()) {
            Boolean threw = false;
            try {
                VS_PatientService.findOrCreate(
                    shell('No Consent', Date.newInstance(2000, 2, 2), '9222222222'), false);
            } catch (VS_PatientException e) {
                threw = true;
                System.assertEquals(VS_PatientException.CONSENT_REQUIRED, e.getMessage(),
                    'consent-not-true must throw the CONSENT_REQUIRED code');
            }
            System.assert(threw, 'findOrCreate must throw when consent is false');

            // Null consent is likewise not-true and must throw.
            Boolean threwNull = false;
            try {
                VS_PatientService.findOrCreate(
                    shell('No Consent', Date.newInstance(2000, 2, 2), '9222222222'), null);
            } catch (VS_PatientException e) {
                threwNull = true;
            }
            System.assert(threwNull, 'findOrCreate must throw when consent is null');
            System.assertEquals(0, patientCount(), 'a consent-less patient must never be created');
        }
    }

    // ---- Guard: invalid input (null patient / blank match-key inputs) throws, creates nothing ------
    @IsTest
    static void testInvalidInput_throws() {
        System.runAs(patientUser()) {
            assertInvalid(null);
            assertInvalid(shell(null, Date.newInstance(1990, 1, 1), '9000000003'));   // blank name
            assertInvalid(shell('Missing DOB', null, '9000000003'));                  // null DOB
            assertInvalid(shell('Missing Mobile', Date.newInstance(1990, 1, 1), ' ')); // blank mobile
            System.assertEquals(0, patientCount(), 'invalid input must never create a row');
        }
    }

    private static void assertInvalid(VS_Patient__c patient) {
        Boolean threw = false;
        try {
            VS_PatientService.findOrCreate(patient, true);
        } catch (VS_PatientException e) {
            threw = true;
            System.assertEquals(VS_PatientException.INVALID_INPUT, e.getMessage(),
                'invalid input must throw the INVALID_INPUT code');
        }
        System.assert(threw, 'findOrCreate must throw on invalid input');
    }

    // ---- The normalization algorithm is the single source of truth (D-017) ------------------------
    @IsTest
    static void testBuildMatchKey_normalization() {
        // trim + collapse whitespace (incl. tab) + lowercase name; ISO zero-padded DOB; digits-only mobile.
        String key = VS_PatientService.buildMatchKey(
            '  Jane\tSmith  ', Date.newInstance(2001, 3, 5), '(999) 111-2222');
        System.assertEquals('jane smith|2001-03-05|9991112222', key,
            'buildMatchKey must normalize name/DOB/mobile deterministically');
    }
}
