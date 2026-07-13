import { LightningElement, track } from 'lwc';
import getFacilities from '@salesforce/apex/VS_BookingController.getFacilities';
import getServices from '@salesforce/apex/VS_BookingController.getServices';
import getAvailableSlots from '@salesforce/apex/VS_BookingController.getAvailableSlots';
import sendOtp from '@salesforce/apex/VS_BookingController.sendOtp';
import verifyOtp from '@salesforce/apex/VS_BookingController.verifyOtp';
import book from '@salesforce/apex/VS_BookingController.book';

export default class VsSlotPicker extends LightningElement {
    @track facilityOptions = [];
    @track serviceOptions = [];
    @track slots = [];

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

    handleFacility(e) { this.facilityId = e.detail.value; this.slots = []; this.slotId = undefined; }
    handleService(e) { this.serviceId = e.detail.value; this.slots = []; this.slotId = undefined; }
    handleDay(e) { this.day = e.detail.value; this.slots = []; this.slotId = undefined; }
    handleName(e) { this.fullName = e.detail.value; }
    handleDob(e) { this.dob = e.detail.value; }
    handleMobile(e) { this.mobile = e.detail.value; }
    handleOtpCode(e) { this.otpCode = e.detail.value; }
    handleSlot(e) { this.slotId = e.currentTarget.dataset.id; }

    get canSearch() { return this.facilityId && this.serviceId && this.day; }
    get hasSlots() { return this.slots && this.slots.length > 0; }
    get canSendOtp() { return this.slotId && this.fullName && this.dob && this.mobile; }
    get canBook() { return this.otpVerified && this.canSendOtp; }

    async findSlots() {
        try {
            this.loading = true;
            this.error = undefined;
            this.slots = await getAvailableSlots({
                facilityId: this.facilityId, serviceId: this.serviceId, day: this.day
            });
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

    showError(e) {
        this.error = (e && e.body && e.body.message) ? e.body.message
            : (e && e.message) ? e.message : 'Something went wrong. Please try again.';
    }
}
