# Discovery Workshop — Raw Notes

**Project:** Citizen Appointment & Vaccination Scheduling System (RFP/DHS/2026/014)
**Date:** 02 July 2026, 10:30 AM – 1:45 PM
**Location:** DHS Conference Room, District Hospital campus + 2 remote
**Note-taker:** BA (vendor side)

**Attendees:**
- Dr. A. Kulkarni — District Health Officer (DHO), sponsor
- Mr. S. Deshmukh — e-Governance Cell (technical committee)
- Sr. Nurse M. Pawar — CHC Ambegaon, 14 yrs in immunization
- Mr. R. Shinde — Medical Officer in charge, PHC Wadgaon
- Ms. K. Joshi — Data Entry Operator, District Hospital
- Two ASHA workers (names not recorded) — joined for the last 40 min

*(These are raw notes, lightly cleaned. Direct quotes marked with "". Items marked ⚠ were unresolved in the room.)*

---

## 1. The morning rush — everyone's top pain

Dr. Kulkarni opened with it: "By 7:15 there are already a hundred people at the gate of the district hospital. Half of them don't need to be there before noon."

Nurse Pawar: token system collapses on drive days. On the last typhoid drive at Ambegaon they issued 240 tokens by 8 AM against a realistic capacity of ~150 administrations for the day. 90 people sent home, "and those are the ones who shout at us, correctly."

Elderly citizens are the worst affected — they arrive earliest because they fear missing out, then stand the longest.

## 2. How capacity actually works ⚠ (contradiction — needs follow-up)

- Mr. Shinde described capacity as a **daily number**: "Wadgaon can do 120 vaccinations in a day, that's it."
- Nurse Pawar pushed back: her CHC thinks in **sessions** — a morning session (9–1) and afternoon session (2–5) with different staffing, so morning capacity is roughly double afternoon. "If you give me one number for the whole day, people will still all book the morning."
- ⚠ Not resolved. Dr. Kulkarni: "Design it so both work." **Action: BA to propose a capacity model that supports per-session or time-distributed capacity, review with both facilities.**

## 3. Slots, timing, granularity

- General agreement that 15-minute slot granularity "sounds right" for vaccination; OPD consultations run longer, maybe 20–30 min. Nobody committed to final numbers. ⚠
- Booking horizon: Deshmukh suggested 14 days ahead. No objection.
- Facilities close on the government holiday list, but Mr. Shinde noted PHCs sometimes run **special Sunday drives** that are announced only a week or two ahead. The system must allow staff to add capacity on an otherwise-closed day. ⚠ (how this interacts with the holiday calendar — TBD)

## 4. Walk-ins are not going away — important

Strong consensus, worth quoting Dr. Kulkarni in full: "You cannot build a system that turns away a grandmother who took two buses to get here because she doesn't have a smartphone. Booked citizens get priority, walk-ins get whatever is left."

- Working assumption in the room: reserve some portion of daily capacity for walk-ins, at least initially. Nurse Pawar suggested 20–30%. Not decided. ⚠
- ASHA workers said they routinely book/queue on behalf of elderly citizens using their own phones — the system should allow one phone number to manage bookings for multiple family/assisted patients. Ms. Joshi confirmed this pattern at the hospital too.

## 5. Cancellation / reschedule policy

- Nurse Pawar wants a cut-off "a few hours before" so freed places can actually be reused the same day. Number floated in the room: **4 hours**. Dr. Kulkarni fine with it. Treat as working policy, confirm in design sign-off.
- No-shows: staff want them marked automatically at end of day. Dr. Kulkarni raised repeat offenders: "Some people book every drive and never come." Suggestion: after some number of no-shows, restrict access to the early/priority slots for a period. **No numbers agreed.** ⚠

## 6. Vials and wastage — the money question

- Nurse Pawar walked through vial mechanics: e.g., a 10-dose vial once opened must be used within the session/manufacturer window or discarded. The painful decision is at ~4 PM: 6 doses left in an open vial question is fine, but "do I open a NEW vial for 3 waiting people at 4:30?" Today it's guesswork.
- What staff actually want from the system: at any point in the day, see **confirmed upcoming bookings for the rest of the day** next to **doses remaining in opened vials** — so the open-a-new-vial decision is informed. An alert near closing time would help.
- Batch numbers are recorded by hand today into the register and later typed into Excel by Ms. Joshi. Error-prone. Batch entry should be a pick from stock on hand, not free text.

## 7. Second doses / follow-up

- Ms. Joshi currently maintains a due-list in Excel and ASHA workers phone people. Coverage is patchy: "If the ASHA didi knows you, you get the call."
- Wanted: automatic computation of the next due date from the administered dose, SMS invitation when due, and a link that lands the citizen directly on bookable slots for the right service. If ignored, remind again after some days.

## 8. Reminders & SMS realities

- Two reminders felt right in the room: day before + a couple of hours before. ⚠ exact timings TBD.
- ⚠ **SMS gateway vendor is NOT decided.** The department's DLT-registered templates exist for another programme; Deshmukh to confirm whether they can be extended or new registration is needed. **Open dependency — flag in the requirements brief.**
- Many citizens have feature phones (no smartphone). SMS is the reliable channel; anything essential must work over SMS + a printable confirmation at the facility if needed.

## 9. Check-in on the ground

- District Hospital has 2 Android tablets; most PHCs have none — check-in may run on staff's personal phones initially. Mr. Shinde: "Whatever it is, it must work with one thumb while I'm also answering questions."
- QR on the confirmation would be nice; typing a short booking reference must also work (QR won't render on feature phones).
- Connectivity at 3 of the 14 PHCs is described as "unreliable after it rains." ⚠ Degraded-connectivity behavior for check-in needs thought; no requirement agreed.

## 10. Certificates

- Citizens ask for vaccination certificates constantly (travel, school admission, employers). Today: handwritten slip with a stamp.
- Wanted: PDF certificate with a verifiable ID, downloadable from the citizen's bookings page and emailed where email exists. Deshmukh: keep a verification lookup in mind for phase 2 (employer scans code, sees valid/invalid). Not in scope now, don't preclude.

## 11. Dashboards — what the DHO actually looks at

Dr. Kulkarni, asked what he'd check every Monday: "Three things. Which facilities are turning people away or sitting idle. How much vaccine we wasted and where. Who is not coming back for the second dose." Also wants drive-day live view eventually, but "monthly-to-weekly is already a revolution."

## 12. Identity & data notes (from Deshmukh)

- **Do NOT collect or store Aadhaar numbers.** Phone + name + DOB is sufficient for this programme. This is a hard directive from the state cell.
- Chat assistant, if built, must verify identity (booking ref, or registered phone + DOB) before revealing or changing anything, and must never answer medical questions — route to helpline 104.
- Data residency: state directive requires data hosted in-country. Deshmukh to share the departmental data-handling annexure. ⚠ (received later — see compliance folder)

## Parking lot / follow-ups
1. Capacity model: daily vs per-session — BA to propose, review with Pawar + Shinde.
2. Walk-in reserve percentage — pilot decision.
3. No-show penalty thresholds — DHO to consult state guidance.
4. SMS gateway/DLT templates — Deshmukh, blocking for reminders build.
5. Special Sunday drives vs holiday calendar — design question.
6. Slot duration defaults per service type — confirm with facilities.
7. Poor-connectivity check-in behavior — revisit after tablet survey.

*Synthetic document for POC purposes; all persons and facilities fictional.*
