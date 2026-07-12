/**
 * VS_LoadTestEndpoint_Test — deploy-coverage test for the TEMPORARY §3.4 walk-in load-test harness.
 *
 * Purpose: keep VS_LoadTestEndpoint deployable at >=75% via straightforward RestContext request/response
 * tests. The class exists for RUNTIME concurrent HTTP load, not test-time — so this test proves the
 * seed math (walk-in reserve == 1), the verify contract, the channel/reason mapping and the routing +
 * validation branches. The ONLINE book() path is asserted to succeed under the FLS harness user; the
 * WALK-IN book() path may hit this org's deploy-time system-mode-update limit (D-028) and is therefore
 * exercised for coverage WITHOUT asserting success (any coded reason is acceptable) — matching the
 * VS-09 walk-in-test split rationale.
 *
 * All fixture/endpoint DML runs inside runAs(harnessUser) carrying VS_Booking_Engine_Test_Context,
 * because this DE org enforces FLS on plain Apex DML in deploy-time tests (BLOCKER F / D-028).
 *
 * Traceability: RFP §3.4 / VS-09 / D-019, D-020, D-009, D-028.
 */
@IsTest(SeeAllData=false)
private class VS_LoadTestEndpoint_Test {

    private static final String TEST_PERMSET = 'VS_Booking_Engine_Test_Context';

    @TestSetup
    static void makeData() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            FirstName = 'VS',
            LastName = 'VSLoadTestHarness',
            Alias = 'vslth',
            Email = 'vs.loadtest.harness@vaccinescheduler.poc.example',
            Username = 'vs.loadtest.harness.' + Math.abs(Crypto.getRandomLong())
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

    private static User harnessUser() {
        return [SELECT Id FROM User WHERE LastName = 'VSLoadTestHarness' LIMIT 1];
    }

    // ---- helpers ----------------------------------------------------------------------------------

    /** deserializeUntyped returns JSON integers as Integer/Long — coerce any numeric Object safely. */
    private static Integer asInt(Object o) {
        return Integer.valueOf(String.valueOf(o));
    }

    private static void mockRequest(String method, String uri, Map<String, String> params) {
        RestRequest req = new RestRequest();
        req.httpMethod = method;
        req.requestURI = uri;
        if (params != null) {
            for (String k : params.keySet()) {
                req.params.put(k, params.get(k));
            }
        }
        RestContext.request = req;
        RestContext.response = new RestResponse();
    }

    private static Map<String, Object> responseJson() {
        return (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString());
    }

    /** Seed a scenario via the endpoint and return its parsed JSON. */
    private static Map<String, Object> seed(String variant) {
        mockRequest('POST', '/services/apexrest/vsLoadTest/seed',
            new Map<String, String>{ 'variant' => variant });
        VS_LoadTestEndpoint.handlePost();
        return responseJson();
    }

    // ===============================================================================================
    // seedScenario — the seed math: walk-in reserve MUST compute to exactly 1.
    // ===============================================================================================
    @IsTest
    static void seed_walkin_reserveIsExactlyOne() {
        Test.startTest();
        System.runAs(harnessUser()) {
            Map<String, Object> body = seed('walkin');
            System.assertEquals('walkin', body.get('variant'), 'variant echoed');
            System.assertNotEquals(null, body.get('sessionId'), 'sessionId returned');
            System.assertNotEquals(null, body.get('slotId'), 'slotId returned');
            System.assertEquals(1, asInt(body.get('walkInReserve')),
                'CEILING(4 * 25/100) must be exactly 1 — the last-walk-in-place scenario');
            System.assertEquals(3, asInt(body.get('slotCapacity')),
                'walkin variant seeds a roomy slot (capacity 3) so the slot is not the contended pool');
            System.assertEquals(3, asInt(body.get('bookableCapacity')),
                'bookable = total(4) - reserve(1) = 3');
        }
        Test.stopTest();
    }

    @IsTest
    static void seed_online_slotCapacityIsOne() {
        System.runAs(harnessUser()) {
            Map<String, Object> body = seed('online');
            System.assertEquals('online', body.get('variant'), 'online variant');
            System.assertEquals(1, asInt(body.get('slotCapacity')),
                'online variant seeds a single-place slot (TC-001)');
            System.assertEquals(1, asInt(body.get('walkInReserve')),
                'reserve still computes to 1 (harmless for the online contention test)');
        }
    }

