/**
 * vsErrorLabels — shared helpers to map the booking service's stable coded reasons (SLOT_FULL,
 * WITHIN_CUTOFF, NOT_APPOINTMENT_OWNER, ...) to friendly, localizable Custom Labels (REQ-060). The
 * controller returns codes (never raw English or stack traces); the UI is the single place that turns a
 * code into human copy, so translation is additive. OTP errors already carry a user-actionable sentence
 * from VS_OtpService, so an unknown/non-coded message falls back to that sentence, then to a generic label.
 */
import VS_Err_Generic from '@salesforce/label/c.VS_Err_Generic';
import VS_Err_SLOT_FULL from '@salesforce/label/c.VS_Err_SLOT_FULL';
import VS_Err_WALKIN_RESERVE_FULL from '@salesforce/label/c.VS_Err_WALKIN_RESERVE_FULL';
import VS_Err_WITHIN_CUTOFF from '@salesforce/label/c.VS_Err_WITHIN_CUTOFF';
import VS_Err_ALREADY_CANCELLED from '@salesforce/label/c.VS_Err_ALREADY_CANCELLED';
import VS_Err_NOT_APPOINTMENT_OWNER from '@salesforce/label/c.VS_Err_NOT_APPOINTMENT_OWNER';
import VS_Err_APPOINTMENT_NOT_FOUND from '@salesforce/label/c.VS_Err_APPOINTMENT_NOT_FOUND';
import VS_Err_SESSION_NOT_OPEN from '@salesforce/label/c.VS_Err_SESSION_NOT_OPEN';
import VS_Status_Booked from '@salesforce/label/c.VS_Status_Booked';
import VS_Status_WalkIn from '@salesforce/label/c.VS_Status_WalkIn';

const ERROR_BY_CODE = {
    SLOT_FULL: VS_Err_SLOT_FULL,
    WALKIN_RESERVE_FULL: VS_Err_WALKIN_RESERVE_FULL,
    WITHIN_CUTOFF: VS_Err_WITHIN_CUTOFF,
    ALREADY_CANCELLED: VS_Err_ALREADY_CANCELLED,
    NOT_APPOINTMENT_OWNER: VS_Err_NOT_APPOINTMENT_OWNER,
    APPOINTMENT_NOT_FOUND: VS_Err_APPOINTMENT_NOT_FOUND,
    SESSION_NOT_OPEN: VS_Err_SESSION_NOT_OPEN
};

const STATUS_BY_CODE = {
    Booked: VS_Status_Booked,
    WalkIn: VS_Status_WalkIn
};

/** Pull the raw message a controller AuraHandledException surfaced to the client. */
function rawMessage(e) {
    if (e && e.body && e.body.message) {
        return e.body.message;
    }
    if (e && e.message) {
        return e.message;
    }
    return '';
}

/** Map a caught imperative-Apex error to a friendly, localized sentence — never a stack trace. */
export function friendlyError(e) {
    const msg = rawMessage(e);
    if (msg && ERROR_BY_CODE[msg]) {
        return ERROR_BY_CODE[msg];
    }
    // A coded reason we don't render specially, or an OTP sentence: prefer the sentence, else generic.
    return msg && msg.length > 0 ? msg : VS_Err_Generic;
}

/** A text status label (never colour alone — REQ-057). Falls back to the raw code if unmapped. */
export function statusLabel(code) {
    return STATUS_BY_CODE[code] || code;
}
