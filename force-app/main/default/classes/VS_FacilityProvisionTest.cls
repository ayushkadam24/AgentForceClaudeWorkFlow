/**
 * VS_FacilityProvisionTest — tests for facility public-group provisioning and GroupMember maintenance
 * (VS-20, REQ-053, D-031 (3)).
 *
 * Covers: the facility after-insert trigger -> Queueable group provisioning (end-to-end, admin context),
 * VS_FacilityShareService.provisionGroups() idempotent re-adopt, writeBackGroupIds(), and the GroupMember
 * add + prune LOGIC (reconcileGroupMembership) + the public syncGroupMembership()/invocable read path.
 *
 * === DE-org D-028 handling (no ManageUsers) ===
 * This org FLS-filters custom-field DML AND ManageUsers drags a heavy dependency chain, so it is NOT
 * granted. Consequences:
 *   - GroupMember add/prune LOGIC is UNIT-PROVEN by calling reconcileGroupMembership() directly with an
 *     explicit user->facility map (no User.VS_Facility__c write needed).
 *   - Writing User.VS_Facility__c (which drives the public syncGroupMembership) needs ManageUsers, so that
 *     WIRING is RUNTIME-GATED (syncGroupMembership_publicPath attempts the admin write and asserts the
 *     membership only if it succeeds, else the documented no-op).
 *   - Writing VS_Facility__c.VS_Sharing_Group_Id__c runs under runAs(powerUser) (FLS via
 *     VS_Facility_Share_Test_Context) on a facility powerUser OWNS (edit access under Public-Read OWD).
 * All SOQL binds use plain local variables (never a bind expression) to avoid the "tmpVar" binder issue.
 */
@isTest(SeeAllData=false)
private class VS_FacilityProvisionTest {

    @TestSetup
    static void seed() {
        VS_FacilityTriggerHandler.bypass = true;
        VS_AppointmentTriggerHandler.bypass = true;

        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User powerUser = buildUser('vs20pw', p.Id);
        User staff = buildUser('vs20st', p.Id);
        PermissionSet sharePs = [SELECT Id FROM PermissionSet WHERE Name = 'VS_Facility_Share_Test_Context' LIMIT 1];

        System.runAs(admin()) {
            insert new List<User>{ powerUser, staff };
            insert new PermissionSetAssignment(AssigneeId = powerUser.Id, PermissionSetId = sharePs.Id);
        }

        // facA / facB (admin) drive the group + membership tests
        VS_Facility__c facA = new VS_Facility__c(Name = 'Prov Alpha');
        VS_Facility__c facB = new VS_Facility__c(Name = 'Prov Bravo');
        insert new List<VS_Facility__c>{ facA, facB };

        // facC is OWNED BY powerUser so the write-back test can edit it (Public-Read OWD => owner can edit)
        System.runAs(powerUser) {
            insert new VS_Facility__c(Name = 'Prov Charlie');
        }

        // groups with the deterministic DeveloperName the service resolves by (setup, runAs admin)
        Group gA = new Group(Name = 'VS Facility: Prov Alpha', DeveloperName = 'VS_FAC_' + facA.Id, Type = 'Regular');
        Group gB = new Group(Name = 'VS Facility: Prov Bravo', DeveloperName = 'VS_FAC_' + facB.Id, Type = 'Regular');
        System.runAs(admin()) {
            insert new List<Group>{ gA, gB };
        }
    }

    @isTest
    static void facilityTrigger_enqueuesGroupProvisioning() {
        Test.startTest();
        VS_Facility__c facD = new VS_Facility__c(Name = 'Prov Delta');   // trigger active (bypass default false)
        insert facD;
        Test.stopTest();                                                 // provisioner Queueable runs as admin
        String devD = 'VS_FAC_' + facD.Id;
        System.assertEquals(1, [SELECT COUNT() FROM Group WHERE DeveloperName = :devD],
            'Facility after-insert trigger must provision exactly one Regular group for the new facility');
    }

    @isTest
    static void provisionGroups_isIdempotent() {
        Id facCId = [SELECT Id FROM VS_Facility__c WHERE Name = 'Prov Charlie' LIMIT 1].Id;
        String devC = 'VS_FAC_' + facCId;
        // both calls run while VS_Sharing_Group_Id__c is still blank -> the second must RE-ADOPT by
        // DeveloperName, never duplicate the group.
        Map<Id, Id> first = VS_FacilityShareService.provisionGroups(new Set<Id>{ facCId });
        Map<Id, Id> second = VS_FacilityShareService.provisionGroups(new Set<Id>{ facCId });
        System.assert(first.containsKey(facCId), 'provisionGroups must return a group for the facility');
        System.assertEquals(first.get(facCId), second.get(facCId), 'idempotent: same group re-adopted');
        System.assertEquals(1, [SELECT COUNT() FROM Group WHERE DeveloperName = :devC],
            'provisionGroups must not create a duplicate group on re-run');
    }

