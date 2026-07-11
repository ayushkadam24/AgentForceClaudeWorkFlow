# Requirements Brief — Citizen Appointment & Vaccination Scheduling System

<!--
feature:        F-001 slot-booking-core (pilot); brief also captures full-engagement scope
producing-agent: ba-analyst
date:           2026-07-11
phase:          DISCOVERY
derives-from:   00-inputs/rfp/RFP-DHS-2026-014-appointment-system.md
                00-inputs/discovery-notes/2026-07-02-discovery-workshop-notes.md
                00-inputs/current-state/current-process-documentation.md
                00-inputs/stakeholders/stakeholder-personas.md
                00-inputs/compliance/annexure-c-compliance-constraints.md
downstream:     01-discovery/open-questions.md (OQ-###), technical-design (EP-##)
-->

## Problem statement (client's language)

The District Health Society of Nandgaon runs 14 PHCs, 4 CHCs and 1 District Hospital serving
~1.1 million citizens. All scheduling is manual: citizens arrive without appointments, take paper
tokens first-come, and wait hours. 60–70% of daily footfall lands between 7:00–9:30 AM, elderly
citizens wait 2.5+ hours, 11–14% of multi-dose vials are wasted to unpredictable demand, only ~63%
of second doses complete on time, and officials see performance data 3–5 weeks late as Excel. DHS
wants a Salesforce (Public Sector Solutions) system that lets citizens book a specific slot with
SMS confirmation, lets staff check-in and record vaccinations and see stock, reminds citizens and
recalls them for next doses, issues verifiable certificates, and gives the DHO weekly visibility —
above all guaranteeing (RFP §3.4) that no slot is ever overbooked, even under simultaneous booking.

**Pilot scope (F-001 slot-booking-core):** citizen slot booking + the §3.4 slot-integrity guarantee
+ its compliance envelope. Broader requirements are captured here so nothing is lost, priced by
MoSCoW, and each traced to a source. Uncommitted numbers and ambiguities live in `open-questions.md`.

## Personas summary (P1–P8)

| P | Persona | Success criterion |
|---|---|---|
| P1 | Citizen / Patient | Books in < 3 min; arrives; seen within ~20 min of slot time |
| P2 | Assisted Citizen (via ASHA/family) | One mobile manages bookings for multiple patients; patient's identity on record |
| P3 | ASHA / Community Health Worker | Books quickly on behalf of citizens; sees who is due (phase 2 ok) |
| P4 | Facility Front-Desk / Check-in Staff | Finds a booking by ref/QR in seconds; one-thumb check-in on a shared tablet |
| P5 | Nurse / Vaccinator (Nurse-in-Charge) | Records dose (batch from stock, not typed); sees today's bookings vs doses left in open vials |
| P6 | Medical Officer in Charge | Sets services/capacity, blocks holidays, adds Sunday drives, cancels slots with auto-notify |
| P7 | District Health Officer (DHO) | Weekly view: over/under-capacity facilities, wastage, second-dose completion |
| P8 | Data Entry Operator / District MIS | Stops re-typing registers; exports state-format Excel |

## Requirements register

Priority key (per skill rules of evidence): **Must** = RFP-mandatory or Annexure-C-binding;
**Should** = workshop consensus / persona success criterion / desirable; **Could** = raised but
unresolved and non-blocking. "Must (if built)" = binding *only if* the optional capability is delivered.
Source key: RFP = RFP §; WS = workshop notes §; CS = current-state §; PER = personas; C = Annexure C.

### A. Citizen booking & discovery

| ID | Requirement ("The system shall…") | Priority | Source | Personas | Notes/OQ |
|---|---|---|---|---|---|
| REQ-001 | provide online discovery of services offered at each facility, searchable by service and proximity to the citizen's location. | Must | RFP §3.1 | P1,P2 | |
| REQ-002 | allow advance booking of a specific date and time slot, returning instant confirmation by SMS (and email where available) that includes a unique booking reference. | Must | RFP §3.1 | P1,P2,P3 | **F-001 core** |
| REQ-003 | allow citizen self-service rescheduling and cancellation, subject to a cut-off policy. | Must | RFP §3.1; WS §5 | P1 | cut-off value → OQ-004 |
| REQ-004 | permit one mobile number/login to create and manage bookings for multiple patients, recording the patient's identity (not the booker's) on the appointment and certificate. | Must | PER P2/P3; WS §4 | P2,P3 | de-dup → OQ-020 |
| REQ-005 | make the booking experience usable by elderly and low-digital-literacy citizens and function acceptably on low-cost smartphones over 3G-class connectivity. | Must | RFP §3.1,§5 | P1 | |
| REQ-006 | enable a citizen to complete a booking in under 3 minutes. | Should | PER P1 | P1 | success target, not committed metric |
| REQ-007 | give confirmed bookings priority and serve walk-ins from remaining capacity, reserving a configurable portion of daily capacity for walk-ins. | Must | WS §4 | P1,P4 | reserve % → OQ-003 |

