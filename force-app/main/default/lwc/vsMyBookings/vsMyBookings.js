import { LightningElement } from 'lwc';
import sendOtp from '@salesforce/apex/VS_BookingController.sendOtp';
import verifyOtp from '@salesforce/apex/VS_BookingController.verifyOtp';
import findMyAppointments from '@salesforce/apex/VS_BookingController.findMyAppointments';
import cancelMyAppointment from '@salesforce/apex/VS_BookingController.cancelMyAppointment';
import rescheduleMyAppointment from '@salesforce/apex/VS_BookingController.rescheduleMyAppointment';
import getServices from '@salesforce/apex/VS_BookingController.getServices';
import getFacilities from '@salesforce/apex/VS_BookingController.getFacilities';
import getAvailableSlots from '@salesforce/apex/VS_BookingController.getAvailableSlots';
import { friendlyError, statusLabel } from 'c/vsErrorLabels';

// REQ-060: all citizen-facing copy comes from Custom Labels.
import VS_Manage_Title from '@salesforce/label/c.VS_Manage_Title';
import VS_Manage_Intro from '@salesforce/label/c.VS_Manage_Intro';
import VS_Field_Mobile from '@salesforce/label/c.VS_Field_Mobile';
import VS_Btn_Send_Otp from '@salesforce/label/c.VS_Btn_Send_Otp';
import VS_Field_Otp from '@salesforce/label/c.VS_Field_Otp';
import VS_Btn_Verify_Otp from '@salesforce/label/c.VS_Btn_Verify_Otp';
import VS_Mobile_Verified from '@salesforce/label/c.VS_Mobile_Verified';
import VS_Btn_View_Bookings from '@salesforce/label/c.VS_Btn_View_Bookings';
import VS_No_Bookings from '@salesforce/label/c.VS_No_Bookings';
import VS_Col_Reference from '@salesforce/label/c.VS_Col_Reference';
import VS_Col_Facility from '@salesforce/label/c.VS_Col_Facility';
import VS_Col_Service from '@salesforce/label/c.VS_Col_Service';
import VS_Col_When from '@salesforce/label/c.VS_Col_When';
import VS_Col_Status from '@salesforce/label/c.VS_Col_Status';
import VS_Btn_Cancel from '@salesforce/label/c.VS_Btn_Cancel';
import VS_Btn_Reschedule from '@salesforce/label/c.VS_Btn_Reschedule';
import VS_Cancel_Confirm from '@salesforce/label/c.VS_Cancel_Confirm';
import VS_Btn_Confirm_Cancel from '@salesforce/label/c.VS_Btn_Confirm_Cancel';
import VS_Btn_Keep from '@salesforce/label/c.VS_Btn_Keep';
import VS_Cancelled_Success from '@salesforce/label/c.VS_Cancelled_Success';
import VS_Reschedule_Pick from '@salesforce/label/c.VS_Reschedule_Pick';
import VS_Field_Facility from '@salesforce/label/c.VS_Field_Facility';
import VS_Field_Facility_Placeholder from '@salesforce/label/c.VS_Field_Facility_Placeholder';
import VS_Field_Service from '@salesforce/label/c.VS_Field_Service';
import VS_Field_Service_Placeholder from '@salesforce/label/c.VS_Field_Service_Placeholder';
import VS_Field_Date from '@salesforce/label/c.VS_Field_Date';
import VS_Btn_Find_Slots from '@salesforce/label/c.VS_Btn_Find_Slots';
import VS_Available_Times from '@salesforce/label/c.VS_Available_Times';
import VS_Slots_Left from '@salesforce/label/c.VS_Slots_Left';
import VS_No_Slots from '@salesforce/label/c.VS_No_Slots';
import VS_Btn_Confirm_Reschedule from '@salesforce/label/c.VS_Btn_Confirm_Reschedule';
import VS_Reschedule_Success from '@salesforce/label/c.VS_Reschedule_Success';
import VS_Reference_Label from '@salesforce/label/c.VS_Reference_Label';
import VS_Btn_Back from '@salesforce/label/c.VS_Btn_Back';
import VS_Loading from '@salesforce/label/c.VS_Loading';

export default class VsMyBookings extends LightningElement {
    label = {
        VS_Manage_Title, VS_Manage_Intro, VS_Field_Mobile, VS_Btn_Send_Otp, VS_Field_Otp,
        VS_Btn_Verify_Otp, VS_Mobile_Verified, VS_Btn_View_Bookings, VS_No_Bookings, VS_Col_Reference,
        VS_Col_Facility, VS_Col_Service, VS_Col_When, VS_Col_Status, VS_Btn_Cancel, VS_Btn_Reschedule,
        VS_Cancel_Confirm, VS_Btn_Confirm_Cancel, VS_Btn_Keep, VS_Cancelled_Success, VS_Reschedule_Pick,
        VS_Field_Facility, VS_Field_Facility_Placeholder, VS_Field_Service, VS_Field_Service_Placeholder,
        VS_Field_Date, VS_Btn_Find_Slots, VS_Available_Times, VS_Slots_Left, VS_No_Slots,
        VS_Btn_Confirm_Reschedule, VS_Reschedule_Success, VS_Reference_Label, VS_Btn_Back, VS_Loading
    };

    // step: 'auth' | 'list' | 'confirmCancel' | 'reschedule'
    step = 'auth';

    mobile;
    otpCode;
    otpSent = false;
    otpVerified = false;

    appointments = [];
    selected;              // the appointment row a cancel/reschedule is acting on

