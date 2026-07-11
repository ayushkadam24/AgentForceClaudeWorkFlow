# Open Questions Register — Citizen Appointment & Vaccination Scheduling System

<!--
feature:        F-001 slot-booking-core (pilot); register covers full-engagement discovery
producing-agent: ba-analyst
date:           2026-07-11
phase:          DISCOVERY
derives-from:   requirements-brief.md (REQ-###) + all five 00-inputs documents
downstream:     technical-design decisions, sprint plan, QA test design
-->

Every ⚠ item, contradiction, uncommitted figure, external dependency and silent gap found in the
inputs is logged here. **"Suggested default" is the BA's recommendation only — not a client decision.**
Nothing here has been silently resolved into the requirements brief. Severity order:
`blocks-build > blocks-design > blocks-launch > clarification`.

## Summary table

| ID | Question | Why it matters (blocks) | Owner | Suggested default (BA) | Status |
|---|---|---|---|---|---|
| OQ-001 | Capacity model: single daily number (Shinde) vs per-session/time-block (Pawar)? | blocks-design (slot generation, F-001) | BA propose → Shinde+Pawar+DHO | Model capacity per time-block/session; a single daily block is the degenerate case | Open |
| OQ-002 | Slot granularity per service type (15-min vax? 20–30-min OPD?) | blocks-build (slot generation) | Facilities (Shinde+Pawar) | 15 min vaccination, configurable per service via Custom Metadata | Open |
| OQ-003 | Walk-in reserve % of daily capacity (20–30% floated) | blocks-build (capacity split) | DHO (pilot decision) | 25%, configurable per facility/service | Open |
| OQ-004 | Cancellation/reschedule cut-off hours (4 h floated) | blocks-build (reschedule/cancel rules) | DHO / design sign-off | 4 h before slot, configurable | Open |
| OQ-005 | Reminder timings — pre-appointment (2) and next-dose re-remind interval | blocks-build (scheduling) | DHO | 24 h + 3 h before; re-remind next-dose after 7 days; all configurable | Open |
| OQ-006 | Booking horizon (14 days suggested, "no objection") | blocks-design (minor) | Deshmukh/DHO | 14 days, configurable | Open |
| OQ-007 | Repeat no-show penalty: threshold count + restriction period | blocks-launch (REQ-017 penalty) | DHO → state guidance | Defer enforcement to phase 2; capture no-show count now; placeholder 3 no-shows / 6 months | Open |
| OQ-008 | 60/40 smartphone/feature-phone split (unverified, A-001) | clarification (channel priority) | DHO | Treat SMS as primary channel until data confirms | Open |
| OQ-009 | Exact vaccination-record retention schedule (≥10 yr placeholder) | blocks-launch (archival design) | Dept medical-records rules | Treat as permanent (min 10 yr); design purge switch per class | Open |
| OQ-010 | Per-vaccine open-vial usage windows and multi-dose schedules not provided | blocks-build (wastage alert REQ-022/023, next-dose REQ-024) | Pawar / cold-chain store | Hold as configurable reference data per vaccine | Open |
| OQ-011 | SMS gateway vendor undecided | blocks-build (SMS send path) | Deshmukh | Build behind replaceable interface (REQ-059); stub provider in POC | Open |
| OQ-012 | DLT templates: extend existing programme's or new registration (1–3 wk lead)? | blocks-launch (all SMS) | Deshmukh | Assume new registration; start template drafting now | Open |
| OQ-013 | DPDP consent + notice wording (department-approved) | blocks-launch (registration) | Department (Data Fiduciary) | Draft plain-language consent for department approval | Open |
| OQ-014 | Data-residency written confirmation before UAT | blocks-launch | Vendor + department | Provision org in India region (Hyderabad/Mumbai) from day 1 | Open |
| OQ-015 | Government holiday calendar — source, format, per-facility maintenance | blocks-build (slot generation) | Shinde / e-Gov cell | Staff-maintained holiday list per facility, configurable | Open |
| OQ-016 | Future CoWIN/U-WIN integration expectations (must not preclude) | clarification (design constraint) | State Health Dept | Keep external-ID + integration seam; no build now | Open |
| OQ-017 | Breach-notification nodal officer identity + path | blocks-launch | Department | Document path to a named nodal officer pre-go-live | Open |
| OQ-018 | Degraded/offline check-in behaviour at connectivity-poor PHCs | blocks-design (check-in) | Shinde (after tablet survey) | Online-only check-in for pilot + paper fallback; offline = phase 2 | Open |
| OQ-019 | Special Sunday drive vs holiday calendar — override mechanics | blocks-build (slot generation) | Design / Shinde | Staff-added capacity overrides holiday closure for that facility+date | Open |
| OQ-020 | Multi-patient de-duplication without Aadhaar (name+DOB+mobile collisions) | blocks-design (person model, F-001) | BA + department | Match on name+DOB+mobile; allow many patients per mobile; manual merge | Open |
| OQ-021 | Citizen lost booking reference — recovery flow (feature phone, no email) | blocks-design (booking mgmt) | BA | Lookup by registered mobile + DOB; resend confirmation SMS | Open |
| OQ-022 | "Rebooking assistance" after staff slot cancellation — auto-rebook vs invite? | blocks-design (REQ-034) | DHO | Notify + one-tap link to earliest alternatives; no silent auto-rebook | Open |
| OQ-023 | Certificate issuance timing / delayed-or-offline administration recording | clarification (REQ-029) | BA / Pawar | Certificate available once administration record is saved | Open |
| OQ-024 | Late-but-same-day arrival — no-show or served walk-in? | clarification (REQ-016) | Pawar | Present-but-late = checked-in if capacity, not a no-show | Open |
| OQ-025 | Is OPD appointment booking in scope this engagement, or vaccination only? | blocks-design (scope, F-001) | DHO / Deshmukh | Vaccination-first; OPD as a configurable service type, not in pilot | Open |
| OQ-026 | Data-field specifics: gender value set; DOB captured vs age (register uses age) | clarification (person model) | Department | Capture DOB (derive age); gender optional enumerated | Open |
| OQ-027 | Citizen self-service authentication mechanism (RFP silent; C9 covers chat only) | blocks-design (portal access, F-001) | Deshmukh | OTP to registered mobile | Open |

---

## Section 1 — Contradictions between sources or attendees

### OQ-001 — Capacity model: daily number vs per-session
- **What is unclear:** Mr. Shinde (MO, PHC Wadgaon) described capacity as a single **daily number**
  ("Wadgaon can do 120 in a day"). Sr. Nurse Pawar (CHC Ambegaon) insists capacity is **per session**
  (morning 9–1 roughly double afternoon 2–5), warning a single daily number causes everyone to book
  the morning. Two stakeholders describe the same concept differently (WS §2). Dr. Kulkarni said
  "design it so both work" but no concrete model was agreed.
- **Why it blocks:** This is the heart of F-001 slot generation (REQ-009, REQ-011). The slot data
  model, the walk-in split (OQ-003), and the §3.4 capacity ceiling (REQ-008) all depend on whether
  the atomic capacity unit is a day or a session/time-block.
- **Who must answer:** BA proposes a model; Shinde + Pawar + DHO ratify at design sign-off.
- **BA recommendation:** Model capacity at the **time-block/session** level and treat a single daily
  block as the degenerate configuration — this satisfies both without a redesign. *This is my
  recommendation, not a client decision.*

### OQ-024 — Late-but-same-day arrival: no-show or walk-in?
- **What is unclear:** REQ-016 auto-marks no-shows at end of day (WS §5), but nothing defines a
  citizen who arrives after their slot time yet the same day. The walk-in directive (WS §4) implies
  they could still be served from remaining capacity — the two rules can collide.
- **Why it blocks:** clarification for no-show metrics (feeds dashboard REQ-032) and check-in flow.
- **Who must answer:** Nurse Pawar / DHO.
- **BA recommendation:** Present-but-late counts as checked-in if capacity remains; only truly absent
  bookings become no-shows. *My recommendation.*

## Section 2 — Stated-but-unverified figures (treat as assumptions, never facts)

These numbers appear in the inputs but **no one committed to them.** They are carried as configurable
defaults, never asserted as fact in the brief. Logged assumptions: A-001 (split), A-003 (tunables).

- **OQ-002** slot granularity (15 / 20–30 min) — WS §3, "nobody committed" ⚠.
- **OQ-003** walk-in reserve 20–30% — WS §4, "not decided" ⚠.
- **OQ-004** cut-off 4 hours — WS §5, "confirm in design sign-off."
- **OQ-005** reminder timings (day-before + hours-before; re-remind after N days) — WS §7, §8, "TBD" ⚠.
- **OQ-006** booking horizon 14 days — WS §3, "no objection" (weak consensus, not a decision).
- **OQ-007** no-show penalty thresholds — WS §5, "no numbers agreed" ⚠, DHO to consult state guidance.
- **OQ-008** 60/40 smartphone/feature-phone split — PER, explicitly "⚠ unverified — treat as assumption" (A-001).
- **OQ-009** exact vaccination-record retention (≥10 yr placeholder) — C4.1, "confirm exact schedule" ⚠.
- **OQ-010** per-vaccine open-vial windows / multi-dose schedules — WS §6 & CS §C say "varies by vaccine";
  actual windows and dose intervals were never supplied. Needed for REQ-022/023 wastage logic and
  REQ-024 next-dose computation.

Each has a suggested default in the summary table; all are BA recommendations pending owner confirmation.

## Section 3 — External dependencies (outside the team's control)

### OQ-011 — SMS gateway vendor undecided
- **What is unclear:** No SMS provider chosen (WS §8, C7.4 ⚠). Confirmations (REQ-002) and reminders
  (REQ-025, REQ-027) all depend on an SMS channel.
- **Why it blocks:** blocks-build of any live send path; the whole reminder/confirmation surface.
- **Who must answer:** Deshmukh / e-Gov cell.
- **BA recommendation:** Build behind the replaceable provider interface (REQ-059) and ship the POC
  with a stub/mock provider so build is not blocked; swap in the real gateway when named. *My recommendation.*

### OQ-012 — DLT template registration
- **What is unclear:** Whether the department's existing DLT-registered templates (from another
  programme) can be extended, or new registration is required. Lead time 1–3 weeks (C7.1, WS §8).
