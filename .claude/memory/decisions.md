# Decision Log (D-###)

Format per entry: ID | date | decider | decision | rationale | alternatives rejected.
Agents append; humans may append; nobody edits past entries (corrections = new entry superseding).

| ID | Date | Decider | Decision | Rationale | Rejected |
|---|---|---|---|---|---|
| D-001 | 2026-07-11 | human | Pipeline workspace lives at the root of the existing SFDX project | one project, one org config, .claude auto-discovered | nested sub-project |
| D-002 | 2026-07-11 | human | PIPELINE_STATE.md YAML block is the single machine-readable state; 4 human gates enforced | auditable, resumable, human-controlled | Jira status as the state spine |
| D-003 | 2026-07-11 | human | 00-inputs/ are immutable; intentional gaps stay in until the retro | the POC is graded on catching them | "cleaning up" inputs |
