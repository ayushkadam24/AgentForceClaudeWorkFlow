/**
 * VS_BookingController — the @AuraEnabled seam between the citizen booking UI (vsSlotPicker LWC, and
 * the Experience/LWR site) and the backend services. NOTHING in the services is @AuraEnabled; this is
 * the ONLY class the UI/site calls.
 *
 * === Sharing posture (important, guest-user aware) ===
 * `with sharing` at the class level. The read/availability methods intentionally run their SOQL in an
 * elevated `without sharing` inner helper (Reader) because facility / service / session / slot
 * availability is PUBLIC, browseable reference data — a citizen (incl. an unauthenticated guest whose
 * sharing is read-only) must be able to see open slots without a per-row guest sharing rule for every
 * session. No personal data is exposed by these reads.
 *
 * The write path (verifyOtp/book) delegates to the existing services unchanged:
 *  - VS_OtpService.verify (identity, Annexure C9) — hash compare, lockout.
 *  - VS_PatientService.findOrCreate (`insert as user`) — the acting user needs Create+FLS on
 *    VS_Patient__c (granted to the guest/community profile).
 *  - VS_BookingService.book (`with sharing`, §3.4 FOR UPDATE lock, D-019/D-020) — UNCHANGED.
 *
 * GUEST-BOOKING LIMITATION (documented, not worked around here): VS_BookingService is `with sharing`
 * and updates the Slot/Session capacity counters; a pure unauthenticated guest cannot hold write
 * sharing on those rows (Salesforce guest sharing is read-only), so book() succeeds for an
 * authenticated citizen/community user but NOT for a raw guest. The compliant resolution is OTP-verified
 * identity + an authenticated (or trusted post-verification) booking path — see the review packet.
 */
