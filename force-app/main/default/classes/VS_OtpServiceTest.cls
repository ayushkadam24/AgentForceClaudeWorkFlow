/**
 * VS_OtpServiceTest — tests for the VS-13 OTP verification seam (VS_OtpService + VS_IOtpProvider +
 * VS_OtpStubProvider + VS_OtpException + VS_OTP_Verification__c), EP-06, design §6.4 / D-013.
 *
 * PROVES:
 *  - issue() stores a HASH, never the plaintext code (D-013 — the crown-jewel privacy guarantee here).
 *  - a correct code verifies and flips VS_Verified__c.
 *  - an expired challenge is rejected with the EXPIRED code, independent of attempts.
 *  - the lockout ceiling: 3 wrong codes each record a failed attempt, the 4th call is rejected with
 *    TOO_MANY_ATTEMPTS (ticket AC) BEFORE any hash comparison.
 *  - the provider seam is swappable (A-004): a fake VS_IOtpProvider is honoured with zero service change.
 *
 * === FLS/USER_MODE TEST PATTERN (D-028) ===
 * This DE org enforces FLS/CRUD on USER_MODE Apex DML during deploy-time RunLocalTests. The harness User
 * is created OUTSIDE runAs in @TestSetup (setup DML), and ALL fixture DML plus the service calls run
 * INSIDE System.runAs(otpUser()), a user carrying the VS_Otp_Test_Context harness permset that grants
 * CRUD+FLS on VS_OTP_Verification__c. Setup DML outside + non-setup inside runAs avoids MIXED_DML.
 * Production code is UNCHANGED; the harness permset is TEST-ONLY.
 *
 * Meaningful asserts on final state (row counters + flags), not merely "no exception". @TestSetup builds
 * the synthetic user; no SeeAllData; no Aadhaar (rules/10).
 *
 * Traceability: REQ-058/059, EP-06 / D-013, A-004.
 */
@IsTest(SeeAllData=false)
private class VS_OtpServiceTest {

    private static final String TEST_PERMSET = 'VS_Otp_Test_Context';
    private static final String MOBILE = '9000000001';
    private static final String FAKE_CODE = '135790';

