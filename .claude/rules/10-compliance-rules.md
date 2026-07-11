# Compliance Rules — distilled from 00-inputs/compliance/annexure-c (binding)

1. NO AADHAAR: no field, variable, test data, log line, or free text may collect, store, or
   reference Aadhaar numbers. Applies to code, metadata, seed data, and Playwright test data.
2. Data minimization (C1): person data = full name, DOB, gender (optional), mobile, locality/pin,
   optional email. Nothing else. Health data = the vaccination event + appointment history only.
3. Synthetic data only in dev/test orgs (C3.2). Seed scripts generate fictional citizens.
4. Residency (C3.1): org region India (Hyderabad/Mumbai); no personal data leaves the platform
   boundary — relevant to any AI/chat feature and to logs.
5. Retention (C4): vaccination records ≥10 yrs (permanent), bookings 3 yrs, SMS logs 1 yr,
   audit trail 3 yrs tamper-evident. Design must make archival/purge possible per class.
6. Access (C5): facility staff see only their facility; every record read attributable;
   bulk export = District MIS role only, logged; shared-device session timeout ≤ 15 min.
7. Accessibility (C6): WCAG 2.1 AA on citizen journeys; keyboard-only + screen-reader operable;
   200% zoom usable; color never the only signal. These are testable requirements, not aspirations.
8. SMS (C7): DLT-registered templates only, transactional category, helpline number in every
   actionable template, provider isolated behind a replaceable interface (vendor undecided).
9. Chat assistant, if built (C9): identity verification before any personal data; zero medical
   advice — route to 104; read-back + explicit confirm before any transaction.
