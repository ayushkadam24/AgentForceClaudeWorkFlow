/**
 * VS_SlotGenerationService — slot-construction logic for the VS-06 slot-generation engine (EP-02).
 *
 * Owns the actual construction of VS_Slot__c rows from VS_Session__c sessions. VS_SlotGenBatch
 * (the Database.Batchable orchestrator) only selects eligible sessions and delegates here, so the
 * generation rules live in ONE service rather than being scattered inside a batch class.
 *
 * Design references:
 *  - D-008 : slot granularity is CONFIGURABLE (per-service VS_Service__c.VS_Slot_Granularity_Mins__c,
 *            falling back to VS_Setting__mdt.DefaultSlotGranularityMins.VS_Value__c) — never a hardcoded 15.
 *  - D-018 : a VS_Is_Drive_Day__c session generates slots even on a VS_Holiday__c-closed date;
 *            a normal session on a holiday date generates NO slots.
 *  - D-023 / A-005 : EVEN capacity distribution across slots, remainder to the EARLIEST slots, such
 *            that sum(VS_Slot__c.VS_Capacity__c) == VS_Session__c.VS_Bookable_Capacity__c EXACTLY.
 *            **BINDING (drift-check radar):** that distribution lives in exactly ONE private method,
 *            distributeCapacity(...), so a future switch to weighted/front-loaded distribution is a
 *            single-method swap, not a redesign. Do not inline it elsewhere.
 *
 * Bulk posture (REQ-062): all SOQL/DML is issued OUTSIDE the per-session loop — services and holidays
 * are read once into Maps/Sets, slots are accumulated into one List and inserted with a single DML.
 * Handles 250+ sessions in a single execute() without governor errors or SOQL/DML-in-loop.
 *
 * Traceability: REQ-009, REQ-012, REQ-013, REQ-014, REQ-062 / EP-02 / D-008, D-018, D-023.
 */
