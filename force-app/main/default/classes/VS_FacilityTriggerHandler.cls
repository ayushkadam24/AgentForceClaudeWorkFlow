/**
 * VS_FacilityTriggerHandler — routing handler for VS_FacilityTrigger (VS-20, REQ-053, D-031).
 *
 * After a facility is inserted, enqueues asynchronous public-group provisioning. The enqueue (not the
 * group DML) is all that happens in the facility-insert transaction, so there is no MIXED_DML_OPERATION:
 * Group (setup) is inserted in the Queueable's own transaction, then Group.Id is written back to
 * VS_Facility__c (non-setup) in a chained second transaction (VS_FacilityGroupProvisioner ->
 * VS_FacilityGroupLinker). No business logic lives here — routing only (rules/20, sf-apex-patterns).
 */
public with sharing class VS_FacilityTriggerHandler {

    /** Static bypass for data loads / test seeding (sf-apex-patterns handler pattern). */
    public static Boolean bypass = false;

    /**
     * After-insert entry point: enqueue group provisioning for the new facilities.
     * @param newList the inserted facilities (Trigger.new). Bulk-safe: one enqueue for the whole batch.
     */
    public void afterInsert(List<VS_Facility__c> newList) {
        if (bypass || newList == null || newList.isEmpty()) return;
        Set<Id> facilityIds = new Set<Id>();
        for (VS_Facility__c f : newList) {
            facilityIds.add(f.Id);
        }
        // Async: escapes the facility-insert (non-setup) transaction so the Group (setup) DML is not mixed.
        System.enqueueJob(new VS_FacilityGroupProvisioner(facilityIds));
    }
}
