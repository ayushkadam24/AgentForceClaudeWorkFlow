# SETUP — Ticket Workshop (5 minutes)

1. Open this folder in Claude Code (CLAUDE.md + rules load at session start).
2. Nothing to rename — client naming conventions are read per-ticket from what you paste.
3. Confirm Node works: `node scripts/metadata-lint.js --help` (used at every build).
4. SAFETY (read once): agents here NEVER touch an org — no deploys, no dry-runs, no queries.
   Every ticket ends in a deploy-steps.md that YOU execute. Keep it that way; client prod/sandbox
   orgs are authenticated on this machine.
5. Start your first ticket:  /ticket-new SCRUM-123 "short title"  → paste the Jira content →
   /ticket-solve → /ticket-build → /ticket-test → /ticket-package → you deploy → /ticket-close.
6. Anytime: /ticket-status for the shop floor overview.

Knowledge carried in: .claude/skills/sf-deploy-troubleshooting (deploy-failure taxonomy),
sf-apex-patterns, flow-patterns; .claude/memory/org-facts.md is pre-seeded — append your own
org quirks as you learn them, future tickets cite them.
