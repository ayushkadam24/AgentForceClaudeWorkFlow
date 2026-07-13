# scripts/ — pipeline tooling

Deterministic guards and helpers for the vaccine-scheduler POC. All are Node (cross-platform,
no deps) except `org-setup.sh`. Run from the **project root**.

| Script | Purpose | Run |
|---|---|---|
| `health-check.js` | Pipeline invariants: phase validity, artifact presence, citation integrity, log freshness, no-Aadhaar source scan | `node scripts/health-check.js` (via `/health`) |
| `metadata-lint.js` | Metadata + Apex deploy-trap linter — description caps, illegal `__mdt` elements, `$CustomMetadata` formula coupling, FLS on required/MD fields, MD-detail read without master read, `caseSensitive` without `unique`, and Apex SOQL traps (**`ORDER BY` on a `FOR UPDATE` query**, **`WITH USER_MODE` mis-ordered after `ORDER BY`/`LIMIT`**) | `node scripts/metadata-lint.js` (before any review packet claims "buildable") |
| `check-no-aadhaar.js` | Scans **staged** content for Aadhaar-shaped 12-digit runs — catches Bash-redirect writes the PreToolUse Write-guard can't see. Runs at commit-time and is CI-usable | `node scripts/check-no-aadhaar.js` |
| `org-capability-probe.js` | On first connect to any org: detect edition + flag the two DE deploy quirks (D-027 CMDT records, D-028 FLS on system-mode DML); records to `.claude/memory/org-capabilities.md` | `node scripts/org-capability-probe.js -o <alias>` |
| `org-setup.sh` | Scratch/DE org skeleton setup | `bash scripts/org-setup.sh` |

## One-time activation: the no-Aadhaar pre-commit hook

The hook lives in the version-controlled `.githooks/` dir. Point git at it **once per clone**:

```
git config core.hooksPath .githooks
```

After that, every `git commit` runs `check-no-aadhaar.js` and blocks the commit on a match.
The same script belongs in CI (`node scripts/check-no-aadhaar.js` on the staged/changed set).

## Note on the Stop-hook enhancement (NEXT-STEPS item 7)

`scripts/proposed/stop-guard.js` is a **staged, non-active** upgrade to `.claude/hooks/stop-guard.js`
that additionally enforces a non-empty PIPELINE_STATE.md `next_command:` pointer (on top of the
existing run-log freshness rule). Guardrails can't be edited by the agent they guard, so a **human**
must activate it:

```
cp scripts/proposed/stop-guard.js .claude/hooks/stop-guard.js
```

No `settings.json` change is needed — the Stop/SubagentStop hooks already point at that path.
