/**
 * VS_PatientService — patient identity / exact-match de-dup service (VS-10, EP-05, design §2.3/§5).
 *
 * SINGLE PUBLIC ENTRY POINT: findOrCreate(). Resolves an incoming person to exactly ONE
 * VS_Patient__c row using D-011's EXACT-match rule (full name + DOB + mobile = same patient; any one
 * field differing = a new, separate patient — possible duplicates are accepted, NEVER silently
 * merged, and there is deliberately NO fuzzy matching in the POC).
 *
 * === Race-safety (D-017, AC-3) ===
 * De-dup is enforced at the DATABASE by the Unique External Id VS_Patient__c.VS_Match_Key__c, NOT by
 * a prior SOQL existence check (which would race under concurrency — a TOCTOU window between the check
 * and the insert). findOrCreate() attempts the INSERT first; the unique constraint is the source of
 * truth. If the insert fails with DUPLICATE_VALUE (a row already owns that key — a pre-existing
 * patient OR a concurrent request that won the race), we re-query by the key and return the winner's
 * Id. Two racing calls for the same new key therefore converge on ONE row: the loser's insert is
 * rejected by the DB and falls into the same re-query path. (Honest note: an Apex UNIT test runs in a
 * single transaction and cannot spawn truly parallel transactions, so the tests prove the
 * catch-then-requery LOGIC; the constraint itself provides the runtime serialization.)
 *
 * === Consent (REQ-046 / DPDP) ===
 * Consent is an explicit opt-in: if consentGiven is not true, findOrCreate() THROWS
 * VS_PatientException.CONSENT_REQUIRED before any DML — a consent-less patient is never created. On a
 * successful CREATE the service stamps VS_Consent_Given__c = true and VS_Consent_Timestamp__c = now.
 * An already-existing patient is returned as-is (its earlier consent capture stands; this method does
 * not re-stamp or mutate an existing row — see the ONE-RECORD contract below).
 *
 * === Normalization (single source of truth) ===
 * The match key is built in exactly ONE place — buildMatchKey() — as
 *     normalize(fullName) | ISO-8601(DOB) | digits(mobile)
 * where normalize = trim + collapse internal whitespace + lower-case, DOB is rendered yyyy-MM-dd
 * (timezone-free), and mobile is reduced to digits only. This mirrors the intended VS_Match_Key__c
 * format documented on the field (VS-07) and is the authoritative algorithm (D-017 assigns ownership
 * of the exact algorithm to this ticket). The field is a case-insensitive unique External Id, so
 * lower-casing here is belt-and-braces, not the sole guard.
 *
 * === ONE-RECORD CONTRACT ===
 * findOrCreate() resolves ONE patient per call (registration is a single-person action). It performs
 * one insert and, only on a de-dup hit, one follow-up SOQL — it MUST NOT be looped over a collection
 * (that would multiply DML/SOQL into governor limits). To onboard many people, fan out one call per
 * transaction / record.
 *
 * === Security ===
 * `with sharing`; the patient insert runs WITH USER_MODE (`insert as user`) and the de-dup re-query
 * runs WITH USER_MODE, so CRUD/FLS is enforced on the acting user throughout (rules/20). No system-
 * mode DML, no hardcoded Ids, no empty catch (a non-duplicate DmlException is rethrown untouched).
 *
 * Traceability: REQ-004, REQ-046 / EP-05 / D-011, D-017, D-028.
 */