public with sharing class VS_BookingController {

    private static final String CHANNEL_PORTAL = 'Portal';

    @AuraEnabled(cacheable=true)
    public static List<VS_Facility__c> getFacilities() {
        return new Reader().facilities();
    }

    @AuraEnabled(cacheable=true)
    public static List<VS_Service__c> getServices() {
        return new Reader().services();
    }

    /**
     * Open, bookable slots for a facility+service on a given day, ascending by start time.
     * @return SlotView DTOs (id, human label, start, remaining capacity).
     */
    @AuraEnabled(cacheable=true)
    public static List<SlotView> getAvailableSlots(Id facilityId, Id serviceId, Date day) {
        if (facilityId == null || serviceId == null || day == null) {
            throw badRequest('Please choose a facility, service and date.');
        }
        List<SlotView> views = new List<SlotView>();
        for (VS_Slot__c s : new Reader().openSlots(facilityId, serviceId, day)) {
            views.add(new SlotView(s));
        }
        return views;
    }

    /** Issue an OTP challenge to the citizen's mobile (identity verification, Annexure C9). */
    @AuraEnabled
    public static void sendOtp(String mobile) {
        try {
            VS_OtpService.issue(mobile);
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    /** Verify the citizen-supplied OTP. Returns true on success; throws a friendly error otherwise. */
    @AuraEnabled
    public static Boolean verifyOtp(String mobile, String code) {
        try {
            return VS_OtpService.verify(mobile, code);
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    /**
     * Book one appointment for a (de-duplicated) citizen on the chosen slot.
     *
     * D-030: the actual booking runs in the `without sharing` Booker wrapper — the SOLE elevated caller
     * of VS_BookingService.book() — so a least-privilege citizen (who has NO edit on VS_Session__c /
     * VS_Slot__c, the D-020 red line) can still acquire the §3.4 FOR UPDATE lock and let the service
     * maintain its own counters. A SERVER-SIDE OTP gate (Annexure C9) inside that wrapper re-verifies the
     * mobile's challenge is verified + unexpired BEFORE any booking and consumes it (replay guard) — the
     * client's "verified" flag is never trusted. Returns the booking reference for the confirmation screen.
     */
    @AuraEnabled
    public static String book(String fullName, Date dob, String mobile, Id slotId) {
        if (String.isBlank(fullName) || dob == null || String.isBlank(mobile) || slotId == null) {
            throw badRequest('Missing booking details.');
        }
        try {
            return new Booker().bookVerified(fullName, dob, mobile, slotId);
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    // Test-only passthrough to the elevated Booker WITHOUT the toAura wrapper, so the A-018 proof test can
    // assert the RAW residual (the D-028 object-CRUD wall) after the `without sharing` elevation clears the
    // sharing/FLS barriers. Never called by the UI (book() is the sole @AuraEnabled entry). See D-030a.
    @TestVisible
    private static String bookElevatedRaw(String fullName, Date dob, String mobile, Id slotId) {
        return new Booker().bookVerified(fullName, dob, mobile, slotId);
    }

    // ======================================================================================
    //  CITIZEN SELF-SERVICE: view / cancel / reschedule my booking (VS-16, EP-06)
    //  Every method is OTP-gated (Annexure C9) AND IDOR-safe (ownership checked BEFORE any elevation).
    //  D-030 posture is preserved verbatim: the state-changing cancel/reschedule run through the SAME
    //  `without sharing` elevation as book(), so a least-privilege citizen (NO edit on Session/Slot, the
    //  D-020 red line) can acquire the §3.4 lock and let VS_BookingService maintain its own counters.
    // ======================================================================================

    /**
     * The caller's UPCOMING appointments (status Booked/WalkIn, slot start in the future), keyed strictly
     * to the OTP-verified mobile. VIEW-only: it requires a server-verified OTP for `mobile` but does NOT
     * consume the challenge (a citizen typically views before deciding to cancel/reschedule — the
     * challenge is consumed by the state-changing action, not by a read). The elevated read is filtered
     * to `mobile` and can NEVER return another mobile's rows.
     *
     * @param mobile the citizen's OTP-verified mobile.
     * @return the caller's own upcoming appointments as display DTOs (never another mobile's).
     */
    @AuraEnabled
    public static List<AppointmentView> findMyAppointments(String mobile) {
        if (String.isBlank(mobile)) {
            throw badRequest('Please verify your mobile number first.');
        }
        try {
            return new PortalManager().myUpcoming(mobile);
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    /**
     * Cancel one of the caller's OWN appointments. Order of guards (all BEFORE the elevated cancel):
     *   1. server-side C9 OTP gate for `mobile` (the client "verified" flag is never trusted);
     *   2. IDOR ownership check — the OTP-verified `mobile` MUST equal the appointment's owner mobile
     *      (VS_Patient__r.VS_Mobile__c or VS_Booked_By_Mobile__c), else NOT_APPOINTMENT_OWNER;
     *   3. VS_BookingService.cancel() via the elevated `without sharing` wrapper (cut-off + §3.4 lock);
     *   4. the OTP challenge is CONSUMED only after the cancel commits (replay guard on the ACTION).
     * WITHIN_CUTOFF and every other coded reason surface as friendly, localizable messages via the LWC.
     */
    @AuraEnabled
    public static void cancelMyAppointment(Id appointmentId, String mobile) {
        if (appointmentId == null || String.isBlank(mobile)) {
            throw badRequest('Missing the appointment or a verified mobile number.');
        }
        try {
            new PortalManager().cancelOwned(appointmentId, mobile);
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    /**
     * Reschedule one of the caller's OWN appointments onto a new slot. Same C9 OTP gate and IDOR
     * ownership check as cancelMyAppointment() run BEFORE elevating; the new booking's channel is
     * 'Portal'. Returns the new booking reference for the confirmation screen.
     */
    @AuraEnabled
    public static String rescheduleMyAppointment(Id appointmentId, Id newSlotId, String mobile) {
        if (appointmentId == null || newSlotId == null || String.isBlank(mobile)) {
            throw badRequest('Missing the appointment, the new slot, or a verified mobile number.');
        }
        try {
            return new PortalManager().rescheduleOwned(appointmentId, newSlotId, mobile);
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    // Test-only raw passthroughs (no toAura wrap) so the D-028/D-030a proof tests can assert the RAW
    // residual after the elevation clears sharing/FLS — mirrors bookElevatedRaw(). Never called by the UI.
    @TestVisible
    private static void cancelMyAppointmentElevatedRaw(Id appointmentId, String mobile) {
        new PortalManager().cancelOwned(appointmentId, mobile);
    }

    // ---- DTOs --------------------------------------------------------------------------------
    public class AppointmentView {
        @AuraEnabled public Id id;
        @AuraEnabled public String reference;
        @AuraEnabled public String facilityName;
        @AuraEnabled public String serviceName;
        @AuraEnabled public Datetime slotStart;
        @AuraEnabled public String status;   // stable code (Booked/WalkIn); the LWC maps it to a text label
        public AppointmentView(VS_Appointment__c a) {
            this.id = a.Id;
            this.reference = a.VS_Booking_Reference__c;
            this.facilityName = a.VS_Facility__r != null ? a.VS_Facility__r.Name : null;
            this.serviceName = a.VS_Service__r != null ? a.VS_Service__r.Name : null;
            this.slotStart = a.VS_Slot__r != null ? a.VS_Slot__r.VS_Slot_Start__c : null;
            this.status = a.VS_Status__c;
        }
    }

    public class SlotView {
        @AuraEnabled public Id id;
        @AuraEnabled public String label;
        @AuraEnabled public Datetime startTime;
        @AuraEnabled public Integer remaining;
        public SlotView(VS_Slot__c s) {
            this.id = s.Id;
            this.startTime = s.VS_Slot_Start__c;
            Decimal rem = (s.VS_Capacity__c == null ? 0 : s.VS_Capacity__c)
                        - (s.VS_Booked_Count__c == null ? 0 : s.VS_Booked_Count__c);
            this.remaining = (Integer) rem;
            this.label = s.VS_Slot_Start__c != null ? s.VS_Slot_Start__c.format('h:mm a') : s.Name;
        }
    }

    // ---- Elevated reads: PUBLIC availability data only, no personal fields -----------------------
    private without sharing class Reader {
        List<VS_Facility__c> facilities() {
            return [SELECT Id, Name, VS_Facility_Type__c, VS_Pincode__c, VS_Helpline_Number__c
                    FROM VS_Facility__c WHERE VS_Is_Active__c = true ORDER BY Name LIMIT 500];
        }
        List<VS_Service__c> services() {
            return [SELECT Id, Name, VS_Vaccine_Name__c
                    FROM VS_Service__c WHERE VS_Is_Active__c = true ORDER BY Name LIMIT 500];
        }
        List<VS_Slot__c> openSlots(Id facilityId, Id serviceId, Date day) {
            // NOTE: SOQL cannot compare two fields (VS_Capacity__c > VS_Booked_Count__c is illegal).
            // A slot at capacity is flipped to 'Full' by VS_BookingService under the lock, so
            // VS_Status__c = 'Open' already means "has remaining capacity". Remaining is computed in SlotView.
            return [SELECT Id, Name, VS_Slot_Start__c, VS_Capacity__c, VS_Booked_Count__c
                    FROM VS_Slot__c
                    WHERE VS_Status__c = 'Open'
                      AND VS_Session__r.VS_Facility__c = :facilityId
                      AND VS_Session__r.VS_Service__c = :serviceId
                      AND VS_Session__r.VS_Session_Date__c = :day
                      AND VS_Session__r.VS_Status__c = 'Open'
                    ORDER BY VS_Slot_Start__c LIMIT 200];
        }
        String referenceFor(Id apptId) {
            return [SELECT VS_Booking_Reference__c FROM VS_Appointment__c WHERE Id = :apptId LIMIT 1]
                     .VS_Booking_Reference__c;
        }
    }

    // ---- Elevated, OTP-gated booking (D-030) — the ONLY without-sharing caller of book() -------------
    // `without sharing` so a least-privilege citizen can acquire the §3.4 lock and let VS_BookingService
    // (inherited sharing) maintain its service-owned counters, WITHOUT holding edit on the capacity rows
    // (D-020). The appointment/patient inserts inside the services still run `insert as user`, so CRUD/FLS
    // on the citizen's OWN records is always enforced. See the class-level D-030 note.
    private without sharing class Booker {
        String bookVerified(String fullName, Date dob, String mobile, Id slotId) {
            OtpGate gate = new OtpGate();
            Id challengeId = gate.assertVerified(mobile);   // Annexure C9 — server-side identity gate
            VS_Patient__c person = new VS_Patient__c(
                VS_Full_Name__c = fullName, VS_Date_Of_Birth__c = dob, VS_Mobile__c = mobile);
            Id patientId = VS_PatientService.findOrCreate(person, true);
            Id apptId = VS_BookingService.book(patientId, slotId, UserInfo.getUserId(), CHANNEL_PORTAL);
            // OWNERSHIP FIELD (VS-16): stamp the OTP-verified booker mobile onto the new appointment via an
            // elevated post-book update — WITHOUT touching VS_BookingService — so the cancel/reschedule IDOR
            // check has a STABLE owner field even when the booker's mobile differs from the patient's own
            // (REQ-004, a relative booking for an elderly patient). System-mode DML: succeeds on a standard
            // org; on this DE org it tracks the SAME D-028 CRUD posture as book()'s counter writes (needs
            // FLS+edit — granted to the portal/harness permsets). The value is the already-verified mobile,
            // no re-query, so the §3.4 write path is untouched (D-020 red line held — no Session/Slot edit).
            update new VS_Appointment__c(Id = apptId, VS_Booked_By_Mobile__c = mobile);
            gate.consume(challengeId);   // replay guard: one verification -> one booking (consume on success)
            return [SELECT VS_Booking_Reference__c FROM VS_Appointment__c WHERE Id = :apptId LIMIT 1]
                     .VS_Booking_Reference__c;
        }
    }

    // ---- Elevated citizen self-service: view / cancel / reschedule my OWN booking (VS-16) -----------
    // `without sharing` so the citizen can reach the §3.4 lock (same as Booker); every method is OTP-gated
    // and IDOR-guarded (ownership checked BEFORE any elevated write). The elevated SOQL runs in system mode
    // so the citizen needs NO direct read on OTP/Appointment rows — but reads are STRICTLY filtered to the
    // OTP-verified mobile, never returning another citizen's data.
    private without sharing class PortalManager {

        private final Set<String> UPCOMING_STATUSES = new Set<String>{ 'Booked', 'WalkIn' };

        List<AppointmentView> myUpcoming(String mobile) {
            new OtpGate().assertVerified(mobile);   // C9 — VIEW does NOT consume (consume on the action)
            List<AppointmentView> views = new List<AppointmentView>();
            for (VS_Appointment__c a : [
                    SELECT Id, VS_Booking_Reference__c, VS_Status__c,
                           VS_Facility__r.Name, VS_Service__r.Name, VS_Slot__r.VS_Slot_Start__c
                    FROM VS_Appointment__c
                    WHERE VS_Status__c IN :UPCOMING_STATUSES
                      AND VS_Slot__r.VS_Slot_Start__c >= :System.now()
                      AND (VS_Patient__r.VS_Mobile__c = :mobile OR VS_Booked_By_Mobile__c = :mobile)
                    ORDER BY VS_Slot__r.VS_Slot_Start__c ASC
                    LIMIT 200]) {
                views.add(new AppointmentView(a));
            }
            return views;
        }

        void cancelOwned(Id appointmentId, String mobile) {
            OtpGate gate = new OtpGate();
            Id challengeId = gate.assertVerified(mobile);           // (a) C9 gate
            assertOwnership(appointmentId, mobile);                 // (b) IDOR guard BEFORE elevating
            VS_BookingService.cancel(appointmentId, UserInfo.getUserId());   // (c) cut-off + §3.4 lock
            gate.consume(challengeId);                              // (d) consume on the state change
        }

        String rescheduleOwned(Id appointmentId, Id newSlotId, String mobile) {
            OtpGate gate = new OtpGate();
            Id challengeId = gate.assertVerified(mobile);           // C9 gate
            assertOwnership(appointmentId, mobile);                 // SAME IDOR guard BEFORE elevating
            Id newApptId = VS_BookingService.reschedule(
                appointmentId, newSlotId, UserInfo.getUserId(), CHANNEL_PORTAL);
            // Carry ownership onto the moved booking (reschedule creates a NEW appointment via book(),
            // which does not set the booker mobile). Same D-028 posture as the book() stamp.
            update new VS_Appointment__c(Id = newApptId, VS_Booked_By_Mobile__c = mobile);
            gate.consume(challengeId);
            return [SELECT VS_Booking_Reference__c FROM VS_Appointment__c WHERE Id = :newApptId LIMIT 1]
                     .VS_Booking_Reference__c;
        }

        // IDOR guard: load the appointment ELEVATED (system mode, so a citizen with no row access can be
        // authorized here) and confirm the OTP-verified `mobile` owns it — matching either the patient's
        // own mobile OR the booker mobile. A mismatch throws NOT_APPOINTMENT_OWNER; a missing row throws
        // APPOINTMENT_NOT_FOUND. The check runs BEFORE any elevated write, so a citizen can NEVER change
        // another citizen's booking by Id (the D-030 residual MUST-FIX).
        void assertOwnership(Id appointmentId, String mobile) {
            List<VS_Appointment__c> rows = [
                SELECT Id, VS_Booked_By_Mobile__c, VS_Patient__r.VS_Mobile__c
                FROM VS_Appointment__c WHERE Id = :appointmentId LIMIT 1];
            if (rows.isEmpty()) {
                throw new VS_BookingException(VS_BookingException.APPOINTMENT_NOT_FOUND);
            }
            VS_Appointment__c a = rows[0];
            String patientMobile = (a.VS_Patient__r != null) ? a.VS_Patient__r.VS_Mobile__c : null;
            Boolean owns = mobile != null
                && (mobile == a.VS_Booked_By_Mobile__c || mobile == patientMobile);
            if (!owns) {
                throw new VS_BookingException(VS_BookingException.NOT_APPOINTMENT_OWNER);
            }
        }
    }

    // ---- Elevated, reusable Annexure C9 OTP gate (D-030) --------------------------------------------
    // `without sharing` + system-mode DML so the citizen needs NO read/edit on VS_OTP_Verification__c.
    // assertVerified() proves an issued, verified, unexpired challenge exists for the mobile WITHOUT
    // consuming it; consume() flips it un-verified so one verification authorizes exactly one action
    // (replay guard). Splitting assert from consume lets a VIEW verify-without-consume while a
    // state-changing action consumes only after it commits.
    private without sharing class OtpGate {
        Id assertVerified(String mobile) {
            List<VS_OTP_Verification__c> ch = [
                SELECT Id FROM VS_OTP_Verification__c
                WHERE VS_Mobile__c = :mobile AND VS_Verified__c = true AND VS_Expiry__c > :System.now()
                ORDER BY VS_Expiry__c DESC LIMIT 1];
            if (ch.isEmpty()) {
                throw VS_OtpException.of(VS_OtpException.INVALID_INPUT,
                    'Please verify your mobile number with an OTP first.');
            }
            return ch[0].Id;
        }
        void consume(Id challengeId) {
            update new VS_OTP_Verification__c(Id = challengeId, VS_Verified__c = false);
        }
    }

    // ---- Error helpers: never leak a raw stack trace to the UI -----------------------------------
    private static AuraHandledException badRequest(String msg) {
        AuraHandledException e = new AuraHandledException(msg);
        e.setMessage(msg);
        return e;
    }
    private static AuraHandledException toAura(Exception e) {
        String msg = (e instanceof VS_OtpException || e instanceof VS_BookingException
                      || e instanceof VS_PatientException)
                     ? e.getMessage()                                   // coded, user-actionable
                     : 'Something went wrong. Please try again.';        // hide internals
        AuraHandledException ax = new AuraHandledException(msg);
        ax.setMessage(msg);
        return ax;
    }
}
