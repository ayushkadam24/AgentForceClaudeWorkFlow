# VS-13 Code Review — VS_IOtpProvider + VS_OtpService (stub) + VS_OTP_Verification__c

- Feature: F-001 slot-booking-core
- Producing agent: code-reviewer (independent)
- Date: 2026-07-13
- Phase: PIPELINE_STATE = DONE (F-001 pilot closed). VS-13 is a forward/next-sprint build (EP-06),
  reviewed on orchestrator request. Phase-advance is a human gate — see compliance note.
- Ticket: VS-13 (EP-06, design section 6.4) — derives from REQ-058/059, D-013, A-004, C7 (rules/10 section 8)
- Files reviewed: VS_OTP_Verification__c object + 5 fields; VS_IOtpProvider, VS_OtpStubProvider,
  VS_OtpService, VS_OtpException, VS_OtpServiceTest (+ meta); VS_Otp_Test_Context permset.

## UNVERIFIED — NO ORG DRY-RUN AT REVIEW TIME
No `sf` command was run (org-safety). Deployability assessed by static read + offline
`node scripts/metadata-lint.js` only. The orchestrator's consolidated delta dry-run + `sf apex run test`
must confirm buildability and coverage before this packet may claim "buildable". "XML well-formed" is
not evidence of deployability.

## Metadata lint (offline, real output)
`node scripts/metadata-lint.js` → exit 1, 2 issues, BOTH on pre-existing non-VS-13 files:
- VS_Session__c/VS_Walk_In_Reserve_Count__c ($CustomMetadata formula — Sprint 1, known/D-027)
- VS_Setting__mdt/VS_Value__c ($CustomMetadata coupling — Sprint 1)
No VS-13 file trips the linter. Per the review bar, a lint FAIL is a blocker only when on the ticket's
own files; VS-13's files are lint-clean. (The two standing FAILs are a pre-existing repo condition, not
introduced here.)

## Verdict by category
- CORRECTNESS vs AC: PASS
- SECURITY (least-privilege, CRUD/FLS, write-path): PASS with 1 MAJOR hardening (counter race)
- COMPLIANCE (no-Aadhaar / C1-minimal / OWD Private): PASS
- STANDARDS (rules/20): PASS
- TESTS: PASS (7 methods, meaningful state asserts, negative + lockout paths)
- DEPLOYABILITY: UNVERIFIED (no org) — lint-clean on VS-13 files; tunable CMDT records absent (fallbacks)

## AC walk-through
- AC1 object VS_OTP_Verification__c OWD Private + 5 described VS_ fields: MET. sharingModel Private;
  VS_Mobile__c(Phone), VS_Code_Hash__c(Text 128), VS_Expiry__c(DateTime), VS_Attempts__c(Number def 0),
  VS_Verified__c(Checkbox def false). All described. No Aadhaar.
- AC2 VS_IOtpProvider seam + service orchestration + fixed-code POC stub, store hash not plaintext:
  MET. issue() persists mobile + salted SHA-256 hex + expiry + attempts=0 + verified=false; plaintext is
  transient only. Stub TEST_CODE "000000" documented. Seam swap proven by test #7.
- AC3 verify() lockout after 3 failed attempts, hash compare, with sharing / user-mode DML / custom
  exception / ApexDoc: MET. 4th call rejected TOO_MANY_ATTEMPTS before hash compare; `with sharing`,
  `insert/update as user`, `WITH USER_MODE` SOQL, VS_OtpException, full ApexDoc.
- Test class (issue-stores-hash, successful verify, expiry, lockout-after-3, D-028 runAs): MET, plus
  invalid-input/not-found/already-verified/seam-swap.

## Findings

