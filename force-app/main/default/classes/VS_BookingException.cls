/**
 * VS_BookingException — domain exception for the slot-integrity booking service (VS-09, EP-03).
 *
 * Thrown by VS_BookingService.book() (and later VS_BookingService.cancel/reschedule, VS-11) when a
 * booking cannot proceed. The exception MESSAGE is a short, stable CODE (never a raw user-facing
 * string) so a caller / LWC / Flow can map it to friendly, localized text — same convention as
 * VS_SlotGenException (rules/20, sf-apex-patterns "custom exceptions per domain with message CODES").
 *
 * The coded reasons are exposed as constants so callers and tests reference
 * VS_BookingException.SLOT_FULL rather than a magic string. The two capacity-ceiling codes
 * (SLOT_FULL, WALKIN_RESERVE_FULL) are the §3.4 rejection reasons the crown-jewel guarantee produces
 * when a booking races for a place that is already exhausted (D-019/D-020).
 *
 * Traceability: REQ-002/006/007/008, EP-03 / D-016, D-019, D-020, D-009.
 */
public class VS_BookingException extends Exception {

    /** patientId, slotId, or channel was null/blank. */
    public static final String INVALID_INPUT = 'INVALID_INPUT';

    /** channel was not one of Portal | Chat | Staff | WalkIn. */
    public static final String INVALID_CHANNEL = 'INVALID_CHANNEL';

    /** No VS_Slot__c exists for the supplied slotId. */
    public static final String SLOT_NOT_FOUND = 'SLOT_NOT_FOUND';

    /** The owning VS_Session__c is not Open (Closed/Cancelled) — no booking of any channel allowed. */
    public static final String SESSION_NOT_OPEN = 'SESSION_NOT_OPEN';

    /** Online/staff: the chosen slot's published ceiling (VS_Capacity__c) is reached (REQ-008). */
    public static final String SLOT_FULL = 'SLOT_FULL';

    /** Walk-in: the session's walk-in reserve pool (VS_Walk_In_Reserve_Count__c) is reached (D-009). */
    public static final String WALKIN_RESERVE_FULL = 'WALKIN_RESERVE_FULL';

    /**
     * The random booking reference collided with an existing VS_Booking_Reference__c on BOTH the
     * initial insert AND the single regenerate-and-retry — astronomically unlikely at 32^8 (~1.1
     * trillion) combinations. book() surfaces this coded reason rather than leaking a raw DmlException
     * (m-1). A caller/LWC can safely present "please retry" — a fresh attempt gets a fresh reference.
     */
    public static final String REFERENCE_COLLISION = 'REFERENCE_COLLISION';
}
