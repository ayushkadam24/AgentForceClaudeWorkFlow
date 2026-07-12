---
name: sf-deploy-troubleshooting
description: Salesforce Metadata API deploy-failure taxonomy + troubleshooting protocol, distilled from a real engagement where 2 full-manifest deploys failed opaquely and 8 fix-forward blockers (A-H) were needed before a clean deploy. Read BEFORE the first deploy of any project.
---

# Salesforce Deploy Troubleshooting — field-proven taxonomy

## The 6-step protocol (mandatory when a deploy/dry-run fails)
1. CAPTURE before fixing: deploy ID, full --json report, error verbatim, into the deploy ledger.
2. Never retry unchanged twice. Same command + same input = same failure.
3. LAYER BISECTION on opaque errors: single component -> component-class -> pairings.
   Keep pre-built single- and pair-component manifests ready.
4. CLASSIFY each failure: (a) source defect (b) manifest defect (c) deploy-MODE limitation
   (d) test-design defect (e) org-side platform limitation. Only (a)/(b) are code fixes.
5. FIX IN BATCHES: after triage, sweep ALL instances of the defect class project-wide,
   then dry-run ONCE. The platform surfaces only one error per file per run - do not loop.
6. ESCALATE to human after 2 failed fixes on the same error.

## Failure taxonomy (every one of these actually happened)

### 1. UNKNOWN_EXCEPTION (-315522575) - the opaque aggregate
A generic platform crash that MASKS multiple real defects underneath. Do not theorize from the
aggregate: bisect. In one engagement the same error code had FIVE distinct root causes across
contexts. componentFailures[] empty = nothing to read - bisection is the only tool.

### 2. Description-length caps (3 occurrences in one sprint)
CustomPermission 255 - PermissionSet 255 - CustomObject/CustomField 1000.
Long rationale belongs in the review packet, never the XML. LINT for this pre-review.

### 3. Illegal elements per metadata type
`<deploymentStatus>` is invalid on Custom Metadata Types (__mdt) - copy/paste from a custom-object
template. Symptom: "Cannot specify: deploymentStatus for Custom Metadata Type", or worse, an
UNKNOWN_EXCEPTION when bundled with other objects.

### 4. Hand-authored Flow XML (3 fix rounds on ONE flow)
(a) element NAMES: record-backed choice sets are `<dynamicChoiceSets>`, NOT `<recordChoiceSets>`;
(b) XSD element ORDER is enforced; (c) boolean screen inputs may not carry `<isRequired>`.
RULE: never hand-author Flow XML. Build in Flow Builder against an org and retrieve.

### 5. FLS on required / Master-Detail fields (2 rounds, 21 entries)
"You cannot deploy to a required field: X" - permission sets may not carry fieldPermissions for
universally-required or MD fields. The deploy surfaces ONE illegal field per permset per run -
sweep them ALL at once (scripted), or you will loop.

### 6. checkOnly (--dry-run) vs Custom Metadata RECORDS
A first-time CMDT type+records bundle can NEVER pass a dry-run (records validate against a type
the check-only transaction never commits). A records dry-run cannot be a gate - plan Phase 1
(CMDT) as a REAL deploy by design. Formula fields reading $CustomMetadata have the same issue
against uncommitted records.

### 7. Org-side platform limitation: CMDT records rejected entirely
One DE org rejected EVERY CustomMetadata record deploy via Metadata API (all modes, all sizes,
fresh minimal record included) while type+fields deployed fine. Resolution: create records
manually in Setup, verify via anonymous Apex, record as a decision. Detect this early with a
1-record probe deploy; do not burn rounds assuming a source defect.

### 8. Deploy-time RunLocalTests + USER_MODE code (blockers C-F, 6 rounds)
New MDAPI-deployed fields have NO profile FLS for the deploying admin. Tests of `WITH USER_MODE` /
`insert as user` code MUST establish an FLS context or every test dies at setup:
- dedicated TEST/CI harness permission set granting exactly the CRUD/FLS the engine needs
  (never assign it to a real user; flag the production-permset gap separately);
- create the harness User OUTSIDE runAs (setup DML), assign permset, then run engine calls
  INSIDE System.runAs(user);
- some orgs enforce FLS even on plain fixture DML at deploy-time: fixtures may also need to run
  inside runAs - keep governor-measurement windows tight around the engine call only;
- read CMDT via `T__mdt.getInstance('DevName')` (cache-backed, FLS-free), not SOQL - runAs
  harness users may get "sObject type not supported" on CMDT SOQL.

### 9. RunSpecifiedTests is CLASS-level in the deploy API
`Class.method` names silently run 0 tests -> deploy rolls back on 0% coverage. Pass class names
only; split un-runnable methods into a separate class if you must exclude them.

## Org-safety gate (before ANY deploy command)
`sf org list` + `sf org display --target-org <alias>`: confirm the instance URL pattern matches
the intended org (DE orgs: `-dev-ed.develop.my.salesforce.com`). Client prod/sandbox orgs may be
authenticated on the same machine - EVERY command passes --target-org explicitly. No defaults.

## Ledger discipline
Every attempt (even failed dry-runs) = one row in the deploy ledger: date | scope | manifest |
target | deploy ID | dry-run | tests | result | by. Failed rows keep verbatim error text.
The ledger is what lets the NEXT session skip re-deriving all of the above.
