Package a ticket. Args: KEY. Launch ticket-developer in packaging mode.
Preconditions: status TESTED.
Postconditions: package/package.xml reconciled against src/ (0 missing / 0 extra, count stated);
deploy-steps.md complete (explicit --target-org placeholder, class-level RunSpecifiedTests,
post-deploy checks, rollback note); register -> PACKAGED + history + run-log.
Next: HUMAN runs deploy-steps.md in the org, records real results in 04-test-evidence.md,
then /ticket-close KEY.
