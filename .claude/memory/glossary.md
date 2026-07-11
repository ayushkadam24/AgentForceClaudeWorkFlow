# Domain Glossary

| Term | Meaning in this project |
|---|---|
| PHC / CHC | Primary / Community Health Centre (14 / 4 in district, + 1 District Hospital) |
| ASHA worker | Community health worker; books on behalf of citizens (persona P3) |
| Drive day | Announced vaccination campaign day; demand peaks to ~6,000/day district-wide |
| Session | Facility working block (e.g., 9–1, 2–5) with its own staffing/capacity |
| Slot | Bookable time window generated from capacity; carries the §3.4 integrity guarantee |
| Walk-in reserve | Portion of daily capacity kept for citizens without bookings (% TBD — OQ) |
| Vial wastage | Doses discarded when an opened multi-dose vial expires within its usage window |
| Open-vial decision | Late-day judgement whether to open a new vial for few remaining citizens |
| Due list | Citizens due for a next dose; today an Excel + ASHA phone calls |
| DLT template | TRAI-registered SMS template — mandatory for sending SMS in India (1–3 wk lead) |
| DPDP | Digital Personal Data Protection Act, 2023 |
| GIGW | Government of India Guidelines for Websites (accessibility) |
| 104 | District health helpline; all medical questions route there |
| U-WIN / CoWIN | National immunization platforms; future integration, out of scope now |
| Booking reference | Unique, human-typeable ID returned on booking; used for check-in and lookup |
| No-show | A confirmed booking whose citizen did not attend; auto-marked at end of day |
| Cut-off policy | Time before a slot after which self-service reschedule/cancel is blocked (default 4h — OQ) |
| Booking horizon | How far ahead a citizen may book (proposed default 14 days — OQ) |
| Certificate ID | Unique, non-guessable identifier printed on each vaccination certificate |
| Data Fiduciary / Processor | DPDP roles: department = Data Fiduciary; vendor + platform = Data Processors |
| OPD | Outpatient Department — general (non-vaccination) consultations; scope TBD (OQ-025) |
| DHS / DHO | District Health Society / District Health Officer (Dr. Kulkarni, sponsor) |
| Check-in | On-arrival confirmation of a booking by reference or QR at the facility entrance |