public with sharing class VS_SlotGenerationService {

    // Absolute last-resort fallback, used ONLY if the VS_Setting__mdt config record is somehow
    // absent AND a service carries no per-service granularity. Mirrors D-008's agreed default so the
    // service degrades safely rather than dividing by zero; it is NOT the source of truth (config is).
    @TestVisible
    private static final Integer DEFAULT_GRANULARITY_FALLBACK = 15;

    /**
     * Generate and insert VS_Slot__c rows for a batch of sessions. Bulk-safe: 3 SOQL + 1 DML
     * regardless of how many sessions are passed (per-service granularity, holidays, config default =
     * 3 SOQL; a single slot insert = 1 DML). Sessions must be queried WITH the fields listed in
     * VS_SlotGenBatch.start() (dates, times, VS_Bookable_Capacity__c, drive-day, facility, service).
     *
     * @param sessions eligible sessions (Open, not yet slotted, within the booking horizon)
     * @return number of VS_Slot__c rows inserted
     */
    public static Integer generateForSessions(List<VS_Session__c> sessions) {
        if (sessions == null || sessions.isEmpty()) {
            return 0;
        }

        // ---- 1. Gather lookup keys in memory (no SOQL in this loop) ----
        Set<Id> serviceIds = new Set<Id>();
        Set<Id> facilityIds = new Set<Id>();
        Set<Date> sessionDates = new Set<Date>();
        for (VS_Session__c s : sessions) {
            if (s.VS_Service__c != null)  { serviceIds.add(s.VS_Service__c); }
            if (s.VS_Facility__c != null) { facilityIds.add(s.VS_Facility__c); }
            if (s.VS_Session_Date__c != null) { sessionDates.add(s.VS_Session_Date__c); }
        }

        // ---- 2. One SOQL: per-service granularity (D-008) ----
        Map<Id, Integer> granularityByService = new Map<Id, Integer>();
        for (VS_Service__c svc : [
                SELECT Id, VS_Slot_Granularity_Mins__c
                FROM VS_Service__c
                WHERE Id IN :serviceIds
                WITH USER_MODE]) {
            if (svc.VS_Slot_Granularity_Mins__c != null) {
                granularityByService.put(svc.Id, svc.VS_Slot_Granularity_Mins__c.intValue());
            }
        }

        // ---- 3. One SOQL: holidays for these facilities+dates -> facility|date key set (D-018) ----
        Set<String> holidayKeys = new Set<String>();
        for (VS_Holiday__c h : [
                SELECT VS_Facility__c, VS_Holiday_Date__c
                FROM VS_Holiday__c
                WHERE VS_Facility__c IN :facilityIds
                  AND VS_Holiday_Date__c IN :sessionDates
                WITH USER_MODE]) {
            holidayKeys.add(holidayKey(h.VS_Facility__c, h.VS_Holiday_Date__c));
        }

        // ---- 4. One SOQL (Custom Metadata): org-wide default granularity fallback (D-008) ----
        Integer defaultGranularity = getConfiguredDefaultGranularity();

        // ---- 5. Build every slot in memory (NO SOQL/DML in this loop) ----
        List<VS_Slot__c> slotsToInsert = new List<VS_Slot__c>();
        for (VS_Session__c s : sessions) {
            // D-018 holiday/drive-day rule.
            Boolean isHoliday = holidayKeys.contains(holidayKey(s.VS_Facility__c, s.VS_Session_Date__c));
            if (isHoliday && s.VS_Is_Drive_Day__c != true) {
                continue; // normal session on a holiday date -> no slots
            }

            Integer granularity = granularityByService.containsKey(s.VS_Service__c)
                ? granularityByService.get(s.VS_Service__c)
                : defaultGranularity;

            // Robustness: a genuinely un-slottable session (no/invalid window, window shorter than
            // one slot) is SKIPPED so one bad session never aborts the whole batch. The same math
            // (computeSlotCount) backs the strict buildSlots() guard below, so there is no drift.
            if (computeSlotCount(s, granularity) <= 0) {
                continue;
            }

            slotsToInsert.addAll(buildSlots(s, granularity));
        }

        // ---- 6. One DML for the entire scope, FLS/CRUD enforced (rules/20) ----
        if (!slotsToInsert.isEmpty()) {
            insert as user slotsToInsert;
        }
        return slotsToInsert.size();
    }

    /**
     * Build (but do NOT insert) the VS_Slot__c rows for a single session at a given granularity.
     * Strict: throws VS_SlotGenException on invalid input so the contract is unit-testable in
     * isolation. generateForSessions() pre-validates via computeSlotCount() so it never trips these
     * guards in the batch path.
     *
     * @throws VS_SlotGenException INVALID_GRANULARITY / INVALID_WINDOW
     */
    @TestVisible
    public static List<VS_Slot__c> buildSlots(VS_Session__c session, Integer granularityMins) {
        if (granularityMins == null || granularityMins <= 0) {
            throw new VS_SlotGenException('INVALID_GRANULARITY');
        }
        Integer slotCount = computeSlotCount(session, granularityMins);
        if (slotCount <= 0) {
            throw new VS_SlotGenException('INVALID_WINDOW');
        }

        Integer bookable = session.VS_Bookable_Capacity__c == null
            ? 0
            : session.VS_Bookable_Capacity__c.intValue();
        List<Integer> capacities = distributeCapacity(bookable, slotCount);

        List<VS_Slot__c> slots = new List<VS_Slot__c>();
        Datetime cursor = session.VS_Start_Time__c;
        for (Integer i = 0; i < slotCount; i++) {
            Datetime slotEnd = cursor.addMinutes(granularityMins);
            slots.add(new VS_Slot__c(
                VS_Session__c    = session.Id,
                VS_Slot_Start__c = cursor,
                VS_Slot_End__c   = slotEnd,
                VS_Capacity__c   = capacities[i],
                VS_Booked_Count__c = 0,
                VS_Status__c     = 'Open'));
            cursor = slotEnd;
        }
        return slots;
    }

    /**
     * D-023 (BINDING — DRIFT-CHECK RADAR) / A-005: the EVEN slot-capacity distribution.
     *
     * This is the ONE and ONLY place the split lives. Even share to every slot; the remainder is
     * assigned to the EARLIEST slots (index 0..remainder-1) so that sum(result) == bookableCapacity
     * EXACTLY. Swapping the POC's even split for a later weighted/front-loaded scheme is a change to
     * THIS METHOD ONLY — do not inline this arithmetic anywhere else.
     *
     * @param bookableCapacity the session's online-bookable total (VS_Bookable_Capacity__c)
     * @param slotCount        number of slots to spread it across (> 0)
     * @return per-slot capacities, earliest-first; size == slotCount; sum == bookableCapacity
     */
    private static List<Integer> distributeCapacity(Integer bookableCapacity, Integer slotCount) {
        List<Integer> perSlot = new List<Integer>();
        if (slotCount == null || slotCount <= 0) {
            return perSlot;
        }
        Integer capacity  = (bookableCapacity == null || bookableCapacity < 0) ? 0 : bookableCapacity;
        Integer base      = capacity / slotCount;
        Integer remainder = Math.mod(capacity, slotCount);
        for (Integer i = 0; i < slotCount; i++) {
            perSlot.add(base + (i < remainder ? 1 : 0)); // remainder -> earliest slots (A-005)
        }
        return perSlot;
    }

    /**
     * Whole-slot count for a session at a granularity: floor((end - start) / granularity).
     * Returns 0 (never throws) for any un-slottable session so the batch orchestration can skip it.
     * Single source of truth for the count math (used by both generateForSessions and buildSlots).
     */
    private static Integer computeSlotCount(VS_Session__c session, Integer granularityMins) {
        if (granularityMins == null || granularityMins <= 0) { return 0; }
        if (session.VS_Start_Time__c == null || session.VS_End_Time__c == null) { return 0; }
        if (session.VS_End_Time__c <= session.VS_Start_Time__c) { return 0; }
        Integer windowMins = ((session.VS_End_Time__c.getTime()
            - session.VS_Start_Time__c.getTime()) / 60000L).intValue();
        return windowMins / granularityMins;
    }

    /**
     * Reads the org-wide default slot granularity from VS_Setting__mdt (D-008). Custom Metadata is
     * always readable (no FLS surface), so no USER_MODE clause is applied here.
     */
    private static Integer getConfiguredDefaultGranularity() {
        List<VS_Setting__mdt> settings = [
            SELECT VS_Value__c
            FROM VS_Setting__mdt
            WHERE DeveloperName = 'DefaultSlotGranularityMins'
            LIMIT 1];
        if (!settings.isEmpty() && settings[0].VS_Value__c != null) {
            return settings[0].VS_Value__c.intValue();
        }
        return DEFAULT_GRANULARITY_FALLBACK;
    }

    private static String holidayKey(Id facilityId, Date d) {
        return String.valueOf(facilityId) + '|' + (d == null ? '' : String.valueOf(d));
    }
}