### B. Slot generation & capacity model (F-001 core)

| ID | Requirement ("The system shall…") | Priority | Source | Personas | Notes/OQ |
|---|---|---|---|---|---|
| REQ-008 | guarantee that confirmed bookings for any slot never exceed that slot's published capacity under any conditions, including simultaneous booking attempts by multiple citizens. | **Must (highest)** | RFP §3.4 | P1 | **F-001 core, QA Tier-1**; acceptance concurrency test |
| REQ-009 | automatically generate bookable slots from defined capacity, respecting facility operating days/hours and the government holiday calendar. | Must | RFP §3.2 | P6 | holiday source → OQ-015 |
| REQ-010 | let facility staff define services offered and daily intake capacity per facility, per service. | Must | RFP §3.2 | P6 | |
| REQ-011 | support a capacity model that expresses per-session or time-distributed capacity, not only a single daily number. | Must | WS §2 (DHO: "design so both work") | P5,P6 | model → OQ-001 (contradiction) |
| REQ-012 | let staff add capacity on an otherwise-closed day (e.g., special Sunday drives announced 1–2 weeks ahead). | Must | WS §3 | P6 | vs holiday cal → OQ-019 |
| REQ-013 | limit booking to a configurable horizon ahead (proposed default 14 days). | Should | WS §3 | P1 | value → OQ-006 |
| REQ-014 | support slot granularity configurable per service type (proposed default 15 min vaccination, 20–30 min OPD). | Should | WS §3 | P6 | values → OQ-002 |

### C. Cancellation, reschedule & no-show

| ID | Requirement ("The system shall…") | Priority | Source | Personas | Notes/OQ |
|---|---|---|---|---|---|
| REQ-015 | enforce a cancellation/reschedule cut-off so freed places can be reused the same day (proposed working default 4 hours). | Should | WS §5 | P1,P5 | value → OQ-004 |
| REQ-016 | mark un-attended bookings as no-shows automatically at end of day. | Must | WS §5 | P4,P5 | late-arrival edge → OQ-024 |
| REQ-017 | after a threshold of no-shows, restrict a citizen's access to early/priority slots for a period. | Could | WS §5 | P4 | thresholds unresolved → OQ-007 |

### D. Staff & check-in

| ID | Requirement ("The system shall…") | Priority | Source | Personas | Notes/OQ |
|---|---|---|---|---|---|
| REQ-018 | provide rapid check-in of arriving citizens by booking reference or scannable code, suitable for one-thumb use on a shared tablet at the facility entrance. | Must | RFP §3.2; WS §9 | P4 | offline behaviour → OQ-018 |
| REQ-019 | accept a short typed booking reference for check-in (QR will not render on feature phones). | Must | WS §9 | P4 | |

### E. Vaccination recording & stock

| ID | Requirement ("The system shall…") | Priority | Source | Personas | Notes/OQ |
|---|---|---|---|---|---|
| REQ-020 | record the administered vaccination including vaccine, batch number, and administering staff member. | Must | RFP §3.2; CS §A; WS §6 | P5 | |
| REQ-021 | require batch number to be picked from stock on hand, not entered as free text. | Must | WS §6; CS §C | P5 | |
| REQ-022 | show, at any point in the day, confirmed upcoming bookings for the rest of the day alongside doses remaining in opened vials, to inform the open-a-new-vial decision. | Must | RFP §3.2; WS §6 | P5 | vial windows → OQ-010 |
| REQ-023 | alert the nurse-in-charge near closing time to inform the open-a-new-vial decision. | Should | WS §6 | P5 | |

### F. Follow-up & reminders

