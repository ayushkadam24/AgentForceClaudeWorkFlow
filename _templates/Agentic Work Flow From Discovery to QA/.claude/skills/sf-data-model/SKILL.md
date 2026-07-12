---
name: sf-data-model
description: Conventions for the technical design document, data model, and Mermaid ERD. Used by architect in ARCH_DESIGN.
---

# Technical Design & Data Model Conventions

## technical-design.md structure
1. Header block; design goals ranked (integrity <CRITICAL_REQ> > usability for P1/P2 > compliance > ops visibility).
2. Data model: per object — API name (PFX_*), purpose, ownership/OWD, key fields (API name,
   type, description), relationships with master-detail vs lookup justification, external IDs.
3. ERD: Mermaid `erDiagram` in 01-discovery/erd/data-model.mermaid (objects, relationships, cardinality).
4. Slot integrity design: the locking sequence step-by-step, failure modes, and exactly how the
   DHS concurrency test passes. Include the negative case (both requests try the last place).
5. Automation matrix: requirement → mechanism (Apex service / record-triggered flow / scheduled
   flow / platform event) → owner ticket routing (senior/mid).
6. Security & compliance mapping: each Annexure C item → permission sets, FLS, sharing, session
   settings, audit approach.
7. Epics EP-## with scope statements and REQ coverage.
8. Decision log references (D-### in memory/decisions.md) for every choice a reviewer might question.

## Domain model guidance (adapt, don't copy blindly)
Expected shape: Citizen/Person (minimal per C1), Facility, Service (<domain> type/OPD),
Schedule/Session (capacity definition — must support daily AND per-session capacity), Slot
(generated, holds capacity + booked count), Appointment (status: Booked/CheckedIn/Completed/
Cancelled/NoShow), <Domain> Event (<domain-item>, batch → lookup to Stock/Vial, dose number,
administered-by), Vial/Stock at facility, Certificate, Notification log.
Booker vs patient are different people (P2/P3): one mobile number manages many patients.

## ERD rules
- Every relationship line labeled with cardinality and a verb ("Facility ||--o{ PFX_Slot : offers").
- No <RESTRICTED_PII> field anywhere. Retention class (C4) noted per object as a comment.
