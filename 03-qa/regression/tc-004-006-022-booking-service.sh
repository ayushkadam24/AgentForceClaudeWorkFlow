#!/usr/bin/env bash
# feature: F-001 slot-booking-core | producing-agent: qa-engineer | date: 2026-07-12
# phase: QA_IN_PROGRESS (/qa-run A) | derives-from: 03-qa/test-plan.md TC-004/TC-006/TC-022,
#   force-app/main/default/classes/VS_BookingServiceTest.cls
#
# Regression spec for TC-004 (online capacity ceiling boundary), TC-006 (repeat-after-full rejected,
# no dup row) and TC-022 (booking reference format/uniqueness/collision-retry).
#
# WHY THIS WRAPS THE DEPLOYED UNIT TEST INSTEAD OF FRESH QA-AUTHORED FIXTURES: live Anonymous Apex
# under the connected admin session cannot invoke VS_BookingService.book() at all in this DE org (the
# admin has no FLS on VS_Session__c.VS_Walk_In_Reserve_Count__c, which book()'s FOR UPDATE lock query
# reads for EVERY channel) — see 03-qa/evidence/run-A/TC-024-and-live-book-blocker-diagnostic.txt.
# VS_BookingServiceTest.cls internally creates its OWN FLS-bearing user and runs book() under
# System.runAs() (legal only inside @IsTest) — this IS "Apex regression vs deployed unit test, real
# org data" exactly as TC-004's Type column in the test plan specifies, executed live against
# AgentForceClaudeWorkFlow (not a simulation), with fresh, real, per-run pass/fail evidence.
#
# TC-004 <- testCapacityExhaustion_online_neverOverbooks (fills slot cap=2 exactly, 3rd throws
#           SLOT_FULL, asserts VS_Booked_Count__c never exceeds capacity, slot flips Full).
# TC-006 <- the SAME test's final asserts (apptCount(slot) == capacity exactly after the rejected
#           3rd attempt -> no duplicate/extra VS_Appointment__c row from a rejected repeat booking).
# TC-022 <- testBookingReference_uniqueAndPopulatedAndTypeable (8-char, Crockford base32 regex
#           [0-9A-HJKMNP-TV-Z]{8} i.e. no I/L/O/U, two bookings get distinct references) +
#           testReferenceCollision_regeneratesAndRetriesOnce_bookingSucceeds (forced collision ->
#           regenerate + retry once -> succeeds with a NEW distinct reference) +
#           testReferenceCollision_twiceInARow_throwsCodedException (forced double collision ->
#           coded REFERENCE_COLLISION, not a leaked DmlException, and no extra row).
#
# Usage:
#   bash 03-qa/regression/tc-004-006-022-booking-service.sh
set -euo pipefail
sf apex run test \
  --tests VS_BookingServiceTest \
  --target-org AgentForceClaudeWorkFlow \
  --result-format human \
  --synchronous

# Expected: "Outcome Passed", 9/9 tests, 100% pass rate. A FAIL here on
# testCapacityExhaustion_online_neverOverbooks or either reference-collision test is a Sev-1/Sev-2
# regression of the RFP §3.4 online ceiling or the D-016 reference contract respectively — file a
# BUG-### immediately per 03-qa/bug-reports skill, do not re-run-until-green.
