/**
 * VS_LoadTestEndpoint — TEMPORARY QA §3.4 walk-in load-test harness (human-approved).
 *
 * NOT part of F-001. Deployed for the load test only, REMOVED immediately after (see
 * 02-build/deployments.md). Wraps VS_BookingService.book() so genuinely-concurrent external HTTP can
 * prove the FOR UPDATE walk-in serialization that deploy-time tests cannot (D-028).
 *
 * === Why a DEPLOYED endpoint (already diagnosed — not re-litigated here) ===
 * On this DE org the deploying admin has NO FLS on the optional/formula/required VS_ fields, and
 * anonymous Apex compiles field references against the RUNNING USER's FLS — so any anonymous block
 * referencing VS_Walk_In_Reserve_Count__c / VS_Walk_In_Used_Count__c fails to COMPILE ("No such
 * column"). A DEPLOYED class compiles at deploy time (fields visible) and its system-mode SOQL runs
 * regardless of caller FLS. This class therefore seeds + invokes book() as admin with NO harness-user
 * session. book()'s lock query is plain system-mode SOQL; only the appointment insert is USER_MODE.
 *
 * === `without sharing` + system-mode is DELIBERATE ===
 * The admin caller has no FLS on the capacity fields; system-mode (plain) SOQL/DML is the whole point.
 * This class ONLY orchestrates — seed data + call VS_BookingService.book() + read back counters. It
 * does NOT modify VS_BookingService or any production class. NO AADHAAR: no 12-digit identifiers are
 * created anywhere (fictional 10-digit mobiles + synthetic match keys only, rules/10).
 *
 * === Seed math — how walk-in reserve == 1 is GUARANTEED ===
 * VS_Session__c.VS_Walk_In_Reserve_Count__c is a FORMULA:
 *     CEILING(VS_Total_Capacity__c * WalkInReservePct / 100),  WalkInReservePct = 25 (VS-02 / D-009).
 * With VS_Total_Capacity__c = 4:  CEILING(4 * 25 / 100) = CEILING(1.0) = 1  → reserve == 1 exactly,
 * VS_Bookable_Capacity__c = 4 - 1 = 3. (Total 1/2/3 also yield 1; 4 is used so the online pool is
 * non-trivial and reserve is comfortably NOT pre-consumed — VS_Walk_In_Used_Count__c defaults to 0.)
 * Because reserve is a formula, the harness cannot set it directly — it sets VS_Total_Capacity__c and
 * the platform computes reserve. verify returns the ACTUAL computed walkInReserve so the load driver
 * asserts against the real value, never an assumption.
 *
 * REST contract (base: /services/apexrest/vsLoadTest):
 *   POST   /vsLoadTest/seed?variant=walkin|online|disjoint  -> { sessionId, slotId, variant,
 *                                                                slotCapacity, walkInReserve }
 *   POST   /vsLoadTest/book?slotId=..&channel=online|walkin  -> { success, apptId, reason }
 *   GET    /vsLoadTest/verify?sessionId=..  (or ?slotId=..)  -> { apptCount, slotBookedCount,
 *                                                slotCapacity, walkInUsed, walkInReserve, slotStatus }
 *   DELETE /vsLoadTest/reset?sessionId=..                    -> { deletedAppts, deletedPatients }
 *
 * Traceability: RFP §3.4 / QA TC-001 (online cap=1), TC-002 (walk-in reserve=1), TC-003 (disjoint
 * pools, D-020) / VS-09 / D-019, D-020, D-009, D-028.
 */
