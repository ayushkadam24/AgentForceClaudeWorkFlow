/**
 * VS_NoShowBatch — scheduled, idempotent no-show sweep for the vaccine scheduler (VS-12, EP-06).
 *
 * Marks past, un-attended bookings as no-shows and keeps a per-patient running count:
 *  - AC-1: a VS_Appointment__c with VS_Status__c = 'Booked' whose slot window has already ended
 *    (VS_Slot__r.VS_Slot_End__c < now) and was never checked in (a check-in moves status to
 *    'CheckedIn', so it is out of the 'Booked' scope) is transitioned to 'NoShow', and its
 *    VS_Patient__c.VS_No_Show_Count__c is incremented by 1.
 *  - AC-2 (IDEMPOTENT): the start() scope selects ONLY VS_Status__c = 'Booked' rows, so a row that
 *    has already been flipped to 'NoShow' is excluded from every subsequent run — re-running the
 *    batch never double-increments. Only a genuine Booked -> NoShow transition counts.
 *  - AC-3 (BULK, 200+): no SOQL/DML inside any loop. Per execute() chunk the class issues a CONSTANT
 *    number of statements regardless of scope size: 1 SOQL (re-read patient counts) + 2 DML (one
 *    appointment update, one patient update). Per-patient increments are aggregated in a Map and
 *    applied as ONE patient DML per chunk — a patient is NEVER updated inside the appointment loop.
 *
 * ATOMICITY: the appointment transition DML and the patient increment DML run in the same execute()
 * transaction with all-or-none semantics. If the patient update fails, the appointment transition
 * rolls back with it, so the still-Booked rows are re-selected on the next run — no lost or double
 * increment. Ordering of the two DMLs is therefore irrelevant to the AC-2 guarantee.
 *
 * SECURITY: with sharing; CRUD/FLS enforced via WITH USER_MODE (SOQL) and AccessLevel.USER_MODE
 * (DML). The scheduling/running user must therefore hold edit access to VS_Appointment__c.VS_Status__c
 * and VS_Patient__c.VS_No_Show_Count__c AND be able to see the appointments to sweep. No production
 * role permset grants this today (same class of gap as A-018) — see the review packet's manual steps.
 *
 * Schedulable-wireable:
 *   System.schedule('VS No-Show Sweep', '0 30 1 * * ?', new VS_NoShowBatch());
 *
 * Traceability: REQ-017 (no-show capture), AC-1/2/3 of VS-12 / EP-06 / D-020 (plain writable counter),
 * D-028 (deploy-time FLS — test harness runs under a runAs FLS user).
 */
public with sharing class VS_NoShowBatch implements Database.Batchable<SObject>, Database.Stateful, Schedulable {

    private static final String STATUS_BOOKED = 'Booked';
    private static final String STATUS_NO_SHOW = 'NoShow';
    private static final Integer DEFAULT_SCOPE_SIZE = 200;

    private final Integer configuredScopeSize;

    // Stateful run metrics, surfaced in finish() (Database.Stateful).
    private Integer appointmentsMarkedNoShow = 0;
    private Integer patientsIncremented = 0;

    /** Default scope size (200) — the AC-3 bulk target. */
    public VS_NoShowBatch() {
        this(DEFAULT_SCOPE_SIZE);
    }

    /**
     * @param scopeSize batch chunk size used when the Schedulable path launches the batch;
     *                  null or <= 0 falls back to the default (200).
     */
    public VS_NoShowBatch(Integer scopeSize) {
        this.configuredScopeSize = (scopeSize == null || scopeSize <= 0) ? DEFAULT_SCOPE_SIZE : scopeSize;
    }

    /**
     * Schedulable entry point — launches the batch. Wire with System.schedule(name, cron, instance).
     * @param sc scheduler context supplied by the platform
     */
    public void execute(SchedulableContext sc) {
        Database.executeBatch(this, this.configuredScopeSize);
    }

    /**
     * Scope = every still-'Booked' appointment whose slot window has already ended. NoShow / CheckedIn /
     * Completed / Cancelled rows are excluded, which is exactly what makes the batch idempotent (AC-2).
     * @param bc batch context
     * @return locator over the due, unattended bookings
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        Datetime nowDt = Datetime.now();
        return Database.getQueryLocator([
            SELECT Id, VS_Patient__c
            FROM VS_Appointment__c
            WHERE VS_Status__c = :STATUS_BOOKED
              AND VS_Slot__r.VS_Slot_End__c != null
              AND VS_Slot__r.VS_Slot_End__c < :nowDt
            WITH USER_MODE
        ]);
    }

    /**
     * Transitions the chunk to 'NoShow' and applies aggregated per-patient increments. Constant
     * statement budget (1 SOQL + 2 DML) irrespective of chunk size — bulkified (AC-3).
     * @param bc    batch context
     * @param scope the due appointments for this chunk
     */
    public void execute(Database.BatchableContext bc, List<VS_Appointment__c> scope) {
        if (scope == null || scope.isEmpty()) {
            return;
        }

        List<VS_Appointment__c> transitions = new List<VS_Appointment__c>();
        Map<Id, Integer> incrementByPatientId = new Map<Id, Integer>();

        for (VS_Appointment__c appt : scope) {
            // Fresh sObject carrying ONLY the written field — never re-save fields the running user may
            // not have FLS on (D-029 lesson from the booking service).
            transitions.add(new VS_Appointment__c(Id = appt.Id, VS_Status__c = STATUS_NO_SHOW));
            if (appt.VS_Patient__c != null) {
                Integer running = incrementByPatientId.get(appt.VS_Patient__c);
                incrementByPatientId.put(appt.VS_Patient__c, (running == null ? 0 : running) + 1);
            }
        }

        // ONE DML for all appointment transitions in this chunk.
        Database.update(transitions, AccessLevel.USER_MODE);
        this.appointmentsMarkedNoShow += transitions.size();

        if (!incrementByPatientId.isEmpty()) {
            // ONE SOQL to read current counts for every affected patient (no query in the loop above).
            List<VS_Patient__c> patientUpdates = new List<VS_Patient__c>();
            for (VS_Patient__c pat : [
                    SELECT Id, VS_No_Show_Count__c
                    FROM VS_Patient__c
                    WHERE Id IN :incrementByPatientId.keySet()
                    WITH USER_MODE]) {
                Decimal current = (pat.VS_No_Show_Count__c == null) ? 0 : pat.VS_No_Show_Count__c;
                patientUpdates.add(new VS_Patient__c(
                    Id = pat.Id,
                    VS_No_Show_Count__c = current + incrementByPatientId.get(pat.Id)));
            }
            // ONE DML for all patient increments in this chunk — never inside the appointment loop.
            Database.update(patientUpdates, AccessLevel.USER_MODE);
            this.patientsIncremented += patientUpdates.size();
        }
    }

    /**
     * Emits run metrics to the debug log. VS_Error_Log__c is a designed-but-deferred object (design
     * §2.2) not yet on disk, so metrics go to the log for the POC; a later ticket can route them.
     * @param bc batch context
     */
    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO,
            'VS_NoShowBatch complete: appointmentsMarkedNoShow=' + this.appointmentsMarkedNoShow
            + ', patientsIncremented=' + this.patientsIncremented);
    }
}