| ID | Requirement ("The system shall…") | Priority | Source | Personas | Notes/OQ |
|---|---|---|---|---|---|
| REQ-024 | automatically compute the next-dose due date from the administered dose for multi-dose schedules. | Must | RFP §3.1; WS §7 | P1,P8 | schedules source → OQ-010 |
| REQ-025 | send an SMS invitation when a next dose becomes due, with a direct link landing the citizen on bookable slots for the correct service. | Must | RFP §3.1; WS §7 | P1,P3 | |
| REQ-026 | re-send the next-dose reminder after a configurable interval if the first is not acted on. | Should | WS §7 | P1 | interval → OQ-005 |
| REQ-027 | send automated reminders before an appointment (two by default: day-before and hours-before), with timings held as configuration. | Must | RFP §3.1; WS §8 | P1 | timings → OQ-005 |
| REQ-028 | ensure essential information is deliverable over SMS and, where needed, as a printable confirmation at the facility. | Must | WS §8 | P1,P2 | |

### G. Certificates

| ID | Requirement ("The system shall…") | Priority | Source | Personas | Notes/OQ |
|---|---|---|---|---|---|
| REQ-029 | provide a downloadable PDF vaccination certificate after a dose is administered, available from the citizen's bookings page and emailed where an email exists. | Must | RFP §3.1; WS §10 | P1 | issuance timing → OQ-023 |
| REQ-030 | carry on each certificate a unique, non-guessable certificate ID and the issuing facility, showing only the C1.3 minimum data (no Aadhaar, no address). | Must | C8.1–8.2 | P1 | |
| REQ-031 | not architecturally preclude a phase-2 certificate-verification lookup by a third party. | Should | C8.3; WS §10 | P1 | future phase |

### H. Dashboards & administration

| ID | Requirement ("The system shall…") | Priority | Source | Personas | Notes/OQ |
|---|---|---|---|---|---|
| REQ-032 | provide dashboards covering at minimum coverage by facility and service, no-show rates, vaccine wastage rates, and multi-dose completion rates. | Must | RFP §3.3; WS §11 | P7 | |
| REQ-033 | support weekly reporting cadence at launch, with drive-day live view as a later enhancement. | Should | WS §11; PER P7 | P7 | |
| REQ-034 | let authorized staff cancel a facility's slots in exceptional circumstances (stock-out, staff unavailability) with automatic notification and rebooking assistance for affected citizens. | Must | RFP §3.3 | P6 | rebook mechanism → OQ-022 |
| REQ-035 | provide export capability for state-level reporting formats that remain Excel-based. | Should | PER P8 | P8 | |
| REQ-036 | restrict bulk export to the District MIS role and log every bulk export. | Must | C5.2 | P8 | |

### I. Conversational assistant (highly desirable; guardrails binding if built)

| ID | Requirement ("The system shall…") | Priority | Source | Personas | Notes/OQ |
|---|---|---|---|---|---|
| REQ-037 | offer a conversational (chat) assistant through which a citizen can complete a booking end-to-end without navigating forms. | Should | RFP §3.1 (highly desirable) | P1 | scored 10% |
| REQ-038 | verify identity (booking reference, or registered mobile + DOB) before revealing or modifying any personal data in the assistant. | Must (if built) | C9.1; WS §12 | P1 | |
| REQ-039 | decline all medical questions (contraindication, symptom, dosage suitability) and redirect to helpline 104; verified explicitly in UAT. | Must (if built) | RFP §4; C9.2 | P1 | |
| REQ-040 | read back facility, service, date and time and obtain explicit citizen confirmation before executing any booking/reschedule/cancel. | Must (if built) | C9.3 | P1 | |
| REQ-041 | retain assistant transcripts per notification-log rules unless they contain a transaction, in which case the transaction follows booking retention. | Must (if built) | C9.4; C4 | — | |
| REQ-042 | not transmit personal data to any service outside the approved platform boundary (applies to any AI/chat feature). | Must (if built) | C3.3 | — | |

### J. Cross-cutting & compliance (Annexure C — binding)

