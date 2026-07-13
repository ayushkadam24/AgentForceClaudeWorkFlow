/**
 * VS_AppointmentTriggerHandler — routing handler for VS_AppointmentTrigger (VS-20, REQ-053, D-031).
 *
 * Maintains facility managed sharing for appointments and their patients. The actual recompute is
 * delegated to VS_FacilityShareService and runs ASYNCHRONOUSLY (VS_AppointmentShareRecalc Queueable):
 * the handler only collects the affected Ids and enqueues. This is deliberate — it guarantees the §3.4
 * booking transaction (single VS_Session__c FOR UPDATE lock, D-019/D-020) gains NO extra SOQL/DML and is
 * not lengthened; the share work runs after that transaction commits. `without sharing` because share
 * maintenance is system-owned. Routing only — no share logic here.
 */
public without sharing class VS_AppointmentTriggerHandler {

    /** Static bypass for data loads / test seeding (sf-apex-patterns handler pattern). */
    public static Boolean bypass = false;

    private static final String STATUS_CANCELLED = 'Cancelled';

    /** After insert: every new appointment may need an appointment share; its patient a patient share. */
    public void afterInsert(List<VS_Appointment__c> newList) {
        if (bypass || newList == null || newList.isEmpty()) return;
        Set<Id> apptIds = new Set<Id>();
        Set<Id> patientIds = new Set<Id>();
        for (VS_Appointment__c a : newList) {
            apptIds.add(a.Id);
            if (a.VS_Patient__c != null) patientIds.add(a.VS_Patient__c);
        }
        enqueue(apptIds, patientIds);
    }

    /** After update: only rows whose facility, status or patient changed can affect sharing. */
    public void afterUpdate(List<VS_Appointment__c> newList, Map<Id, VS_Appointment__c> oldMap) {
        if (bypass || newList == null || newList.isEmpty()) return;
        Set<Id> apptIds = new Set<Id>();
        Set<Id> patientIds = new Set<Id>();
        for (VS_Appointment__c a : newList) {
            VS_Appointment__c old = oldMap.get(a.Id);
            // Sharing is affected ONLY by: facility change, patient reparent, or the status crossing the
            // Cancelled boundary. A Booked->NoShow/CheckedIn/Completed transition does NOT change facility
            // scoping, so it is deliberately skipped (keeps VS_NoShowBatch's updates share-neutral).
            Boolean cancelBoundary = (a.VS_Status__c == STATUS_CANCELLED) != (old.VS_Status__c == STATUS_CANCELLED);
            if (a.VS_Facility__c != old.VS_Facility__c
                    || a.VS_Patient__c != old.VS_Patient__c
                    || cancelBoundary) {
                apptIds.add(a.Id);
                if (a.VS_Patient__c != null) patientIds.add(a.VS_Patient__c);
                if (old.VS_Patient__c != null) patientIds.add(old.VS_Patient__c);   // reparented patient
            }
        }
        enqueue(apptIds, patientIds);
    }

    /** After delete: the deleted appointments' own shares cascade away; only their patients' shares need
     *  recomputing (a patient may have lost their last appointment at a facility). */
    public void afterDelete(Map<Id, VS_Appointment__c> oldMap) {
        if (bypass || oldMap == null || oldMap.isEmpty()) return;
        Set<Id> patientIds = new Set<Id>();
        for (VS_Appointment__c a : oldMap.values()) {
            if (a.VS_Patient__c != null) patientIds.add(a.VS_Patient__c);
        }
        enqueue(new Set<Id>(), patientIds);
    }

    /** After undelete: managed shares are not auto-restored, so recompute like an insert. */
    public void afterUndelete(List<VS_Appointment__c> newList) {
        afterInsert(newList);
    }

    /** Enqueue the async recompute once for the whole batch (bulk-safe: one job, not one per record). */
    private void enqueue(Set<Id> apptIds, Set<Id> patientIds) {
        if (apptIds.isEmpty() && patientIds.isEmpty()) return;
        System.enqueueJob(new VS_AppointmentShareRecalc(apptIds, patientIds));
    }
}
