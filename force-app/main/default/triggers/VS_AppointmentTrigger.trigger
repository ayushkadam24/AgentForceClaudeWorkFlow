/**
 * VS_AppointmentTrigger — the one trigger on VS_Appointment__c (VS-20, REQ-053, D-031).
 * No logic here: delegates to VS_AppointmentTriggerHandler (rules/20, one trigger per object).
 * After-only: facility managed sharing is maintained after the booking/commit, never inside the §3.4 lock.
 */
trigger VS_AppointmentTrigger on VS_Appointment__c (after insert, after update, after delete, after undelete) {
    VS_AppointmentTriggerHandler handler = new VS_AppointmentTriggerHandler();
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            handler.afterInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            handler.afterUpdate(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isDelete) {
            handler.afterDelete(Trigger.oldMap);
        } else if (Trigger.isUndelete) {
            handler.afterUndelete(Trigger.new);
        }
    }
}
