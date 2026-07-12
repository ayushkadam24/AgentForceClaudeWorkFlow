# Apex & Trigger Best Practices (reference)

## Triggers
- ONE trigger per object, no logic in it: delegate to PFX_<Object>TriggerHandler.
- Handler pattern: static boolean bypass flag (for data loads), context-method routing
  (beforeInsert/afterUpdate...), recursion guard via static Set<Id> of processed records.
- Order-of-execution awareness: after-save flows run AFTER apex triggers; never implement the
  same rule in both. The automation matrix in technical-design.md decides which owns what.
- Never assume Trigger.new size is 1 — every path handles 200 records.

## Bulkification & limits
- SOQL: outside loops, selective WHERE (indexed: Id, Name, External IDs, lookups), only needed
  fields. Aggregate queries for counts, not loops.
- DML: collect in Lists, one DML per object type per context. Use Database.insert(records, false)
  + Database.SaveResult inspection when partial success is acceptable; all-or-none otherwise.
- Watch: 100 SOQL / 150 DML per sync transaction; heap 6MB; CPU 10s. Near limits? Move to Queueable.

## Error handling
- Custom exceptions per domain (PFX_BookingException, PFX_StockException) with message CODES
  ('SLOT_FULL', 'CUTOFF_PASSED') the UI maps to friendly text — never user-facing raw messages.
- try/catch only where you can act on it; log to PFX_Error_Log__c (or Platform Event) with class,
  method, record ids, stack; NEVER an empty catch.
- addError() in triggers for record-level validation failures (keeps the rest of the batch).

## Security
- `with sharing` default; `inherited sharing` for service classes callable from various contexts.
- WITH USER_MODE on SOQL / Security.stripInaccessible before DML in user-facing paths.
- No dynamic SOQL from user input without String.escapeSingleQuotes + bind variables.

## Async
- Queueable > future (chaining, complex args, Finalizers for guaranteed cleanup/retry).
- Scheduled jobs idempotent: re-running the no-show marker or reminder job must not double-fire
  (check a marker field/log before acting).
- Batch Apex only for >50k-row jobs (archival per retention rules C4).

## Testing
- Test the CONTRACT: given inputs → expected records/exception, not implementation details.
- @TestSetup data factory (PFX_TestFactory) — never org data, no SeeAllData.
- System.runAs per persona permission set to test visibility rules (C5).
- Negative paths mandatory: full slot, past cut-off, wrong facility staff access.
- Test.startTest/stopTest around async to force execution; assert the async OUTCOME.
