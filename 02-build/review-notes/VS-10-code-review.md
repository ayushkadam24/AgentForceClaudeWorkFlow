# VS-10 Code Review — VS_PatientService.findOrCreate (exact-match de-dup)

- Feature: F-001 slot-booking-core
- Producing agent: code-reviewer (independent)
- Date: 2026-07-13
- Phase: (pipeline YAML = DONE; this is a forward-build ticket reviewed on request — see note)
- Upstream IDs: REQ-004, REQ-046 / EP-05 / D-011, D-017, D-028 / VS-07 (schema), VS-09 (pattern parent)
- Files reviewed: VS_PatientService.cls, VS_PatientException.cls, VS_PatientServiceTest.cls (+ meta),
  VS_Patient_Service_Test_Context.permissionset-meta.xml, VS_Patient__c fields.

> UNVERIFIED — NO ORG DRY-RUN AT REVIEW-TIME. Per ORG-SAFETY (live client orgs connected) no `sf`
> command was run. `node scripts/metadata-lint.js` WAS run offline (output below). A delta
> `sf project deploy start --dry-run` + `sf apex run test` on the DE org is the orchestrator's
> consolidated step; this packet must NOT be treated as "buildable" until that green run exists.
> The central finding below (BLOCKER-1) is a predicted deploy-time TEST FAILURE reasoned statically;
> it is org-unverified but high-confidence for the reason given.

## metadata-lint (offline, real output)
```
== Metadata lint ==
  FAIL formula reads $CustomMetadata ... VS_Session__c/fields/VS_Walk_In_Reserve_Count__c.field-meta.xml
  FAIL formula reads $CustomMetadata ... VS_Setting__mdt/fields/VS_Value__c.field-meta.xml
== 2 metadata-limit issue(s) ==
```
Both FAILs are the pre-existing documented `$CustomMetadata`-in-formula items (VS-05/VS-02), NOT
VS-10 files. No VS-10 file is flagged. Ticket-scoped lint: PASS.

## Verdict by category
- CORRECTNESS vs AC: FINDINGS (AC-1/2/3/4 logic correct in production code, but create-path TESTS
  will not pass as written — BLOCKER-1).
- §3.4 INTEGRITY: N/A (not booking-path; no capacity/lock in scope).
- SECURITY: PASS (with sharing; `insert as user`; SOQL WITH USER_MODE; custom coded exception;
  no hardcoded Ids; no empty catch; duplicate detection by STATUS CODE not message/field-read).
- COMPLIANCE: PASS (no Aadhaar; C1-only person data; match key composed of C1 fields, FLS-restricted;
  synthetic .example test data; OWD Private honored via with sharing).
- STANDARDS: PASS with minors (service-layer, single-source normalization, ApexDoc present).
- DEPLOYABILITY: FINDINGS (BLOCKER-1 fails RunSpecifiedTests → deploy would fail).
- TESTS: FINDINGS (harness permset gap + two uncovered negative branches).

## Findings

### BLOCKER-1 — Test harness permset omits FLS on the three REQUIRED match-key input fields → create-path tests fail under `insert as user`
- File: force-app/main/default/permissionsets/VS_Patient_Service_Test_Context.permissionset-meta.xml
  (fieldPermissions block, lines 17-51) vs VS_PatientService.cls:88 (`insert as user patient`).
- What: `findOrCreate()` writes VS_Full_Name__c, VS_Date_Of_Birth__c, VS_Mobile__c (always),
  plus VS_Match_Key__c/VS_Consent_Given__c/VS_Consent_Timestamp__c, then inserts in USER_MODE.
  The harness permset grants FLS on Match_Key, Consent_Given, Consent_Timestamp, Email, Gender,
  Locality, Pincode — but NOT on VS_Full_Name__c, VS_Date_Of_Birth__c, VS_Mobile__c. All three are
  required=true and are set on every create.
- Why it matters: `insert as user` enforces FLS. Writing values into fields the running user cannot
  edit fails the DML (FLS violation; and these being required, a strip would instead yield
  REQUIRED_FIELD_MISSING) — either way a non-DUPLICATE_VALUE DmlException. `isDuplicateKeyError()`
  returns false, so it is rethrown untouched. Every test that reaches the `insert as user` path
  therefore fails: testCreatesNewPatient_stampsConsent, testExactMatch_returnsSameId_noNewRow,
  testDifferingField_createsNew, and testRaceSafe_duplicateInsertResolvesToExisting (the seeded row
  is plain `insert`, but the service's `insert as user` throws on FLS before ever reaching the
  duplicate). Only the throw-before-DML tests (consent-false, invalid-input) and buildMatchKey pass.
  Deploy runs with RunSpecifiedTests → the deploy FAILS, and ACs 1/2/3/4-positive are never actually
  demonstrated. Contrast: VS_BookingServiceTest.newPatient uses PLAIN `insert` (system FLS, not
  enforced) so it passed with only Match_Key FLS — that precedent does NOT carry to this class,
  which uses USER_MODE.
- Direction: add readable+editable fieldPermissions for VS_Patient__c.VS_Full_Name__c,
  .VS_Date_Of_Birth__c, .VS_Mobile__c to this TEST-ONLY permset, then re-run
  `sf apex run test -t VS_PatientServiceTest` on the DE org and paste the green result before the
  packet may claim buildable. (Org-unverified but high-confidence; confirm on the run.)

