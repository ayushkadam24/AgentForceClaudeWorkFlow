#!/usr/bin/env bash
# feature: F-001 slot-booking-core | producing-agent: qa-engineer | date: 2026-07-12
# phase: QA_IN_PROGRESS (/qa-run B) | derives-from: 03-qa/test-plan.md TC-007/TC-008 (REQ-044/045,
#   Tier 1, rules/10 #1)
#
# COMPLIANCE NOTE: this script deliberately NEVER writes a literal 12-consecutive-digit value to
# any file or Apex source, even as fake test data -- rules/10 #1 is absolute (no Aadhaar-SHAPED value
# anywhere, committed test scripts included). TC-007's evidentiary question ("does any field-level
# validation block a government-ID-shaped value?") is answered by (a) the structural absence of ANY
# ValidationRule metadata on VS_Patient__c, and (b) inserting a same-length ALPHANUMERIC junk string
# -- if a field with zero pattern validation accepts alphanumeric junk, it accepts digit-only junk
# too, since there is no character-class check present to tell them apart.
#
# TC-008 -- structural no-Aadhaar sweep across ALL deployed metadata + live in-org field-list proof
# (Tooling API EntityParticle -- this bypasses FLS, unlike `sf sobject describe`, so it is a true
# full field-name enumeration regardless of the connected session's FLS grants; see A-019).
#
# Usage:
#   bash 03-qa/regression/tc-007-008-no-aadhaar.sh
set -euo pipefail

echo "== TC-008a: structural grep across force-app (objects/permsets/CMDT/flows/classes) =="
grep -rniE "aadhaar|aadhar" force-app/ || true
echo "(every hit above must be negative-confirmation prose e.g. 'NO Aadhaar field' -- any hit that is"
echo " an actual field/label/value NAMED or SHAPED like Aadhaar is a Sev-1 finding, stop-and-report)"

echo
echo "== TC-008b: confirm zero validationRules directory under VS_Patient__c (supports TC-007) =="
if [ -d force-app/main/default/objects/VS_Patient__c/validationRules ]; then
  echo "UNEXPECTED: validation rules exist -- re-verify TC-007 assumption"
else
  echo "(none -- expected; no ValidationRule metadata on VS_Patient__c at all)"
fi

echo
echo "== TC-008c: live in-org field enumeration via Tooling API EntityParticle (bypasses FLS) =="
for OBJ in VS_Patient__c VS_Appointment__c; do
  QF="$(mktemp)"
  printf "SELECT QualifiedApiName FROM EntityParticle WHERE EntityDefinition.QualifiedApiName='%s'" "$OBJ" > "$QF"
  echo "--- $OBJ ---"
  sf data query --file "$QF" --use-tooling-api --target-org AgentForceClaudeWorkFlow --json
done
# Any QualifiedApiName containing "aadhaar"/"aadhar" (case-insensitive) in either object's field list
# is a Sev-1 BUG (Aadhaar field exists in-org), release-blocking, stop-and-report per rules/10 #1.
# Also eyeball the field list for anything diagnosis/clinical-shaped (REQ-045) -- none expected;
# VS_Dose_Number__c is an administrative dose-sequence counter, not clinical/diagnosis data.

echo
echo "== TC-007: live insert-then-delete of a same-length ALPHANUMERIC junk value in a free-text field =="
QF2="$(mktemp)"
cat > "$QF2" << 'APEXEOF'
VS_Patient__c pat = new VS_Patient__c(
    VS_Full_Name__c = 'ZZQATESTZZQA',
    VS_Date_Of_Birth__c = Date.newInstance(1990,1,1),
    VS_Mobile__c = '9000000099'
);
try {
    insert pat;
    System.debug('TC007:RESULT=INSERT_SUCCEEDED id=' + pat.Id);
    delete pat;
    System.debug('TC007:CLEANUP=DELETED');
} catch (Exception e) {
    System.debug('TC007:RESULT=INSERT_BLOCKED type=' + e.getTypeName() + ' msg=' + e.getMessage());
}
APEXEOF
sf apex run --file "$QF2" --target-org AgentForceClaudeWorkFlow
# Expected: INSERT_SUCCEEDED (no pattern validation blocks free-text junk) -- this is NOT a bug, it is
# the expected/designed posture per test-plan TC-007's own framing (data minimization = field ABSENCE,
# not input filtering). If INSERT_BLOCKED, investigate the new validation rule before assuming a bug.
