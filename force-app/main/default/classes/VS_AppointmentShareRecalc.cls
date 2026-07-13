/**
 * VS_AppointmentShareRecalc — Queueable that recomputes facility managed sharing AFTER the appointment
 * transaction commits (VS-20, REQ-053, D-031).
 *
 * Enqueued by VS_AppointmentTriggerHandler. Running the recompute here (rather than inline in the
 * after-trigger) is what keeps the §3.4 booking transaction's FOR UPDATE lock free of any extra SOQL/DML
 * (D-019/D-020): the booking transaction only enqueues this job; the share SOQL/DML happens post-commit.
 */
public without sharing class VS_AppointmentShareRecalc implements Queueable {

    private final Set<Id> apptIds;
    private final Set<Id> patientIds;

    public VS_AppointmentShareRecalc(Set<Id> apptIds, Set<Id> patientIds) {
        this.apptIds = apptIds == null ? new Set<Id>() : apptIds;
        this.patientIds = patientIds == null ? new Set<Id>() : patientIds;
    }

    /** Delegate to the share service (bulk-safe, constant SOQL/DML). */
    public void execute(QueueableContext ctx) {
        VS_FacilityShareService.recomputeSharesById(apptIds, patientIds);
    }
}
