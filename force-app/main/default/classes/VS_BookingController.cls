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

    // ---- DTO ---------------------------------------------------------------------------------
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
            requireVerifiedOtp(mobile);        // Annexure C9 — server-side identity gate + replay guard
            VS_Patient__c person = new VS_Patient__c(
                VS_Full_Name__c = fullName, VS_Date_Of_Birth__c = dob, VS_Mobile__c = mobile);
            Id patientId = VS_PatientService.findOrCreate(person, true);
            Id apptId = VS_BookingService.book(patientId, slotId, UserInfo.getUserId(), CHANNEL_PORTAL);
            return [SELECT VS_Booking_Reference__c FROM VS_Appointment__c WHERE Id = :apptId LIMIT 1]
                     .VS_Booking_Reference__c;
        }

        // The mobile MUST have a VS_OTP_Verification__c challenge that is Verified and not expired. This
        // SOQL runs in the elevated context, so the citizen needs NO read on OTP records. On success the
        // challenge is CONSUMED (flipped un-verified) so the same verification cannot book twice (replay).
        void requireVerifiedOtp(String mobile) {
            List<VS_OTP_Verification__c> ch = [
                SELECT Id FROM VS_OTP_Verification__c
                WHERE VS_Mobile__c = :mobile AND VS_Verified__c = true AND VS_Expiry__c > :System.now()
                ORDER BY VS_Expiry__c DESC LIMIT 1];
            if (ch.isEmpty()) {
                throw VS_OtpException.of(VS_OtpException.INVALID_INPUT,
                    'Please verify your mobile number with an OTP before booking.');
            }
            update new VS_OTP_Verification__c(Id = ch[0].Id, VS_Verified__c = false);
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
