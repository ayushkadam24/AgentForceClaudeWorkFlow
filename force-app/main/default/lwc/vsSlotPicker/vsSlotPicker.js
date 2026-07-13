import { LightningElement } from 'lwc';
import getFacilities from '@salesforce/apex/VS_BookingController.getFacilities';
import getServices from '@salesforce/apex/VS_BookingController.getServices';
import getAvailableSlots from '@salesforce/apex/VS_BookingController.getAvailableSlots';
import sendOtp from '@salesforce/apex/VS_BookingController.sendOtp';
import verifyOtp from '@salesforce/apex/VS_BookingController.verifyOtp';
import book from '@salesforce/apex/VS_BookingController.book';

// REQ-060: every citizen-facing string is a Custom Label (Marathi/Hindi is an additive translation later).
import VS_Book_Title from '@salesforce/label/c.VS_Book_Title';
import VS_Field_Facility from '@salesforce/label/c.VS_Field_Facility';
import VS_Field_Facility_Placeholder from '@salesforce/label/c.VS_Field_Facility_Placeholder';
import VS_Field_Service from '@salesforce/label/c.VS_Field_Service';
import VS_Field_Service_Placeholder from '@salesforce/label/c.VS_Field_Service_Placeholder';
import VS_Field_Date from '@salesforce/label/c.VS_Field_Date';
import VS_Btn_Find_Slots from '@salesforce/label/c.VS_Btn_Find_Slots';
import VS_Available_Times from '@salesforce/label/c.VS_Available_Times';
import VS_Slots_Left from '@salesforce/label/c.VS_Slots_Left';
import VS_No_Slots from '@salesforce/label/c.VS_No_Slots';
import VS_Field_Full_Name from '@salesforce/label/c.VS_Field_Full_Name';
import VS_Field_DOB from '@salesforce/label/c.VS_Field_DOB';
import VS_Field_Mobile from '@salesforce/label/c.VS_Field_Mobile';
import VS_Btn_Send_Otp from '@salesforce/label/c.VS_Btn_Send_Otp';
import VS_Field_Otp from '@salesforce/label/c.VS_Field_Otp';
import VS_Btn_Verify_Otp from '@salesforce/label/c.VS_Btn_Verify_Otp';
import VS_Mobile_Verified from '@salesforce/label/c.VS_Mobile_Verified';
import VS_Btn_Confirm_Booking from '@salesforce/label/c.VS_Btn_Confirm_Booking';
import VS_Booking_Confirmed from '@salesforce/label/c.VS_Booking_Confirmed';
import VS_Reference_Label from '@salesforce/label/c.VS_Reference_Label';
import VS_Keep_Reference from '@salesforce/label/c.VS_Keep_Reference';
import VS_Btn_Print from '@salesforce/label/c.VS_Btn_Print';
import VS_Btn_Book_Another from '@salesforce/label/c.VS_Btn_Book_Another';
import VS_Loading from '@salesforce/label/c.VS_Loading';
import VS_Choose_All from '@salesforce/label/c.VS_Choose_All';
import { friendlyError } from 'c/vsErrorLabels';

export default class VsSlotPicker extends LightningElement {
    label = {
        VS_Book_Title, VS_Field_Facility, VS_Field_Facility_Placeholder, VS_Field_Service,
        VS_Field_Service_Placeholder, VS_Field_Date, VS_Btn_Find_Slots, VS_Available_Times,
        VS_Slots_Left, VS_No_Slots, VS_Field_Full_Name, VS_Field_DOB, VS_Field_Mobile,
        VS_Btn_Send_Otp, VS_Field_Otp, VS_Btn_Verify_Otp, VS_Mobile_Verified,
        VS_Btn_Confirm_Booking, VS_Booking_Confirmed, VS_Reference_Label, VS_Keep_Reference,
        VS_Btn_Print, VS_Btn_Book_Another, VS_Loading, VS_Choose_All
    };

