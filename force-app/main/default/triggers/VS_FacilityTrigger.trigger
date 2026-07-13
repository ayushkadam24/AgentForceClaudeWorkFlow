/**
 * VS_FacilityTrigger — the one trigger on VS_Facility__c (VS-20, REQ-053, D-031).
 * No logic here: delegates to VS_FacilityTriggerHandler (rules/20, one trigger per object).
 */
trigger VS_FacilityTrigger on VS_Facility__c (after insert) {
    if (Trigger.isAfter && Trigger.isInsert) {
        new VS_FacilityTriggerHandler().afterInsert(Trigger.new);
    }
}