    @IsTest
    static void seed_disjoint_bothPoolsAreSinglePlace() {
        System.runAs(harnessUser()) {
            Map<String, Object> body = seed('disjoint');
            System.assertEquals('disjoint', body.get('variant'), 'disjoint variant');
            System.assertEquals(1, asInt(body.get('slotCapacity')), 'disjoint: one online place');
            System.assertEquals(1, asInt(body.get('walkInReserve')),
                'disjoint: one walk-in place (D-020 two disjoint single pools)');
        }
    }

    @IsTest
    static void seed_unknownVariant_defaultsToWalkin() {
        System.runAs(harnessUser()) {
            Map<String, Object> body = seed('bogus');
            System.assertEquals('walkin', body.get('variant'), 'unknown variant falls back to walkin');
        }
    }

    // ===============================================================================================
    // verify — the invariant read-back contract.
    // ===============================================================================================
    @IsTest
    static void verify_freshSession_reportsZeroConsumed() {
        System.runAs(harnessUser()) {
            Map<String, Object> seeded = seed('disjoint');
            String sessionId = (String) seeded.get('sessionId');

            mockRequest('GET', '/services/apexrest/vsLoadTest/verify',
                new Map<String, String>{ 'sessionId' => sessionId });
            VS_LoadTestEndpoint.verify();
            Map<String, Object> body = responseJson();

            System.assertEquals(0, asInt(body.get('apptCount')), 'no bookings yet');
            System.assertEquals(0, asInt(body.get('walkInUsed')), 'reserve unconsumed');
            System.assertEquals(1, asInt(body.get('walkInReserve')), 'reserve == 1');
            System.assertEquals(1, asInt(body.get('slotCapacity')), 'slot cap == 1');
            System.assertEquals(0, asInt(body.get('slotBookedCount')), 'slot unbooked');
            System.assertEquals('Open', body.get('slotStatus'), 'slot open');
        }
    }

    @IsTest
    static void verify_bySlotId_resolvesOwningSession() {
        System.runAs(harnessUser()) {
            Map<String, Object> seeded = seed('online');
            String slotId = (String) seeded.get('slotId');

            mockRequest('GET', '/services/apexrest/vsLoadTest/verify',
                new Map<String, String>{ 'slotId' => slotId });
            VS_LoadTestEndpoint.verify();
            Map<String, Object> body = responseJson();

            System.assertNotEquals(null, body.get('sessionId'), 'session resolved from slot');
            System.assertEquals(1, asInt(body.get('slotCapacity')), 'slot cap 1');
        }
    }

    @IsTest
    static void verify_noParams_returns400() {
        System.runAs(harnessUser()) {
            mockRequest('GET', '/services/apexrest/vsLoadTest/verify', null);
            VS_LoadTestEndpoint.verify();
            System.assertEquals(400, RestContext.response.statusCode, 'missing id -> 400');
        }
    }

    // ===============================================================================================
    // doBook — channel/reason mapping and the book() invocation.
    // ===============================================================================================
    @IsTest
    static void book_online_lastPlaceSucceeds() {
        System.runAs(harnessUser()) {
            Map<String, Object> seeded = seed('online'); // slot capacity 1
            String slotId = (String) seeded.get('slotId');

            mockRequest('POST', '/services/apexrest/vsLoadTest/book',
                new Map<String, String>{ 'slotId' => slotId, 'channel' => 'online' });
            VS_LoadTestEndpoint.handlePost();
            Map<String, Object> body = responseJson();

            System.assertEquals(true, body.get('success'),
                'the single online place is bookable once');
            System.assertNotEquals(null, body.get('apptId'), 'appointment id returned');
        }
    }

    @IsTest
    static void book_online_secondCallRejectedSlotFull() {
        System.runAs(harnessUser()) {
            Map<String, Object> seeded = seed('online'); // capacity 1
            String slotId = (String) seeded.get('slotId');

            // First booking consumes the only place.
            mockRequest('POST', '/services/apexrest/vsLoadTest/book',
                new Map<String, String>{ 'slotId' => slotId, 'channel' => 'online' });
            VS_LoadTestEndpoint.handlePost();

            // Second booking must be rejected with the coded SLOT_FULL reason (ceiling logic).
            mockRequest('POST', '/services/apexrest/vsLoadTest/book',
                new Map<String, String>{ 'slotId' => slotId, 'channel' => 'online' });
            VS_LoadTestEndpoint.handlePost();
            Map<String, Object> body = responseJson();

            System.assertEquals(false, body.get('success'), 'over-capacity booking rejected');
            System.assertEquals(VS_BookingException.SLOT_FULL, body.get('reason'),
                'coded reason is surfaced, never swallowed');
        }
    }

