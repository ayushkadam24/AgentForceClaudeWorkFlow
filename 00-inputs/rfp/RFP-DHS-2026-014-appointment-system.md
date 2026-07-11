# Request for Proposal — RFP/DHS/2026/014

**Issuing Authority:** District Health Society, Nandgaon District (fictional), Department of Public Health
**Title:** Citizen Appointment & Vaccination Scheduling System for District Health Centers
**Date of Issue:** 02 June 2026
**Proposal Due:** 30 June 2026
**Contract Type:** Fixed-price implementation + 12-month support

---

## 1. Background

The District Health Society (DHS) operates 14 Primary Health Centres (PHCs), 4 Community Health Centres (CHCs), and 1 District Hospital. These facilities deliver routine immunization, seasonal vaccination drives (COVID-19 boosters, typhoid, influenza), and general outpatient (OPD) consultations to a catchment population of approximately 1.1 million citizens.

All patient-facing scheduling today is manual. Citizens arrive without appointments, receive paper tokens on a first-come basis, and wait — often for several hours. The department has received sustained complaints regarding wait times for elderly citizens, and internal audits have documented significant vaccine wastage attributable to unpredictable daily demand.

The Department holds an existing enterprise agreement with Salesforce (Public Sector Solutions licenses procured under the state e-governance framework in FY 2025-26). **Bidders are required to deliver the solution on this platform**; proposals recommending alternative platforms will be deemed non-responsive.

## 2. Problem Statement

The DHS seeks to remedy the following documented problems:

1. **Overcrowding at opening hours.** Facility registers show 60–70% of daily footfall arrives between 7:00 and 9:30 AM, overwhelming staff in the morning and leaving them idle after 2 PM.
2. **Excessive waiting for vulnerable citizens.** Average recorded wait time for citizens aged 60+ during vaccination drives exceeds 2.5 hours.
3. **Vaccine wastage.** Multi-dose vials, once opened, must be used within the manufacturer's specified window. Unpredictable attendance means opened vials are frequently discarded partially used. FY 2025-26 internal audit estimated wastage at 11–14% for multi-dose presentations.
4. **Missed follow-up doses.** For multi-dose schedules, second-dose completion within the recommended window is approximately 63%. There is no systematic reminder or recall mechanism.
5. **No management visibility.** District officials receive facility performance data as monthly Excel compilations, typically 3–5 weeks after the fact.

## 3. Scope of Work

The selected vendor shall design, build, test, and deploy a system providing:

### 3.1 Citizen-facing capabilities
- Online discovery of health services offered at each facility, searchable by service and proximity to the citizen's location.
- Advance booking of a specific date and time slot, with instant confirmation delivered by SMS and (where available) email, including a unique booking reference.
- Self-service rescheduling and cancellation, subject to a cut-off policy to be finalized during design.
- Automated reminders before the appointment.
- A downloadable vaccination certificate following administration of a dose.
- Automatic notification when a citizen becomes due for a subsequent dose in a multi-dose schedule, with a direct link to book it.
- The booking experience must be usable by elderly and low-digital-literacy citizens, and must function acceptably on low-cost smartphones over 3G-class connectivity.
- A conversational assistant (chat) through which a citizen can complete a booking end-to-end without navigating forms is **highly desirable** and will be scored favorably.

### 3.2 Facility staff capabilities
- Definition of services offered and daily intake capacity per facility, per service.
- Automatic generation of bookable slots from the defined capacity, respecting facility operating days/hours and the government holiday calendar.
- Rapid check-in of arriving citizens by booking reference or scannable code, suitable for use on a shared tablet at the facility entrance.
- Recording of the administered vaccination, including vaccine, batch number, and administering staff member.
- Visibility of vaccine stock at the facility sufficient to support wastage reduction decisions (e.g., whether to open a new vial late in the day).

### 3.3 District administration capabilities
- Dashboards covering, at minimum: coverage by facility and service, no-show rates, vaccine wastage rates, and multi-dose completion rates.
- Ability for authorized staff to cancel a facility's slots in exceptional circumstances (stock-out, staff unavailability) with automatic notification and rebooking assistance for affected citizens.

### 3.4 Integrity requirement (mandatory)
The system **must guarantee that the number of confirmed bookings for any slot never exceeds that slot's published capacity, under any conditions, including simultaneous booking attempts by multiple citizens.** During pre-launch acceptance testing, the DHS technical committee will conduct a concurrency test simulating simultaneous booking of the final available place in a slot; any observed overbooking constitutes acceptance failure.

## 4. Out of Scope (this engagement)
- Integration with the national CoWIN / U-WIN immunization platforms (planned as a future phase; the design should not preclude it).
- Payment collection of any kind. All services in scope are free at point of delivery.
- Clinical decision support or medical advice of any form. Any conversational assistant must decline medical questions and redirect citizens to the district health helpline (104).
- Inventory procurement / supply-chain management upstream of the facility.

## 5. Non-Functional Requirements
- **Accessibility:** Conformance to WCAG 2.1 Level AA and applicable Government of India web accessibility guidance (GIGW). Full keyboard and screen-reader operability of the booking flow is mandatory.
- **Language:** English at launch; the interface architecture must support Marathi and Hindi localization in a subsequent phase without redesign.
- **Data protection:** Compliance with the Digital Personal Data Protection Act, 2023, and departmental data-handling directives (see Annexure C, provided to shortlisted bidders).
- **Availability:** Business hours availability 7 AM – 8 PM; scheduled maintenance permitted outside these hours.
- **Volumes (planning figures):** ~1,900 appointments/day district-wide at steady state; peaks up to 6,000/day during announced vaccination drives.

## 6. Deliverables
1. Solution design document, reviewed and signed off by the DHS technical committee prior to build.
2. Configured and tested system in a pre-production environment.
3. Acceptance test evidence, including the concurrency test in §3.4.
4. Training for facility staff (train-the-trainer model) and user guides in plain language.
5. 12 months of post-go-live support.

## 7. Evaluation Criteria (summary)
| Criterion | Weight |
|---|---|
| Understanding of the problem & solution fit | 25% |
| Technical soundness, esp. §3.4 integrity guarantee | 25% |
| Usability for elderly / low-literacy citizens | 20% |
| Conversational booking capability | 10% |
| Delivery plan & team | 10% |
| Cost | 10% |

## 8. Points of Contact
- **Programme sponsor:** Dr. A. Kulkarni, District Health Officer
- **Technical committee chair:** Mr. S. Deshmukh, District e-Governance Cell
- **Administrative queries:** Ms. P. Iyer, DHS Procurement

*This RFP is a synthetic document created for a proof-of-concept exercise. The Nandgaon District Health Society, its facilities, and named individuals are fictional.*
