Create a new ticket workspace. Args: KEY "title" (e.g. /ticket-new SCRUM-42 "Fix booking cutoff").
1. Slugify the title; create tickets/<KEY>-<slug>/ by COPYING tickets/_template/ (all files).
2. Tell the human to paste the full Jira ticket (description, ACs, comments, any code context)
   into 01-ticket.md, then confirm.
3. Add register row to TICKETS.md (status NEW, created today, folder + package paths) + one
   status-history line + run-log line.
Postcondition: folder exists, register updated. Next: /ticket-solve KEY.
