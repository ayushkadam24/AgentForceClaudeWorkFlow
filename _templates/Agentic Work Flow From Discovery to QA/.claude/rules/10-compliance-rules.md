# Compliance Rules — TEMPLATE (binding once filled in)

> Distill the client's compliance annexures from `00-inputs/compliance/` into numbered, binding,
> TESTABLE rules before /kickoff. Keep the numbering style — BA cites these as C-refs, QA writes
> TCs against them. Delete this note when done. The structure below is a proven shape.

1. RESTRICTED PII (<RESTRICTED_PII>): no field, variable, test data, log line, or free text may
   collect, store, or reference it. Applies to code, metadata, seed data, and test data.
2. Data minimization (C1): person data = <list the exact allowed fields>. Nothing else.
   Domain data = <the business event + its history> only.
3. Synthetic data only in dev/test orgs (C3): seed scripts generate fictional records.
4. Residency (C3.1): org region <region>; no personal data leaves the platform boundary —
   relevant to any AI/chat feature and to logs.
5. Retention (C4): <record class> >= <years>; <class 2> <years>; audit trail <years>
   tamper-evident. Design must make archival/purge possible per class.
6. Access (C5): <role> sees only <scope>; every record read attributable; bulk export =
   <role> only, logged; shared-device session timeout <= <minutes> min.
7. Accessibility (C6): WCAG 2.1 AA on <user-facing journeys>; keyboard-only + screen-reader
   operable; 200% zoom usable; color never the only signal. Testable requirements, not aspirations.
8. Messaging (C7): <regulatory template regime, sender registration, mandatory content>;
   provider isolated behind a replaceable interface if the vendor is undecided.
9. AI/chat features, if built (C9): identity verification before any personal data; zero
   <regulated-advice-domain> advice — route to <official channel>; read-back + explicit confirm
   before any transaction.
