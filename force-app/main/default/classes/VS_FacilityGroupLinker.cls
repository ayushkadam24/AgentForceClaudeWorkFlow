/**
 * VS_FacilityGroupLinker — Queueable that writes provisioned Group Ids back onto their facilities
 * (VS-20, D-031).
 *
 * Second hop of the provisioning chain. Runs in its own transaction so the VS_Facility__c update
 * (NON-setup DML) is not mixed with the Group insert (setup DML) performed by VS_FacilityGroupProvisioner.
 */
public without sharing class VS_FacilityGroupLinker implements Queueable {

    private final Map<Id, Id> facilityToGroup;

    public VS_FacilityGroupLinker(Map<Id, Id> facilityToGroup) {
        this.facilityToGroup = facilityToGroup;
    }

    public void execute(QueueableContext ctx) {
        VS_FacilityShareService.writeBackGroupIds(facilityToGroup);
    }
}