    @isTest
    static void writeBackGroupIds_setsField() {
        Id facCId = [SELECT Id FROM VS_Facility__c WHERE Name = 'Prov Charlie' LIMIT 1].Id;
        Id facAId = [SELECT Id FROM VS_Facility__c WHERE Name = 'Prov Alpha' LIMIT 1].Id;
        String devA = 'VS_FAC_' + facAId;
        Id groupId = [SELECT Id FROM Group WHERE DeveloperName = :devA LIMIT 1].Id;

        System.runAs(powerUser()) {   // owns facC (edit) + FLS on VS_Sharing_Group_Id__c via the test permset
            VS_FacilityShareService.writeBackGroupIds(new Map<Id, Id>{ facCId => groupId });
            VS_Facility__c reloaded = [SELECT VS_Sharing_Group_Id__c FROM VS_Facility__c WHERE Id = :facCId LIMIT 1];
            System.assertEquals(groupId, (Id) reloaded.VS_Sharing_Group_Id__c,
                'writeBackGroupIds must store the provisioned Group Id on the facility');
        }
    }

    @isTest
    static void reconcileGroupMembership_addsThenPrunes() {
        // UNIT-PROVEN: the add/prune LOGIC, driven by an explicit user->facility map (no User.VS_Facility__c
        // write — that needs ManageUsers, which we do not grant).
        String staffPattern = 'vs20st-%';
        Id staffId = [SELECT Id FROM User WHERE Username LIKE :staffPattern LIMIT 1].Id;
        Id facAId = [SELECT Id FROM VS_Facility__c WHERE Name = 'Prov Alpha' LIMIT 1].Id;
        Id facBId = [SELECT Id FROM VS_Facility__c WHERE Name = 'Prov Bravo' LIMIT 1].Id;
        String devA = 'VS_FAC_' + facAId;
        String devB = 'VS_FAC_' + facBId;
        Id gA = [SELECT Id FROM Group WHERE DeveloperName = :devA LIMIT 1].Id;
        Id gB = [SELECT Id FROM Group WHERE DeveloperName = :devB LIMIT 1].Id;

        Test.startTest();
        System.runAs(admin()) {   // GroupMember DML has no custom-field FLS -> admin
            VS_FacilityShareService.reconcileGroupMembership(
                new Map<Id, Id>{ staffId => facAId }, new Set<Id>{ staffId });
        }
        System.assertEquals(1, [SELECT COUNT() FROM GroupMember
            WHERE GroupId = :gA AND UserOrGroupId = :staffId], 'add: staff joins facility-A group');

        System.runAs(admin()) {   // reassign to B -> prune A, add B
            VS_FacilityShareService.reconcileGroupMembership(
                new Map<Id, Id>{ staffId => facBId }, new Set<Id>{ staffId });
        }
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM GroupMember
            WHERE GroupId = :gA AND UserOrGroupId = :staffId], 'prune: stale facility-A membership removed');
        System.assertEquals(1, [SELECT COUNT() FROM GroupMember
            WHERE GroupId = :gB AND UserOrGroupId = :staffId], 'add: staff now member of facility-B group');
    }

    @isTest
    static void syncGroupMembership_publicPath() {
        // Covers the public read path (syncGroupMembership + invocable). The User.VS_Facility__c write that
        // drives it needs ManageUsers, so it is RUNTIME-GATED: attempt the admin write, assert membership
        // only if it succeeds (standard org), else assert the documented no-op.
        String staffPattern = 'vs20st-%';
        Id staffId = [SELECT Id FROM User WHERE Username LIKE :staffPattern LIMIT 1].Id;
        Id facAId = [SELECT Id FROM VS_Facility__c WHERE Name = 'Prov Alpha' LIMIT 1].Id;
        String devA = 'VS_FAC_' + facAId;
        Id gA = [SELECT Id FROM Group WHERE DeveloperName = :devA LIMIT 1].Id;

        Boolean fieldWriteWorked = false;
        try {
            update new User(Id = staffId, VS_Facility__c = facAId);   // needs ManageUsers + FLS (may be blocked)
            fieldWriteWorked = true;
        } catch (Exception e) {
            System.debug('User.VS_Facility__c write not permitted here (runtime-gated wiring): ' + e);
        }

        Test.startTest();
        VS_FacilityGroupMemberInvocable.sync(new List<Id>{ staffId });   // delegates to syncGroupMembership
        Test.stopTest();

        Integer members = [SELECT COUNT() FROM GroupMember WHERE GroupId = :gA AND UserOrGroupId = :staffId];
        if (fieldWriteWorked) {
            System.assertEquals(1, members,
                'when User.VS_Facility__c IS set, syncGroupMembership must add the facility-group membership');
        } else {
            System.assertEquals(0, members,
                'field write blocked here -> membership drive is runtime-gated (logic proven in reconcile test)');
        }
    }

    // helpers
    private static User admin() { return new User(Id = UserInfo.getUserId()); }
    private static User powerUser() {
        String pattern = 'vs20pw-%';
        return [SELECT Id FROM User WHERE Username LIKE :pattern LIMIT 1];
    }

    private static User buildUser(String prefix, Id profileId) {
        return new User(
            FirstName = 'VS', LastName = prefix,
            Alias = prefix.left(8), Email = 'vs20@example.com',
            Username = prefix + '-' + Math.abs(Crypto.getRandomLong()) + '@vs20.test.example.com',
            ProfileId = profileId,
            TimeZoneSidKey = 'Asia/Kolkata', LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US');
    }
}
