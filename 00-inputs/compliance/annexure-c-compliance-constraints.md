# Annexure C — Compliance & Data-Handling Constraints

**Issued by:** District e-Governance Cell (Mr. S. Deshmukh) on behalf of the State Cell
**Applies to:** RFP/DHS/2026/014 and all resulting design/build work
**Status:** Binding. Deviations require written approval of the Technical Committee.

---

## C1. Personal data — collection minimization
1. The system shall collect only: full name, date of birth, gender (optional), mobile number, and locality/pin code. Email is optional.
2. **Aadhaar numbers shall NOT be collected, stored, transmitted, or requested**, in any field including free-text notes. This is a hard directive from the State Cell for this programme.
3. Health data captured is limited to the vaccination event itself (service, vaccine, batch, dose number, date, administering facility/staff) and appointment history. No diagnoses, symptoms, or clinical notes.

## C2. Digital Personal Data Protection Act, 2023 (DPDP)
1. The department is the Data Fiduciary; the vendor and platform operate as Data Processors.
2. Notice and consent for the stated purpose (appointment scheduling, reminders, vaccination record, certificate issuance) must be presented in plain language at registration; consent wording to be approved by the department.
3. Purpose limitation: data collected shall not be used for any purpose beyond the programme without fresh consent. No marketing or unrelated government messaging through this channel.
4. Citizens may request correction of their personal details and access to their own records. Deletion requests are subject to the retention directive in C4 (health records are retained per departmental rules; the citizen must be informed of this at consent).
5. A breach-notification path to the department's nodal officer must be documented before go-live.

## C3. Residency & platform
1. All citizen personal data at rest must reside in data centers located in India. The Salesforce org shall be provisioned/configured accordingly (Hyderabad/Mumbai region); the vendor shall furnish written confirmation of data residency before UAT.
2. No citizen personal data in sandboxes: development and test environments shall use synthetic or masked data only.
3. Any AI/conversational feature must not transmit personal data to services outside the approved platform boundary. Model prompts/logs containing personal data are subject to the same residency and retention rules.

## C4. Records retention
1. Vaccination records (the clinical event and certificate) are permanent health records: retain for the period specified by departmental medical-records rules (treat as **minimum 10 years** for design purposes; confirm exact schedule at design sign-off ⚠).
2. Appointment/booking records (including no-shows and cancellations): retain **3 years**, then eligible for archival/purge.
3. SMS/notification logs: **1 year**.
4. Audit trail of who viewed/modified citizen records: **3 years**, tamper-evident.

## C5. Access control & audit
1. Role-based access: facility staff see only their facility's citizens/appointments; district roles see district-wide aggregates and, where justified, record-level data with audit.
2. Every read of a citizen's record by staff must be attributable (user, timestamp). Bulk exports restricted to the District MIS role and logged.
3. Shared-device reality (one tablet, many staff): individual logins are still required; session timeout ≤ 15 minutes of inactivity on shared devices.

## C6. Accessibility
1. WCAG 2.1 Level AA conformance for all citizen-facing surfaces; GIGW guidance applies.
2. The complete booking, reschedule, cancel, and certificate-download journeys must be operable by keyboard alone and by screen reader, and usable at 200% zoom.
3. Color must never be the only carrier of meaning (e.g., slot availability states need text/labels, not just red/green).

## C7. Messaging (SMS) compliance
1. All SMS must be sent via a TRAI DLT-registered header and pre-registered templates. Template registration lead time is typically 1–3 weeks — **plan for this in the delivery schedule**.
2. Transactional/service-implicit category only; no promotional content.
3. Every template requiring citizen action must include the facility helpline number.
4. ⚠ Gateway vendor undecided as of the discovery workshop; the design must isolate the SMS provider behind a replaceable interface.

## C8. Certificates
1. Certificates must carry a unique, non-guessable certificate ID and the issuing facility.
2. Certificate data shown is the minimum in C1.3; no Aadhaar, no address.
3. Phase-2 verification lookup (third party checks a certificate ID's validity) should not be architecturally precluded.

## C9. Conversational assistant guardrails (if delivered)
1. Identity verification before any personal data is revealed or modified: booking reference, or registered mobile + DOB.
2. No medical advice under any circumstance: contraindication, symptom, dosage-suitability and similar questions must be redirected to helpline 104. This must be tested explicitly in UAT.
3. Every booking/reschedule/cancel action must be read back (facility, service, date, time) and explicitly confirmed by the citizen before execution.
4. Conversation transcripts follow the retention rule for notification logs (C4.3) unless they contain a transaction, in which case the transaction record follows C4.2.

*Synthetic document for POC purposes. It paraphrases the general spirit of Indian public-sector norms for realism but is not legal guidance.*
