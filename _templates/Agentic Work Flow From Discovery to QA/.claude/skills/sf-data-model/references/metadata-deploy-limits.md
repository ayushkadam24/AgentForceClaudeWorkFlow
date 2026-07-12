# Salesforce Metadata Deploy Limits & Gotchas (field-verified 2026-07-12, F-001 Sprint 1)

Every one of these caused a REAL deploy failure that six static code-reviews missed.
Dev agents validate against this BEFORE writing the review packet; code-reviewer re-checks.

## Description length caps (deploy-blocking, not warnings)
| Metadata type | <description> max |
|---|---|
| CustomPermission | 255 |
| PermissionSet | 255 |
| CustomObject | 1000 |
| CustomField | 1000 |
Rule: the deployable description states WHAT in one or two sentences and stays under the cap.
The rich WHY/rationale lives in the ticket's review packet — never in the metadata.

## Elements illegal on specific types
- Custom Metadata Types (`__mdt` objects): NO `<deploymentStatus>`, NO `<sharingModel>` —
  both are invalid on __mdt and fail the deploy.
- Flow XML is XSD-ordered: element ORDER inside a flow (e.g. `recordChoiceSets` placement)
  matters; alphabetical-ish XSD order, not authoring order. When in doubt, retrieve a
  working flow of the same type and mirror its element order.

## Deploy-mode gotchas
- Formulas reading `$CustomMetadata.X__mdt...` CANNOT compile-validate under checkOnly
  (dry-run) when the CMDT records deploy in the same transaction. Options: two-phase deploy
  (CMDT records first, formula fields second) or read the tunable in Apex instead of formula.
  Architect: ask "does any formula read $CustomMetadata?" at design review.
- `*.settings` metadata has strict enum values (e.g. Security.settings sessionTimeout takes
  values like `TwelveHours`) — verify against current Metadata API docs, never from memory.

## Verification ladder (each rung is necessary, none is sufficient alone)
XML well-formed → metadata-lint clean (scripts/metadata-lint.js) → `--dry-run` passes →
real deploy passes → tests pass with measured coverage. A packet may only claim the rungs
it actually climbed; anything below the top is labeled with what was NOT verified.