### MAJOR
- M-1 (security) VS_OtpService.verify() lines 86-128: the lockout counter is a read-modify-write on
  VS_Attempts__c with NO row lock (SELECT ... WITHOUT FOR UPDATE, then update). Under concurrent verify()
  calls for one mobile, N requests each read attempts=0 before any increment commits, so the brute-force
  ceiling can be bypassed — the whole purpose of the lockout over a 6-digit space. Not a section 3.4
  booking path and the AC is satisfied sequentially, so this is not a blocker, but it is the hostile-
  thinking gap on this feature. Direction: `SELECT ... FOR UPDATE` on the challenge row before the
  attempts check/increment (mirrors the section 3.4 pattern), or gate issue/verify per-mobile. Note: not
  reproducible in an Apex unit test — call out as a QA/load concern for real citizen-auth rollout.

### MINOR
- N-1 (design drift) VS_Expiry__c: ticket AC says VS_Expiry__c, technical-design 2.3 says
  VS_Expires_At__c. Built to AC and flagged in the field description. Architect must reconcile the
  canonical name before any downstream consumer (registration/booking journey) references it — a later
  rename is a breaking change. Correctly surfaced by the builder, not silently dropped.
- N-2 (production readiness) VS_OtpService line 30: the stub is the hard-coded DEFAULT provider
  (`new VS_OtpStubProvider()`). Shipped as-is to a real org, every OTP is "000000". Acceptable and
  in-scope for the POC (no real gateway exists to bind), and documented, but there is no environment
  guard. Direction: before any non-POC org, bind the real VS_IOtpProvider via config (CMDT/type name)
  and/or throw if the stub is active outside a sandbox. Must never reach prod.
- N-3 (config) Tunable records VS_Setting.OtpExpiryMinutes / OtpMaxAttempts are not authored (DE-org
  CMDT MDAPI quirk, D-027). getInstance returns null → coded fallbacks (10 min / 3 attempts) apply, so
  the service runs, but the "config not hardcode" intent is only half-realized until the records are
  created in Setup. Documented manual post-deploy step — acceptable; confirm the values match design.
- N-4 (hardening) Hash salt is mobile-only, no server-side pepper/HMAC. Adequate vs simple rainbow
  tables for the POC; production should use a per-record random salt or HMAC with a Protected CMDT
  secret. Cheap future change behind the same field. Builder-flagged.
- N-5 (policy) verify() takes the latest challenge (ORDER BY CreatedDate DESC LIMIT 1). Fine for the
  single-active-challenge POC flow; confirm desired multi-challenge policy before multi-issue scenarios.

### NIT
- Descriptions contain the word "Aadhaar" only in negation ("NO Aadhaar field ever"). Consistent with
  prior tickets and QA's no-Aadhaar scan (which targets numerals/fields); benign, no action required.

## Recommendation: APPROVE-WITH-FIXES
No blocker: all ACs met, write path is single + user-mode, OWD Private, hash-not-plaintext verified,
lint-clean on VS-13 files. Batch M-1 (concurrency lockout) and N-2 (stub-default guard) before this seam
backs a real citizen-auth journey; N-1 needs an architect ruling on the field name. Human runs the
verdict; orchestrator must still run the delta dry-run + apex tests to clear the UNVERIFIED banner.

## ORG-VERIFIED (2026-07-13) + two deploy-fixes (surfaced only at org compile)
Validate-only deploy (RunLocalTests) against AgentForceClaudeWorkFlow = **Succeeded**,
54 tests / 0 failures; VS_OtpService coverage 97%.
1. `VS_OTP_Verification__c.VS_Code_Hash__c` had `<caseSensitive>true</caseSensitive>` without
   `unique` — invalid ("CaseSensitive can only be set for fields with unique also set"). Removed it;
   the hash comparison is a case-sensitive Apex String equality regardless of the DB-field setting.
2. `VS_OtpService.verify()` SOQL had `WITH USER_MODE` AFTER `ORDER BY`/`LIMIT` (parse error). Moved
   it to the correct clause position (immediately after WHERE, before ORDER BY).
