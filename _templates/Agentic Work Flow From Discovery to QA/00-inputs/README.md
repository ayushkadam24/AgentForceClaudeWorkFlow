# 00-inputs — client source documents (READ-ONLY after paste)

Paste the client's real documents here BEFORE `/kickoff`, then never edit them again
(rules/00: this folder is read-only for every agent, and the pretool-guard hook enforces it).

Expected files (rename to match what you have):
- `rfp.md` — the RFP / requirements document (convert PDFs to md/txt for the BA)
- `discovery-notes.md` — workshop and interview notes
- `current-state.md` — the as-is system / process description
- `stakeholders.md` — decision-makers, owners, escalation paths
- `compliance/` — every compliance annexure (data protection, accessibility, messaging, security)

Tips:
- More source text = better BA output. Do not summarize documents yourself — paste them whole;
  the ba-analyst's job is the distillation, and every REQ-### it produces must trace here.
- If a document contains restricted PII, redact it BEFORE pasting (rules/10).
