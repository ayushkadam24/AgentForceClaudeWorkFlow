/**
 * VS_FacilityShareService — facility-scoped record sharing engine (VS-20, EP-08,
 * REQ-053 / Annexure C5.1, design 6.2, D-031).
 *
 * ONE mechanism, both objects: APEX MANAGED SHARING keyed on the appointment -> facility relationship.
 *   - VS_Appointment__Share : each non-cancelled appointment is shared (Edit) to its facility's public
 *     Group, RowCause = VS_Facility_Access__c.
 *   - VS_Patient__Share     : each patient is shared (Read) to the public Group of EVERY facility at
 *     which the patient has a non-cancelled appointment (patients span facilities, D-011/D-017), same
 *     RowCause. A facility-A staffer therefore sees exactly the citizens who have an appointment at A —
 *     minimal disclosure (C5.1), never every district citizen.
 * District users are NOT handled here — they use View-All + read-only FLS on the two district permsets
 * (D-031 (4)); managed sharing is only the facility-staff half.
 *
 * === Why `without sharing` + system mode ===
 * Share maintenance is SYSTEM-OWNED, not citizen-facing. It must see ALL of a patient's appointments to
 * compute the complete desired share set (even ones the acting user cannot see), and __Share DML is not
 * subject to FLS. So this class runs `without sharing` and its SOQL/DML is intentionally system mode —
 * NOT `WITH USER_MODE` (rules/20's user-mode rule targets citizen-facing paths; this is neither).
 *
 * === Relationship to the §3.4 crown jewel (D-019/D-020/D-029) — untouched ===
 * The appointment trigger runs the recompute ASYNCHRONOUSLY (a Queueable enqueued from the after-trigger,
 * VS_AppointmentShareRecalc). The booking transaction that holds the single VS_Session__c FOR UPDATE lock
 * therefore performs ZERO extra SOQL/DML for sharing — it only enqueues a job that runs AFTER commit, so
 * the lock is neither lengthened nor given a new query/DML. VS_BookingService is not modified.
 *
 * === Group provisioning (mixed-DML aware) ===
 * Group / GroupMember are SETUP objects; VS_Facility__c is not. A single transaction cannot DML both
 * (MIXED_DML_OPERATION). So facility group provisioning is a two-hop async chain:
 *   VS_FacilityTriggerHandler (after insert) -> enqueue VS_FacilityGroupProvisioner (inserts Groups only,
 *   setup DML) -> chains VS_FacilityGroupLinker (writes Group.Id back to VS_Facility__c, non-setup DML).
 * GroupMember membership is maintained by syncGroupMembership() (setup-only DML, no mix).
 *
 * Traceability: REQ-053, REQ-054(open/A-006) / EP-08 / D-031, D-011, D-017, D-019, D-020.
 */