@RestResource(urlMapping='/vsLoadTest/*')
global without sharing class VS_LoadTestEndpoint {

    // WalkIn is proven separately from the slot pool (D-020). book() channel vocabulary is
    // Portal|Chat|Staff|WalkIn; the harness exposes the friendlier online|walkin and maps here.
    private static final String CHANNEL_ONLINE_APEX = 'Portal';
    private static final String CHANNEL_WALKIN_APEX = 'WalkIn';

    // Total capacity that makes CEILING(Total * 25/100) == 1 (see class ApexDoc seed math).
    private static final Integer TOTAL_CAPACITY_RESERVE_ONE = 4;

    // ======================================================================================
    // POST — routes to seedScenario or doBook by the trailing URL segment (or ?action=).
    // ======================================================================================
    @HttpPost
    global static void handlePost() {
        String action = actionSegment();
        if (action == 'seed') {
            seedScenario();
        } else if (action == 'book') {
            doBook();
        } else {
            writeJson(400, new Map<String, Object>{
                'error' => 'Unknown POST action "' + action + '". Use /vsLoadTest/seed or /vsLoadTest/book.'
            });
        }
    }

    /**
     * Create ONE fresh, self-contained scenario: Facility + Service + active Facility_Service +
     * Open Session (Total_Capacity=4 -> walk-in reserve == 1) + one Slot. Fresh session per call so the
     * driver can simply re-seed between the 3 repeats (simpler + safer than reset). Fictional data only.
     *
     * variant (query param, default walkin):
     *   walkin   — slot capacity 3 (roomy); the contended place is the SINGLE walk-in reserve place.
     *   online   — slot capacity 1;  the contended place is the SINGLE online slot place (TC-001).
     *   disjoint — slot capacity 1 AND reserve 1; two disjoint single places, one per pool (TC-003).
     */
    private static void seedScenario() {
        String variant = paramOrDefault('variant', 'walkin').toLowerCase();
        Integer slotCapacity;
        if (variant == 'online' || variant == 'disjoint') {
            slotCapacity = 1;
        } else {
            variant = 'walkin';
            slotCapacity = 3;
        }

        String stamp = String.valueOf(Datetime.now().getTime());

        VS_Facility__c facility = new VS_Facility__c(
            Name = 'LT Facility ' + stamp,
            VS_Facility_Type__c = 'PHC',
            VS_Is_Active__c = true,
            VS_Helpline_Number__c = '104'
        );
        insert facility;

        VS_Service__c service = new VS_Service__c(
            Name = 'LT Vaccination ' + stamp,
            VS_Service_Type__c = 'Vaccination',
            VS_Is_Active__c = true
        );
        insert service;

        insert new VS_Facility_Service__c(
            VS_Facility__c = facility.Id,
            VS_Service__c = service.Id,
            VS_Is_Active__c = true
        );

        Datetime startTime = Datetime.now().addDays(1);
        Datetime endTime = startTime.addHours(1);

        VS_Session__c session = new VS_Session__c(
            VS_Facility__c = facility.Id,
            VS_Service__c = service.Id,
            VS_Session_Date__c = Date.today().addDays(1),
            VS_Start_Time__c = startTime,
            VS_End_Time__c = endTime,
            VS_Total_Capacity__c = TOTAL_CAPACITY_RESERVE_ONE,  // -> reserve == 1 (formula, see ApexDoc)
            VS_Status__c = 'Open'
            // VS_Walk_In_Used_Count__c defaults to 0 -> reserve NOT pre-consumed.
        );
        insert session;

        VS_Slot__c slot = new VS_Slot__c(
            VS_Session__c = session.Id,
            VS_Slot_Start__c = startTime,
            VS_Slot_End__c = endTime,
            VS_Capacity__c = slotCapacity,
            VS_Booked_Count__c = 0,
            VS_Status__c = 'Open'
        );
        insert slot;

        // Read back the platform-computed reserve so the driver asserts against the ACTUAL value.
        VS_Session__c seeded = [
            SELECT VS_Walk_In_Reserve_Count__c, VS_Bookable_Capacity__c
            FROM VS_Session__c WHERE Id = :session.Id LIMIT 1
        ];

        writeJson(200, new Map<String, Object>{
            'sessionId' => session.Id,
            'slotId' => slot.Id,
            'variant' => variant,
            'slotCapacity' => slotCapacity,
            'walkInReserve' => seeded.VS_Walk_In_Reserve_Count__c,
            'bookableCapacity' => seeded.VS_Bookable_Capacity__c
        });
    }

    /**
     * Create a FRESH VS_Patient__c per call (so N concurrent calls contend as N DISTINCT patients),
     * then call VS_BookingService.book(patientId, slotId, currentUser, apexChannel). Never swallows —
     * returns the VS_BookingException coded reason (SLOT_FULL / WALKIN_RESERVE_FULL / ...) on failure.
     *
     * params: slotId (required), channel = online | walkin (default online).
     */
    private static void doBook() {
        String slotIdRaw = param('slotId');
        String channelRaw = paramOrDefault('channel', 'online').toLowerCase();

        if (String.isBlank(slotIdRaw)) {
            writeJson(400, new Map<String, Object>{
                'success' => false, 'apptId' => null, 'reason' => 'MISSING_SLOT_ID'
            });
            return;
        }

        String apexChannel;
        if (channelRaw == 'walkin') {
            apexChannel = CHANNEL_WALKIN_APEX;
        } else if (channelRaw == 'online') {
            apexChannel = CHANNEL_ONLINE_APEX;
        } else {
            writeJson(400, new Map<String, Object>{
                'success' => false, 'apptId' => null,
                'reason' => 'INVALID_CHANNEL_PARAM (' + channelRaw + ')'
            });
            return;
        }

        Id slotId;
        try {
            slotId = (Id) slotIdRaw;
        } catch (Exception e) {
            writeJson(400, new Map<String, Object>{
                'success' => false, 'apptId' => null, 'reason' => 'MALFORMED_SLOT_ID'
            });
            return;
        }

        // Fresh, fictional, NON-Aadhaar patient per call — 10-digit mobile, synthetic match key.
        VS_Patient__c patient = newFictionalPatient();
        insert patient;

        try {
            Id apptId = VS_BookingService.book(patient.Id, slotId, UserInfo.getUserId(), apexChannel);
            writeJson(200, new Map<String, Object>{
                'success' => true, 'apptId' => apptId, 'reason' => null
            });
        } catch (VS_BookingException be) {
            // be.getMessage() is the STABLE coded reason (SLOT_FULL / WALKIN_RESERVE_FULL / etc.).
            writeJson(200, new Map<String, Object>{
                'success' => false, 'apptId' => null, 'reason' => be.getMessage()
            });
        } catch (Exception ex) {
            // Any non-booking failure is surfaced verbatim — never swallowed.
            writeJson(200, new Map<String, Object>{
                'success' => false, 'apptId' => null,
                'reason' => 'UNEXPECTED:' + ex.getTypeName() + ':' + ex.getMessage()
            });
        }
    }

    // ======================================================================================
    // GET — verify the §3.4 invariant from system-mode SOQL.
    // ======================================================================================
    @HttpGet
    global static void verify() {
        String sessionIdRaw = param('sessionId');
        String slotIdRaw = param('slotId');

        Id sessionId;
        Id slotId;
        if (String.isNotBlank(sessionIdRaw)) {
            sessionId = safeId(sessionIdRaw);
        }
        if (String.isNotBlank(slotIdRaw)) {
            slotId = safeId(slotIdRaw);
        }
        // Allow verify by slotId alone: resolve its owning session.
        if (sessionId == null && slotId != null) {
            List<VS_Slot__c> s = [SELECT VS_Session__c FROM VS_Slot__c WHERE Id = :slotId LIMIT 1];
            if (!s.isEmpty()) {
                sessionId = s[0].VS_Session__c;
            }
        }
        if (sessionId == null) {
            writeJson(400, new Map<String, Object>{
                'error' => 'verify requires ?sessionId=.. or a resolvable ?slotId=..'
            });
            return;
        }

        VS_Session__c session = [
            SELECT VS_Walk_In_Used_Count__c, VS_Walk_In_Reserve_Count__c, VS_Status__c
            FROM VS_Session__c WHERE Id = :sessionId LIMIT 1
        ];

        Integer apptCount = [SELECT COUNT() FROM VS_Appointment__c WHERE VS_Session__c = :sessionId];

        // Slot metrics: use the explicit slot if given, else aggregate the session's slots.
        Decimal slotBookedCount = 0;
        Decimal slotCapacity = 0;
        String slotStatus = null;
        List<VS_Slot__c> slots = (slotId != null)
            ? [SELECT VS_Booked_Count__c, VS_Capacity__c, VS_Status__c
               FROM VS_Slot__c WHERE Id = :slotId]
            : [SELECT VS_Booked_Count__c, VS_Capacity__c, VS_Status__c
               FROM VS_Slot__c WHERE VS_Session__c = :sessionId];
        for (VS_Slot__c sl : slots) {
            slotBookedCount += (sl.VS_Booked_Count__c == null ? 0 : sl.VS_Booked_Count__c);
            slotCapacity += (sl.VS_Capacity__c == null ? 0 : sl.VS_Capacity__c);
        }
        if (slots.size() == 1) {
            slotStatus = slots[0].VS_Status__c;
        }

        writeJson(200, new Map<String, Object>{
            'sessionId' => sessionId,
            'apptCount' => apptCount,
            'slotBookedCount' => slotBookedCount,
            'slotCapacity' => slotCapacity,
            'walkInUsed' => session.VS_Walk_In_Used_Count__c,
            'walkInReserve' => session.VS_Walk_In_Reserve_Count__c,
            'slotStatus' => slotStatus,
            'sessionStatus' => session.VS_Status__c
        });
    }

    // ======================================================================================
    // DELETE — optional reset between repeats (prefer re-seeding a fresh session instead).
    // ======================================================================================
    @HttpDelete
    global static void reset() {
        String sessionIdRaw = param('sessionId');
        Id sessionId = String.isNotBlank(sessionIdRaw) ? safeId(sessionIdRaw) : null;
        if (sessionId == null) {
            writeJson(400, new Map<String, Object>{ 'error' => 'reset requires ?sessionId=..' });
            return;
        }

        List<VS_Appointment__c> appts = [
            SELECT Id, VS_Patient__c FROM VS_Appointment__c WHERE VS_Session__c = :sessionId
        ];
        Set<Id> patientIds = new Set<Id>();
        for (VS_Appointment__c a : appts) {
            if (a.VS_Patient__c != null) {
                patientIds.add(a.VS_Patient__c);
            }
        }
        Integer deletedAppts = appts.size();
        if (!appts.isEmpty()) {
            delete appts;
        }
        Integer deletedPatients = 0;
        if (!patientIds.isEmpty()) {
            List<VS_Patient__c> pts = [SELECT Id FROM VS_Patient__c WHERE Id IN :patientIds];
            deletedPatients = pts.size();
            if (!pts.isEmpty()) {
                delete pts;
            }
        }

        // Zero the counters + reopen the slots so the same session could be reused if desired.
        List<VS_Slot__c> slots = [
            SELECT Id, VS_Booked_Count__c, VS_Status__c
            FROM VS_Slot__c WHERE VS_Session__c = :sessionId
        ];
        for (VS_Slot__c sl : slots) {
            sl.VS_Booked_Count__c = 0;
            sl.VS_Status__c = 'Open';
        }
        if (!slots.isEmpty()) {
            update slots;
        }
        VS_Session__c session = [
            SELECT Id, VS_Walk_In_Used_Count__c FROM VS_Session__c WHERE Id = :sessionId LIMIT 1
        ];
        session.VS_Walk_In_Used_Count__c = 0;
        update session;

        writeJson(200, new Map<String, Object>{
            'deletedAppts' => deletedAppts,
            'deletedPatients' => deletedPatients
        });
    }

    // ======================================================================================
    // Helpers
    // ======================================================================================

    /** Build a fictional, non-Aadhaar patient (10-digit mobile, synthetic unique match key). */
    private static VS_Patient__c newFictionalPatient() {
        // 10-digit mobile: leading 9 + 9 random digits. 10 digits (NOT a 12-digit Aadhaar).
        String mobile = '9' + leftPadDigits(Math.abs(Crypto.getRandomLong()), 9);
        String uniq = 'LT-' + Datetime.now().getTime() + '-' + Math.abs(Crypto.getRandomInteger());
        return new VS_Patient__c(
            VS_Full_Name__c = 'LoadTest Citizen ' + uniq,
            VS_Date_Of_Birth__c = Date.newInstance(1990, 1, 1),  // required (C1); fictional fixed DOB
            VS_Mobile__c = mobile,
            VS_Match_Key__c = uniq   // unique per call -> never trips the D-017 unique constraint
        );
    }

    /** Left-pad the absolute value of a number to exactly `len` digits (truncating any excess). */
    private static String leftPadDigits(Long value, Integer len) {
        String digits = String.valueOf(Math.abs(value));
        if (digits.length() > len) {
            return digits.substring(digits.length() - len);
        }
        while (digits.length() < len) {
            digits = '0' + digits;
        }
        return digits;
    }

    /** Trailing path segment after /vsLoadTest/ (lowercased), or the ?action= param, else ''. */
    private static String actionSegment() {
        String uri = RestContext.request != null ? RestContext.request.requestURI : null;
        if (String.isNotBlank(uri)) {
            List<String> parts = uri.split('/');
            if (!parts.isEmpty()) {
                String last = parts[parts.size() - 1];
                if (String.isNotBlank(last) && last.toLowerCase() != 'vsloadtest') {
                    return last.toLowerCase();
                }
            }
        }
        String actionParam = param('action');
        return actionParam == null ? '' : actionParam.toLowerCase();
    }

    /** A request query param, or null. */
    private static String param(String key) {
        if (RestContext.request == null || RestContext.request.params == null) {
            return null;
        }
        return RestContext.request.params.get(key);
    }

    private static String paramOrDefault(String key, String fallback) {
        String v = param(key);
        return String.isBlank(v) ? fallback : v;
    }

    /** Coerce a raw string to an Id, returning null (never throwing) on a malformed value. */
    private static Id safeId(String raw) {
        try {
            return (Id) raw;
        } catch (Exception e) {
            return null;
        }
    }

    /** Serialize `body` as JSON onto the REST response with the given HTTP status. */
    private static void writeJson(Integer statusCode, Map<String, Object> body) {
        RestResponse res = RestContext.response;
        if (res == null) {
            return;
        }
        res.statusCode = statusCode;
        res.addHeader('Content-Type', 'application/json');
        res.responseBody = Blob.valueOf(JSON.serialize(body));
    }
}
