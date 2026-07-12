/**
 * VS_BookingService — the RFP §3.4 slot-integrity booking service (VS-09, EP-03 — the crown jewel).
 *
 * SINGLE PUBLIC ENTRY POINT for creating a confirmed appointment of ANY channel — online (Portal),
 * chat, staff-console, and walk-in ALL call book(). There is deliberately NO separate walk-in
 * service and NO second lock target (D-019 SUPERSEDES D-015; D-020).
 *
 * === The §3.4 guarantee (no overbooking under concurrency) ===
 * Every booking for a session — of every channel — takes exactly ONE pessimistic lock:
 *
 *     SELECT ... FROM VS_Session__c WHERE Id = :sessionId FOR UPDATE
 *
 * on the PARENT VS_Session__c row. Two requests racing for the last place serialize on that one row:
 * the second blocks until the first commits, then re-reads the freshly-committed counters INSIDE its
 * own lock, sees the ceiling met, and is rejected. Because ALL channels take THAT SAME lock, there is
 * no online-vs-walk-in seam (the gap D-015's dual lock left open). Counters are read AND written only
 * inside this lock; they are never maintained by a roll-up or trigger, which do not serialize
 * (rules/20). See technical-design.md §4.
 *
 * === Two capacity pools, one lock (D-009 / D-020) ===
 *  - Online / Staff / Chat consume the CHOSEN SLOT's published ceiling
 *    (VS_Slot__c.VS_Capacity__c vs VS_Booked_Count__c, REQ-008); the slot flips to 'Full' at the
 *    ceiling.
 *  - Walk-in consumes the SESSION's reserve pool
 *    (VS_Session__c.VS_Walk_In_Reserve_Count__c vs VS_Walk_In_Used_Count__c, D-009) and never touches
 *    a slot's bookable count.
 * The two pools are disjoint but guarded by the SAME session lock, so neither can be overbooked and
 * neither channel can consume the other's capacity.
 *
 * === Security ===
 * `with sharing`; the appointment insert is executed WITH USER_MODE (`insert as user`) so CRUD/FLS is
 * enforced on the record the acting user creates (rules/20). The lock/counter reads and the counter
 * updates on VS_Session__c/VS_Slot__c run in system mode by design: those denormalized counters are
 * owned and maintained solely by this service under the lock (D-020) and a Portal citizen must NOT be
 * granted direct edit on capacity rows (least privilege). This split is called out in the review packet.
 *
 * Concurrency-test honesty: an Apex UNIT test runs in ONE transaction and cannot spawn truly parallel
 * transactions, so the unit tests prove the capacity-CEILING LOGIC (check-then-insert rejects the
 * over-limit booking); FOR UPDATE provides the runtime serialization, which is validated by a
 * parallel load test on the org. See VS_BookingServiceTest and 02-build/review-notes/VS-09-review.md.
 *
 * Traceability: REQ-002, REQ-006, REQ-007, REQ-008, REQ-062 (session-scoped) / EP-03 /
 *               D-019, D-020, D-016, D-009.
 */
