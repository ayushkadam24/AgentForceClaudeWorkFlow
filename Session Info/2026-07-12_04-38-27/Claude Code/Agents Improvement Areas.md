# Agents & Workflow — Improvement Areas (Claude Code session)

**Authored:** Sunday, 12 July 2026, 04:38 AM · **Basis:** the full F-001 Sprint-1 build+review+deploy session.
This is an honest post-mortem of where the agents/workflow struggled, ranked by impact, each with a concrete fix.

---

## TOP FINDING — static review gave false confidence; real defects only surfaced at deploy
**What happened:** Six independent code-reviews (2 deep, 4 standard) passed everything (XML well-formedness + standards + design fidelity). Yet the FIRST real dry-run failed, and bisection found **7 deploy-blocking defects the reviews never caught**:
- `VS_Bulk_Export` description > 255 (custom-permission limit)
- `VS_Setting__mdt` had illegal `<deploymentStatus>` (invalid on `__mdt`)
- All **5** permission-set descriptions 1000–1665 chars (> 255 limit)
- `VS_Appointment__c` (1401) and `VS_Patient__c` (1108) descriptions > 1000 (object limit)
- `VS_Session_Screen_DefineCapacity` flow `recordChoiceSets` XSD element-ordering violation

**Why it matters:** cost 2+ failed dry-run rounds and a lot of agent time; "APPROVE" verdicts were given on metadata that could not deploy.
**Fixes:**
1. **Give every dev/review agent a "Salesforce Metadata API limits" checklist** to validate against: description length caps (255 for CustomPermission & PermissionSet; 1000 for CustomObject/CustomField), valid enum values (e.g. `Security.settings` `sessionTimeout`), element-ordering for Flow XSD, elements invalid on `__mdt` (`deploymentStatus`, `sharingModel`, etc.).
2. **Connect the DE org EARLY and dry-run per ticket (or per batch) during build** — a `sf project deploy start --dry-run` at build time turns "estimated/clean" into "actually compiles." Static XML well-formedness is necessary but far from sufficient.
3. Add a lightweight **pre-commit metadata linter** (even a Bash/Node script counting `<description>` lengths and flagging `__mdt` illegal elements) so these never reach a dry-run.

## 2. Agents wrote descriptions that were great docs but violated platform limits
Rich, multi-hundred-char `<description>` blocks (perm sets up to 1665 chars) read beautifully but broke deploy.
**Fix:** deployable `<description>` stays within the platform cap (≤255 / ≤1000); the long rationale lives in the **review packet**, not the metadata. Bake this rule into rules/20 and the dev agent prompts.

## 3. No early compile/test signal → coverage and correctness were "estimated"
Every Apex ticket reported "coverage ~90% (ESTIMATED, not measured)" because no org was connected until the very end. The honesty was exemplary, but the pipeline ran blind on compilation and tests for the whole build.
**Fix:** authorize the DE org before DEV_IN_PROGRESS starts; dry-run + `sf apex run test --code-coverage` per Apex ticket. The user's instinct ("record verdicts from REAL results, not estimates") was exactly right and should be the default.

## 4. Opaque platform errors need the bisection protocol from the START
The aggregate deploy failed with a generic `UNKNOWN_EXCEPTION` that MASKED multiple real defects; only layer-by-layer bisection surfaced them. The devops agent had to be **upgraded mid-session** (opus + a mandatory capture-first/bisect/classify/escalate protocol) to handle it.
**Fix:** ship the upgraded devops protocol as the default; on ANY deploy failure, `--json` capture → record every `componentFailure` verbatim BEFORE fixing → bisect by layer → classify (schema / missing-dep / **org-capability→D-### exclude** / test-failure / deploy-strategy). Never retry an unchanged deploy.

## 5. Architecture hit a deploy-mode gotcha it didn't anticipate
`VS_Session__c` formula fields read `$CustomMetadata.VS_Setting__mdt…` — which **cannot compile-validate under `checkOnly` (dry-run)** against CMDT records created in the same transaction (a known Salesforce limitation). The design (D-020, reserve as a formula reading CMDT) is clean at runtime but couples deploy order.
**Fix:** the architect should weigh **deploy-mode constraints**, not just runtime correctness. Options to document as a pattern: two-phase deploy (CMDT first) or reading the tunable in Apex instead of a formula. Add "does any formula read `$CustomMetadata`?" to the design review.

## 6. Concurrent sub-agents risked corrupting append-only audit logs
Running parallel agents that each did read-modify-write on `agent-runs.log` / `jira-log.md` risked lost/interleaved lines. (Separately, an injection actually corrupted a log line — handled.) Mitigated by **centralizing shared-log writes through the orchestrator** and telling reviewers to write nothing.
**Fix:** formalize it — sub-agents never write shared audit files concurrently; the orchestrator serializes those writes, or agents use atomic (`>>`) appends only. This became a de-facto rule; make it explicit in rules/30.

## 7. Decision-ID collisions (human said "D-016/D-017" when taken)
Several times the human referenced a D-### that was already assigned; the orchestrator had to renumber (→ D-019, D-023, etc.) and flag it.
**Fix:** any agent assigning an ID must first read the register and take the next free number; the orchestrator should surface a collision immediately (this worked, but was manual each time).

## 8. An over-tight instruction caused a real design-fidelity omission
The orchestrator told VS-07 "C1 fields ONLY, nothing more," which caused `VS_No_Show_Count__c` (in design §2.3) to be dropped — caught later as A-013 (MAJOR) and fixed.
**Fix:** instruct agents to **build to the design section** ("per §2.3") rather than an over-narrow restriction; when restricting, cross-check against the design so a real field isn't excluded. Design fidelity should win over a paraphrased constraint.

## 9. Deployment/agent runs were slow; too many sequential round-trips
Deploy agents took ~6–11 min each; multiple dry-run rounds. Some of this is unavoidable (org round-trips), but iterating one-defect-at-a-time wasted rounds.
**Fix:** the bisection protocol already helps by finding the FULL failing set in one triage pass (fix everything at once). Batch fixes; dry-run once after all fixes, not per fix.

---

## What WORKED well (keep doing)
- **Pipeline discipline:** every run logged (agent-runs.log + PIPELINE_STATE), decisions/assumptions registered, handoffs written, traceability REQ→EP→VS→D maintained, honest "not deployed / estimated coverage" reporting.
- **Human-gate model + `/advance`:** kept the human in control of phase transitions; the orchestrator proposed, never chained.
- **§3.4 design rigor:** the single-lock rework (D-019) and its line-by-line review (no TOCTOU, no unlocked write path) were high quality.
- **Org-safety gate:** devops **refused to deploy** to the connected client `prutech.com` orgs and verified the DE org identity before acting — exactly right given the blast radius.
- **Security posture:** the injection attempt (fabricated grading + concealment demand) was caught by a sub-agent, refused, surfaced, and remediated; the answer key was never read.
- **Honesty on verification limits:** agents consistently distinguished "XML well-formed" from "compiles/deploys/tests pass," and "ceiling logic proven" from "concurrency proven."

## One-line summary
The build-and-review pipeline is strong on *design and documentation discipline* but was **blind to deploy-time platform constraints** until a real org was connected — connect the org and dry-run EARLY, arm agents with a metadata-limits checklist, and keep the upgraded devops bisection protocol as the default.
