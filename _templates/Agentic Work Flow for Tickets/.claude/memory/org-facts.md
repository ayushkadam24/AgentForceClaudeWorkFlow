# Org Facts — quirks knowledge base (append-only; check BEFORE debugging a deploy)

Format: - date | org/alias | fact | evidence

Seeded from the previous engagement (full detail: .claude/skills/sf-deploy-troubleshooting/SKILL.md):
- (prior) | a Developer Edition org | rejected ALL CustomMetadata RECORD deploys via Metadata API — records had to be created manually in Setup | deploy ledger D-027
- (prior) | same org | enforced FLS on plain Apex DML in deploy-time RunLocalTests — test fixtures needed runAs + harness permset | blockers C–F
- (prior) | platform | RunSpecifiedTests accepts CLASS names only; Class.method silently runs 0 tests and rolls back on coverage | blocker H
- (prior) | platform | first-time CMDT type+records bundles can never pass --dry-run (checkOnly) | D-026