    @TestSetup
    static void makeData() {
        // Setup-object DML (User + PermissionSetAssignment) in the default context, before any
        // non-setup DML — the canonical MIXED_DML-safe ordering.
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            FirstName = 'VS',
            LastName = 'VSOtpTest',
            Alias = 'vsotp',
            Email = 'vs.otp.test@vaccinescheduler.poc.example',
            Username = 'vs.otp.test.' + Math.abs(Crypto.getRandomLong()) + '@vaccinescheduler.poc.example',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id);
        insert u;
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :TEST_PERMSET LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
    }

    /** The FLS-bearing harness user under which fixtures AND the service calls execute (D-028). */
    private static User otpUser() {
        return [SELECT Id FROM User WHERE LastName = 'VSOtpTest' LIMIT 1];
    }

    /** Fetch the single challenge row for the test mobile (harness user context). */
    private static VS_OTP_Verification__c currentChallenge() {
        return [
            SELECT Id, VS_Mobile__c, VS_Code_Hash__c, VS_Expiry__c, VS_Attempts__c, VS_Verified__c
            FROM VS_OTP_Verification__c
            WHERE VS_Mobile__c = :MOBILE
            ORDER BY CreatedDate DESC
            LIMIT 1];
    }

    // ---- 1. issue() stores a HASH, never plaintext (D-013) --------------------------------------------
    @IsTest
    static void issueStoresHashNotPlaintext() {
        System.runAs(otpUser()) {
            Test.startTest();
            Id challengeId = VS_OtpService.issue(MOBILE);
            Test.stopTest();

            System.assertNotEquals(null, challengeId, 'issue() should return the new challenge Id');
            VS_OTP_Verification__c row = currentChallenge();

            System.assertEquals(MOBILE, row.VS_Mobile__c, 'Mobile should be stored as issued');
            System.assertEquals(0, row.VS_Attempts__c.intValue(), 'Attempts should start at 0');
            System.assertEquals(false, row.VS_Verified__c, 'Verified should start false');
            System.assert(row.VS_Expiry__c > Datetime.now(), 'Expiry should be in the future');

            // The stored value must NOT be the plaintext, and MUST be the salted SHA-256 hex digest.
            System.assertNotEquals(VS_OtpStubProvider.TEST_CODE, row.VS_Code_Hash__c,
                'Plaintext code must NEVER be stored (D-013)');
            String expectedHash = EncodingUtil.convertToHex(
                Crypto.generateDigest('SHA-256', Blob.valueOf(MOBILE + ':' + VS_OtpStubProvider.TEST_CODE)));
            System.assertEquals(expectedHash, row.VS_Code_Hash__c, 'Stored value should be the salted SHA-256 hash');
            System.assertEquals(64, row.VS_Code_Hash__c.length(), 'SHA-256 hex digest is 64 chars');
        }
    }

    // ---- 2. successful verify flips VS_Verified__c ----------------------------------------------------
    @IsTest
    static void verifySucceedsWithCorrectCode() {
        System.runAs(otpUser()) {
            VS_OtpService.issue(MOBILE);

            Test.startTest();
            Boolean result = VS_OtpService.verify(MOBILE, VS_OtpStubProvider.TEST_CODE);
            Test.stopTest();

            System.assertEquals(true, result, 'Correct code should verify');
            VS_OTP_Verification__c row = currentChallenge();
            System.assertEquals(true, row.VS_Verified__c, 'Challenge should be marked verified');
            System.assertEquals(0, row.VS_Attempts__c.intValue(), 'A correct first try records no failed attempts');
        }
    }

    // ---- 3. expired challenge is rejected -------------------------------------------------------------
    @IsTest
    static void verifyRejectsExpiredChallenge() {
        System.runAs(otpUser()) {
            VS_OtpService.issue(MOBILE);
            // Force the challenge into the past (harness user has FLS edit).
            VS_OTP_Verification__c row = currentChallenge();
            row.VS_Expiry__c = Datetime.now().addMinutes(-1);
            update row;

            Boolean threw = false;
            Test.startTest();
            try {
                VS_OtpService.verify(MOBILE, VS_OtpStubProvider.TEST_CODE);
            } catch (VS_OtpException e) {
                threw = true;
                System.assertEquals(VS_OtpException.EXPIRED, e.code, 'Should reject with EXPIRED code');
                System.assert(String.isNotBlank(e.getMessage()), 'Should carry a user-actionable message');
            }
            Test.stopTest();

            System.assert(threw, 'Verifying an expired challenge should throw VS_OtpException');
            System.assertEquals(false, currentChallenge().VS_Verified__c, 'Expired challenge stays unverified');
        }
    }

    // ---- 4. lockout after 3 failed attempts (ticket AC) ----------------------------------------------
    @IsTest
    static void verifyLocksOutAfterThreeFailures() {
        System.runAs(otpUser()) {
            VS_OtpService.issue(MOBILE);

            Test.startTest();
            // Three wrong codes — each recorded as a failed attempt, each rejected with INVALID_CODE.
            for (Integer i = 0; i < 3; i++) {
                try {
                    VS_OtpService.verify(MOBILE, '999999');
                    System.assert(false, 'A wrong code should throw');
                } catch (VS_OtpException e) {
                    System.assertEquals(VS_OtpException.INVALID_CODE, e.code, 'Wrong code should be INVALID_CODE');
                }
            }
            System.assertEquals(3, currentChallenge().VS_Attempts__c.intValue(), 'Three failures should be recorded');

            // The 4th call is rejected as locked out BEFORE any hash comparison — even the CORRECT code fails.
            Boolean lockedOut = false;
            try {
                VS_OtpService.verify(MOBILE, VS_OtpStubProvider.TEST_CODE);
            } catch (VS_OtpException e) {
                lockedOut = true;
                System.assertEquals(VS_OtpException.TOO_MANY_ATTEMPTS, e.code, 'The 4th attempt should be locked out');
                System.assert(String.isNotBlank(e.getMessage()), 'Lockout carries a user-actionable message');
            }
            Test.stopTest();

            System.assert(lockedOut, 'The 4th attempt must be rejected as locked out');
            VS_OTP_Verification__c row = currentChallenge();
            System.assertEquals(false, row.VS_Verified__c, 'A locked-out challenge is never verified');
            System.assertEquals(3, row.VS_Attempts__c.intValue(), 'Lockout does not increment past the ceiling');
        }
    }

    // ---- 5. invalid input + not-found negative paths -------------------------------------------------
    @IsTest
    static void guardsRejectInvalidInputAndMissingChallenge() {
        System.runAs(otpUser()) {
            Test.startTest();
            try {
                VS_OtpService.issue('   ');
                System.assert(false, 'Blank mobile should throw');
            } catch (VS_OtpException e) {
                System.assertEquals(VS_OtpException.INVALID_INPUT, e.code, 'Blank mobile is INVALID_INPUT');
            }
            try {
                VS_OtpService.verify(MOBILE, null);
                System.assert(false, 'Blank code should throw');
            } catch (VS_OtpException e) {
                System.assertEquals(VS_OtpException.INVALID_INPUT, e.code, 'Blank code is INVALID_INPUT');
            }
            try {
                VS_OtpService.verify('9111111111', VS_OtpStubProvider.TEST_CODE);
                System.assert(false, 'No challenge should throw');
            } catch (VS_OtpException e) {
                System.assertEquals(VS_OtpException.NOT_FOUND, e.code, 'No active challenge is NOT_FOUND');
            }
            Test.stopTest();
        }
    }

    // ---- 6. already-verified challenge cannot be re-verified ------------------------------------------
    @IsTest
    static void verifyRejectsAlreadyVerified() {
        System.runAs(otpUser()) {
            VS_OtpService.issue(MOBILE);
            VS_OtpService.verify(MOBILE, VS_OtpStubProvider.TEST_CODE);

            Boolean threw = false;
            Test.startTest();
            try {
                VS_OtpService.verify(MOBILE, VS_OtpStubProvider.TEST_CODE);
            } catch (VS_OtpException e) {
                threw = true;
                System.assertEquals(VS_OtpException.ALREADY_VERIFIED, e.code, 'Re-verify should be ALREADY_VERIFIED');
            }
            Test.stopTest();
            System.assert(threw, 'Re-verifying a verified challenge should throw');
        }
    }

    // ---- 7. provider seam is swappable (A-004) -------------------------------------------------------
    @IsTest
    static void providerSeamIsSwappable() {
        System.runAs(otpUser()) {
            VS_OtpService.provider = new FakeProvider();

            Test.startTest();
            VS_OtpService.issue(MOBILE);
            Boolean result = VS_OtpService.verify(MOBILE, FAKE_CODE);
            Test.stopTest();

            System.assertEquals(true, result, 'A swapped-in provider should work with zero service change');
            // The fixed stub code must NOT equal the fake provider's code — proves the swap is meaningful.
            System.assertNotEquals(FAKE_CODE, VS_OtpStubProvider.TEST_CODE,
                'Fake and stub codes differ, so the swap is meaningful');
        }
    }

    /** A stand-in gateway returning a different fixed code — proves VS_IOtpProvider is honoured (A-004). */
    private class FakeProvider implements VS_IOtpProvider {
        public String issue(String mobile) {
            return FAKE_CODE;
        }
    }
}
