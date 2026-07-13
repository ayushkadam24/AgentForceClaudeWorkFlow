/**
 * VS_OtpException — domain exception for the citizen OTP verification service (VS-13, EP-06).
 *
 * Thrown by VS_OtpService.issue()/verify() when a challenge cannot proceed. Unlike the pure
 * message-is-a-code convention of VS_BookingException, an OTP failure is shown DIRECTLY to a citizen
 * mid-journey (the ticket AC requires a "user-actionable message"), so this exception carries BOTH:
 *   - getMessage()  → a short, user-actionable sentence safe to surface in the UI, AND
 *   - code          → a stable machine code (the constants below) for programmatic branching/tests,
 *                     so callers/tests assert on VS_OtpException.TOO_MANY_ATTEMPTS, not on prose.
 * Construct via the of(code, userMessage) factory so the two never drift apart.
 *
 * Messages are intentionally generic (never echo the correct code, never say "wrong by one digit")
 * to avoid leaking anything about the code over the small 6-digit space (D-013).
 *
 * Traceability: REQ-058/059, EP-06 / D-013, A-004.
 */
public class VS_OtpException extends Exception {

    /** mobile and/or code was null/blank. */
    public static final String INVALID_INPUT = 'INVALID_INPUT';

    /** No active (issued, not-yet-expired) challenge exists for the supplied mobile. */
    public static final String NOT_FOUND = 'NOT_FOUND';

    /** The challenge's VS_Expiry__c has passed — the citizen must request a new code. */
    public static final String EXPIRED = 'EXPIRED';

    /** The supplied code did not match the stored hash; the attempt counter was incremented. */
    public static final String INVALID_CODE = 'INVALID_CODE';

    /** VS_Attempts__c has reached the configured maximum — the challenge is locked (D-013 brute-force guard). */
    public static final String TOO_MANY_ATTEMPTS = 'TOO_MANY_ATTEMPTS';

    /** The challenge was already verified; re-verifying is rejected so a proof cannot be replayed. */
    public static final String ALREADY_VERIFIED = 'ALREADY_VERIFIED';

    /** Stable machine code (one of the constants above) paired with the user-actionable getMessage(). */
    public String code;

    /**
     * Factory that keeps the machine code and the user-facing message in lock-step.
     *
     * @param code        one of the constants above.
     * @param userMessage a short sentence safe to show a citizen.
     * @return a VS_OtpException whose getMessage() is userMessage and whose code is code.
     */
    public static VS_OtpException of(String code, String userMessage) {
        VS_OtpException e = new VS_OtpException(userMessage);
        e.code = code;
        return e;
    }
}