    // reschedule slot-selection state (reuses the availability Apex the slot picker uses)
    facilityOptions = [];
    serviceOptions = [];
    facilityId;
    serviceId;
    day;
    slots = [];
    searched = false;
    newSlotId;

    successMessage;
    newReference;
    error;
    loading = false;

    // ---- getters ----
    get isAuth() { return this.step === 'auth'; }
    get isList() { return this.step === 'list'; }
    get isConfirmCancel() { return this.step === 'confirmCancel'; }
    get isReschedule() { return this.step === 'reschedule'; }
    get hasAppointments() { return this.appointments && this.appointments.length > 0; }
    get noAppointments() { return this.otpVerified && !this.hasAppointments; }
    get sendOtpDisabled() { return this.loading || !this.mobile; }
    get canSearch() { return !!(this.facilityId && this.serviceId && this.day); }
    get searchDisabled() { return this.loading || !this.canSearch; }
    get hasSlots() { return this.slots && this.slots.length > 0; }
    get noSlots() { return this.searched && !this.hasSlots; }
    get confirmRescheduleDisabled() { return this.loading || !this.newSlotId; }

    // ---- auth / OTP ----
    handleMobile(e) { this.mobile = e.detail.value; }
    handleOtpCode(e) { this.otpCode = e.detail.value; }

    async requestOtp() {
        try {
            this.loading = true;
            this.error = undefined;
            await sendOtp({ mobile: this.mobile });
            this.otpSent = true;
        } catch (e) { this.showError(e); } finally { this.loading = false; }
    }

    async confirmOtp() {
        try {
            this.loading = true;
            this.error = undefined;
            this.otpVerified = await verifyOtp({ mobile: this.mobile, code: this.otpCode });
            if (this.otpVerified) {
                await this.loadAppointments();
                this.step = 'list';
            }
        } catch (e) { this.otpVerified = false; this.showError(e); } finally { this.loading = false; }
    }

    async loadAppointments() {
        const rows = await findMyAppointments({ mobile: this.mobile });
        this.appointments = rows.map((a) => ({
            id: a.id,
            reference: a.reference,
            facilityName: a.facilityName,
            serviceName: a.serviceName,
            slotStart: a.slotStart,
            statusText: statusLabel(a.status)
        }));
    }

    // ---- cancel ----
    startCancel(e) {
        this.selected = this.findRow(e.currentTarget.dataset.id);
        this.error = undefined;
        this.step = 'confirmCancel';
    }
    keepAppointment() { this.selected = undefined; this.step = 'list'; }

    async confirmCancel() {
        try {
            this.loading = true;
            this.error = undefined;
            await cancelMyAppointment({ appointmentId: this.selected.id, mobile: this.mobile });
            this.successMessage = this.label.VS_Cancelled_Success;
            this.newReference = undefined;
            await this.reVerifyAndReload();
        } catch (e) { this.showError(e); } finally { this.loading = false; }
    }

    // ---- reschedule ----
    startReschedule(e) {
        this.selected = this.findRow(e.currentTarget.dataset.id);
        this.error = undefined;
        this.resetSlotSelection();
        this.step = 'reschedule';
        this.loadReferenceData();
    }

    async loadReferenceData() {
        try {
            this.loading = true;
            const [facs, svcs] = await Promise.all([getFacilities(), getServices()]);
            this.facilityOptions = facs.map((f) => ({ label: f.Name, value: f.Id }));
            this.serviceOptions = svcs.map((s) => ({ label: s.Name, value: s.Id }));
        } catch (e) { this.showError(e); } finally { this.loading = false; }
    }

    handleFacility(e) { this.facilityId = e.detail.value; this.clearSlots(); }
    handleService(e) { this.serviceId = e.detail.value; this.clearSlots(); }
    handleDay(e) { this.day = e.detail.value; this.clearSlots(); }
    handleNewSlot(e) { this.newSlotId = e.currentTarget.dataset.id; }

    async findSlots() {
        try {
            this.loading = true;
            this.error = undefined;
            const rows = await getAvailableSlots({
                facilityId: this.facilityId, serviceId: this.serviceId, day: this.day
            });
            this.slots = rows.map((s) => ({
                ...s,
                ariaLabel: `${s.label}, ${s.remaining} ${this.label.VS_Slots_Left}`
            }));
            this.searched = true;
        } catch (e) { this.showError(e); } finally { this.loading = false; }
    }

    async confirmReschedule() {
        try {
            this.loading = true;
            this.error = undefined;
            this.newReference = await rescheduleMyAppointment({
                appointmentId: this.selected.id, newSlotId: this.newSlotId, mobile: this.mobile
            });
            this.successMessage = this.label.VS_Reschedule_Success;
            await this.reVerifyAndReload();
        } catch (e) { this.showError(e); } finally { this.loading = false; }
    }

    // A cancel/reschedule consumes the OTP challenge (replay guard), so re-issue+verify to refresh the
    // list. The stub OTP verifies with a fixed code; a live provider would prompt the citizen again.
    async reVerifyAndReload() {
        await sendOtp({ mobile: this.mobile });
        await verifyOtp({ mobile: this.mobile, code: this.otpCode });
        await this.loadAppointments();
        this.selected = undefined;
        this.step = 'list';
    }

    backToList() {
        this.selected = undefined;
        this.error = undefined;
        this.step = 'list';
    }

    // ---- helpers ----
    findRow(id) { return this.appointments.find((a) => a.id === id); }
    resetSlotSelection() {
        this.facilityId = this.serviceId = this.day = this.newSlotId = undefined;
        this.clearSlots();
    }
    clearSlots() { this.slots = []; this.newSlotId = undefined; this.searched = false; }
    showError(e) { this.error = friendlyError(e); }
}
