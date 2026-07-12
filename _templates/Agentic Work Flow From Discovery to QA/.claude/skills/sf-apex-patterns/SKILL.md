---
name: sf-apex-patterns
description: Apex patterns for the <domain-item> scheduler — service layer, FOR UPDATE slot locking, test patterns. Used by dev-senior (and dev-mid for simple Apex) in DEV_IN_PROGRESS.
---

# Apex Patterns

## Service layer shape
`PFX_BookingService.book(patientId, slotId, bookedById)` is the ONLY path that creates a
confirmed appointment (UI, chat, staff console all call it). Pattern:

```apex
public with sharing class PFX_BookingService {
    public class PFX_BookingException extends Exception {}

    public static Id book(Id patientId, Id slotId, Id bookedById) {
        // 1. Lock the slot row — blocks concurrent bookers until commit
        PFX_Slot__c slot = [SELECT Id, PFX_Capacity__c, PFX_Booked_Count__c, PFX_Status__c
                           FROM PFX_Slot__c WHERE Id = :slotId FOR UPDATE];
        // 2. Re-check capacity INSIDE the lock
        if (slot.PFX_Booked_Count__c >= slot.PFX_Capacity__c || slot.PFX_Status__c != 'Open') {
            throw new PFX_BookingException('SLOT_FULL');
        }
        // 3. Create appointment + increment counter in the SAME transaction
        //    (counter denormalized on slot; the lock makes the read-check-write atomic)
        ...
    }
}
```
Why this passes <CRITICAL_REQ (e.g. RFP §x.y)>: two simultaneous requests for the last place serialize on the row
lock; the second re-reads inside its lock, sees capacity exhausted, and gets SLOT_FULL.
Never check capacity outside the lock; never maintain the count only via triggers/rollups
(they don't serialize).

## Other patterns
- Trigger → `PFX_<Object>TriggerHandler` (one per object) → service. Handler has no logic beyond routing.
- Async: Queueable for SMS dispatch fan-out; Scheduled Apex/Flow for end-of-day no-show marking
  and next-dose due computation. Idempotent — safe to re-run.
- Config via `PFX_Setting__mdt`: CutOffHours, ReminderOffsets, WalkInReservePct, BookingHorizonDays.
- SMS behind an interface (`PFX_ISmsProvider` + `PFX_SmsService`) — gateway vendor undecided (Annexure C7.4);
  POC implementation logs to `PFX_Notification_Log__c` instead of calling a real gateway.

## Test patterns
- @TestSetup builds facility→service→schedule→slots; helpers make synthetic citizens (no real data).
- Capacity-exhaustion test: fill a slot to capacity, assert next book() throws SLOT_FULL and
  no extra appointment row exists.
- Cut-off test: cancellation inside cut-off window rejected.
- Assert data state after the action, not merely "no exception thrown".

## Deep reference
Full Apex & trigger best practices: `references/apex-best-practices.md` in this skill folder.
