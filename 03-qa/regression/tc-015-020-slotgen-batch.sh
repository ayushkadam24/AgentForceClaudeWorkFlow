#!/usr/bin/env bash
# feature: F-001 slot-booking-core | producing-agent: qa-engineer | date: 2026-07-12
# phase: QA_IN_PROGRESS (/qa-run A) | derives-from: 03-qa/test-plan.md TC-015..020,
#   force-app/main/default/classes/VS_SlotGenBatchTest.cls
#
# Regression spec for TC-015 (even distribution), TC-016 (holiday skip), TC-017 (drive-day
# override), TC-018 (booking-horizon boundary), TC-019 (>=200-session governor safety), TC-020
# (idempotent re-run). Same rationale as tc-004-006-022-booking-service.sh for wrapping the deployed
# test class rather than fresh live Anonymous Apex (VS_SlotGenerationService.generateForSessions()'s
# start()-query equivalent also reads FLS-gated optional fields — VS_Is_Drive_Day__c,
# VS_Bookable_Capacity__c — that the connected admin session cannot access live; the test class's own
# System.runAs(slotGenUser()) sidesteps this legally, inside @IsTest only).
#
# TC-015 <- testEvenDistribution_sumsToBookableExactly (80 total/25% reserve -> 60 bookable, 16
#           slots, sum(slot cap)==60 EXACTLY, remainder(12) on the 12 earliest slots -> 4 each vs 3).
# TC-016 <- testHolidaySkip_generatesNoSlots (normal session on a VS_Holiday__c date -> 0 slots).
# TC-017 <- testDriveDayOverridesHoliday_generatesSlots (VS_Is_Drive_Day__c=true on the SAME holiday
#           date -> slots generated, sum still == bookable).
# TC-018 <- testBookingHorizon_excludesBeyondHorizon (session at today+30, beyond
#           BookingHorizonDays=14 -> 0 slots; in-horizon session still generates). NOTE: this test
#           does not independently exercise the exact day-13/14/15 + past-dated matrix the test plan
#           describes (A-015 past-date exclusion is unit-tested elsewhere in
#           VS_SlotGenerationService/VS_SlotGenBatch design, not re-verified fresh this run) — see
#           the qa-engineer Run A report for the explicit caveat.
# TC-019 <- testBulk_250Sessions_isGovernorSafe (250 sessions -> 2000 slots, <=4 SOQL / ==1 DML for
#           the whole scope, sum invariant spot-checked).
# TC-020 <- testReRun_isIdempotent (2nd Database.executeBatch on an already-slotted session adds 0).
#
# Usage:
#   bash 03-qa/regression/tc-015-020-slotgen-batch.sh
set -euo pipefail
sf apex run test \
  --tests VS_SlotGenBatchTest \
  --target-org AgentForceClaudeWorkFlow \
  --result-format human \
  --synchronous

# Expected: "Outcome Passed", 12/12 tests, 100% pass rate. A FAIL on testEvenDistribution_* is a
# Sev-1 A-005/D-023 regression; a FAIL on testBulk_250Sessions_isGovernorSafe (SOQL>4 or DML!=1) is a
# Sev-1 REQ-062 governor regression. File a BUG-### per the bug-reports skill.
