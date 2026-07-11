# Parallel Dev Lanes (binding while two build sessions run)

Two Claude Code sessions build simultaneously in git worktrees. Lane identity comes from the
`LANE` file at the worktree root (created by /lane). No LANE file = single-lane mode, all lane rules off.

## Lane assignment (static — no dynamic claiming)
- **Lane A** (main worktree, this folder): all tickets routed **dev-senior**. Lane A is PRIMARY.
- **Lane B** (worktree ../AW-lane-B, branch lane-b): all tickets routed **dev-mid**.
- A lane NEVER builds the other lane's tickets, even if idle. Re-routing a ticket = human edit
  to sprint-plan.md in Lane A, then sync.

## Dependencies across lanes
Before starting a ticket, check its `Depends on:` line in jira-log.md. If a dependency belongs
to the other lane and is not yet merged to main, DO NOT start — pick the next unblocked ticket
in your own lane. Nothing unblocked? Stop and say so.

## Shared-file discipline
- **PIPELINE_STATE.md YAML**: Lane A ONLY. Lane B never changes phase; it appends log lines only.
- **jira-log.md / agent-runs.log / state log / memory files**: append-only in both lanes;
  .gitattributes union-merge makes concurrent appends merge cleanly.
- **sprint-plan.md**: read-only in both lanes during build.
- **force-app/**: each ticket touches only its own components — the dependency ordering is what
  prevents overlap. If your ticket must edit a file the other lane created and it isn't merged
  yet, that IS a cross-lane dependency: wait.

## Merge protocol (Lane A executes, after each ticket or small batch)
1. Lane B: commit `VS-## <title> (lane-b)` — leave the working tree clean.
2. Lane A: commit own work, then `git merge lane-b`. Union-merge handles append-only files;
   a real conflict in force-app/ means the dependency rule was violated — stop, tell the human.
3. Lane B: `git merge main` to pick up Lane A's work before its next ticket.
4. /deploy runs only from Lane A on merged main — never from an unmerged lane.

## Ground rules
- Both lanes obey all existing rules, hooks, and guardrails (they travel with the worktree via git).
- code-reviewer and /dev-review run in Lane A on MERGED code only.
- If in doubt whether a file is yours to write: it isn't. Ask.
