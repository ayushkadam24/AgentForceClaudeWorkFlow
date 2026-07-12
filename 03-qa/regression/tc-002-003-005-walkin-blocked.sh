#!/usr/bin/env bash
# feature: F-001 slot-booking-core | producing-agent: qa-engineer | date: 2026-07-12
# phase: QA_IN_PROGRESS (/qa-run A) | derives-from: 03-qa/test-plan.md TC-002/TC-003/TC-005, D-028,
#   force-app/main/default/classes/VS_BookingServiceWalkInTest.cls
#
# Regression spec for the walk-in reserve path (TC-002 mixed-channel load, TC-003 mixed disjoint
# pools, TC-005 walk-in reserve functional ceiling). THIS IS AN EXPECTED-FAIL / KNOWN-ORG-LIMIT
# REGRESSION CHECK, not a green-bar spec: D-028 documents that this DE org FLS-filters the plain
# system-mode `update session;` on the REQUIRED field VS_Walk_In_Used_Count__c
# (VS_BookingService.book():182) even under a permset-bearing runAs user, so all 3 walk-in test
# methods fail at that line, not at any overbooking assert. Re-run this on every future QA pass on
# THIS org to confirm the failure signature is UNCHANGED (still exactly book:182,
# "fields being inaccessible on Sobject VS_Session__c") — any DIFFERENT failure (e.g. an assert
# failure instead of a DmlException, or a failure at a different line) would mean either the org
# limitation was resolved (re-run the full walk-in suite as a real test, not just a regression
# check) or a NEW regression was introduced — either way, escalate immediately.
#
# Usage:
#   bash 03-qa/regression/tc-002-003-005-walkin-blocked.sh
set -euo pipefail
sf apex run test \
  --tests VS_BookingServiceWalkInTest \
  --target-org AgentForceClaudeWorkFlow \
  --result-format human \
  --synchronous || true

echo ""
echo "EXPECTED (until D-028's org limitation is lifted or a devops-provided workaround exists):"
echo "  3 tests run, 0 pass, 3 fail, ALL at VS_BookingService.book:182 with"
echo "  'System.DmlException: Operation failed due to fields being inaccessible on Sobject VS_Session__c'"
echo "If the failure signature differs from this, STOP and escalate (see script header)."
