/**
 * VS_SlotGenBatch — batch orchestrator for the VS-06 slot-generation engine (EP-02).
 *
 * Selects every VS_Session__c that is Open, within the configurable booking horizon
 * (VS_Setting__mdt.BookingHorizonDays.VS_Value__c, D-008/REQ-013), and not yet slotted, then
 * delegates the actual VS_Slot__c construction to VS_SlotGenerationService. All generation rules
 * (granularity D-008, holiday/drive-day D-018, even distribution D-023/A-005) live in the service —
 * this class is orchestration only.
 *
 * Bulk-safe (REQ-062): the service issues a fixed number of SOQL/DML statements per execute()
 * regardless of scope size, so a 250+ session chunk completes with no SOQL/DML-in-loop and no
 * governor errors. Idempotent by construction — the start() query excludes sessions that already
 * have slots (Id NOT IN (SELECT VS_Session__c FROM VS_Slot__c)), so a re-run never double-generates.
 *
 * Run (human, on the DE org — D-025):  Database.executeBatch(new VS_SlotGenBatch(), 200);
 *
 * Traceability: REQ-009, REQ-012, REQ-013, REQ-014, REQ-062 / EP-02 / D-008, D-018, D-023.
 */
public with sharing class VS_SlotGenBatch implements Database.Batchable<SObject>, Database.Stateful {

    private final Date horizonStartDate;
    private final Date horizonEndDate;

    // Stateful run metrics (surfaced in finish()).
    private Integer sessionsProcessed = 0;
    private Integer slotsCreated = 0;

    public VS_SlotGenBatch() {
        this.horizonStartDate = Date.today();
        this.horizonEndDate = Date.today().addDays(getBookingHorizonDays());
    }

    /**
     * Eligible sessions: Open, dated between today and the booking horizon inclusive, and not yet
     * slotted. Past-dated sessions are excluded (A-015) — generating bookable slots for a session
     * already in the past is pointless; only the "beyond horizon" bound is a stated AC.
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        Date startDate = this.horizonStartDate;
        Date endDate = this.horizonEndDate;
        return Database.getQueryLocator([
            SELECT Id, VS_Session_Date__c, VS_Start_Time__c, VS_End_Time__c,
                   VS_Bookable_Capacity__c, VS_Is_Drive_Day__c, VS_Facility__c, VS_Service__c
            FROM VS_Session__c
            WHERE VS_Status__c = 'Open'
              AND VS_Session_Date__c >= :startDate
              AND VS_Session_Date__c <= :endDate
              AND Id NOT IN (SELECT VS_Session__c FROM VS_Slot__c)
            WITH USER_MODE
        ]);
    }

    public void execute(Database.BatchableContext bc, List<VS_Session__c> scope) {
        sessionsProcessed += scope.size();
        slotsCreated += VS_SlotGenerationService.generateForSessions(scope);
    }

    public void finish(Database.BatchableContext bc) {
        // VS_Error_Log__c is a designed-but-deferred object (design §2.2) not yet on disk, so POC
        // run metrics are emitted to the debug log only. A later ticket can route these to
        // VS_Error_Log__c / a notification once that object is built.
        System.debug(LoggingLevel.INFO,
            'VS_SlotGenBatch complete: sessionsProcessed=' + sessionsProcessed
            + ', slotsCreated=' + slotsCreated);
    }

    /**
     * Booking horizon in days from VS_Setting__mdt (D-008/REQ-013). Read via the cache-backed,
     * FLS-free VS_Setting__mdt.getInstance(DeveloperName) rather than SOQL: SOQL on a Custom Metadata
     * Type is rejected on a USER_MODE/runAs path in this org, and getInstance is the SF-recommended read
     * anyway. getInstance returns null if the record is absent — falls back to the design default (14).
     */
    private static Integer getBookingHorizonDays() {
        VS_Setting__mdt setting = VS_Setting__mdt.getInstance('BookingHorizonDays');
        if (setting != null && setting.VS_Value__c != null) {
            return setting.VS_Value__c.intValue();
        }
        return 14;
    }
}