- **Why it blocks:** blocks-launch — no SMS may be sent without registered templates.
- **Who must answer:** Deshmukh to confirm with the DLT operator.
- **BA recommendation:** Assume new registration is needed; begin drafting template text now against
  REQ-058 (transactional, helpline number included). *My recommendation.*

### OQ-013 / OQ-014 / OQ-016 / OQ-017 — Department/state approvals
- **OQ-013** DPDP consent + notice wording must be department-approved (C2.2) — blocks-launch of registration.
- **OQ-014** Written data-residency confirmation required before UAT (C3.1) — blocks-launch/UAT.
- **OQ-016** Future CoWIN/U-WIN integration expectations (RFP §4) — design must not preclude; clarification.
- **OQ-017** Named breach-notification nodal officer + documented path (C2.5) — blocks-launch.
- **Owners:** department / State Cell / State Health Dept as noted; BA recommendations in summary table.

## Section 4 — Silent gaps (scenarios the inputs never address)

Found by walking each persona journey and each artifact lifecycle (booking / slot / vial / certificate /
SMS) end-to-end and asking "what happens when this goes wrong or does not exist?"

### OQ-015 — Government holiday calendar: source and maintenance
- **Gap:** REQ-009 requires respecting the "government holiday calendar," but no input says where it
  comes from, its format, or who maintains it per facility. blocks-build of slot generation.
