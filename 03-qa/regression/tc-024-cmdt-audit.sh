#!/usr/bin/env bash
# feature: F-001 slot-booking-core | producing-agent: qa-engineer | date: 2026-07-12
# phase: QA_IN_PROGRESS (/qa-run B) | derives-from: 03-qa/test-plan.md TC-024 (D-027)
#
# TC-024 -- VS_Setting__mdt full tunable audit. Run this FIRST in any QA session (capacity-dependent
# TCs assume WalkInReservePct=25 etc). Queries all 6 records and asserts exact values.
#
# Usage:
#   bash 03-qa/regression/tc-024-cmdt-audit.sh
set -euo pipefail
QUERY_FILE="$(mktemp)"
printf 'SELECT DeveloperName, VS_Value__c, VS_Value_Text__c FROM VS_Setting__mdt ORDER BY DeveloperName' > "$QUERY_FILE"
sf data query --file "$QUERY_FILE" --target-org AgentForceClaudeWorkFlow --json

# Expected exact values (assert manually against the JSON output above, or pipe to a JSON assertion
# tool in CI):
#   BookingHorizonDays        VS_Value__c = 14
#   CutOffHours                VS_Value__c = 4
#   DefaultSlotGranularityMins VS_Value__c = 15
#   NoShowThresholdCount       VS_Value__c = 3
#   ReminderOffsetsHours       VS_Value_Text__c = "24,3"
#   WalkInReservePct           VS_Value__c = 25
# A mismatch on WalkInReservePct/CutOffHours/DefaultSlotGranularityMins is a Sev-2+ config-integrity
# bug (these feed the §3.4 capacity math directly) -- file BUG-### immediately, do not proceed to
# capacity-dependent TCs until fixed/explained (e.g. TC-021's intentional temporary edit, restored).
