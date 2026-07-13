/**
 * VS_FacilityGroupProvisioner — Queueable that creates one Regular public Group per facility (VS-20, D-031).
 *
 * First hop of the mixed-DML-safe provisioning chain. It runs in its OWN transaction (enqueued from the
 * facility after-insert trigger), so the Group insert (SETUP DML) is not mixed with the facility insert
 * (non-setup). It then chains VS_FacilityGroupLinker to write the Group Ids back to the facilities
 * (non-setup DML) in a THIRD transaction — the write-back cannot happen here without re-introducing
 * MIXED_DML_OPERATION.
 */
public without sharing class VS_FacilityGroupProvisioner implements Queueable {

    private final Set<Id> facilityIds;

    public VS_FacilityGroupProvisioner(Set<Id> facilityIds) {
        this.facilityIds = facilityIds;
    }

    public void execute(QueueableContext ctx) {
        // FAIL-SAFE: facility creation already committed in a prior transaction, so a provisioning failure
        // here must never surface as an error (async, decoupled). Log best-effort and stop.
        try {
            Map<Id, Id> facToGroup = VS_FacilityShareService.provisionGroups(facilityIds);
            if (facToGroup.isEmpty()) return;
            // Chaining a Queueable from a Queueable is unsupported in a test transaction; the linker is
            // tested directly. In production this chains to perform the non-setup write-back.
            if (Test.isRunningTest()) return;
            System.enqueueJob(new VS_FacilityGroupLinker(facToGroup));
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'VS_FacilityGroupProvisioner failed (fail-safe; facility creation unaffected): ' + e);
        }
    }
}