- **Owner:** Shinde / e-Gov cell. **BA recommendation:** staff-maintained, configurable holiday list per facility.

### OQ-018 — Degraded / offline check-in
- **Gap:** 3 of 14 PHCs have connectivity "unreliable after it rains"; check-in may run on personal
  phones (WS §9). No offline behaviour was agreed (⚠). blocks-design of check-in (REQ-018).
- **Owner:** Shinde after the tablet survey. **BA recommendation:** online-only check-in for the pilot
  with a paper fallback; treat offline/queued check-in as phase 2.

### OQ-019 — Special Sunday drive vs holiday closure
- **Gap:** Staff must be able to add capacity on a day the calendar marks closed (WS §3). The precedence
  and override mechanics are undefined. blocks-build of slot generation.
- **Owner:** design + Shinde. **BA recommendation:** an explicit staff-added capacity block overrides the
  holiday closure for that facility+date only.

### OQ-020 — Multi-patient identity & de-duplication without Aadhaar
- **Gap:** REQ-004 allows one mobile to hold many patients, and REQ-044 forbids Aadhaar — the usual
  unique key. Nothing defines how duplicate persons are detected/merged. blocks-design of the person
  model, which is F-001 foundational.
- **Owner:** BA + department. **BA recommendation:** soft-match on name + DOB + mobile; permit multiple
  patients per mobile; provide a manual merge; never auto-merge on partial matches.

