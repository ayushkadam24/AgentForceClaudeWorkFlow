/**
 * VS_OtpService — orchestrates citizen mobile-OTP verification for F-001 (VS-13, EP-06, design §6.4).
 *
 * RESPONSIBILITY: bind the (swappable, A-004) VS_IOtpProvider seam to the VS_OTP_Verification__c store.
 *   - issue(mobile)      : asks the provider for a code, stores ONLY the mobile + a SHA-256 HASH of the
 *                          code + an expiry (never plaintext, D-013), attempts = 0, verified = false.
 *   - verify(mobile,code): locates the active challenge, enforces the lockout + expiry, and compares
 *                          HASHES (never plaintext). After the configured maximum of FAILED attempts,
 *                          the next call is rejected with a user-actionable message (ticket AC).
 *
 * SECURITY (rules/20): `with sharing`; every SOQL/DML runs in USER_MODE (WITH USER_MODE / `as user`) so
 * CRUD/FLS is enforced for the running citizen context. Custom exception (VS_OtpException) with a
 * user-actionable message + machine code; no empty catch; no hardcoded IDs. Tunables (expiry window,
 * max attempts) come from VS_Setting__mdt via getInstance with safe fallbacks — never magic numbers.
 *
 * COMPLIANCE: the record holds no personal attribute beyond the mobile (design §2.5); no plaintext
 * code, no password, no Aadhaar anywhere (rules/10). The plaintext code exists only transiently in
 * memory between the provider and the hash.
 *
 * PROVIDER BINDING: the POC binds VS_OtpStubProvider (fixed test code, no live SMS). A real gateway
 * swaps in by changing the single `provider` binding — zero caller change (A-004).
 *
 * Traceability: REQ-058/059, EP-06 / D-013, A-004, C7 (rules/10 §8).
 */
