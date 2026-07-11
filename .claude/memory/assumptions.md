# Assumptions Register (A-###)

Anything treated as true without client confirmation. Owner = who must verify.
| ID | Date | Raised by | Assumption | Impact if wrong | Owner | Status |
|---|---|---|---|---|---|---|
| A-001 | 2026-07-11 | human | 60/40 smartphone/feature-phone split (flagged ⚠ unverified in personas doc) | channel priorities shift toward SMS | BA → DHO | Open |
| A-002 | 2026-07-11 | ba-analyst | Vaccination is the pilot/primary scope; OPD appointment booking is a configurable service type deferred beyond F-001 (RFP scope is vaccination-centric but current-state §B describes OPD) | If OPD is in-scope now, slot model + effort estimates grow | DHO/Deshmukh (OQ-025) | Open |
| A-003 | 2026-07-11 | ba-analyst | All unresolved tunables (slot granularity, walk-in %, cut-off hours, reminder offsets, booking horizon, no-show thresholds) are implemented as configurable settings (Custom Metadata), so the open numbers do not block build | If a value must be hardcoded/behaviour-shaping, rework needed when confirmed | BA/architect (OQ-002/003/004/005/006/007) | Open |
| A-004 | 2026-07-11 | ba-analyst | Citizen self-service authentication is OTP to the registered mobile (RFP is silent; no Aadhaar; feature-phone friendly) | If a different auth is mandated (e.g., state SSO), portal access redesign | Deshmukh (OQ-027) | Open |
