#!/usr/bin/env bash
# feature: F-001 slot-booking-core | producing-agent: qa-engineer | date: 2026-07-12
# phase: QA_IN_PROGRESS (/qa-run B) | derives-from: 03-qa/test-plan.md TC-028 (REQ-001/004/046)
#
# TC-028 -- structural data-model spot audit, live in-org via Tooling API EntityParticle (bypasses
# FLS, full field enumeration regardless of the connected session's grants):
#   - VS_Appointment__c.VS_Booked_By_Mobile__c present (REQ-004 booker != patient)
#   - VS_Facility__c discovery fields present (REQ-001, structural only -- VS_Location__c geolocation
#     for proximity + VS_Pincode__c; no discovery UI exists to test end-to-end)
#   - VS_Patient__c.VS_Consent_Given__c / VS_Consent_Timestamp__c present (REQ-046 fields only --
#     enforcement is VS-10, not built in this pilot)
#
# Usage:
#   bash 03-qa/regression/tc-028-data-model-audit.sh
set -euo pipefail
for OBJ in VS_Appointment__c VS_Facility__c VS_Patient__c; do
  QF="$(mktemp)"
  printf "SELECT QualifiedApiName FROM EntityParticle WHERE EntityDefinition.QualifiedApiName='%s'" "$OBJ" > "$QF"
  echo "--- $OBJ ---"
  sf data query --file "$QF" --use-tooling-api --target-org AgentForceClaudeWorkFlow --json
done
echo
echo "Assert manually (or grep the JSON above) for:"
echo "  VS_Appointment__c: VS_Booked_By_Mobile__c"
echo "  VS_Facility__c:    VS_Location__c, VS_Pincode__c"
echo "  VS_Patient__c:     VS_Consent_Given__c, VS_Consent_Timestamp__c"
