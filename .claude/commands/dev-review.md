---
description: Review a ticket — code-reviewer agent does the deep pass, human records the verdict
argument-hint: VS-##
---
1. Require phase DEV_IN_PROGRESS or DEV_COMPLETE. Verify 02-build/review-notes/VS-$ARGUMENTS-review.md exists (else the ticket isn't In Review — STOP).
2. Launch the code-reviewer subagent on VS-$ARGUMENTS. It writes 02-build/review-notes/VS-$ARGUMENTS-code-review.md with per-category verdicts, severity-ranked findings (file:line), and an APPROVE / REQUEST-CHANGES recommendation.
3. Present to the human: the reviewer's recommendation, all BLOCKER/MAJOR findings verbatim, and the developer's own "scrutinize this" notes from the review packet. WAIT for the human verdict.
4. Record the human's APPROVED / CHANGES-REQUESTED (with notes) in the review packet and update the ticket in jira-log.md. CHANGES-REQUESTED reopens the ticket for /dev-implement, and the fix goes back through step 2 on request.
5. A BLOCKER finding on booking-path integrity (§3.4) must also be echoed into .claude/memory/handoffs.md so the drift check and QA see it.