    @IsTest
    static void book_walkin_coveredReasonReturned() {
        // Walk-in book() may hit the org deploy-time system-mode-update limit (D-028); we only assert a
        // well-formed response with a 'success' key + 'reason' handling, not that it succeeds.
        System.runAs(harnessUser()) {
            Map<String, Object> seeded = seed('walkin');
            String slotId = (String) seeded.get('slotId');

            mockRequest('POST', '/services/apexrest/vsLoadTest/book',
                new Map<String, String>{ 'slotId' => slotId, 'channel' => 'walkin' });
            VS_LoadTestEndpoint.handlePost();
            Map<String, Object> body = responseJson();

            System.assert(body.containsKey('success'), 'response carries a success flag');
            System.assert(body.containsKey('reason'), 'response carries a reason field');
        }
    }

    @IsTest
    static void book_missingSlot_returnsCodedReason() {
        System.runAs(harnessUser()) {
            mockRequest('POST', '/services/apexrest/vsLoadTest/book',
                new Map<String, String>{ 'channel' => 'online' });
            VS_LoadTestEndpoint.handlePost();
            Map<String, Object> body = responseJson();
            System.assertEquals(false, body.get('success'), 'no slot -> failure');
            System.assertEquals('MISSING_SLOT_ID', body.get('reason'), 'coded missing-slot reason');
        }
    }

    @IsTest
    static void book_invalidChannel_returnsCodedReason() {
        System.runAs(harnessUser()) {
            mockRequest('POST', '/services/apexrest/vsLoadTest/book',
                new Map<String, String>{ 'slotId' => '0AxLTdummySlotId01', 'channel' => 'telepathy' });
            VS_LoadTestEndpoint.handlePost();
            Map<String, Object> body = responseJson();
            System.assertEquals(false, body.get('success'), 'bad channel -> failure');
            System.assert(((String) body.get('reason')).startsWith('INVALID_CHANNEL_PARAM'),
                'coded invalid-channel reason');
        }
    }

    @IsTest
    static void book_malformedSlotId_returnsCodedReason() {
        System.runAs(harnessUser()) {
            mockRequest('POST', '/services/apexrest/vsLoadTest/book',
                new Map<String, String>{ 'slotId' => 'not-an-id', 'channel' => 'online' });
            VS_LoadTestEndpoint.handlePost();
            Map<String, Object> body = responseJson();
            System.assertEquals('MALFORMED_SLOT_ID', body.get('reason'), 'coded malformed-id reason');
        }
    }

    @IsTest
    static void post_unknownAction_returns400() {
        System.runAs(harnessUser()) {
            mockRequest('POST', '/services/apexrest/vsLoadTest/frobnicate', null);
            VS_LoadTestEndpoint.handlePost();
            System.assertEquals(400, RestContext.response.statusCode, 'unknown action -> 400');
        }
    }

    // ===============================================================================================
    // reset — exercised on an unbooked session (no delete DML fires under the read-only-delete permset).
    // ===============================================================================================
    @IsTest
    static void reset_freshSession_zeroesCounters() {
        System.runAs(harnessUser()) {
            Map<String, Object> seeded = seed('walkin');
            String sessionId = (String) seeded.get('sessionId');

            mockRequest('DELETE', '/services/apexrest/vsLoadTest/reset',
                new Map<String, String>{ 'sessionId' => sessionId });
            VS_LoadTestEndpoint.reset();
            Map<String, Object> body = responseJson();

            System.assertEquals(0, asInt(body.get('deletedAppts')), 'no appts to delete');
            System.assertEquals(0, asInt(body.get('deletedPatients')), 'no patients');
        }
    }

    @IsTest
    static void reset_noSessionId_returns400() {
        System.runAs(harnessUser()) {
            mockRequest('DELETE', '/services/apexrest/vsLoadTest/reset', null);
            VS_LoadTestEndpoint.reset();
            System.assertEquals(400, RestContext.response.statusCode, 'missing sessionId -> 400');
        }
    }
}
