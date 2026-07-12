#!/usr/bin/env bash
# feature: F-001 slot-booking-core | producing-agent: qa-engineer | date: 2026-07-12
# phase: QA_IN_PROGRESS (/qa-run B) | derives-from: 03-qa/test-plan.md TC-010/TC-011 (REQ-053/036,
#   Tier 1, Annexure C5, A-018)
#
# TC-010 -- permission-set grant audit, live in-org (queries the actual ObjectPermissions rows, not
# just the source XML -- catches any org drift the source doesn't show):
#   (a) NONE of the 5 PRODUCTION permsets (VS_Facility_Staff/VS_Nurse/VS_MO_Facility_Admin/
#       VS_District_Admin/VS_District_MIS) grants ANY access (R/C/E/D) to VS_Patient__c or
#       VS_Appointment__c -- only the harness VS_Booking_Engine_Test_Context should show rows here
#       (A-018, expected/documented, not a bug).
#   (b) VS_Session__c Create+Edit is granted to VS_MO_Facility_Admin ONLY among the 5 production sets.
#
# TC-011 -- VS_Bulk_Export custom permission is enabled ONLY in VS_District_MIS, live in-org
# (SetupEntityAccess is the authoritative live grant graph).
#
# Usage:
#   bash 03-qa/regression/tc-010-011-permset-audit.sh
set -euo pipefail

echo "== TC-010a: live ObjectPermissions on VS_Patient__c / VS_Appointment__c, all VS_% permsets =="
QF1="$(mktemp)"
printf "SELECT Parent.Name, SobjectType, PermissionsRead, PermissionsCreate, PermissionsEdit, PermissionsDelete FROM ObjectPermissions WHERE SobjectType IN ('VS_Patient__c','VS_Appointment__c') AND Parent.Name LIKE 'VS_%%' ORDER BY Parent.Name, SobjectType" > "$QF1"
sf data query --file "$QF1" --target-org AgentForceClaudeWorkFlow --json
echo "Expected: ONLY VS_Booking_Engine_Test_Context rows appear. Any of the 5 production permsets"
echo "(Facility_Staff/Nurse/MO_Facility_Admin/District_Admin/District_MIS) appearing here is an"
echo "unexpected production-grant expansion -- a Sev-1/Sev-2 finding depending on the grant, since it"
echo "would mean a real staff/portal user could now read/write Patient or Appointment PII without a"
echo "corresponding VS-08/17/20 ticket ever landing."

echo
echo "== TC-010b: live ObjectPermissions on VS_Session__c, all VS_% permsets =="
QF2="$(mktemp)"
printf "SELECT Parent.Name, PermissionsRead, PermissionsCreate, PermissionsEdit, PermissionsDelete FROM ObjectPermissions WHERE SobjectType='VS_Session__c' AND Parent.Name LIKE 'VS_%%' ORDER BY Parent.Name" > "$QF2"
sf data query --file "$QF2" --target-org AgentForceClaudeWorkFlow --json
echo "Expected: VS_MO_Facility_Admin (Create=true,Edit=true) + VS_Booking_Engine_Test_Context"
echo "(Create/Edit=true, TEST-ONLY) are the only Create/Edit rows; District_Admin/District_MIS/"
echo "Facility_Staff/Nurse are Read-only."

echo
echo "== TC-011: live SetupEntityAccess for the VS_Bulk_Export CustomPermission =="
QF3="$(mktemp)"
printf "SELECT SetupEntityId, ParentId, Parent.Name FROM SetupEntityAccess WHERE SetupEntityType='CustomPermission'" > "$QF3"
sf data query --file "$QF3" --target-org AgentForceClaudeWorkFlow --json
echo "Expected: exactly ONE row, Parent.Name = VS_District_MIS. Any additional row (a second permset"
echo "granted VS_Bulk_Export) is a Sev-1 compliance finding (REQ-036/Annexure C5 -- bulk export must"
echo "be District MIS role ONLY)."

echo
echo "== TC-010c: current PermissionSetAssignments (confirms harness is NOT on a real-persona user) =="
QF4="$(mktemp)"
printf "SELECT Assignee.Username, PermissionSet.Name FROM PermissionSetAssignment WHERE PermissionSet.Name LIKE 'VS_%%' ORDER BY PermissionSet.Name" > "$QF4"
sf data query --file "$QF4" --target-org AgentForceClaudeWorkFlow --json