### MINOR-1 — Two negative branches uncovered by tests
- File: VS_PatientService.cls:91-92 (non-duplicate DmlException rethrow) and :135-137
  (existingIdForKey miss → DEDUP_LOOKUP_FAILED).
- What: neither branch is exercised. The rethrow path is a meaningful negative (an unrelated DML
  failure must propagate as the raw DmlException, not be misclassified as a dup); the
  DEDUP_LOOKUP_FAILED path is "unreachable" but coded deliberately.
- Why it matters: rules/20 wants a negative test; and once BLOCKER-1 is fixed, coverage should be
  re-measured to confirm >=85% with these branches accounted for.
- Direction: add a test that forces a non-duplicate DmlException through findOrCreate (e.g. a
  value that violates a different constraint) and asserts a plain DmlException (not VS_PatientException)
  surfaces. DEDUP_LOOKUP_FAILED may stay uncovered with a one-line justification.

### NIT-1 — VS_Match_Key__c field description (VS-07) says "upsert-by-external-id"; implementation uses insert+catch
- File: force-app/main/default/objects/VS_Patient__c/fields/VS_Match_Key__c.field-meta.xml:5.
- What: the VS-07 field doc states the key is populated "via upsert-by-external-id". VS-10 implements
  the AC-3 co-equal alternative (insert + catch DUPLICATE_VALUE + re-query).
- Why it matters: doc drift only; AC-3 explicitly permits this option, and insert+catch is in fact
  SAFER than upsert here (it never overwrites an existing row's consent). Not editable by this ticket.
- Direction: reconcile the VS-07 field description wording in a later touch; no code change.

## Open-flag rulings (builder asked reviewer to confirm)
- insert+catch vs literal "upsert by external id" (design line 340/D-017): ACCEPTABLE and preferred.
  AC-3 lists "insert + catch DUPLICATE_VALUE then re-query" as co-equal; it gives clean create-vs-existing
  semantics and does not mutate an existing patient's consent. Confirmed OK.
- A-new-a (consent gate enforced upfront even for existing-patient resolution): reasonable/conservative;
  a BA/DHO confirmation item, not a code defect. No consent-less row can ever be created; an existing
  row is returned unmutated.
- Concurrent OTP ticket's VS_Otp_Test_Context lint FAIL: not a VS-10 file; correctly left untouched.

## Recommendation
REJECT — BLOCKER-1 (harness permset FLS gap) will fail the deploy-time test run for all four
substantive AC tests; fix is mechanical (3 fieldPermissions) but it currently blocks buildable/deploy.
Re-review after the permset fix + a green `sf apex run test VS_PatientServiceTest` on the DE org.
Production code (VS_PatientService/VS_PatientException) is otherwise sound, secure, and compliant.

---

## Fix-cycle resolution (orchestrator, 2026-07-13) — BLOCKER-1 REJECTED as a false positive

BLOCKER-1 asked to add `fieldPermissions` for `VS_Full_Name__c`, `VS_Date_Of_Birth__c`,
`VS_Mobile__c` to `VS_Patient_Service_Test_Context`. That fix is **not applied** because it is
both unnecessary and itself a deploy-breaker:

1. All three fields are verified `required=true` (universally required — see their field-meta.xml).
   A universally-required field CANNOT carry field-level security; a `<fieldPermissions>` entry for
   one fails deploy with "field cannot have field-level security". This is exactly what the new
   `scripts/metadata-lint.js` check-4 catches and what memory A-021 already recorded on the A-018
   permset. Adding the three entries would introduce a fresh check-4 lint FAIL.
2. Universally-required fields are inherently editable by any user with object Create/Edit — they
   have no FLS to violate. Under `insert as user`, the harness user (granted `allowCreate=true` on
   VS_Patient__c plus FLS on the FLS-eligible written fields: Match_Key, Consent_Given,
   Consent_Timestamp) can therefore write the three required fields without an FLS error. The
   create-path tests are expected to PASS with the permset **as-is**.

The reviewer conflated "absent from the permset's fieldPermissions" with "not editable"; for a
required field those are not the same. `VS_PatientService.cls` and
`VS_Patient_Service_Test_Context.permissionset-meta.xml` are therefore **left unchanged**.

Full-tree `node scripts/metadata-lint.js` = clean on all VS-10 files (only the 2 pre-existing
Sprint-1 `$CustomMetadata`-formula FAILs remain, unrelated).

Single org-confirm item: on the consolidated `sf apex run test -t VS_PatientServiceTest` run,
confirm the create-path tests pass. If — contrary to standard semantics — this DE org's D-028
anomaly were to strip a required field under USER_MODE, the correct remedy would be to switch the
patient `insert` to system mode for that write, NOT to add impossible FLS. Not pre-applied;
standard semantics say the current code is correct.

MINOR-1 (non-duplicate-DmlException negative test) and NIT-1 (VS-07 field-doc wording) are carried
to a follow-up per the fix-2-blockers scope.

## ORG-VERIFIED (2026-07-13, AgentForceClaudeWorkFlow) — BLOCKER-1 false-positive CONFIRMED
Validate-only deploy (RunLocalTests) = **Succeeded**, 54 tests / 0 failures / 0 coverage warnings.
`VS_PatientServiceTest` create-path tests PASS with the permset **unchanged** — proving BLOCKER-1
was a false positive (required fields don't need/allow FLS; writable under insert-as-user).
VS_PatientService coverage 93%. The org-confirm item flagged above is now CLOSED-CONFIRMED.
