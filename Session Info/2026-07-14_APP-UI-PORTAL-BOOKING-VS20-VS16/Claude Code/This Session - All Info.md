# Session — App UI + Portal Booking (D-030) + Facility Sharing (VS-20) + Citizen Journey (VS-16)

**Span:** 2026-07-13 evening → 2026-07-14
**Branch:** `main` (forward-build-sprint2-4 was merged in at `74447da`)
**Org:** `AgentForceClaudeWorkFlow` (Developer Edition) — all work deployed here
**Pipeline phase:** DONE throughout (all work is POST-DONE forward-build; YAML untouched)

---

## TL;DR — what shipped
1. **Track B pipeline hardening finished** (metadata-lint now catches 8 defect classes incl. 3 Apex/field deploy-traps; no-Aadhaar pre-commit hook active; org-capability-probe run for real).
2. **Forward-build (VS-10..20) blockers fixed + org-verified** — including a real §3.4 crown-jewel regression in VS-11.
3. **App UI built** — the "Vaccine Scheduler" Lightning app: 11 tabs, page + compact layouts, list views. Now navigable in the org.
4. **Option A citizen portal booking (D-030/D-030a)** — `@AuraEnabled` controller + `vsSlotPicker` LWC + least-privilege permset + guest profile. OTP-verified, IDOR-safe.
5. **VS-20 facility-scoped record sharing (D-031)** — Apex managed sharing; the compliance-critical REQ-053. Facility isolation unit-proven.
6. **VS-16 citizen journey** — view/cancel/reschedule LWC, OTP+IDOR, 57 Custom Labels, accessibility, printable confirmation.

**The recurring theme:** this **Developer Edition org's D-028 quirk** (FLS/CRUD enforced even on system-mode + async DML) turned several least-privilege features into **standard-org runtime gates** here. It cost the most time (VS-20 took ~6 deploy rounds). **Strongest signal yet: move the pilot off DE to a proper sandbox.**

---

## Commits this session (newest first)
| Commit | What |
|---|---|
| `790497c` | **VS-16** citizen journey — view/cancel/reschedule LWC, OTP+IDOR, Custom Labels, a11y, printable |
| `eaaf53e` | **VS-20** facility-scoped record sharing via Apex managed sharing (REQ-053, D-031) |
| `48be1f8` | **Option A** citizen booking — `VS_BookingController` + `vsSlotPicker` LWC + D-030 portal path |
| `3c719c7` | App UI — page + compact layouts for the 6 user-facing objects |
| `4e932c3` | App UI — Vaccine Scheduler Lightning app + 11 object tabs + list views |
| `15b21b0` | metadata-lint — add 3 Apex/field deploy-trap checks (offline catches) |
| `0a3952f` | Forward-build — org-verified deploy-fixes (VS-11 ORDER BY, VS-13 OTP, VS-20 sharingRules) |
| `b3b04c2` | Sprint 2-4 forward-build (VS-10..20) + fix 2 review blockers |
| `76d2bf9` / `fd2d554` / `c17f6a0` | A-018 permset · org-probe real run · Track B hardening |

`74447da` = the merge that brought forward-build-sprint2-4 onto `main`.

---

