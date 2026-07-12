// TC-007: confirm whether ANY pattern/format validation exists on a free-text-capable
// VS_Patient__c field that would specifically block a government-ID-shaped numeric value.
//
// COMPLIANCE NOTE (rules/10 #1, Annexure C1.2): this file previously contained a literal
// 12-consecutive-digit placeholder value in VS_Full_Name__c. The project's own pretool guardrail
// correctly flagged that as Aadhaar-shaped and blocked a later write in this same session before it
// could land in a new file -- redacted here for consistency (rules/10 is absolute: no Aadhaar-shaped
// value belongs in any file, committed evidence included, even as an admittedly-fake test placeholder).
// The evidentiary question TC-007 asks ("is there field-level format validation on this object at
// all, or does data-minimization rely purely on field ABSENCE?") does not require an actual
// Aadhaar-shaped digit run to answer -- an arbitrary same-length ALPHANUMERIC junk string proves the
// identical thing: if a free-text field with NO regex/pattern validation rule accepts arbitrary
// 12-character junk, it would equally accept a 12-digit run, because there is no validation logic on
// this field capable of distinguishing the two. This is corroborated independently and more strongly
// by the structural finding that VS_Patient__c carries ZERO ValidationRule metadata at all (no
// force-app/main/default/objects/VS_Patient__c/validationRules directory exists) -- so no character
// class, digit count, or Aadhaar-pattern check exists anywhere on the object, full stop.
VS_Patient__c pat = new VS_Patient__c(
    VS_Full_Name__c = 'ZZQATESTZZQA',   // 12-char alphanumeric junk, deliberately NOT digit-only/Aadhaar-shaped
    VS_Date_Of_Birth__c = Date.newInstance(1990,1,1),
    VS_Mobile__c = '9000000099'
);
try {
    insert pat;
    System.debug('TC007:RESULT=INSERT_SUCCEEDED id=' + pat.Id + ' fullName=' + pat.VS_Full_Name__c);
    // cleanup immediately
    delete pat;
    System.debug('TC007:CLEANUP=DELETED');
} catch (Exception e) {
    System.debug('TC007:RESULT=INSERT_BLOCKED type=' + e.getTypeName() + ' msg=' + e.getMessage());
}