    facilityOptions = [];
    serviceOptions = [];
    slots = [];

    facilityId;
    serviceId;
    day;
    slotId;

    fullName;
    dob;
    mobile;
    otpCode;

    otpSent = false;
    otpVerified = false;
    bookingReference;
    searched = false;
    error;
    loading = false;

    connectedCallback() {
        this.loadReferenceData();
    }

    async loadReferenceData() {
        try {
            this.loading = true;
            const [facs, svcs] = await Promise.all([getFacilities(), getServices()]);
            this.facilityOptions = facs.map((f) => ({ label: f.Name, value: f.Id }));
            this.serviceOptions = svcs.map((s) => ({ label: s.Name, value: s.Id }));
        } catch (e) {
            this.showError(e);
        } finally {
            this.loading = false;
        }
    }

    handleFacility(e) { this.facilityId = e.detail.value; this.resetSlots(); }
    handleService(e) { this.serviceId = e.detail.value; this.resetSlots(); }
    handleDay(e) { this.day = e.detail.value; this.resetSlots(); }
    handleName(e) { this.fullName = e.detail.value; }
    handleDob(e) { this.dob = e.detail.value; }
    handleMobile(e) { this.mobile = e.detail.value; }
    handleOtpCode(e) { this.otpCode = e.detail.value; }
    handleSlot(e) { this.slotId = e.currentTarget.dataset.id; }

    resetSlots() {
        this.slots = [];
        this.slotId = undefined;
        this.searched = false;
    }

    get canSearch() { return !!(this.facilityId && this.serviceId && this.day); }
    get searchDisabled() { return this.loading || !this.canSearch; }
    get hasSlots() { return this.slots && this.slots.length > 0; }
    get noSlots() { return this.searched && !this.hasSlots; }
    get slotChosen() { return !!this.slotId; }

    async findSlots() {
        if (!this.canSearch) {
            this.error = this.label.VS_Choose_All;
            return;
        }
        try {
            this.loading = true;
            this.error = undefined;
            const rows = await getAvailableSlots({
                facilityId: this.facilityId, serviceId: this.serviceId, day: this.day
            });
            // remaining is shown as TEXT ("N places left"); an aria-label describes each option fully.
            this.slots = rows.map((s) => ({
                ...s,
                ariaLabel: `${s.label}, ${s.remaining} ${this.label.VS_Slots_Left}`,
                selected: false
            }));
            this.searched = true;
        } catch (e) {
            this.showError(e);
        } finally {
            this.loading = false;
        }
    }

    async requestOtp() {
        try {
            this.loading = true;
            this.error = undefined;
            await sendOtp({ mobile: this.mobile });
            this.otpSent = true;
        } catch (e) {
            this.showError(e);
        } finally {
            this.loading = false;
        }
    }

    async confirmOtp() {
        try {
            this.loading = true;
            this.error = undefined;
            this.otpVerified = await verifyOtp({ mobile: this.mobile, code: this.otpCode });
        } catch (e) {
            this.otpVerified = false;
            this.showError(e);
        } finally {
            this.loading = false;
        }
    }

    async confirmBooking() {
        try {
            this.loading = true;
            this.error = undefined;
            this.bookingReference = await book({
                fullName: this.fullName, dob: this.dob, mobile: this.mobile, slotId: this.slotId
            });
        } catch (e) {
            this.showError(e);
        } finally {
            this.loading = false;
        }
    }

    handlePrint() {
        // The confirmation section is print-friendly (@media print in the CSS hides everything else).
        window.print();
    }

    handleBookAnother() {
        this.bookingReference = undefined;
        this.facilityId = this.serviceId = this.day = undefined;
        this.fullName = this.dob = this.mobile = this.otpCode = undefined;
        this.otpSent = this.otpVerified = false;
        this.error = undefined;
        this.resetSlots();
    }

    showError(e) {
        this.error = friendlyError(e);
    }
}