public with sharing class VS_BookingService {

    // Channels that draw from a slot's bookable ceiling (as opposed to the session walk-in reserve).
    private static final String CHANNEL_WALK_IN = 'WalkIn';
    private static final Set<String> SLOT_CHANNELS = new Set<String>{ 'Portal', 'Chat', 'Staff' };

    // Appointment status values (match VS_Appointment__c.VS_Status__c picklist, VS-08).
    private static final String STATUS_BOOKED = 'Booked';
    private static final String STATUS_WALK_IN = 'WalkIn';

    // Session/slot lifecycle values (match the respective VS_Status__c picklists).
    private static final String SESSION_OPEN = 'Open';
    private static final String SLOT_OPEN = 'Open';
    private static final String SLOT_FULL = 'Full';

    /**
     * Book one appointment through the single §3.4 write path.
     *
     * === ONE-BOOKING-PER-TRANSACTION CONTRACT (m-2 — documentation only, no behavior change) ===
     * This method takes a PESSIMISTIC `SELECT ... FOR UPDATE` lock on the owning VS_Session__c row and
     * then performs UP TO 2 DML on VS_Appointment__c (the insert, plus one regenerate-and-retry insert
     * on the rare reference collision — see below) PLUS one counter `update`. It MUST be invoked
     * EXACTLY ONCE per transaction. Callers MUST NOT loop it over a collection: a loop would (a)
     * acquire and hold the session row lock repeatedly, serialising unrelated bookings and inviting
     * lock contention/timeouts, and (b) multiply DML/SOQL straight into governor limits. To place many
     * bookings, FAN OUT one booking per transaction (e.g. a Queueable/Batch that processes ONE record
     * each), so every booking takes its own fresh lock. This is a contract note to stop a future caller
     * from bulk-looping book() into a governor-limit or lock-contention failure.
     *
     * === REFERENCE-COLLISION HANDLING (m-1) ===
     * VS_Booking_Reference__c is a Unique External Id, so on the astronomically-rare 8-char Crockford
     * collision the appointment insert fails with a DUPLICATE_VALUE DmlException. book() catches ONLY
     * that duplicate-reference case, REGENERATES the reference (Crypto) and retries the insert ONCE
     * inside this SAME FOR UPDATE transaction (the session lock is never released). A second collision
     * throws VS_BookingException(REFERENCE_COLLISION). ANY OTHER DmlException propagates unchanged — no
     * silent swallow (rules/20).
     *
     * @param patientId  the VS_Patient__c being booked (found/created by VS_PatientService, VS-10).
     * @param slotId     the VS_Slot__c the citizen picked (required for every channel — a walk-in
     *                   references the arrival-time slot for reporting even though it draws the
     *                   session reserve, not the slot's bookable count).
     * @param bookedById the acting user placing the booking (staff/citizen). Retained per the design
     *                   contract for attribution; the current VS-08 schema has no dedicated "booked
     *                   by user" field, so audit attribution is via the record's CreatedById (see
     *                   assumption A-017 in the review packet).
     * @param channel    Portal | Chat | Staff | WalkIn.
     * @return the Id of the inserted VS_Appointment__c.
     * @throws VS_BookingException with a coded reason: INVALID_INPUT, INVALID_CHANNEL, SLOT_NOT_FOUND,
     *         SESSION_NOT_OPEN, SLOT_FULL, WALKIN_RESERVE_FULL, REFERENCE_COLLISION.
     */
    public static Id book(Id patientId, Id slotId, Id bookedById, String channel) {
        // ---- Input validation (before we take any lock) -----------------------------------------
        if (patientId == null || slotId == null || String.isBlank(channel)) {
            throw new VS_BookingException(VS_BookingException.INVALID_INPUT);
        }
        Boolean isWalkIn = (channel == CHANNEL_WALK_IN);
        if (!isWalkIn && !SLOT_CHANNELS.contains(channel)) {
            throw new VS_BookingException(VS_BookingException.INVALID_CHANNEL);
        }

        // ---- 1. Resolve the owning session for the chosen slot (no lock yet) ---------------------
        List<VS_Slot__c> slotLookup = [
            SELECT Id, VS_Session__c FROM VS_Slot__c WHERE Id = :slotId LIMIT 1
        ];
        if (slotLookup.isEmpty()) {
            throw new VS_BookingException(VS_BookingException.SLOT_NOT_FOUND);
        }
        Id sessionId = slotLookup[0].VS_Session__c;

        // ---- 2. THE LOCK: SELECT ... FOR UPDATE on the parent VS_Session__c row -------------------
        //     Every booking for this session — online, staff, chat, walk-in — serializes HERE until
        //     this transaction commits or rolls back. This is the one and only lock (D-019/D-020).
        VS_Session__c session = [
            SELECT Id, VS_Status__c, VS_Facility__c, VS_Service__c,
                   VS_Walk_In_Reserve_Count__c, VS_Walk_In_Used_Count__c
            FROM VS_Session__c
            WHERE Id = :sessionId
            FOR UPDATE
        ];
        if (session.VS_Status__c != SESSION_OPEN) {
            throw new VS_BookingException(VS_BookingException.SESSION_NOT_OPEN);
        }

        // ---- 3. Re-read the target slot INSIDE the session lock -----------------------------------
        //     Because every booking holds this same session lock, no other booking can interleave, so
        //     the slot counters read here cannot be raced by a concurrent transaction.
        VS_Slot__c slot = [
            SELECT Id, VS_Capacity__c, VS_Booked_Count__c, VS_Status__c
            FROM VS_Slot__c
            WHERE Id = :slotId
            LIMIT 1
        ];

        // ---- 4. Capacity check + counter mutation, per channel, still under the lock --------------
        Boolean updateSession = false;
        Boolean updateSlot = false;
        if (isWalkIn) {
            // Walk-in draws the SESSION reserve pool (D-009) — never the slot's bookable count.
            Decimal reserve = zeroIfNull(session.VS_Walk_In_Reserve_Count__c);
            Decimal used = zeroIfNull(session.VS_Walk_In_Used_Count__c);
            if (used >= reserve) {
                throw new VS_BookingException(VS_BookingException.WALKIN_RESERVE_FULL);
            }
            session.VS_Walk_In_Used_Count__c = used + 1;
            updateSession = true;
        } else {
            // Online / staff / chat draw the chosen slot's published bookable ceiling (REQ-008).
            Decimal capacity = zeroIfNull(slot.VS_Capacity__c);
            Decimal booked = zeroIfNull(slot.VS_Booked_Count__c);
            if (slot.VS_Status__c != SLOT_OPEN || booked >= capacity) {
                throw new VS_BookingException(VS_BookingException.SLOT_FULL);
            }
            slot.VS_Booked_Count__c = booked + 1;
            if (slot.VS_Booked_Count__c >= capacity) {
                slot.VS_Status__c = SLOT_FULL;
            }
            updateSlot = true;
        }

        // ---- 5. Insert the appointment (WITH USER_MODE) then persist the counter, in this same tx --
        VS_Appointment__c appt = new VS_Appointment__c(
            VS_Patient__c = patientId,
            VS_Slot__c = slotId,
            VS_Session__c = sessionId,
            VS_Facility__c = session.VS_Facility__c,   // denormalized for sharing/reporting (§2.4)
            VS_Service__c = session.VS_Service__c,      // denormalized for sharing/reporting (§2.4)
            VS_Booking_Reference__c = VS_ReferenceGenerator.next(),  // random, non-guessable (D-016)
            VS_Booked_Channel__c = channel,
            VS_Status__c = isWalkIn ? STATUS_WALK_IN : STATUS_BOOKED
        );
        // Insert the appointment. On the rare Unique-External-Id collision this regenerates the
        // reference and retries ONCE inside this same lock (m-1); any other DML error propagates.
        insertAppointmentWithReferenceRetry(appt);

        // Counter maintenance runs in system mode by design (D-020): the service is the single trusted
        // owner of these denormalized counters and the capacity rows are not user-editable.
        //
        // D-029 ROBUSTNESS: persist the counter(s) via a FRESH minimal sObject carrying ONLY the Id +
        // the field(s) this method actually WROTE — NOT the record loaded by the FOR UPDATE query. The
        // loaded `session`/`slot` sObjects carry read-only $CustomMetadata FORMULA fields
        // (VS_Session__c.VS_Walk_In_Reserve_Count__c) that this DE org's anomalous runtime
        // FLS-on-system-mode-DML (D-028 at runtime) treats as inaccessible, so `update session;` failed
        // with "fields being inaccessible". The value carried is the one ALREADY computed UNDER the lock
        // (used+1 / booked+1 / the Open|Full status decided above) — NO re-query, NO recompute, so the
        // FOR UPDATE serialization and the single write path are untouched (D-019/D-020).
        if (updateSession) {
            update new VS_Session__c(
                Id = session.Id,
                VS_Walk_In_Used_Count__c = session.VS_Walk_In_Used_Count__c
            );
        } else if (updateSlot) {
            update new VS_Slot__c(
                Id = slot.Id,
                VS_Booked_Count__c = slot.VS_Booked_Count__c,
                VS_Status__c = slot.VS_Status__c
            );
        }

        return appt.Id;
    }

    /**
     * Insert the appointment, handling the rare booking-reference collision (m-1).
     *
     * VS_Booking_Reference__c is a Unique External Id: on the astronomically-rare 8-char Crockford
     * collision the insert throws a DUPLICATE_VALUE DmlException. We REGENERATE the reference and retry
     * the insert exactly ONCE, still inside the caller's FOR UPDATE transaction (the session lock is
     * NOT released). A second collision throws the coded VS_BookingException(REFERENCE_COLLISION).
     * Every OTHER DmlException is rethrown unchanged — only the duplicate-reference case retries, so no
     * unrelated failure is ever swallowed (rules/20).
     */
    private static void insertAppointmentWithReferenceRetry(VS_Appointment__c appt) {
        try {
            insert as user appt;   // CRUD/FLS enforced on the user's own record (rules/20)
        } catch (DmlException firstEx) {
            if (!isDuplicateReferenceError(firstEx)) {
                throw firstEx;     // not a reference collision -> propagate untouched (no swallow)
            }
            // Rare Crockford collision: fresh non-guessable reference (Crypto), retry ONCE in-lock.
            appt.VS_Booking_Reference__c = VS_ReferenceGenerator.next();
            try {
                insert as user appt;
            } catch (DmlException retryEx) {
                if (isDuplicateReferenceError(retryEx)) {
                    throw new VS_BookingException(VS_BookingException.REFERENCE_COLLISION);
                }
                throw retryEx;     // a DIFFERENT DML failure on retry -> propagate untouched
            }
        }
    }

    /**
     * True only when the DmlException is a DUPLICATE_VALUE on the appointment insert — which can ONLY be
     * the VS_Booking_Reference__c unique External Id, the sole unique field this service sets on
     * VS_Appointment__c. Detection is by STATUS CODE, not by reading the conflicting record's field
     * names/message: the colliding record (e.g. another facility's appointment) can be FLS-/sharing-
     * masked from the acting user, so requiring field visibility would silently break the
     * retry-then-REFERENCE_COLLISION contract for real least-privilege users. The status code is precise
     * here and needs no record visibility. Any NON-DUPLICATE_VALUE DmlException returns false and is
     * rethrown untouched by the caller (no swallow, rules/20).
     */
    private static Boolean isDuplicateReferenceError(DmlException e) {
        for (Integer i = 0; i < e.getNumDml(); i++) {
            if (e.getDmlType(i) == StatusCode.DUPLICATE_VALUE) {
                return true;
            }
        }
        return false;
    }

    private static Decimal zeroIfNull(Decimal value) {
        return value == null ? 0 : value;
    }
}
