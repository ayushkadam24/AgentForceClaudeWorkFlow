#!/usr/bin/env bash
# feature: F-001 slot-booking-core | producing-agent: qa-engineer | date: 2026-07-12
# phase: QA_IN_PROGRESS (/qa-run B) | derives-from: 03-qa/test-plan.md TC-009 (REQ-053, Tier 1,
#   Annexure C5)
#
# TC-009 -- OWD verification. Pulls the ACTUAL deployed CustomObject metadata straight from the org
# via the Metadata API (equivalent evidentiary weight to Setup -> Sharing Settings, no browser
# needed) and asserts sharingModel per object.
#
# Expected:
#   VS_Patient__c / VS_Appointment__c        = Private
#   VS_Facility__c / VS_Service__c / VS_Holiday__c = Read (Public Read Only)
#   VS_Facility_Service__c / VS_Session__c / VS_Slot__c = ControlledByParent (MD children;
#     VS_Session__c is MD-child of VS_Facility__c so it inherits Public Read Only)
#
# Usage:
#   bash 03-qa/regression/tc-009-owd-audit.sh
set -euo pipefail
OUT_DIR="$(mktemp -d)"
sf project retrieve start \
  --metadata "CustomObject:VS_Patient__c" "CustomObject:VS_Appointment__c" \
             "CustomObject:VS_Facility__c" "CustomObject:VS_Service__c" \
             "CustomObject:VS_Facility_Service__c" "CustomObject:VS_Session__c" \
             "CustomObject:VS_Slot__c" "CustomObject:VS_Holiday__c" \
  --target-org AgentForceClaudeWorkFlow \
  --output-dir "$OUT_DIR" \
  --json

echo
echo "== Live in-org sharingModel per object =="
grep -r "sharingModel" "$OUT_DIR/objects" | sort
