---
description: Human code-review helper — walk a review packet and record the verdict
argument-hint: VS-##
---
1. Require phase DEV_IN_PROGRESS or DEV_COMPLETE. Read 02-build/review-notes/VS-$ARGUMENTS-review.md and the files it lists.
2. Present for the human reviewer: summary of changes, AC-by-AC verification status, code smells or standards violations found against .claude/rules/20-salesforce-standards.md, and suggested review focus points.
3. Record the human's verdict in the review packet (APPROVED / CHANGES-REQUESTED with notes) and update the ticket in jira-log.md accordingly. CHANGES-REQUESTED reopens the ticket for /dev-implement.