## 1. Track B — pipeline hardening (finished)
- `scripts/metadata-lint.js` now catches **8** defect classes: description caps, illegal `__mdt` elements, `$CustomMetadata` formula coupling, **FLS on required/MD fields**, **MD-detail read without master read**, **`caseSensitive` without `unique`**, **`ORDER BY` on a `FOR UPDATE` query**, **`WITH USER_MODE` mis-ordered after `ORDER BY`/`LIMIT`**. The last 3 were added after they bit us on-org this session — they'd have been caught offline.
- `scripts/check-no-aadhaar.js` + `.githooks/pre-commit` active (`core.hooksPath=.githooks`). It ran clean on **every** commit this session.
- `scripts/org-capability-probe.js` — run for real against the DE org; records to `.claude/memory/org-capabilities.md`.
- **HUMAN ACTION PENDING (item 7):** the enhanced Stop-hook is staged at `scripts/proposed/stop-guard.js` — a human must `cp scripts/proposed/stop-guard.js .claude/hooks/stop-guard.js` (agents can't write to `.claude/hooks/`).

## 2. Forward-build (VS-10..20) — blockers fixed + org-verified
- **VS-11 (crown-jewel regression, FIXED):** cancel/reschedule re-validated `ALREADY_CANCELLED` only *before* the session lock → overbooking-by-one under concurrent same-appointment cancels. Fixed with an **in-lock re-read** in `releasePlaceAndCancel` (place freed exactly once). Also fixed `ORDER BY` on the `FOR UPDATE` locking query (Apex forbids it).
- **VS-10 (REJECTED as false positive):** reviewer wanted FLS on 3 required match-key fields — impossible (required fields can't carry FLS) and unnecessary. Left permset/service unchanged; org run confirmed the create-path passes.
- **VS-13 OTP:** `caseSensitive`-without-`unique` field + `WITH USER_MODE` clause-order fixes.
- **Validate-only `RunLocalTests` = 54/54** at that point.

## 3. App UI
- `VS_Vaccine_Scheduler` Lightning app (Standard nav), 11 `VS_*` tabs, `VS_Vaccine_Scheduler_App` visibility permset (assigned to admin), 6 page layouts + 6 compact layouts, 3 list views. **How to see it:** App Launcher → Vaccine Scheduler.
- Org already had seed data (36 facilities / 489 patients / 144 appointments) and the full object set deployed. **Gap found:** no real user holds `VS_Booking_Capability` or a role permset (A-018).

## 4. Option A portal booking — D-030 / D-030a
- `VS_BookingController` (`@AuraEnabled`): elevated availability reads; `sendOtp`/`verifyOtp`; `book()` via a `without sharing` **Booker** with a **server-side C9 OTP gate** (re-verify + consume, never trust the client).
- `VS_BookingService`: `with sharing` → **`inherited sharing`** (architect D-030) so the one `book()` body serves both internal callers and the portal wrapper without forking §3.4.
- `VS_Booking_Portal` least-privilege permset (**no** Session/Slot edit — D-020 red line), guest profile granted, `vsSlotPicker` LWC (lightningCommunity targets → appears in Experience Builder).
- **D-030a:** least-privilege booking *success* is a **standard-org runtime gate** — this DE org's D-028 blocks the counter DML for a Slot-edit-less user; the proof test asserts the elevation clears sharing and hits the documented CRUD wall. **34/34** tests, §3.4 intact.

## 5. VS-20 facility sharing — D-031 (the big one)
- **Apex managed sharing**, not criteria rules (the template compared a lookup to a name and did nothing for Patient). After-triggers maintain `VS_Appointment__Share` / `VS_Patient__Share` (RowCause `VS_Facility_Access__c`), **async** so §3.4 is untouched.
- **Patient scoping solved:** shared to the group of *every* facility it has a live appointment at — the architect rejected "district-wide patient browsing" as a **C5 violation**.
- One auto-provisioned public group per facility; staff→facility via a `User.VS_Facility__c` **text** field (User rejects a custom Lookup to a custom object); district = View-All + read-only FLS.
- **Everything fail-safe** — a sharing failure can never break booking.
- **85/85** tests, VS-20 classes 89-100% covered. **Isolation ship-bar UNIT-PROVEN** (staffer A sees 0 of facility B; patient-at-both visible to both; district sees all with C1 FLS). The share-*write* is a standard-org runtime gate here (D-028).
- **Cost:** architect ruling + 5 dev-senior passes + ~6 deploy rounds, almost entirely D-028 friction.

## 6. VS-16 citizen journey
- `findMyAppointments` / `cancelMyAppointment` / `rescheduleMyAppointment` — all C9 OTP-gated and **IDOR-safe** (`PortalManager` checks ownership BEFORE elevating). `book()` stamps `VS_Booked_By_Mobile__c`.
- LWCs: `vsMyBookings`, `vsBookingJourney` (Book/Manage tabs), `vsErrorLabels`; `vsSlotPicker` made accessible + printable. **57 Custom Labels** (REQ-060, i18n-ready).
- **42/42** tests, controller 94%. **IDOR reject proven** for both cancel and reschedule.

---

## Decisions logged (`.claude/memory/decisions.md`)
- **D-030** — portal booking via `inherited sharing` + one `without sharing` wrapper + server-side C9 OTP gate. §3.4 invariants preserved.
- **D-030a** — least-privilege booking success is a QA Tier-1 **runtime gate** on a standard org (D-028 blocks the deploy-time counter assert here); reject Slot/Session edit and `AccessLevel.SYSTEM_MODE` as "fixes".
- **D-031** — VS-20 Apex managed sharing (Appointment + Patient), auto-provisioned groups, district View-All + FLS; reject criteria-based rules and "district-wide patient browsing".

## Open questions (for the architect)
- **OQ-030** — no target Lightning/Experience app is named for the citizen journey LWCs (VS-14 site out of POC scope). Components are exposed to `lightningCommunity__*` + `lightning__AppPage/HomePage`; where do they get placed?
- **OQ-031** *(the important one)* — cancel/reschedule of a **non-owned** booking is blocked: `VS_BookingService.cancel/reschedule` reads the Private appointment **under sharing**, and `inherited sharing` does **not** elevate from the inner-class caller (org-independent). The **own-booking** path works; a **guest citizen** (guest records are owned by the site default owner) and the **family-member** case hit `APPOINTMENT_NOT_FOUND`. Fix = an elevation-contract decision (top-level `without sharing` wrapper OR an elevated read seam), **not** a §3.4 change.

## Known limitations / flagged follow-ups
- **Move off Developer Edition** — D-027/D-028/D-029 make managed sharing + least-privilege writes "runtime-only" here. This is now the highest-leverage unblock.
- **VS-20 productionization** — the async recompute runs as the enqueuing user, who won't have Modify-All-Data in prod → needs an elevated maintainer (scheduled batch / platform-event as an integration user). Architect follow-up before REQ-053 is launch-complete.
- **Track B item 7** — human `cp` of the staged Stop-hook.
- Accessibility (REQ-056/057) is code-level only — a browser/screen-reader QA pass is still owed.

## Ticket status after this session
- ✅ Done + deployed: VS-01..13, VS-17, **VS-20**, **VS-16**, plus VS-ERRLOG, A-018, the whole App UI, and the D-030 portal layer.
- 🟡 Partial: **VS-14** (community permset + sharing set + retrieve the site to source), **VS-22** (seed script deliverable).
- ⬜ Not started: **VS-15** (facility finder LWC), **VS-18** (SMS seam), **VS-19** (confirmation flow), **VS-21** (retention purge batch).
