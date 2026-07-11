/**
 * VS_ReferenceGenerator — random, non-guessable booking-reference generator (VS-09, EP-03).
 *
 * Produces the value stored in VS_Appointment__c.VS_Booking_Reference__c (D-016): a random,
 * human-typeable, 8-character Crockford base32 code. Crockford base32 (RFC-free, Douglas Crockford)
 * deliberately EXCLUDES the letters I, L, O and U so the code cannot be visually confused with 1/0
 * or read as an offensive word — important because a citizen may read this reference aloud over a
 * feature phone or type it on a keypad for check-in/lookup (REQ-002/REQ-019).
 *
 * Non-guessability (REQ-030 pattern seam): each character is drawn from a cryptographically-strong
 * source (Crypto.getRandomInteger()), NOT a sequence/counter — a sequential or record-Id-derived
 * reference would be enumerable. The value is stored as a Unique External Id on VS_Appointment__c, so
 * the DATABASE is the final arbiter of uniqueness: a colliding reference is rejected outright at
 * insert (a DmlException the caller sees), rather than relying on a non-locked SOQL existence check
 * (same race-safe reasoning as D-017). At 32^8 (~1.1 trillion) combinations the collision
 * probability at pilot volumes is negligible; the DB constraint is the guarantee, not this math.
 *
 * Stateless utility — no SOQL/DML, safe to call inside the VS_Session__c FOR UPDATE lock.
 *
 * Traceability: REQ-002/019/030, EP-03 / D-016.
 */
public with sharing class VS_ReferenceGenerator {

    // Crockford base32 alphabet: digits 0-9 then A-Z minus I, L, O, U (32 symbols).
    private static final String CROCKFORD_ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    private static final Integer ALPHABET_SIZE = 32;

    // Matches VS_Appointment__c.VS_Booking_Reference__c Text(8) length (VS-08). Kept as a constant so
    // a length change is a single edit here, not a hunt through string literals.
    private static final Integer REFERENCE_LENGTH = 8;

    // TEST-ONLY seam (m-1). A test can pre-seed forced reference values so it can DELIBERATELY provoke
    // the Unique-External-Id collision path in VS_BookingService without relying on a 1-in-a-trillion
    // random clash. next() dequeues these ONLY under Test.isRunningTest(); production is always Crypto
    // random, so non-guessability (REQ-030) is never weakened outside a test context.
    @TestVisible
    private static List<String> forcedReferences = new List<String>();

    @TestVisible
    private static void forceNextReference(String reference) {
        forcedReferences.add(reference);
    }

    /**
     * @return a fresh random 8-char Crockford base32 booking reference (e.g. "7F3KQ9ZB").
     */
    public static String next() {
        if (Test.isRunningTest() && !forcedReferences.isEmpty()) {
            return forcedReferences.remove(0);   // test-seeded value, FIFO (m-1)
        }
        String reference = '';
        for (Integer i = 0; i < REFERENCE_LENGTH; i++) {
            // Crypto.getRandomInteger() can be negative; Math.mod can return a negative remainder for
            // a negative dividend, so normalise into [0, 31] before indexing the alphabet.
            Integer index = Math.mod(Crypto.getRandomInteger(), ALPHABET_SIZE);
            if (index < 0) {
                index += ALPHABET_SIZE;
            }
            reference += CROCKFORD_ALPHABET.substring(index, index + 1);
        }
        return reference;
    }
}
