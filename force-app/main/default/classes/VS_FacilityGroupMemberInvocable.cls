/**
 * VS_FacilityGroupMemberInvocable — Flow/manual entry point to reconcile a user's facility-group
 * membership (VS-20, REQ-053, D-031 (3)).
 *
 * Chosen instead of a global trigger on the standard User object: this POC deploys to a SHARED Developer
 * Edition org used for other work, and a User trigger fires on every user change org-wide. An invocable
 * (callable from a Flow, an admin action, or anonymous Apex) plus documented manual GroupMember assignment
 * for the 2 sample facilities is the sanctioned POC path (D-031 (3)); productionizing to a User trigger
 * that calls the same VS_FacilityShareService.syncGroupMembership() is a one-line follow-up.
 */
public with sharing class VS_FacilityGroupMemberInvocable {

    /**
     * Reconcile facility-group membership for the given users (add missing, prune stale).
     * @param userIds users to reconcile (typically after User.VS_Facility__c is set/changed).
     */
    @InvocableMethod(label='VS Sync Facility Group Membership'
                     description='Reconcile facility public-group membership for the given users (REQ-053).')
    public static void sync(List<Id> userIds) {
        if (userIds == null || userIds.isEmpty()) return;
        VS_FacilityShareService.syncGroupMembership(new Set<Id>(userIds));
    }
}