### OQ-021 — Lost booking reference recovery
- **Gap:** A feature-phone citizen with no email who loses the SMS has no described way back to their
  booking. blocks-design of booking management.
- **Owner:** BA. **BA recommendation:** lookup by registered mobile + DOB, then resend the confirmation SMS.

### OQ-022 — "Rebooking assistance" mechanics
- **Gap:** REQ-034 promises "rebooking assistance" when staff cancel a facility's slots, but auto-rebook
  vs. invite-to-rebook is unspecified. blocks-design of the cancellation cascade.
- **Owner:** DHO. **BA recommendation:** notify affected citizens with a one-tap link to the earliest
  alternative slots; no silent auto-rebooking (avoids sending people to a time they can't make).

### OQ-023 — Certificate issuance timing
- **Gap:** REQ-029 issues a certificate "after a dose is administered," but if recording is delayed or
  done offline, when does the certificate become available? clarification.
- **Owner:** BA / Pawar. **BA recommendation:** certificate available the moment the administration record is saved.

### OQ-025 — OPD scope
- **Gap:** RFP scope and personas are vaccination-centric, yet current-state §B describes OPD intake and
  RFP §3.1 mentions "services" generally. Whether OPD appointment booking is in this engagement is
  ambiguous. blocks-design/scope.
- **Owner:** DHO / Deshmukh. **BA recommendation:** vaccination-first; model OPD as a configurable service
  type so it is not precluded, but keep it out of the F-001 pilot. (Logged as A-002.)

### OQ-026 — Person-field specifics
- **Gap:** C1.1 lists fields but not the gender value set, and today's register captures **age** while the
  system needs **DOB** (for next-dose math and de-dup). clarification.
- **Owner:** department. **BA recommendation:** capture DOB and derive age; gender optional, enumerated.

### OQ-027 — Citizen self-service authentication
- **Gap:** The RFP is silent on how a citizen authenticates to the booking portal to view/manage their
  bookings; Annexure C9 covers only the chat assistant. blocks-design of the citizen surface (F-001).
- **Owner:** Deshmukh. **BA recommendation:** OTP to the registered mobile number (works on feature phones,
  no Aadhaar, low-literacy friendly). *My recommendation.* (Logged as A-004.)

---

**Register total: 27 open questions.** F-001-blocking subset the architect must close before/at design
sign-off: OQ-001, OQ-002, OQ-003, OQ-004, OQ-020, OQ-025, OQ-027 (plus OQ-011/OQ-012 before any SMS build).