public with sharing class VS_OtpService {

    // Swappable provider seam (A-004). @TestVisible so a test can inject a fake without a live gateway;
    // production keeps the stub until a real gateway is bound here.
    @TestVisible
    private static VS_IOtpProvider provider = new VS_OtpStubProvider();

    // Tunable fallbacks — used ONLY when the VS_Setting__mdt record is absent (getInstance returns null).
    // These are last-resort defaults, not the source of truth; the CMDT record is (rules/20).
    private static final Integer DEFAULT_EXPIRY_MINUTES = 10;
    private static final Integer DEFAULT_MAX_ATTEMPTS = 3;

    // Hash algorithm for the stored code digest (D-013). SHA-256 → 64 hex chars, fits VS_Code_Hash__c(128).
    private static final String HASH_ALGORITHM = 'SHA-256';

    /**
     * Issue a fresh OTP challenge for a mobile: the bound provider generates/delivers the code, and this
     * method persists ONLY the mobile, a SHA-256 hash of the code, and the expiry (never plaintext, D-013).
     *
     * @param mobile the destination mobile number; must be non-blank.
     * @return the Id of the newly created VS_OTP_Verification__c challenge row.
     * @throws VS_OtpException INVALID_INPUT if mobile is blank.
     */
    public static Id issue(String mobile) {
        if (String.isBlank(mobile)) {
            throw VS_OtpException.of(
                VS_OtpException.INVALID_INPUT,
                'Please enter a valid mobile number to receive your verification code.');
        }
        String plaintextCode = provider.issue(mobile);   // transient — hashed immediately below, never stored
        VS_OTP_Verification__c challenge = new VS_OTP_Verification__c(
            VS_Mobile__c = mobile,
            VS_Code_Hash__c = hashCode(mobile, plaintextCode),
            VS_Expiry__c = Datetime.now().addMinutes(getExpiryMinutes()),
            VS_Attempts__c = 0,
            VS_Verified__c = false
        );
        insert as user challenge;
        return challenge.Id;
    }

    /**
     * Verify a citizen-supplied code against the most recent active challenge for a mobile.
     *
     * Order of checks (each is terminal): input validity → challenge exists → already verified →
     * not expired → not locked out → hash match. A wrong code increments VS_Attempts__c; once attempts
     * reach the configured maximum, the NEXT call is rejected with the lockout message BEFORE any hash
     * comparison (D-013 brute-force guard; ticket AC "after 3 failed attempts a 4th is rejected").
     *
     * @param mobile the mobile the challenge was issued to; must be non-blank.
     * @param code   the code the citizen entered; must be non-blank.
     * @return true when the code matches and the challenge is marked verified.
     * @throws VS_OtpException with a user-actionable message + machine code on any failure path.
     */
    public static Boolean verify(String mobile, String code) {
        if (String.isBlank(mobile) || String.isBlank(code)) {
            throw VS_OtpException.of(
                VS_OtpException.INVALID_INPUT,
                'Please enter both your mobile number and the verification code.');
        }

        List<VS_OTP_Verification__c> rows = [
            SELECT Id, VS_Mobile__c, VS_Code_Hash__c, VS_Expiry__c, VS_Attempts__c, VS_Verified__c
            FROM VS_OTP_Verification__c
            WHERE VS_Mobile__c = :mobile
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw VS_OtpException.of(
                VS_OtpException.NOT_FOUND,
                'We could not find an active code for this number. Please request a new one.');
        }
        VS_OTP_Verification__c challenge = rows[0];

        if (challenge.VS_Verified__c == true) {
            throw VS_OtpException.of(
                VS_OtpException.ALREADY_VERIFIED,
                'This number is already verified. Please continue.');
        }
        if (challenge.VS_Expiry__c == null || challenge.VS_Expiry__c <= Datetime.now()) {
            throw VS_OtpException.of(
                VS_OtpException.EXPIRED,
                'Your verification code has expired. Please request a new one.');
        }

        Integer maxAttempts = getMaxAttempts();
        Integer attempts = (challenge.VS_Attempts__c == null) ? 0 : challenge.VS_Attempts__c.intValue();
        if (attempts >= maxAttempts) {
            throw VS_OtpException.of(
                VS_OtpException.TOO_MANY_ATTEMPTS,
                'Too many incorrect attempts. For your security this code is now locked — please request a new one.');
        }

        if (hashCode(mobile, code) == challenge.VS_Code_Hash__c) {
            challenge.VS_Verified__c = true;
            update as user challenge;
            return true;
        }

        // Wrong code: record the failed attempt so the lockout ceiling is enforced on the next call.
        challenge.VS_Attempts__c = attempts + 1;
        update as user challenge;
        throw VS_OtpException.of(
            VS_OtpException.INVALID_CODE,
            'That code is incorrect. Please check the code and try again.');
    }

    /**
     * One-way, salted SHA-256 digest of the code. Salting with the mobile means two citizens who happen
     * to hold the same code do not share a hash, blunting a precomputed-table attack over the small code
     * space (D-013). Returns lowercase hex (64 chars for SHA-256).
     */
    private static String hashCode(String mobile, String code) {
        Blob digest = Crypto.generateDigest(HASH_ALGORITHM, Blob.valueOf(mobile + ':' + code));
        return EncodingUtil.convertToHex(digest);
    }

    /** Configured OTP validity window in minutes (VS_Setting__mdt.OtpExpiryMinutes), else the fallback. */
    private static Integer getExpiryMinutes() {
        VS_Setting__mdt setting = VS_Setting__mdt.getInstance('OtpExpiryMinutes');
        if (setting != null && setting.VS_Value__c != null) {
            return setting.VS_Value__c.intValue();
        }
        return DEFAULT_EXPIRY_MINUTES;
    }

    /** Configured max failed attempts before lockout (VS_Setting__mdt.OtpMaxAttempts), else the fallback. */
    private static Integer getMaxAttempts() {
        VS_Setting__mdt setting = VS_Setting__mdt.getInstance('OtpMaxAttempts');
        if (setting != null && setting.VS_Value__c != null) {
            return setting.VS_Value__c.intValue();
        }
        return DEFAULT_MAX_ATTEMPTS;
    }
}
