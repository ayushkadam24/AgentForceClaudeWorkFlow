/**
 * VS_IOtpProvider — the swappable OTP delivery/issue seam for citizen authentication (VS-13, EP-06).
 *
 * WHY AN INTERFACE (A-004, design §6.4 / D-013): the real SMS-OTP gateway vendor is undecided (C7.4).
 * By expressing "issue an OTP to this mobile" as an interface, the concrete gateway can be swapped in
 * later with ZERO change to VS_OtpService or any caller — exactly the vendor-isolation the compliance
 * rule requires (rules/10 §8, "provider isolated behind a replaceable interface"). The POC ships
 * VS_OtpStubProvider (a fixed, documented test code, no live SMS); production replaces only the
 * implementation bound in VS_OtpService.
 *
 * CONTRACT: issue() generates the one-time code for the given mobile, DELIVERS it to that mobile
 * (SMS in a real gateway; a no-op in the stub), and RETURNS the plaintext code so the orchestrating
 * service can HASH and store it. The plaintext is returned to the service transiently and is NEVER
 * persisted — VS_OtpService stores only a SHA-256 hash (D-013). No passwords, no Aadhaar.
 *
 * Traceability: REQ-058/059, EP-06 / D-013, A-004, C7 (rules/10 §8).
 */
public interface VS_IOtpProvider {

    /**
     * Generate and deliver a one-time code to the supplied mobile.
     *
     * @param mobile the destination mobile number (already validated by the caller/service).
     * @return the plaintext one-time code that was issued/delivered, for the service to hash + store.
     *         The implementation MUST NOT persist the plaintext anywhere.
     */
    String issue(String mobile);
}
