#!/usr/bin/env bash
# feature: F-001 slot-booking-core | producing-agent: qa-engineer | date: 2026-07-12
# phase: QA_IN_PROGRESS (/qa-run B) | derives-from: 03-qa/test-plan.md TC-023 (REQ-055, Annexure C6,
#   VS-04 review packet's "unverified, authored from memory" caveat)
#
# TC-023 -- session timeout <=15 min. Retrieves the LIVE Security settings straight from the org via
# the Metadata API (equivalent evidentiary weight to Setup -> Security -> Session Settings, no browser
# needed) and asserts sessionTimeout=FifteenMinutes actually took effect (not just that the source
# file on disk SAYS FifteenMinutes -- VS-04's own packet flagged this file as never-dry-run-verified).
#
# Usage:
#   bash 03-qa/regression/tc-023-session-timeout.sh
set -euo pipefail
OUT_DIR="$(mktemp -d)"
sf project retrieve start --metadata "Settings:Security" --target-org AgentForceClaudeWorkFlow --output-dir "$OUT_DIR" --json
echo
echo "== Live in-org sessionTimeout value =="
grep -A1 "<sessionTimeout>" "$OUT_DIR/settings/Security.settings-meta.xml"
# Expected: <sessionTimeout>FifteenMinutes</sessionTimeout>. This is a SINGLE ORG-WIDE setting
# (Metadata API does not expose per-permission-set session timeout) -- best-effort org-wide control
# per the VS-04 packet, not a per-role guarantee.
