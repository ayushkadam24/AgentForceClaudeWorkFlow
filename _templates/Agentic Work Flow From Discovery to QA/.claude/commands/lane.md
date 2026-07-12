---
description: Parallel dev lanes — set up, run, and merge two build sessions (rules/40)
argument-hint: setup | A | B | merge | status
---
Read .claude/rules/40-parallel-lanes.md first. Then by $ARGUMENTS:

**setup** (run once, in the main folder):
1. Verify git repo exists with all work committed (`git status` clean; if not, commit everything as `chore: pre-lane checkpoint`). If no repo, STOP — tell the human to run git init + initial commit first.
2. `git branch lane-b && git worktree add "../AW-lane-B" lane-b`
3. Write a file `LANE` containing `A` at this worktree root; write `LANE` containing `B` at ../AW-lane-B root.
4. Tell the human: open "../AW-lane-B" in a second VS Code window, start claude there, and run `/lane B` to verify. This window is Lane A.

**A** or **B**: print this worktree's LANE file, current branch, and the list of this lane's tickets (routing dev-senior for A, dev-mid for B) with status and unblocked-yes/no per the dependency rule. Confirm which ticket /dev-implement would take next.

**merge** (Lane A only — refuse if LANE says B):
1. Commit local work. `git merge lane-b`.
2. If force-app/ conflicts: STOP, report which files — that's a lane-discipline violation for the retro.
3. Run `node scripts/health-check.js` on the merged tree and show output.
4. Remind: Lane B should now run `git merge main`.

**status**: show both branches' last commits, unmerged ticket commits per lane, and any file both lanes have touched since the last merge (early-warning for conflicts).
