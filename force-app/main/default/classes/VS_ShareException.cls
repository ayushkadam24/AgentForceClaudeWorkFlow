/**
 * VS_ShareException — domain exception for the facility-scoped record-sharing subsystem
 * (VS-20, EP-08, REQ-053 / Annexure C5.1, design 6.2, D-031).
 *
 * Thrown by VS_FacilityShareService / VS_FacilityTriggerHandler when facility-group provisioning
 * or managed-sharing maintenance cannot proceed. The exception MESSAGE is a short, stable CODE
 * (never a raw user-facing string) so a caller / LWC / Flow can map it to friendly text — the same
 * convention as VS_BookingException, VS_PatientException and VS_OtpException (rules/20,
 * sf-apex-patterns "custom exceptions per domain with message CODES").
 *
 * Traceability: REQ-053 / EP-08 / D-031.
 */
public class VS_ShareException extends Exception {

    /** A required input (facility Id set, user Id set, etc.) was null/blank — the share or group
     *  operation cannot be computed without it. */
    public static final String INVALID_INPUT = 'INVALID_INPUT';

    /** Group provisioning produced no usable Group Id for a facility (insert returned no Id). Surfaced
     *  coded rather than swallowed so provisioning never silently leaves a facility ungrouped
     *  (rules/20, no empty catch). */
    public static final String GROUP_PROVISION_FAILED = 'GROUP_PROVISION_FAILED';
}
