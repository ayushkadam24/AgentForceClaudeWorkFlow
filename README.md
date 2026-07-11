# Salesforce DX Project

Salesforce DX is a development approach that brings source-driven development, team collaboration, and continuous integration to the Salesforce Platform. Instead of working directly in an org through a web browser, you work with metadata as source files in a local DX project, track changes in version control, and deploy through automated processes.

This project template gets you started with the tools and structure you need to build Salesforce applications using source control, scratch orgs, and the Salesforce CLI.

## Prerequisites

Before you start, make sure you have:

- **Salesforce CLI** - Download from [developer.salesforce.com/tools/salesforcecli](https://developer.salesforce.com/tools/salesforcecli). See [Install Salesforce CLI](https://developer.salesforce.com/docs/atlas.en-us.sfdx_setup.meta/sfdx_setup/sfdx_setup_install_cli.htm) for details.
- **VS Code with Salesforce Extension Pack** - See [Installation Instructions](https://developer.salesforce.com/docs/platform/sfvscode-extensions/guide/install.html) for details. Includes the Agentforce Vibes extension.
- **A development org** - Sign up for a free Developer Edition org [here](https://developer.salesforce.com/signup).
- **Dev Hub enabled** (optional, required to create scratch orgs) - You can enable Dev Hub in your development org under Setup > Dev Hub.  See [Provide Developers Access to Salesforce DX Tools](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_setup_dx_tools.htm).

## Project Structure

Your DX project follows this structure:

- **`force-app/main/default/`** - Your metadata source files live in this default package directory. You can configure additional package directories in the `sfdx-project.json` file.
- **`config/`** - Scratch org definitions and project settings
- **`scripts/`** - Automation scripts for common tasks
- **`sfdx-project.json`** - Project manifest that defines package directories, namespace, API version, and other project-level settings

See [Salesforce DX Project Configuration](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_ws_config.htm).

## Get Started

Ready to start developing? The [Get Started with Salesforce DX](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_get_started_dx.htm) guide walks you through your first project, from creating a scratch org to creating a simple Apex class or LWC to deploying your code to a sandbox.

## Common Salesforce CLI Commands

Here are common CLI commands that you'll use the most:

- `sf org login web`: Authorize an org
- `sf org open`: Open your org in a browser
- `sf org create scratch`: Create a scratch org
- `sf project deploy start`: Deploy metadata to your org
- `sf project retrieve start`: Retrieve metadata from your org
- `sf template generate <artifact>`: Scaffold new components, such as Apex classes and triggers, LWC components, Lightning apps, and more
- `sf apex <command>`: Run Apex tests, run anonymous Apex blocks, and view logs
- `sf data <command>`: Work with test data
- `sf alias <command>`: Manage org aliases
- `sf config <command>`: Configure CLI settings

## Use Agentforce Vibes to Build Lightning Apps

Transform your ideas into custom Lightning apps that extend CRM workflows directly in Lightning Experience. Through natural conversations with Agentforce Vibes, implement custom objects and fields, complex business logic, and dynamic UI components. See [Build a Lightning App Using Agentforce Vibes](https://developer.salesforce.com/docs/platform/einstein-for-devs/guide/lexapp-overview.html).

## Additional Resources

- [Agentforce Vibes Developer Guide](https://developer.salesforce.com/docs/platform/einstein-for-devs/guide/einstein-overview.html)
- [Salesforce CLI Installation Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_setup.meta/sfdx_setup/sfdx_setup_intro.htm)
- [Salesforce DX Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/)
- [Salesforce CLI Command Reference](https://developer.salesforce.com/docs/atlas.en-us.sfdx_cli_reference.meta/sfdx_cli_reference/)
- [Salesforce CLI Plugin Development Guide](https://developer.salesforce.com/docs/platform/salesforce-cli-plugin/guide/conceptual-overview.html)
- [Salesforce VS Code Extensions Documentation](https://developer.salesforce.com/tools/vscode/)


---

# AI-Assisted Delivery Pipeline POC

Proof-of-concept for an AI-assisted Salesforce delivery pipeline run through Claude Code subagents, mirroring a real three-phase delivery flow — Discovery (BA → Architect), Build (PM → Senior/Mid developers), and QA (QA Lead → QA engineers) — with a single state file (`PIPELINE_STATE.md`) tracking each feature through the phase machine and human approval gates at every phase transition. Pilot feature: **appointment slot booking** for a Public Health Appointment & Vaccination Scheduler.

## Pipeline folder map

```
├── PIPELINE_STATE.md                   # phase state machine + log (single source of truth)
├── ANSWER-KEY-intentional-gaps.md      # human grading reference; agents must never read it
├── .claude/
│   ├── agents/                         # ba-analyst, architect, pm-planner, dev-senior,
│   │                                   # dev-mid, qa-lead, qa-engineer
│   ├── commands/                       # kickoff.md, advance.md, status.md
│   └── settings.json
├── 00-inputs/                          # fixed client inputs — never modified by agents
│   ├── rfp/  discovery-notes/  current-state/  stakeholders/  compliance/
├── 01-discovery/                       # requirements-brief, open-questions, technical-design, erd/
├── 02-build/                           # sprint-plan, jira-log, review-notes/
├── 03-qa/                              # test-plan, regression/, bug-reports/, evidence/
├── 04-confirmations/                   # human gate sign-offs
├── force-app/main/default/             # Salesforce source (shared with the DX project)
├── config/project-scratch-def.json     # scratch org: "Vaccine Scheduler POC"
├── scripts/org-setup.sh  scripts/seed-data/
└── retro/poc-learnings.md
```

## How to run the pipeline

- `/kickoff` — starts Discovery (verifies phase is NOT_STARTED, then runs the ba-analyst on `00-inputs/`)
- `/status` — reads state (prints the YAML block and last 5 log lines of `PIPELINE_STATE.md`)
- `/advance` — proposes the next phase transition for human approval
