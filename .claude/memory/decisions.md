# Decision Log (D-###)

Format per entry: ID | date | decider | decision | rationale | alternatives rejected.
Agents append; humans may append; nobody edits past entries (corrections = new entry superseding).

| ID | Date | Decider | Decision | Rationale | Rejected |
|---|---|---|---|---|---|
| D-001 | 2026-07-11 | human | Pipeline workspace lives at the root of the existing SFDX project | one project, one org config, .claude auto-discovered | nested sub-project |
| D-002 | 2026-07-11 | human | PIPELINE_STATE.md YAML block is the single machine-readable state; 4 human gates enforced | auditable, resumable, human-controlled | Jira status as the state spine |
| D-003 | 2026-07-11 | human | 00-inputs/ are immutable; intentional gaps stay in until the retro | the POC is graded on catching them | "cleaning up" inputs |
| D-004 | 2026-07-11 | human | Jira (Atlassian MCP) connection DEFERRED — pm-planner and qa-engineer work file-locally: 02-build/jira-log.md is the ticket source of truth until connected. Jira project exists (currently "Public Health App", key SCRUM — to be renamed/re-keyed to VS before mirroring). | POC starts without external dependency | connecting Jira before kickoff |
| D-005 | 2026-07-11 | client — DHO (Dr. Kulkarni), workshop §2 | Capacity model must support BOTH a daily number and per-session/time-distributed capacity ("design it so both work") | Reconciles the Shinde (daily) vs Pawar (session) contradiction without picking a loser; morning-only booking must be preventable | forcing one facility onto the other's model |
| D-006 | 2026-07-11 | client — DHO (Dr. Kulkarni), workshop §4 | Confirmed bookings get priority; walk-ins are served from remaining capacity; a portion of daily capacity is reserved for walk-ins | Cannot turn away a citizen without a smartphone; walk-ins are permanent reality | booking-only system with no walk-in path |
