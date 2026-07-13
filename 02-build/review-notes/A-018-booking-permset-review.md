<!--
feature:         F-001 slot-booking-core
producing-agent: dev-mid
date:            2026-07-13
phase:           DONE (post-DONE launch-readiness item — phase NOT advanced by this ticket)
derives-from:    A-018 (production booking permission gap, .claude/memory/assumptions.md),
                 force-app/main/default/classes/VS_BookingService.cls (VS-09),
                 force-app/main/default/permissionsets/VS_Booking_Engine_Test_Context.permissionset-meta.xml,
                 rules/20-salesforce-standards.md, rules/10-compliance-rules.md (C1/C5)
downstream:      04-confirmations/ (any future drift note), a devops runbook item that ASSIGNS this
                 permset to real Facility Staff / District Admin users (out of scope here)
-->

# A-018 — VS_Booking_Capability Production Permission Set — Review Packet

> **UNVERIFIED — NO ORG CONNECTED.** No org is authenticated in this session and none was targeted.
> `sf project deploy start --dry-run` was NOT run and this packet makes no claim about deployability
> beyond "XML well-formed + `metadata-lint.js` clean" (rules/20 §Platform limits & deploy-readiness
> item 3). Live client sandbox/prod orgs are connected in this environment but were never touched —
> this permset was written to disk only.

## 1. What / why

`VS_BookingService.book()` (VS-09, the RFP §3.4 crown-jewel booking engine) does `insert as user`
(USER_MODE) on `VS_Appointment__c`. No production role permission set currently grants Create or
FLS on `VS_Appointment__c`/`VS_Patient__c` — the only permset that does is the TEST/CI harness
`VS_Booking_Engine_Test_Context`, which per its own description and A-018/A-019 must never be
assigned to a real user. Result: **no real user can call `book()` today.** This ticket closes that
gap with a new, standalone, composable permission set — **`VS_Booking_Capability`** — that grants
ONLY the booking capability at least privilege. It is designed to be assigned ALONGSIDE a role
permset (`VS_Facility_Staff`, `VS_District_Admin`, etc.) which continues to supply Session/Slot/
Facility/Service/Holiday visibility. This ticket does **not** edit any existing permission set and
does **not** perform any assignment — assignment is an explicit separate runbook step (see §6).

## 2. The exact grant (least-privilege, derived from reading `book()`)

### 2.1 Object permissions

| Object | Create | Read | Edit | Delete | View/Modify All |
|---|---|---|---|---|---|
| `VS_Appointment__c` | true | true | **false** | false | false |
| `VS_Patient__c` | true | true | **false** | false | false |

No `objectPermissions` block is added for `VS_Session__c`, `VS_Slot__c`, `VS_Facility__c`,
`VS_Service__c`, or `VS_Holiday__c` — those come from the role permset assigned alongside this one.
The counter-writing DML inside `book()` (`update session`/`update slot`) runs in **system mode**
(D-020) precisely so a booking user needs **no edit** on capacity rows; this permset grants none.

### 2.2 Field-level security

**`VS_Appointment__c` — fields `book()` actually sets** (from the `new VS_Appointment__c(...)`
constructor, `VS_BookingService.cls` lines 165–174):

| Field | `required` | `type` | Granted FLS? |
|---|---|---|---|
| `VS_Patient__c` | false | Lookup | **Yes** — readable/editable |
| `VS_Slot__c` | **true** | Lookup | **No** — required field, cannot carry FLS |
| `VS_Session__c` | false | Lookup | **Yes** — readable/editable |
| `VS_Facility__c` | false | Lookup | **Yes** — readable/editable |
| `VS_Service__c` | false | Lookup | **Yes** — readable/editable |
| `VS_Booking_Reference__c` | false | Text (ExternalId/Unique) | **Yes** — readable/editable |
| `VS_Booked_Channel__c` | false | Picklist | **Yes** — readable/editable |
| `VS_Status__c` | **true** | Picklist | **No** — required field, cannot carry FLS |