| ID | Requirement ("The system shall…") | Priority | Source | Personas | Notes/OQ |
|---|---|---|---|---|---|
| REQ-043 | collect only full name, date of birth, gender (optional), mobile number, locality/pin code, and optional email. | Must | C1.1 | all | field set → OQ-026 |
| REQ-044 | never collect, store, transmit, or request Aadhaar numbers in any field, including free-text notes, logs, or test/seed data. | Must | C1.2; WS §12; rules/10 | all | zero-tolerance; QA Tier-1 |
| REQ-045 | limit health data to the vaccination event and appointment history — no diagnoses, symptoms, or clinical notes. | Must | C1.3 | all | |
| REQ-046 | present DPDP notice and obtain plain-language consent for the stated purposes at registration, using department-approved wording. | Must | C2.2 | P1 | wording → OQ-013 |
| REQ-047 | limit use of collected data to the programme purposes; no marketing or unrelated government messaging without fresh consent. | Must | C2.3 | all | |
| REQ-048 | let citizens request correction of, and access to, their own records; honour deletion subject to the retention directive and inform them at consent. | Must | C2.4 | P1 | |
| REQ-049 | provide a documented breach-notification path to the department's nodal officer before go-live. | Must | C2.5 | — | owner → OQ-017 |
| REQ-050 | keep all citizen personal data at rest in India (Hyderabad/Mumbai region), with written confirmation of residency furnished before UAT. | Must | C3.1 | all | → OQ-014 |
| REQ-051 | use only synthetic or masked data in development and test environments. | Must | C3.2 | — | binds seed scripts |
| REQ-052 | retain records per class (vaccination ≥10 yr, bookings 3 yr, SMS logs 1 yr, audit trail 3 yr tamper-evident) and make archival/purge possible per class. | Must | C4 | — | exact schedule → OQ-009 |
| REQ-053 | enforce role-based access: facility staff see only their own facility's citizens/appointments; district roles see aggregates and justified record-level data with audit. | Must | C5.1 | P4,P6,P7,P8 | QA Tier-1 |
| REQ-054 | make every read of a citizen record attributable (user, timestamp). | Must | C5.2 | all staff | |
| REQ-055 | require individual logins on shared devices and enforce a session timeout of ≤15 minutes of inactivity. | Must | C5.3 | P4 | |
| REQ-056 | conform to WCAG 2.1 AA and GIGW; make the booking, reschedule, cancel and certificate-download journeys fully keyboard- and screen-reader-operable and usable at 200% zoom. | Must | RFP §5; C6 | P1 | QA-testable |
| REQ-057 | never use colour as the only carrier of meaning (e.g., slot-availability states carry text/labels). | Must | C6.3 | P1 | |
| REQ-058 | send all SMS via a TRAI DLT-registered header and pre-registered transactional templates, including the facility helpline number in every actionable template. | Must | C7.1–7.3; RFP §5 | P1 | DLT lead time → OQ-012 |
| REQ-059 | isolate the SMS provider behind a replaceable interface (gateway vendor undecided). | Must | C7.4; WS §8 | — | vendor → OQ-011 |

## Non-functional requirements

| ID | Requirement ("The system shall…") | Priority | Source |
|---|---|---|---|
| REQ-060 | ship in English at launch, with an interface architecture that supports Marathi and Hindi localization in a later phase without redesign. | Must | RFP §5 |
| REQ-061 | be available during business hours 7 AM – 8 PM, with scheduled maintenance permitted outside that window. | Must | RFP §5 |
| REQ-062 | support planning volumes of ~1,900 appointments/day at steady state and peaks up to ~6,000/day during announced drives. | Must | RFP §5; PER |
| — accessibility | covered by REQ-056 / REQ-057 | Must | C6 |
| — data protection | covered by REQ-043–REQ-054 | Must | C1–C5 |

## Out of scope (RFP §4 — restated so nobody builds it)

- Integration with national **CoWIN / U-WIN** platforms — future phase; design must not preclude it (→ OQ-016).
- **Payment collection** of any kind — all in-scope services are free at point of delivery.
- **Clinical decision support / medical advice** of any form — the assistant must decline and redirect to 104 (REQ-039).
- **Inventory procurement / upstream supply-chain** management above the facility level.
- Phase-2 only (not this engagement, do not preclude): certificate verification lookup (REQ-031),
  ASHA area due-lists (PER P3), drive-day live dashboard (REQ-033), OPD booking beyond a configurable
  service type (→ OQ-025).

## Traceability summary

**By MoSCoW:** Must = 51 · Should = 10 · Could = 1 · Won't = 0 · **Total = 62.**
(Five of the 51 Must are "Must if built" — the chat-assistant guardrails REQ-038–042.)

**By primary source document:**
| Source | REQ count |
|---|---|
| RFP | 20 |
| Annexure C (compliance) | 24 |
| Discovery workshop | 15 |
| Personas | 3 |
| Current-state | 0 primary (corroborates REQ-020/021/032) |

**F-001 slot-booking-core critical path:** REQ-002, REQ-007, REQ-008 (integrity, highest),
REQ-009, REQ-010, REQ-011, REQ-053 (role visibility), REQ-044 (no-Aadhaar) — with OQ-001, OQ-002,
OQ-003, OQ-004 needing resolution before the slot-generation build is fully specified.

**All 62 REQs trace to a source document + section.** No requirement is un-sourced. Every ⚠ item and
every uncommitted figure in the inputs has been routed to `open-questions.md` rather than stated as fact.
