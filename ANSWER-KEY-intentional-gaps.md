# Answer Key — Intentional Gaps & Contradictions Planted in the Synthetic Inputs

**⚠ DO NOT feed this file to the `ba-analyst` (or any pipeline agent).**
Keep it outside `00-inputs/`. Its purpose is to let YOU grade the BA agent's output:
a good requirements brief should surface most of these as open questions, assumptions,
or risks — without you prompting for them.

| # | Planted where | The gap / contradiction | What a good BA output does |
|---|---|---|---|
| 1 | Discovery §2 | Shinde says capacity is **daily**; Pawar says **per-session** (morning ≠ afternoon) | Flags the conflict; proposes a model that supports both (e.g., capacity distributed across time bands); lists it as a design decision needing sign-off |
| 2 | Discovery §4 | Walk-in reserve: 20–30% floated, **never decided** | Captures walk-in coexistence as a requirement; reserve % as an open question / configurable parameter |
| 3 | Discovery §3 | Slot durations "sound right" but **no final numbers**; OPD differs from vaccination | Marks durations as per-service configuration with proposed defaults, pending confirmation |
| 4 | Discovery §3 | Special **Sunday drives** conflict with the holiday calendar concept | Surfaces as a rule: staff-added capacity overrides closed days; flags design implication for the slot generator |
| 5 | Discovery §5 | No-show penalty: idea agreed, **thresholds not** | Requirement captured with parameters TBD; not invented numbers |
| 6 | Discovery §8 + Annexure C7 | **SMS gateway undecided**; DLT template lead time 1–3 weeks | Flagged as an external dependency with schedule risk; provider-abstraction noted |
| 7 | Discovery §9 | 3 PHCs have unreliable connectivity; **no requirement agreed** | Raised as a risk/open question for check-in design (not silently ignored, not over-specified) |
| 8 | Stakeholders P2 | One phone manages bookings for **multiple patients** (ASHA/family) — easy to miss, changes the data model | Appears explicitly in requirements (booker ≠ patient); certificate carries the patient |
| 9 | Stakeholders (volumes) | 60/40 smartphone split marked "⚠ unverified" | Carried forward as an assumption, not a fact |
| 10 | RFP §5 vs Discovery | RFP says 7 AM–8 PM availability; facilities operate sessions — subtle mismatch | Ideally noticed; at minimum operating-hours model is per-facility |
| 11 | Annexure C4.1 | Health-record retention "minimum 10 years, confirm exact schedule" | Open question logged for design sign-off |
| 12 | RFP §4 | CoWIN/U-WIN integration out of scope but "must not preclude" | Appears as an architectural constraint, not dropped |
| 13 | Nowhere (deliberate omission) | **Nobody defines what happens to a booked citizen when staff cancel a slot but no alternative capacity exists that week** | A great BA invents the question; an average one misses it |
| 14 | Nowhere (deliberate omission) | Language: RFP says English at launch, Marathi/Hindi later — but SMS templates & certificates for feature-phone users are never given a language decision | Sharp catch if the BA raises it |

## Grading rubric (rough)
- **10+ caught, none hallucinated into invented "requirements":** BA agent instructions are in good shape.
- **6–9 caught:** acceptable; tighten the agent's instructions to explicitly demand contradictions, unverified assumptions, and external dependencies as separate sections.
- **≤5, or the agent invents numbers to fill gaps:** the agent is summarizing, not analyzing — rework its prompt before proceeding to the Architect.

Also watch for the failure mode of over-flagging: if the brief drowns real gaps in dozens of trivial "TBDs," that's noise, not analysis.
