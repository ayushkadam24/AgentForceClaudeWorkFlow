#!/usr/bin/env bash
# feature: F-001 slot-booking-core | producing-agent: qa-engineer | date: 2026-07-12
# phase: QA_IN_PROGRESS (/qa-run A) | derives-from: 03-qa/test-plan.md §3, TC-001/TC-002/TC-003
#
# THE §3.4 CROWN-JEWEL LOAD TEST HARNESS. This is a RE-RUNNABLE script, but it is currently BLOCKED
# (see 03-qa/evidence/run-A/TC-001-run1-concurrent-http-timing.txt for the full run-1 evidence and
# the qa-engineer Run A report for the complete root-cause accounting). It requires an authenticated
# session (access token) for a user carrying FLS equivalent to VS_Booking_Engine_Test_Context on
# VS_Session__c (incl. VS_Walk_In_Reserve_Count__c read) — the connected-org admin does NOT have
# this, and qa-engineer is not authorized to grant it. Precondition for re-running this for real:
# either (a) an authenticated session as the dedicated "QA Load Test Harness" user (seed.apex Part 1
# creates this user + assigns the permset; obtaining a session for it needs devops/admin action this
# environment could not perform — e.g. a connected-app username-password OAuth flow or an
# interactive "Login As"), or (b) the test-plan §3 fallback: a temporary QA-owned diagnostic Apex
# REST endpoint deployed by devops that wraps book() and is removed after the load test.
#
# Usage (once a valid ACCESS_TOKEN + INSTANCE_URL for an FLS-adequate session are available):
#   export SF_ACCESS_TOKEN=...   # never echo/print/persist this value to a file or log
#   export SF_INSTANCE_URL=https://orgfarm-cb999a8bfb-dev-ed.develop.my.salesforce.com
#   export SLOT_ID=<VS_Slot__c Id seeded with the boundary capacity for the TC under test>
#   export CHANNEL=Portal   # or WalkIn for TC-002, or run twice (Portal+WalkIn) for TC-003
#   export N=20              # concurrent calls, test-plan minimum
#   bash 03-qa/regression/tc-001-003-concurrency-load.sh
set -euo pipefail
: "${SF_ACCESS_TOKEN:?export SF_ACCESS_TOKEN first}"
: "${SF_INSTANCE_URL:?export SF_INSTANCE_URL first}"
: "${SLOT_ID:?export SLOT_ID first}"
: "${CHANNEL:=Portal}"
: "${N:=20}"
OUT_DIR="03-qa/evidence/run-A/$(date +%Y%m%d-%H%M%S)-load"
mkdir -p "$OUT_DIR"

for i in $(seq 1 "$N"); do
  APEXBODY="VS_Patient__c p=new VS_Patient__c(VS_Full_Name__c='LoadTest $CHANNEL $i',VS_Date_Of_Birth__c=Date.newInstance(1990,1,1),VS_Mobile__c='90000${i}0000'); insert p; try { Id a=VS_BookingService.book(p.Id, Id.valueOf('$SLOT_ID'), UserInfo.getUserId(), '$CHANNEL'); System.debug('RESULT:SUCCESS:'+a);} catch (Exception e){ System.debug('RESULT:FAIL:'+e.getTypeName()+':'+e.getMessage());}"
  ( curl -s -G "$SF_INSTANCE_URL/services/data/v60.0/tooling/executeAnonymous" \
      -H "Authorization: Bearer $SF_ACCESS_TOKEN" \
      --data-urlencode "anonymousBody=$APEXBODY" \
      -o "$OUT_DIR/call_$i.json" -w "call_$i http=%{http_code} start=%{time_starttransfer}\n" ) &
done
wait
echo "All $N calls fired concurrently -> $OUT_DIR"
echo "Next: SOQL-verify via anonymous Apex (NOT this script) that:"
echo "  - exactly ONE new VS_Appointment__c exists for the seeded place"
echo "  - VS_Slot__c.VS_Booked_Count__c <= VS_Capacity__c (TC-001/003) and/or"
echo "    VS_Session__c.VS_Walk_In_Used_Count__c <= VS_Walk_In_Reserve_Count__c (TC-002/003)"
echo "  - every other call's debug log shows RESULT:FAIL:...SLOT_FULL or WALKIN_RESERVE_FULL"
echo "    (retrieve via ApexLog / Trace Flag if debug-line-level confirmation is required)"
echo "Repeat x3 total per test-plan §3. ANY double-book on ANY repeat = Sev-1, stop-and-report."