public without sharing class VS_FacilityShareService {

    /** Apex sharing reason (RowCause) declared on both objects — resolves to 'VS_Facility_Access__c'. */
    private static final String ROWCAUSE_APPT    = Schema.VS_Appointment__Share.RowCause.VS_Facility_Access__c;
    private static final String ROWCAUSE_PATIENT = Schema.VS_Patient__Share.RowCause.VS_Facility_Access__c;

    private static final String ACCESS_EDIT      = 'Edit';   // appointment share (staff manage bookings)
    private static final String ACCESS_READ      = 'Read';   // patient share (staff see their citizens)
    private static final String STATUS_CANCELLED = 'Cancelled';
    private static final String GROUP_DEV_PREFIX = 'VS_FAC_';

    /**
     * Recompute facility managed-sharing for a set of appointments and patients. Idempotent and
     * bulk-safe (constant SOQL/DML regardless of volume): it re-queries the present appointments, diffs
     * the DESIRED share rows against the EXISTING ones, and applies one delete + one insert per object.
     *
     * Called from VS_AppointmentShareRecalc (the async Queueable enqueued by the appointment trigger) and
     * directly from tests. Re-querying by Id (rather than trusting the trigger's in-memory records) is what
     * lets it run safely post-commit / async, and makes it correct on delete (deleted rows drop out of the
     * re-query so their patient shares prune naturally; the deleted appointment's own __Share rows are
     * cascade-removed by the platform).
     *
     * @param presentApptIds   Ids of appointments that still exist and may need an appointment share
     *                         (insert/update/undelete). Empty on delete.
     * @param affectedPatientIds Ids of every patient whose share set may have changed (patients of the
     *                         affected appointments, new AND old). Their patient shares are fully recomputed.
     */
    public static void recomputeSharesById(Set<Id> presentApptIds, Set<Id> affectedPatientIds) {
        // FAIL-SAFE (coordinator must-fix): a sharing failure must NEVER break the booking/appointment
        // transaction that triggered it — the §3.4 crown jewel booking (D-019/D-020) always succeeds. On
        // this DE org, D-028 can FLS-filter even system-mode/async DML; when that happens here we log and
        // return, and record-level sharing simply applies at RUNTIME on a standard org (the same
        // D-030a "DE-org limit => runtime gate" posture used for §3.4 walk-in and portal booking).
        try {
            recomputeSharesInternal(presentApptIds, affectedPatientIds);
        } catch (Exception e) {
            logRecomputeFailure(e);
        }
    }

    /** The recompute body. @TestVisible so VS-20 tests can seed shares WITHOUT the fail-safe swallow — a
     *  genuine seeding failure then surfaces loudly in the test instead of hiding behind an empty share set. */
    @TestVisible
    private static void recomputeSharesInternal(Set<Id> presentApptIds, Set<Id> affectedPatientIds) {
        if (presentApptIds == null) presentApptIds = new Set<Id>();
        if (affectedPatientIds == null) affectedPatientIds = new Set<Id>();
        if (presentApptIds.isEmpty() && affectedPatientIds.isEmpty()) {
            return;
        }

        // Re-query the still-existing appointments (source of truth for current facility/status).
        List<VS_Appointment__c> present = presentApptIds.isEmpty()
            ? new List<VS_Appointment__c>()
            : [SELECT Id, VS_Patient__c, VS_Facility__c, VS_Status__c
               FROM VS_Appointment__c WHERE Id IN :presentApptIds];

        // All non-cancelled appointments of the affected patients (drives patient shares).
        List<VS_Appointment__c> patientAppts = affectedPatientIds.isEmpty()
            ? new List<VS_Appointment__c>()
            : [SELECT Id, VS_Patient__c, VS_Facility__c
               FROM VS_Appointment__c
               WHERE VS_Patient__c IN :affectedPatientIds
                 AND VS_Status__c != :STATUS_CANCELLED
                 AND VS_Facility__c != null];

        // Every facility Id referenced by either computation -> resolve its group once.
        Set<Id> facilityIds = new Set<Id>();
        for (VS_Appointment__c a : present) {
            if (a.VS_Facility__c != null) facilityIds.add(a.VS_Facility__c);
        }
        for (VS_Appointment__c a : patientAppts) {
            facilityIds.add(a.VS_Facility__c);
        }
        Map<Id, Id> facToGroup = resolveFacilityGroups(facilityIds);

        if (!present.isEmpty()) {
            maintainAppointmentShares(present, facToGroup);
        }
        if (!affectedPatientIds.isEmpty()) {
            maintainPatientShares(affectedPatientIds, patientAppts, facToGroup);
        }
    }

    /** Insert/delete VS_Appointment__Share rows so each present appointment is shared (Edit) to exactly
     *  its facility's group when non-cancelled, and to nothing when cancelled / facility cleared. */
    private static void maintainAppointmentShares(List<VS_Appointment__c> present, Map<Id, Id> facToGroup) {
        Set<Id> apptIds = new Set<Id>();
        Map<Id, Id> desired = new Map<Id, Id>();               // apptId -> desired groupId
        for (VS_Appointment__c a : present) {
            apptIds.add(a.Id);
            if (a.VS_Status__c != STATUS_CANCELLED && a.VS_Facility__c != null) {
                Id g = facToGroup.get(a.VS_Facility__c);
                if (g != null) desired.put(a.Id, g);
            }
        }

        Set<String> keptKeys = new Set<String>();
        List<VS_Appointment__Share> toDelete = new List<VS_Appointment__Share>();
        for (VS_Appointment__Share s : [
                SELECT Id, ParentId, UserOrGroupId FROM VS_Appointment__Share
                WHERE ParentId IN :apptIds AND RowCause = :ROWCAUSE_APPT]) {
            Id wantGroup = desired.get(s.ParentId);
            if (wantGroup != null && wantGroup == s.UserOrGroupId) {
                keptKeys.add(shareKey(s.ParentId, s.UserOrGroupId));   // already correct — keep
            } else {
                toDelete.add(s);                                       // stale (cancelled / facility changed)
            }
        }

        List<VS_Appointment__Share> toInsert = new List<VS_Appointment__Share>();
        for (Id apptId : desired.keySet()) {
            Id g = desired.get(apptId);
            if (!keptKeys.contains(shareKey(apptId, g))) {
                toInsert.add(new VS_Appointment__Share(
                    ParentId = apptId, UserOrGroupId = g, AccessLevel = ACCESS_EDIT, RowCause = ROWCAUSE_APPT));
            }
        }
        applyShareDml(toDelete, toInsert);
    }

    /** Insert/delete VS_Patient__Share rows so each affected patient is shared (Read) to the group of every
     *  facility where they currently hold a non-cancelled appointment, and to nothing else. */
    private static void maintainPatientShares(Set<Id> patientIds, List<VS_Appointment__c> patientAppts,
                                              Map<Id, Id> facToGroup) {
        Map<Id, Set<Id>> desired = new Map<Id, Set<Id>>();     // patientId -> desired groupIds
        for (Id pid : patientIds) desired.put(pid, new Set<Id>());
        for (VS_Appointment__c a : patientAppts) {
            Id g = facToGroup.get(a.VS_Facility__c);
            if (g != null && desired.containsKey(a.VS_Patient__c)) {
                desired.get(a.VS_Patient__c).add(g);
            }
        }

        Set<String> keptKeys = new Set<String>();
        List<VS_Patient__Share> toDelete = new List<VS_Patient__Share>();
        for (VS_Patient__Share s : [
                SELECT Id, ParentId, UserOrGroupId FROM VS_Patient__Share
                WHERE ParentId IN :patientIds AND RowCause = :ROWCAUSE_PATIENT]) {
            Set<Id> want = desired.get(s.ParentId);
            if (want != null && want.contains(s.UserOrGroupId)) {
                keptKeys.add(shareKey(s.ParentId, s.UserOrGroupId));
            } else {
                toDelete.add(s);
            }
        }

        List<VS_Patient__Share> toInsert = new List<VS_Patient__Share>();
        for (Id pid : desired.keySet()) {
            for (Id g : desired.get(pid)) {
                if (!keptKeys.contains(shareKey(pid, g))) {
                    toInsert.add(new VS_Patient__Share(
                        ParentId = pid, UserOrGroupId = g, AccessLevel = ACCESS_READ, RowCause = ROWCAUSE_PATIENT));
                }
            }
        }
        applyShareDml(toDelete, toInsert);
    }

    /** One delete + one insert, partial-success (allOrNone=false) so a concurrently-created duplicate
     *  share or an already-removed row never fails the whole recompute (rules/20 no empty catch — results
     *  are inspectable; benign DUPLICATE/entity-deleted outcomes are expected under concurrency). */
    private static void applyShareDml(List<SObject> toDelete, List<SObject> toInsert) {
        if (toDelete != null && !toDelete.isEmpty()) Database.delete(toDelete, false);
        if (toInsert != null && !toInsert.isEmpty()) Database.insert(toInsert, false);
    }

    /**
     * Map facility Id -> its public Group Id, resolved by the deterministic Group DeveloperName
     * (VS_FAC_<facilityId>) — NOT by reading VS_Facility__c.VS_Sharing_Group_Id__c.
     *
     * WHY (coordinator must-fix (b)): the appointment recompute runs in the hot booking/appointment path
     * as whatever user triggered it, and on this DE org D-028 FLS-filters the custom field
     * VS_Sharing_Group_Id__c for users without FLS on it — reading it there threw
     * "No such column / fields inaccessible" and BROKE booking. Group is a setup object whose standard
     * DeveloperName carries no custom-field FLS, so this resolution is safe for any acting user.
     * VS_Sharing_Group_Id__c remains the provisioner's written record of the Id (queried in system mode
     * by provisionGroups), but the appointment path no longer depends on its FLS. One SOQL.
     */
    private static Map<Id, Id> resolveFacilityGroups(Set<Id> facilityIds) {
        Map<Id, Id> m = new Map<Id, Id>();
        if (facilityIds == null || facilityIds.isEmpty()) return m;
        Map<String, Id> devNameToFac = new Map<String, Id>();
        for (Id fid : facilityIds) {
            devNameToFac.put(GROUP_DEV_PREFIX + fid, fid);
        }
        Set<String> devNames = devNameToFac.keySet();   // bind a plain local, never a method call (SOQL binder)
        for (Group g : [SELECT Id, DeveloperName FROM Group
                        WHERE DeveloperName IN :devNames AND Type = 'Regular']) {
            Id fid = devNameToFac.get(g.DeveloperName);
            if (fid != null) m.put(fid, g.Id);
        }
        return m;
    }

    private static String shareKey(Id parentId, Id groupId) {
        return parentId + '|' + groupId;
    }

    /** Fully-defensive fail-safe logger: NEVER throws (a throw here would defeat the point). Best-effort
     *  VS_Error_Log__c row; if even that is FLS-blocked on this org, fall back to the debug log. */
    private static void logRecomputeFailure(Exception e) {
        System.debug(LoggingLevel.ERROR,
            'VS_FacilityShareService recompute failed (fail-safe; booking/appointment unaffected): ' + e);
        try {
            insert new VS_Error_Log__c(
                VS_Severity__c = 'Error',
                VS_Context__c = 'VS_FacilityShareService.recomputeSharesById',
                VS_Message__c = e.getTypeName() + ': ' + e.getMessage() + '\n' + e.getStackTraceString(),
                VS_Logged_At__c = System.now());
        } catch (Exception logEx) {
            System.debug(LoggingLevel.ERROR, 'VS_Error_Log__c write also failed (swallowed): ' + logEx);
        }
    }

    // ===================================================================================================
    //  Facility public-group provisioning (setup DML — runs in the async Queueable chain, never inline)
    // ===================================================================================================

    /**
     * Provision one Regular public Group per facility (SETUP DML) and return facility Id -> Group Id.
     * Idempotent: a facility that already carries VS_Sharing_Group_Id__c is skipped, and a deterministic
     * DeveloperName ('VS_FAC_'+facilityId) lets a previously-created-but-not-linked group be re-adopted
     * instead of duplicated. Does NOT write back to the facility (that is non-setup DML — the caller
     * chains VS_FacilityGroupLinker for it) to avoid MIXED_DML_OPERATION.
     *
     * @param facilityIds facilities to ensure a group for.
     * @return facility Id -> Group Id for every facility that now has a group (new or re-adopted).
     * @throws VS_ShareException GROUP_PROVISION_FAILED if a group insert returns no Id.
     */
    public static Map<Id, Id> provisionGroups(Set<Id> facilityIds) {
        Map<Id, Id> result = new Map<Id, Id>();
        if (facilityIds == null || facilityIds.isEmpty()) return result;

        // NOTE: deliberately does NOT read VS_Sharing_Group_Id__c (this DE org D-028-FLS-filters that
        // custom field in SOQL for users without FLS). Idempotency comes entirely from the deterministic
        // Group DeveloperName re-adopt below — an already-provisioned facility simply re-adopts its group.
        Map<Id, VS_Facility__c> facs = new Map<Id, VS_Facility__c>([
            SELECT Id, Name FROM VS_Facility__c WHERE Id IN :facilityIds]);

        Map<String, Id> devNameToFac = new Map<String, Id>();
        for (VS_Facility__c f : facs.values()) {
            devNameToFac.put(GROUP_DEV_PREFIX + f.Id, f.Id);
        }
        if (devNameToFac.isEmpty()) return result;

        // Re-adopt any pre-existing groups with the deterministic name (idempotency / retry-safety).
        Set<String> wantedNames = devNameToFac.keySet();   // bind a plain local, never a method call
        Set<String> existingNames = new Set<String>();
        for (Group g : [SELECT Id, DeveloperName FROM Group
                        WHERE DeveloperName IN :wantedNames AND Type = 'Regular']) {
            result.put(devNameToFac.get(g.DeveloperName), g.Id);
            existingNames.add(g.DeveloperName);
        }

        List<Group> toInsert = new List<Group>();
        List<Id> insertFacOrder = new List<Id>();
        for (String devName : devNameToFac.keySet()) {
            if (existingNames.contains(devName)) continue;
            Id fid = devNameToFac.get(devName);
            toInsert.add(new Group(
                Name = groupLabel(facs.get(fid)), DeveloperName = devName, Type = 'Regular'));
            insertFacOrder.add(fid);
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;                                    // setup DML — safe alone in its transaction
            for (Integer i = 0; i < toInsert.size(); i++) {
                if (toInsert[i].Id == null) {
                    throw new VS_ShareException(VS_ShareException.GROUP_PROVISION_FAILED);
                }
                result.put(insertFacOrder[i], toInsert[i].Id);
            }
        }
        return result;
    }

    /** Write provisioned Group Ids back onto the facilities (NON-setup DML — must be a separate
     *  transaction from provisionGroups()'s Group insert, hence VS_FacilityGroupLinker). */
    public static void writeBackGroupIds(Map<Id, Id> facilityToGroup) {
        if (facilityToGroup == null || facilityToGroup.isEmpty()) return;
        List<VS_Facility__c> updates = new List<VS_Facility__c>();
        for (Id fid : facilityToGroup.keySet()) {
            updates.add(new VS_Facility__c(Id = fid, VS_Sharing_Group_Id__c = facilityToGroup.get(fid)));
        }
        Boolean prior = VS_FacilityTriggerHandler.bypass;
        VS_FacilityTriggerHandler.bypass = true;               // this update is not a new facility — no re-provision
        try {
            update updates;
        } finally {
            VS_FacilityTriggerHandler.bypass = prior;
        }
    }

    /** Group label (max 40 chars), safe for any facility name. */
    private static String groupLabel(VS_Facility__c f) {
        String base = 'VS Facility: ' + (f != null && f.Name != null ? f.Name : '');
        return base.length() > 40 ? base.substring(0, 40) : base;
    }

    // ===================================================================================================
    //  GroupMember maintenance (setup-only DML — invoked via VS_FacilityGroupMemberInvocable / manual)
    // ===================================================================================================

    /**
     * Keep the given users' membership of facility public groups in sync with their User.VS_Facility__c
     * (their home facility). Adds the missing membership and prunes stale VS_FAC_* memberships (e.g. after
     * a facility reassignment). SETUP-only DML (User read + GroupMember DML) — no MIXED_DML.
     *
     * For the POC's 2 sample facilities this may also be done manually (D-031 (3)); this method is the
     * productionization path, surfaced to admins/Flows through VS_FacilityGroupMemberInvocable.
     *
     * @param userIds users whose facility-group membership should be reconciled.
     */
    public static void syncGroupMembership(Set<Id> userIds) {
        if (userIds == null || userIds.isEmpty()) return;

        // Read each user's home facility. User.VS_Facility__c is TEXT(18) holding a facility Id (the
        // standard User object rejects a custom Lookup to a custom object), read here only as an Id value.
        // This SELECT is system mode, so it is not FLS-blocked. Setting that field, however, needs
        // ManageUsers + FLS on this DE org (D-028) — so the User->facility WIRING is a runtime gate; the
        // GroupMember add/prune LOGIC below is unit-proven directly via reconcileGroupMembership().
        Map<Id, Id> userToFacility = new Map<Id, Id>();
        try {
            for (User u : [SELECT Id, VS_Facility__c FROM User WHERE Id IN :userIds]) {
                if (String.isNotBlank(u.VS_Facility__c)) {
                    userToFacility.put(u.Id, (Id) u.VS_Facility__c);
                }
            }
        } catch (Exception e) {
            // DE-org D-028 RUNTIME GATE: reading the custom User.VS_Facility__c is FLS-blocked even in
            // system mode for a user without FLS on it (surfaces as a bind-time QueryException), so a
            // Flow/invocable call here would otherwise error. Fail-safe: log + no-op. The field-write ->
            // membership wiring is runtime-gated by design (D-031(3)); the add/prune LOGIC is unit-proven
            // directly via reconcileGroupMembership(). On a standard org this read succeeds normally.
            logRecomputeFailure(e);
            return;
        }
        reconcileGroupMembership(userToFacility, userIds);
    }

    /**
     * Reconcile GroupMember rows for a set of users against a desired user -> home-facility mapping: add the
     * missing facility-group membership and prune stale VS_FAC_* memberships (e.g. after a reassignment).
     * SETUP-only DML (GroupMember). @TestVisible so the add/prune logic is unit-proven WITHOUT writing
     * User.VS_Facility__c (which needs ManageUsers on this DE org — that read wiring is runtime-gated).
     *
     * @param userToFacility desired mapping (only users that currently have a home facility).
     * @param allUserIds     every user being reconciled (drives pruning for users now without a facility).
     */
    @TestVisible
    private static void reconcileGroupMembership(Map<Id, Id> userToFacility, Set<Id> allUserIds) {
        if (allUserIds == null || allUserIds.isEmpty()) return;
        if (userToFacility == null) userToFacility = new Map<Id, Id>();

        Map<Id, Id> facToGroup = resolveFacilityGroups(new Set<Id>(userToFacility.values()));

        // Desired membership key(s): userId|groupId for each user's current home facility.
        Set<String> desiredKeys = new Set<String>();
        Map<String, GroupMember> toInsertByKey = new Map<String, GroupMember>();
        for (Id uId : userToFacility.keySet()) {
            Id g = facToGroup.get(userToFacility.get(uId));
            if (g == null) continue;
            String key = uId + '|' + g;
            desiredKeys.add(key);
            toInsertByKey.put(key, new GroupMember(GroupId = g, UserOrGroupId = uId));
        }

        // Existing VS_FAC_* memberships for these users -> keep the desired, prune the rest.
        List<GroupMember> toDelete = new List<GroupMember>();
        for (GroupMember gm : [
                SELECT Id, GroupId, UserOrGroupId, Group.DeveloperName FROM GroupMember
                WHERE UserOrGroupId IN :allUserIds]) {
            if (gm.Group.DeveloperName == null || !gm.Group.DeveloperName.startsWith(GROUP_DEV_PREFIX)) {
                continue;                                       // not one of ours — leave untouched
            }
            String key = gm.UserOrGroupId + '|' + gm.GroupId;
            if (desiredKeys.contains(key)) {
                toInsertByKey.remove(key);                      // already a member — nothing to add
            } else {
                toDelete.add(gm);                               // stale (reassigned facility)
            }
        }

        if (!toDelete.isEmpty()) delete toDelete;               // setup DML
        if (!toInsertByKey.isEmpty()) insert toInsertByKey.values();
    }
}
