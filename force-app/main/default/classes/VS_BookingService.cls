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
    private static final String STATUS_CANCELLED = 'Cancelled';

    // Cut-off tunable DeveloperName in VS_Setting__mdt (D-010; value seeded to 4 hours).
    private static final String SETTING_CUTOFF_HOURS = 'CutOffHours';

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
     * Cancel a confirmed appointment, freeing its place so the same slot/session is bookable again the
     * SAME day (§4.5, REQ-003/015).
     *
     * === Cut-off (AC-1, REQ-003/015) ===
     * A cancellation attempted INSIDE the configured cut-off window of the slot start
     * (VS_Setting__mdt.CutOffHours = 4, D-010 — read from Custom Metadata via getInstance, NEVER
     * hardcoded) is REJECTED with the user-actionable VS_BookingException(WITHIN_CUTOFF) — never a raw
     * stack trace. If the config record is absent the change fails CLOSED (CUTOFF_CONFIG_MISSING).
     *
     * === The §3.4 lock discipline is REUSED verbatim (D-019/D-020) ===
     * Past the cut-off, this method takes the SAME single pessimistic lock as book():
     *     SELECT ... FROM VS_Session__c WHERE Id = :sessionId FOR UPDATE
     * on the appointment's PARENT session row — NO new lock target and NO second service. Under that one
     * lock it decrements the freed place (the slot's VS_Booked_Count__c for an online/staff/chat
     * booking, or the session's VS_Walk_In_Used_Count__c for a walk-in), flips a slot Full->Open when it
     * drops below capacity, and stamps VS_Status__c=Cancelled + VS_Cancelled_At__c — all in ONE
     * transaction. Counters and the status transition are persisted via FRESH minimal sObjects carrying
     * only the written fields (D-029): the loaded rows carry read-only $CustomMetadata formula fields
     * that this DE org's runtime FLS-on-system-mode-DML treats as inaccessible, and the service is the
     * sole trusted owner of these denormalized counters and of the appointment lifecycle transition
     * (VS_Status__c is service-owned per VS-08 field design; D-020). Record-level authorization is by
     * `with sharing` on the load. (FLS enforcement on the status write tracks the same A-018 runtime
     * permset gap as book()'s counter writes — see the review packet.)
     *
     * @param appointmentId the VS_Appointment__c to cancel.
     * @param cancelledById the acting user requesting the cancel — retained for attribution (the VS-08
     *                      schema has no dedicated actor field; audit is via LastModifiedById, A-017).
     * @throws VS_BookingException INVALID_INPUT, APPOINTMENT_NOT_FOUND, ALREADY_CANCELLED,
     *         SLOT_NOT_FOUND, WITHIN_CUTOFF, CUTOFF_CONFIG_MISSING.
     */
    public static void cancel(Id appointmentId, Id cancelledById) {
        if (appointmentId == null) {
            throw new VS_BookingException(VS_BookingException.INVALID_INPUT);
        }
        VS_Appointment__c appt = loadCancellableAppointment(appointmentId);
        enforceCutOff(appt.VS_Slot__r.VS_Slot_Start__c);

        // THE LOCK (reused from book, D-019/D-020): the appointment's PARENT session row FOR UPDATE.
        VS_Session__c lockedSession = lockSession(appt.VS_Session__c);
        releasePlaceAndCancel(appt, lockedSession);
    }

    /**
     * Move a confirmed appointment to a different slot: cancel-old + book-new ATOMICALLY (§4.5).
     *
     * === Cut-off ===
     * Reschedule is a change to an existing booking, so it is gated by the SAME cut-off as cancel():
     * an attempt inside the cut-off window of the CURRENT slot's start is rejected (WITHIN_CUTOFF,
     * REQ-015).
     *
     * === One lock target, deadlock-safe ordering (AC-3/AC-4, §4.5, D-019/D-020) ===
     * The destination slot may live in a DIFFERENT session from the source. To avoid a lock-ordering
     * deadlock between two concurrent reschedules crossing the same two sessions in opposite directions,
     * BOTH session rows are locked in a SINGLE `SELECT ... FOR UPDATE ... ORDER BY Id` — every
     * transaction therefore acquires them in the same (ascending-Id) global order. When the old and new
     * slots share ONE session the set collapses to a single row -> exactly ONE lock (AC-4). There is
     * still NO new lock target and NO second service: reschedule reuses the session-row lock and then
     * calls book() for the new place, which re-locks the (already-held, re-entrant) destination session.
     *
     * === Atomicity ===
     * A Database savepoint is taken before the old place is released; if the new booking throws (e.g.
     * SLOT_FULL), the whole reschedule is rolled back so the ORIGINAL appointment survives intact even
     * if a caller catches the exception. The coded exception is rethrown unchanged (no swallow, rules/20).
     *
     * @param appointmentId  the appointment being moved.
     * @param newSlotId      the destination VS_Slot__c.
     * @param rescheduledById the acting user (attribution, as in book()/cancel()).
     * @param channel        the channel for the NEW booking (Portal | Chat | Staff | WalkIn).
     * @return the Id of the newly-created VS_Appointment__c.
     * @throws VS_BookingException INVALID_INPUT, INVALID_CHANNEL, APPOINTMENT_NOT_FOUND,
     *         ALREADY_CANCELLED, SLOT_NOT_FOUND, WITHIN_CUTOFF, CUTOFF_CONFIG_MISSING, plus any code
     *         book() raises for the new place (SESSION_NOT_OPEN, SLOT_FULL, WALKIN_RESERVE_FULL, ...).
     */
    public static Id reschedule(Id appointmentId, Id newSlotId, Id rescheduledById, String channel) {
        if (appointmentId == null || newSlotId == null || String.isBlank(channel)) {
            throw new VS_BookingException(VS_BookingException.INVALID_INPUT);
        }
        Boolean isWalkIn = (channel == CHANNEL_WALK_IN);
        if (!isWalkIn && !SLOT_CHANNELS.contains(channel)) {
            throw new VS_BookingException(VS_BookingException.INVALID_CHANNEL);
        }

        // Load the appointment being moved and enforce the cut-off on its CURRENT slot start (REQ-015).
        VS_Appointment__c appt = loadCancellableAppointment(appointmentId);
        enforceCutOff(appt.VS_Slot__r.VS_Slot_Start__c);

        // Resolve the destination slot's owning session (no lock yet).
        List<VS_Slot__c> newSlotRows = [
            SELECT Id, VS_Session__c FROM VS_Slot__c WHERE Id = :newSlotId LIMIT 1
        ];
        if (newSlotRows.isEmpty()) {
            throw new VS_BookingException(VS_BookingException.SLOT_NOT_FOUND);
        }
        Id oldSessionId = appt.VS_Session__c;
        Id newSessionId = newSlotRows[0].VS_Session__c;

        // Acquire the lock(s): one FOR UPDATE ordered by Id -> single lock when same session (AC-4),
        // both rows in deadlock-safe order when cross-session (AC-3). D-019/D-020: one lock target.
        Map<Id, VS_Session__c> lockedById = lockSessionsOrdered(oldSessionId, newSessionId);

        // Atomic cancel-old + book-new under the held lock(s). Savepoint guarantees the original
        // appointment survives if the new booking is rejected, regardless of caller error handling.
        System.Savepoint sp = Database.setSavepoint();
        try {
            releasePlaceAndCancel(appt, lockedById.get(oldSessionId));
            return book(appt.VS_Patient__c, newSlotId, rescheduledById, channel);
        } catch (Exception ex) {
            Database.rollback(sp);
            throw ex;   // propagate the coded reason unchanged (rules/20 — no swallow)
        }
    }

    // ---- Cancel / reschedule internals (shared) ----------------------------------------------

    /**
     * Loads the appointment for a cancel/reschedule under `with sharing` (record-level authorization),
     * in SYSTEM mode: the query selects service-owned fields (VS_Status__c, VS_Slot__c) that a
     * least-privilege citizen permset does not grant FLS on, so a USER_MODE select would strip them.
     * Rejects a missing/invisible row (APPOINTMENT_NOT_FOUND) and an already-cancelled one
     * (ALREADY_CANCELLED) before any lock is taken.
     */
    private static VS_Appointment__c loadCancellableAppointment(Id appointmentId) {
        List<VS_Appointment__c> rows = [
            SELECT Id, VS_Status__c, VS_Booked_Channel__c, VS_Slot__c, VS_Session__c, VS_Patient__c,
                   VS_Slot__r.VS_Slot_Start__c
            FROM VS_Appointment__c
            WHERE Id = :appointmentId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new VS_BookingException(VS_BookingException.APPOINTMENT_NOT_FOUND);
        }
        VS_Appointment__c appt = rows[0];
        if (appt.VS_Status__c == STATUS_CANCELLED) {
            throw new VS_BookingException(VS_BookingException.ALREADY_CANCELLED);
        }
        return appt;
    }

    /**
     * The single §3.4 lock, reused: SELECT ... FOR UPDATE on ONE parent session row (D-019/D-020).
     */
    private static VS_Session__c lockSession(Id sessionId) {
        return [
            SELECT Id, VS_Walk_In_Reserve_Count__c, VS_Walk_In_Used_Count__c
            FROM VS_Session__c
            WHERE Id = :sessionId
            FOR UPDATE
        ];
    }

    /**
     * Locks the one or two session rows a reschedule touches in a SINGLE FOR UPDATE so every transaction
     * acquires them in the same global order (deadlock-safe, §4.5). The ordering is Id-ascending and
     * IMPLICIT: Apex forbids an explicit ORDER BY on a locking query ("Explicit ORDER BY not allowed when
     * locking rows (Id order is implied)") precisely because FOR UPDATE already locks rows in ascending-Id
     * order — which is exactly the global order this method relies on for deadlock safety. A same-session
     * reschedule collapses the Set to one Id -> exactly one row locked (AC-4).
     */
    private static Map<Id, VS_Session__c> lockSessionsOrdered(Id oldSessionId, Id newSessionId) {
        Set<Id> sessionIds = new Set<Id>{ oldSessionId, newSessionId };
        List<VS_Session__c> locked = [
            SELECT Id, VS_Walk_In_Reserve_Count__c, VS_Walk_In_Used_Count__c
            FROM VS_Session__c
            WHERE Id IN :sessionIds
            FOR UPDATE
        ];
        return new Map<Id, VS_Session__c>(locked);
    }

    /**
     * Frees the appointment's place and marks it Cancelled — MUST be called with the appointment's
     * session row already locked FOR UPDATE by the caller (cancel() / reschedule()). Decrements the
     * correct pool (slot bookable count vs session walk-in reserve, disjoint per D-020), flips a slot
     * Full->Open when it drops below capacity, and stamps the status/timestamp. Every write is a FRESH
     * minimal sObject carrying only the written non-formula fields (D-029) so the DE org's
     * FLS-on-system-mode-DML anomaly cannot trip on a carried formula field. Counter floors at 0
     * defensively — a decrement can never drive a pool negative.
     */
    private static void releasePlaceAndCancel(VS_Appointment__c appt, VS_Session__c lockedSession) {
        // ---- §3.4 re-check INSIDE the held session lock (B-1) ------------------------------------
        // The ALREADY_CANCELLED guard in loadCancellableAppointment() ran BEFORE this session row was
        // locked FOR UPDATE, so two transactions cancelling the SAME appointment (e.g. a portal
        // double-click) could BOTH pass it on the stale pre-lock read and each free the place — a
        // double-decrement that under-counts real bookings and admits a later booking past capacity
        // (overbooking-by-one, the exact failure §3.4 exists to prevent). Every cancel/reschedule path
        // holds this appointment's parent-session lock before mutating, so re-reading the status now
        // serializes the check: the second transaction blocks until the first commits, then sees
        // Cancelled here and is rejected — the place is freed EXACTLY once. This mirrors book()'s
        // re-read-all-counters-inside-the-lock discipline; no new lock target (D-019/D-020).
        VS_Appointment__c current = [
            SELECT Id, VS_Status__c FROM VS_Appointment__c WHERE Id = :appt.Id LIMIT 1
        ];
        if (current.VS_Status__c == STATUS_CANCELLED) {
            throw new VS_BookingException(VS_BookingException.ALREADY_CANCELLED);
        }

        Boolean isWalkIn = (appt.VS_Booked_Channel__c == CHANNEL_WALK_IN);
        if (isWalkIn) {
            // Walk-in returns its place to the SESSION reserve pool (never a slot's bookable count).
            Decimal used = zeroIfNull(lockedSession.VS_Walk_In_Used_Count__c);
            update new VS_Session__c(
                Id = lockedSession.Id,
                VS_Walk_In_Used_Count__c = Math.max(0, used - 1)
            );
        } else {
            // Online / staff / chat returns its place to the chosen slot's bookable ceiling. Re-read the
            // slot INSIDE the held session lock so the counter cannot be raced by a concurrent booking.
            VS_Slot__c slot = [
                SELECT Id, VS_Capacity__c, VS_Booked_Count__c, VS_Status__c
                FROM VS_Slot__c
                WHERE Id = :appt.VS_Slot__c
                LIMIT 1
            ];
            Decimal booked = Math.max(0, zeroIfNull(slot.VS_Booked_Count__c) - 1);
            String newStatus = slot.VS_Status__c;
            if (newStatus == SLOT_FULL && booked < zeroIfNull(slot.VS_Capacity__c)) {
                newStatus = SLOT_OPEN;   // the freed place makes the slot bookable again (§4.5)
            }
            update new VS_Slot__c(
                Id = slot.Id,
                VS_Booked_Count__c = booked,
                VS_Status__c = newStatus
            );
        }
        // Service-owned lifecycle transition (VS-08 field design; D-020): stamp Cancelled + timestamp
        // via a fresh minimal record, in the same locked transaction.
        update new VS_Appointment__c(
            Id = appt.Id,
            VS_Status__c = STATUS_CANCELLED,
            VS_Cancelled_At__c = Datetime.now()
        );
    }

    /**
     * Reject the change if `slotStart` falls inside the configured cut-off window (or has already
     * passed). The window length is read from VS_Setting__mdt.CutOffHours (D-010) via the cache-backed,
     * FLS-free getInstance(DeveloperName) — SOQL on a Custom Metadata Type is rejected on this org's
     * USER_MODE/runAs path (same rationale as VS_SlotGenerationService), and the value is NEVER
     * hardcoded (rules/20). Missing config fails CLOSED (CUTOFF_CONFIG_MISSING) rather than assuming a
     * default window on an integrity control.
     */
    private static void enforceCutOff(Datetime slotStart) {
        if (slotStart == null) {
            throw new VS_BookingException(VS_BookingException.SLOT_NOT_FOUND);
        }
        Decimal cutOffHours = getConfiguredCutOffHours();
        Integer cutOffMinutes = (cutOffHours * 60).intValue();   // supports fractional-hour tunables
        Datetime cutOffBoundary = slotStart.addMinutes(-cutOffMinutes);
        if (Datetime.now() >= cutOffBoundary) {
            throw new VS_BookingException(VS_BookingException.WITHIN_CUTOFF);
        }
    }

    /** Reads the cut-off window (hours) from Custom Metadata; fails closed if absent (never hardcoded). */
    private static Decimal getConfiguredCutOffHours() {
        VS_Setting__mdt setting = VS_Setting__mdt.getInstance(SETTING_CUTOFF_HOURS);
        if (setting == null || setting.VS_Value__c == null) {
            throw new VS_BookingException(VS_BookingException.CUTOFF_CONFIG_MISSING);
        }
        return setting.VS_Value__c;
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
