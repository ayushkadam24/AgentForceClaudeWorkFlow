# Stakeholders & Personas

**Project:** Citizen Appointment & Vaccination Scheduling System
**Source:** Compiled from RFP §8 and the 02-Jul discovery workshop.

---

## Primary personas (interact with the system)

### P1 — Citizen / Patient
- **Who:** Residents of the district; skew toward lower income; significant elderly segment (drives).
- **Devices:** Low-cost Android smartphones on 3G/4G; a large minority on feature phones (SMS only).
- **Digital literacy:** Mixed; assume low. Many first-generation smartphone users.
- **Needs:** Know where/when a service is available, book without standing in line, get reminded, get a certificate, know when the next dose is due.
- **Success:** Books in under 3 minutes; arrives; is seen within ~20 minutes of slot time.

### P2 — Assisted Citizen (via ASHA worker or family member)
- **Who:** Elderly or feature-phone-only citizens whose bookings are made by someone else.
- **Key implication:** One phone number/login must be able to create and manage bookings for **multiple patients** (family or assisted citizens). The patient's identity, not the booker's, goes on the appointment and certificate.

### P3 — ASHA / Community Health Worker
- **Who:** Field workers, one per village/ward cluster; the human bridge to low-digital-literacy citizens.
- **Devices:** Personal Android phones.
- **Needs:** Book on behalf of citizens quickly; see who in their area is due for a next dose (phase 2 acceptable).

### P4 — Facility Front-Desk / Check-in Staff
- **Who:** Rotating duty staff at the facility entrance on drive days; a nurse or clerk otherwise.
- **Devices:** Shared Android tablet at CHCs/District Hospital; possibly personal phones at PHCs.
- **Needs:** Find a booking by reference or QR in seconds, one-tap check-in, see at a glance who is expected the rest of the day. "One thumb" operability.

### P5 — Nurse / Vaccinator (Nurse-in-Charge)
- **Who:** e.g., Sr. Nurse Pawar. Administers doses; owns the vial/wastage decision.
- **Needs:** Record the vaccination (vaccine, batch picked from stock — not typed), see remaining bookings today vs. doses left in opened vials, get a heads-up before opening a new vial near closing.

### P6 — Medical Officer in Charge (facility manager)
- **Who:** e.g., Mr. Shinde at PHC Wadgaon. Owns facility capacity and schedule.
- **Needs:** Set services offered and capacity, block holidays, add special drive days (including Sundays), cancel slots in a stock-out and have citizens automatically informed.

### P7 — District Health Officer (DHO)
- **Who:** Dr. Kulkarni. Programme sponsor and consumer of dashboards.
- **Needs (his Monday three):** facilities over/under capacity, wastage by facility, second-dose completion. Weekly cadence acceptable at launch.

### P8 — Data Entry Operator / District MIS
- **Who:** Ms. K. Joshi. Today's human integration layer.
- **Needs:** Stop re-typing registers into Excel; export capability for state-level reporting formats that will remain Excel-based for now.

## Secondary stakeholders (do not log in, but constrain the design)

| Stakeholder | Interest / constraint |
|---|---|
| State e-Governance Cell | Platform standards, no-Aadhaar directive, data residency, GIGW accessibility |
| DHS Technical Committee (Mr. Deshmukh, chair) | Design sign-off, acceptance testing incl. the concurrency test |
| District Cold-Chain Store | Upstream vaccine supply (out of scope, but batch data originates here) |
| District Health Helpline (104) | Referral target for all medical questions from the chat assistant |
| State Health Department | Future CoWIN/U-WIN integration expectations |

## Volume & shape notes for design
- ~1,900 appointments/day steady state; drive peaks to ~6,000/day (RFP §5).
- 19 facilities; from 1 shared tablet (District Hospital) down to zero dedicated devices (most PHCs).
- Assume 60/40 smartphone/feature-phone split among citizens until the department provides better data. ⚠ unverified figure — treat as assumption.

*Synthetic document for POC purposes; all persons and facilities fictional.*
