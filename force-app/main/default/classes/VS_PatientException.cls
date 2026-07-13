/**
 * VS_PatientException — domain exception for the patient identity / de-dup service (VS-10, EP-05).
 *
 * Thrown by VS_PatientService.findOrCreate() when a patient cannot be resolved or created. The
 * exception MESSAGE is a short, stable CODE (never a raw user-facing string) so a caller / LWC / Flow
 * can map it to friendly, localized text — the same convention as VS_BookingException and
 * VS_SlotGenException (rules/20, sf-apex-patterns "custom exceptions per domain with message CODES").
 *
 * The coded reasons are exposed as constants so callers and tests reference
 * VS_PatientException.CONSENT_REQUIRED rather than a magic string.
 *
 * Traceability: REQ-004, REQ-046 / EP-05 / D-011, D-017.
 */
public class VS_PatientException extends Exception {

    /** Consent was not affirmatively passed as true — a consent-less patient must never be created
     *  (REQ-046 / DPDP explicit opt-in). findOrCreate() throws this BEFORE any DML. */
    public static final String CONSENT_REQUIRED = 'CONSENT_REQUIRED';

    /** The supplied patient was null, or one of the three match-key inputs (full name, DOB, mobile)
     *  was null/blank — the D-011/D-017 match key cannot be computed without all three. */
    public static final String INVALID_INPUT = 'INVALID_INPUT';

    /** An insert failed the VS_Match_Key__c unique constraint (a row with that key exists), yet the
     *  follow-up re-query returned nothing — should be unreachable; surfaced coded rather than
     *  swallowed so a caller never silently loses the record (rules/20, no empty catch). */
    public static final String DEDUP_LOOKUP_FAILED = 'DEDUP_LOOKUP_FAILED';
}
