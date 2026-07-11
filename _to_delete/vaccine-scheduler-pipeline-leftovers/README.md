# Vaccine Scheduler Pipeline — AI-Assisted Delivery POC

Proof-of-concept for an AI-assisted Salesforce delivery pipeline run through Claude Code subagents, mirroring a real three-phase delivery flow — Discovery (BA → Architect), Build (PM → Senior/Mid developers), and QA (QA Lead → QA engineers) — with a single state file (`PIPELINE_STATE.md`) tracking each feature through the phase machine and human approval gates at every phase transition. Pilot feature: **appointment slot booking** for a Public Health Appointment & Vaccination Scheduler.

## Folder map

```
vaccine-scheduler-pipeline/
├── README.md
├── PIPELINE_STATE.md
├── ANSWER-KEY-intentional-gaps.md      # human grading reference; agents must never read it
│
├── .claude/
│   ├── agents/                         # one subagent per role
│   │   ├── ba-analyst.md
│   │   ├── architect.md
│   │   ├── pm-planner.md
│   │   ├── dev-senior.md
│   │   ├── dev-mid.md
│   │   ├── qa-lead.md
│   │   └── qa-engineer.md
│   ├── commands/
│   │   ├── kickoff.md
│   │   ├── advance.md
│   │   └── status.md
│   └── settings.json
│
├── 00-inputs/                          # fixed client inputs — never modified by agents
│   ├── rfp/
│   ├── discovery-notes/
│   ├── current-state/
│   ├── stakeholders/
│   └── compliance/
│
├── 01-discovery/                       # BA + Architect outputs
│   ├── requirements-brief.md
│   ├── open-questions.md
│   ├── technical-design.md
│   └── erd/
│
├── 02-build/                           # PM + developer outputs
│   ├── sprint-plan.md
│   ├── jira-log.md
│   └── review-notes/
│
├── 03-qa/                              # QA outputs
│   ├── test-plan.md
│   ├── regression/
│   ├── bug-reports/
│   └── evidence/
│
├── 04-confirmations/                   # human gate sign-offs
│
├── force-app/main/default/             # Salesforce source (classes, lwc, flows, objects, customMetadata)
├── config/project-scratch-def.json
├── scripts/
│   ├── seed-data/
│   └── org-setup.sh
└── retro/poc-learnings.md
```

## How to run

- `/kickoff` — starts Discovery (verifies phase is NOT_STARTED, then runs the ba-analyst on `00-inputs/`)
- `/status` — reads state (prints the YAML block and last 5 log lines of `PIPELINE_STATE.md`)
- `/advance` — proposes the next phase transition for human approval