public with sharing class VS_PatientService {

    private static final String KEY_DELIMITER = '|';

    /**
     * Resolve an incoming person to exactly one VS_Patient__c, creating it if no exact match exists.
     *
     * @param patient      A VS_Patient__c carrying at minimum VS_Full_Name__c, VS_Date_Of_Birth__c and
     *                     VS_Mobile__c (the three match-key inputs); optional C1 attributes it carries
     *                     (email, gender, locality, pincode) are persisted only on a CREATE. Its
     *                     VS_Match_Key__c / consent fields are set by this method and need not be
     *                     pre-populated.
     * @param consentGiven MUST be true — DPDP explicit opt-in (REQ-046). Any other value throws
     *                     VS_PatientException.CONSENT_REQUIRED and creates nothing.
     * @return The Id of the existing (exact-match) or newly-created patient.
     * @throws VS_PatientException CONSENT_REQUIRED (consent not true), INVALID_INPUT (null patient or a
     *         blank/null match-key input), DEDUP_LOOKUP_FAILED (unreachable re-query miss).
     */
    public static Id findOrCreate(VS_Patient__c patient, Boolean consentGiven) {
        if (patient == null) {
            throw new VS_PatientException(VS_PatientException.INVALID_INPUT);
        }
        // AC-4: consent gate FIRST — never create (or even attempt to create) a consent-less patient.
        if (consentGiven != true) {
            throw new VS_PatientException(VS_PatientException.CONSENT_REQUIRED);
        }
        if (String.isBlank(patient.VS_Full_Name__c)
                || patient.VS_Date_Of_Birth__c == null
                || String.isBlank(patient.VS_Mobile__c)) {
            throw new VS_PatientException(VS_PatientException.INVALID_INPUT);
        }

        String matchKey = buildMatchKey(
            patient.VS_Full_Name__c, patient.VS_Date_Of_Birth__c, patient.VS_Mobile__c);
        patient.VS_Match_Key__c = matchKey;
        patient.VS_Consent_Given__c = true;                 // AC-4: stamped only on the create path
        patient.VS_Consent_Timestamp__c = System.now();

        try {
            insert as user patient;                          // DB unique constraint is the race guard
            return patient.Id;                               // AC-2: a genuinely new patient
        } catch (DmlException e) {
            if (!isDuplicateKeyError(e)) {
                throw e;                                     // unrelated failure -> propagate untouched
            }
            // AC-1 / AC-3: an existing row already owns this key (pre-existing or a race winner). The
            // DATABASE, not a prior SOQL check, told us so — resolve the winner's Id by re-query.
            return existingIdForKey(matchKey);
        }
    }

    /**
     * Build the canonical de-dup key. THE single place normalization lives (see class header).
     * Kept @TestVisible so tests can assert the exact algorithm and seed pre-existing rows with a
     * consistent key without duplicating the logic.
     */
    @TestVisible
    private static String buildMatchKey(String fullName, Date dob, String mobile) {
        return normalizeName(fullName) + KEY_DELIMITER + isoDate(dob) + KEY_DELIMITER + digitsOnly(mobile);
    }

    /** trim + collapse internal whitespace to a single space + lower-case. */
    private static String normalizeName(String raw) {
        return raw.trim().replaceAll('\\s+', ' ').toLowerCase();
    }

    /** Reduce a phone string to digits only (drops +, spaces, hyphens, parentheses). */
    private static String digitsOnly(String raw) {
        return raw.replaceAll('[^0-9]', '');
    }

    /** Render a Date as timezone-free ISO-8601 yyyy-MM-dd (never via Datetime.format, which is
     *  timezone-sensitive and could shift the calendar day). */
    private static String isoDate(Date d) {
        return String.valueOf(d.year()) + '-' + pad2(d.month()) + '-' + pad2(d.day());
    }

    private static String pad2(Integer v) {
        return v < 10 ? '0' + String.valueOf(v) : String.valueOf(v);
    }

    /** Re-query the row that owns a match key, WITH USER_MODE (FLS/CRUD enforced). */
    private static Id existingIdForKey(String matchKey) {
        List<VS_Patient__c> found = [
            SELECT Id FROM VS_Patient__c WHERE VS_Match_Key__c = :matchKey WITH USER_MODE LIMIT 1
        ];
        if (found.isEmpty()) {
            throw new VS_PatientException(VS_PatientException.DEDUP_LOOKUP_FAILED);
        }
        return found[0].Id;
    }

    /**
     * True only when the DmlException carries a DUPLICATE_VALUE status — which on VS_Patient__c can
     * ONLY be the VS_Match_Key__c unique External Id, the sole unique field this service sets.
     * Detection is by STATUS CODE (not by parsing the message or reading the conflicting record's
     * fields, which may be FLS-/sharing-masked from the acting user — same reasoning as
     * VS_BookingService.isDuplicateReferenceError). Any other DmlException returns false and is
     * rethrown untouched by the caller (no swallow, rules/20).
     */
    private static Boolean isDuplicateKeyError(DmlException e) {
        for (Integer i = 0; i < e.getNumDml(); i++) {
            if (e.getDmlType(i) == StatusCode.DUPLICATE_VALUE) {
                return true;
            }
        }
        return false;
    }
}
