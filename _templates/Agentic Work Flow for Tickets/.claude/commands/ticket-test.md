Test a ticket. Args: KEY. Launch ticket-tester on tickets/<KEY>-*/.
Preconditions: status BUILT.
Postconditions: test classes in src/; 04-test-evidence.md with per-test expected results marked
"NOT RUN" + manual verification script; register -> TESTED + history + run-log.
Next: /ticket-package KEY.
