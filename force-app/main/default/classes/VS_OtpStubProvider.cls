/**
 * VS_OtpStubProvider — the POC (no-live-SMS) implementation of VS_IOtpProvider (VS-13, EP-06, D-013).
 *
 * Issues a FIXED, well-known test code and performs NO external callout — there is no SMS gateway wired
 * in the POC (vendor undecided, C7.4). This lets QA and demos verify the full issue/verify flow without
 * a live provider. The real gateway (which generates a random code and sends a genuine SMS) drops in by
 * binding a different VS_IOtpProvider in VS_OtpService — this stub is never referenced by callers.
 *
 * TEST CODE (documented for QA): the fixed code is exposed as TEST_CODE below ("000000"). Because this
 * provider ALWAYS returns the same code, it must NEVER be bound in any real/production org — it exists
 * only to exercise the seam. VS_OtpService still stores only a HASH of this code, never the plaintext,
 * so the stored data shape is identical to production (D-013).
 *
 * Traceability: REQ-058/059, EP-06 / D-013, A-004, C7 (rules/10 §8).
 */
public with sharing class VS_OtpStubProvider implements VS_IOtpProvider {

    /**
     * The fixed POC test code. Documented for QA in the VS-13 review packet/summary. Deliberately an
     * obvious, non-random placeholder so it can never be mistaken for a real issued secret.
     */
    public static final String TEST_CODE = '000000';

    /**
     * POC stub: returns the fixed TEST_CODE and does NOT deliver a live SMS (no gateway in the POC).
     *
     * @param mobile the destination mobile (unused by the stub beyond satisfying the contract).
     * @return the fixed TEST_CODE for VS_OtpService to hash + store.
     */
    public String issue(String mobile) {
        // No callout, no plaintext persistence — the orchestrating service hashes the returned code.
        return TEST_CODE;
    }
}
