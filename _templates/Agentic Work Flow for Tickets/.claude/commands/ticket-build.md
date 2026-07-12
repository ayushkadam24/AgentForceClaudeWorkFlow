Build a ticket. Args: KEY. Launch ticket-developer on tickets/<KEY>-*/.
Preconditions: status SOLUTIONED; blocking open questions answered (else BLOCKED, say why).
Postconditions: src/ populated; `node scripts/metadata-lint.js` PASS pasted verbatim in
03-build-notes.md; register -> BUILT + history + run-log. NEVER run org commands.
Next: /ticket-test KEY.