6 of 8 fields carry a `<fieldPermissions>` entry. `VS_Slot__c` and `VS_Status__c` are excluded
because they are `<required>true</required>` on the object — object-level Create already covers a
required field; the platform does not allow (and `metadata-lint.js` rule #4 would FAIL) a
`<fieldPermissions>` entry on a required or Master-Detail field.

**`VS_Patient__c` — C1 person fields + match key a booking find-or-create would set** (VS-10, not
yet built, but the field set is fixed by design §2.3/VS-07):

| Field | `required` | Granted FLS? |
|---|---|---|
| `VS_Full_Name__c` | **true** | **No** — required field |
| `VS_Date_Of_Birth__c` | **true** | **No** — required field |
| `VS_Mobile__c` | **true** | **No** — required field |
| `VS_Gender__c` | false | **Yes** — readable/editable |
| `VS_Locality__c` | false | **Yes** — readable/editable |
| `VS_Pincode__c` | false | **Yes** — readable/editable |
| `VS_Email__c` | false | **Yes** — readable/editable |
| `VS_Match_Key__c` | false (ExternalId/Unique) | **Yes** — readable/editable |

Same required-field exclusion rule applies: `VS_Full_Name__c`/`VS_Date_Of_Birth__c`/`VS_Mobile__c`
are all `required=true`, so Create alone covers them; no delete, no edit-after-create beyond what
find-or-create needs (create-only semantics — matches VS-10's upsert-by-external-id pattern, D-017).

**Full field grant list (11 `<fieldPermissions>` entries):**
`VS_Appointment__c.VS_Booked_Channel__c`, `VS_Appointment__c.VS_Booking_Reference__c`,
`VS_Appointment__c.VS_Facility__c`, `VS_Appointment__c.VS_Patient__c`,
`VS_Appointment__c.VS_Service__c`, `VS_Appointment__c.VS_Session__c`,
`VS_Patient__c.VS_Email__c`, `VS_Patient__c.VS_Gender__c`, `VS_Patient__c.VS_Locality__c`,
`VS_Patient__c.VS_Match_Key__c`, `VS_Patient__c.VS_Pincode__c` — all `readable=true editable=true`.

## 3. The Slot/Status delta — finding (A-021 logged)

The ticket asked me to resolve WHY the test harness (`VS_Booking_Engine_Test_Context`) grants
Appointment FLS on only 6 fields (missing `VS_Slot__c` and `VS_Status__c`, both of which `book()`
sets). **Finding: it is NOT an admin-profile-masking gap.** Both `VS_Slot__c.field-meta.xml` and
`VS_Status__c.field-meta.xml` have `<required>true</required>`. Salesforce does not allow
field-level security on a universally-required field (there's nothing to hide/restrict — the field
must always be settable when the object itself is creatable), and `scripts/metadata-lint.js` rule
#4 encodes exactly this: *"permset sets FLS on required field ... such fields can't have
field-level security."* The test harness's 6-field list is therefore the CORRECT/COMPLETE FLS set
for a real least-privilege user too — it happened to be right, not by admin-profile luck but
because it already respected the required-field exclusion. I applied the identical rule to
`VS_Patient__c` (excluding `VS_Full_Name__c`/`VS_Date_Of_Birth__c`/`VS_Mobile__c`, all required).
Logged as **A-021** in `.claude/memory/assumptions.md` (owner: architect/dev, re-check only if any
of these 5 fields' `required` flag ever changes).

## 4. Metadata-lint output (real, run this session)

```
$ node scripts/metadata-lint.js
== Metadata lint ==
  FAIL formula reads $CustomMetadata (checkOnly cannot validate w/ same-transaction CMDT — needs two-phase deploy or Apex read): force-app\main\default\objects\VS_Session__c\fields\VS_Walk_In_Reserve_Count__c.field-meta.xml
  FAIL formula reads $CustomMetadata (checkOnly cannot validate w/ same-transaction CMDT — needs two-phase deploy or Apex read): force-app\main\default\objects\VS_Setting__mdt\fields\VS_Value__c.field-meta.xml
== 2 metadata-limit issue(s) ==
```

Both FAILs are **pre-existing, unrelated to this ticket** — they fire on `VS_Session__c` and
`VS_Setting__mdt` fields from Sprint 1 (the known D-026/D-027 two-phase-deploy CMDT-formula
coupling, already accepted and already handled operationally by the two-phase deploy sequence used
for the real Sprint-1 deploy). Neither failing file was touched by this ticket. **Zero FAILs
reference `VS_Booking_Capability`** — rule #4 (FLS on required/MD field) and rule #5 (MD-detail
read without master) are both clean for the new permset (confirmed by inspecting the lint output
for any `VS_Booking_Capability` mention: none). Description length checked directly:
`len(<description>) = 244` chars, under the 255 PermissionSet cap.

## 5. Compliance / hygiene checklist

- `<license>Salesforce</license>` — present.
- `<hasActivationRequired>false</hasActivationRequired>` — present.
- `<label>VS Booking Capability</label>` — clear.
- Naming: `VS_Booking_Capability` — `VS_` prefix per rules/20.
- No Aadhaar anywhere (this permset touches no clinical/Aadhaar field; grep of `VS_Patient__c`
  fields directory confirms none exist on the object at all, per VS-07's structural grep).
- C1 data minimization respected: only the C1 person fields + match key get FLS, nothing beyond.
- Least privilege: no edit/delete on either object; no grant on capacity-bearing objects
  (`VS_Session__c`/`VS_Slot__c`) or their counters — a booking user cannot directly manipulate
  capacity, only `VS_BookingService.book()`'s system-mode path can (D-020).

## 6. Manual / setup steps

- **Pre-deploy:** none beyond the standard two-phase CMDT sequence already established for this org
  (D-026/D-027) — this permset has no CMDT/formula dependency itself.
- **Post-deploy (runbook, separate from this ticket):**
  1. Assign `VS_Booking_Capability` to real Facility Staff and District Admin users, ALONGSIDE their
     existing role permset (`VS_Facility_Staff`, `VS_District_Admin`) — never in place of it, since
     this permset carries none of the Session/Slot/Facility/Service visibility a booking flow needs.
  2. Confirm `VS_Booking_Engine_Test_Context` remains assigned ONLY to test/CI users and is never
     assigned to a real user (A-018/A-019 standing constraint).
  3. Re-run the FLS/CRUD live verification pattern QA already used for TC-010/TC-011 (Tooling API
     `ObjectPermissions`/`SetupEntityAccess` query) against a user holding `VS_Booking_Capability` +
     `VS_Facility_Staff` to confirm `book()` is actually callable end-to-end on the target org —
     this ticket only proves the metadata is structurally correct, not that it is deployed/live.
- **Manual-only:** none beyond the assignment step above (no Setup-UI-only metadata type here,
  unlike the CMDT-record quirk noted in `de-org-deploy-quirks`).

## 7. AC mapping (from the ticket instructions)

| Requirement | Met? | Where |
|---|---|---|
| Standalone permset, does not edit role permsets | Yes | new file only; no existing permset touched |
| Object perms: Appointment/Patient create+read, no edit/delete, no View/Modify All | Yes | §2.1 |
| No objectPermissions for Session/Slot/Facility/Service/Holiday | Yes | §2.1 (confirmed absent) |
| FLS on every field `book()` sets, excluding required/MD | Yes | §2.2 |
| Slot/Status delta explained | Yes | §3 |
| Patient FLS on C1 fields + Match_Key, required-excluded | Yes | §2.2 |
| description < 255 chars | Yes | §4 (244 chars) |
| metadata-lint run, output pasted, clean for this permset | Yes | §4 |
| license/hasActivationRequired/label present | Yes | §5 |
| No Aadhaar | Yes | §5 |
| UNVERIFIED — NO ORG CONNECTED banner | Yes | top of packet |
| Assignment note → runbook | Yes | §6 |
| Assumption logged | Yes (A-021) | §3, `.claude/memory/assumptions.md` |

## 8. Verification ladder reached

XML well-formed (yes, by construction/review) → `metadata-lint.js` clean **for this file**
(yes, §4) → `--dry-run` (**NOT RUN — no org connected**) → real deploy (**not attempted**) →
tests (n/a, declarative metadata only). This packet claims no rung above metadata-lint.

## 9. Deliverables

1. `force-app/main/default/permissionsets/VS_Booking_Capability.permissionset-meta.xml`
2. This packet: `02-build/review-notes/A-018-booking-permset-review.md`
3. `.claude/memory/assumptions.md` — A-021 appended
4. `.claude/logs/agent-runs.log` — one run line appended
