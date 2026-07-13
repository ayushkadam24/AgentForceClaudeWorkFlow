# What to do next (after 2026-07-14 session)

State: `main` @ `790497c`. VS-20 + VS-16 closed. Everything deployed to the DE org
`AgentForceClaudeWorkFlow`. Two architect questions open (OQ-030, OQ-031). Full detail:
`Claude Code/This Session - All Info.md`.

---

## A. Do FIRST — quick unblocks (≈30 min total)
1. **Activate the enhanced Stop-hook (Track B item 7)** — human, 1 min:
   `cp scripts/proposed/stop-guard.js .claude/hooks/stop-guard.js`
   (Agents can't write to `.claude/hooks/`; it adds the `next_command`-not-empty guard.)
2. **Architect ruling on OQ-031** — the one thing making portal **cancel/reschedule actually work**
   for a citizen who doesn't own the record (guests never own their appointment; family case).
   Ask: must `VS_BookingService.cancel/reschedule` read the appointment under elevation? If yes, the
   fix is a **top-level `without sharing` wrapper** or an **elevated read seam** in `VS_BookingController`
   — NOT a §3.4 change. Then implement (small controller change) + re-run the manage tests.
3. **Architect ruling on OQ-030** — name/target app for the citizen journey LWCs (or confirm they live
   only on the future Experience site).

## B. The highest-leverage structural move
4. **Move the pilot OFF Developer Edition to a sandbox / proper org.** This is the through-line of the
   whole session: the DE org's **D-028** quirk (FLS/CRUD enforced on system-mode + async DML) forces
   least-privilege portal booking (D-030a) and VS-20 facility sharing (D-031) to be "standard-org runtime"
   gates here, and cost ~6 deploy rounds on VS-20 alone. On a standard org these just work. Re-run the
   `org-capability-probe` + the full `RunLocalTests` there to convert the runtime-gated proofs to real ones.
   (Sprint-1 caveat D-025 already flagged this.)

## C. Make the pilot demonstrable (needs A.2 for full cancel/reschedule)
5. **Assign booking access to a demo user** so a real (non-admin) user can book end-to-end:
   `VS_Booking_Portal` (or `VS_Booking_Capability`) + a role permset on a Platform-license user.
   (There are free Salesforce Platform + Customer Community licenses.)
6. **Place the citizen LWC on a page + publish** — drop `vsBookingJourney` (Book/Manage tabs) onto the
   LWR "Vaccine Scheduler Portal" site (or a Lightning app page per OQ-030) and publish. Browse + OTP work
   now; booking works per the D-030a gate; cancel/reschedule works once A.2 lands.

## D. Finish the "needs completion" tickets
7. **VS-14** — `VS_Citizen_Community` permset + a sharing set keyed to the verified mobile (authenticated
   citizen model) + **retrieve the LWR site into source** (it exists only in the org right now).
8. **VS-22** — the idempotent synthetic **seed script** as a committed deliverable (the org has data but
   there's no script in `scripts/seed-data/`).
9. **VS-20 productionization** (architect follow-up) — the async share-recompute runs as the enqueuing user
   (no Modify-All-Data in prod). Decide the elevated maintainer: a scheduled batch or platform-event handler
   running as an integration user. Required before REQ-053 is "launch-complete."

## E. Not-started tickets (Sprint 3/4 remainder)
10. **VS-15** — `vsFacilityFinder` LWC (search by service + geolocation/proximity, 3G-graceful).
11. **VS-18** — `VS_ISmsProvider` + `VS_SmsService` (log-only, writes `VS_Notification_Log__c`) + test.
12. **VS-19** — `VS_Appointment_AfterSave_LogConfirmation` record-triggered flow (fires the SMS seam).
13. **VS-21** — `VS_RetentionPurgeBatch` (per-class retention) + schedule + test.
14. Activation: schedule `VS_NoShowBatch` via `System.schedule` (VS-12 code is done, not scheduled).

---

## Recommended order
**A (unblocks) → B (move off DE — do before more runtime-gated features) → C (demoable) → D/E.**
Rationale: A.2/A.3 close the two open architect questions cheaply; B removes the D-028 tax that made this
session slow and converts the runtime-gated proofs to real ones; then C makes it demonstrable and D/E
finish the build. If staying on DE for now, do A + C to demo, and keep D/E honest about the runtime gates.
