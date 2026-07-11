#!/usr/bin/env bash
# Org setup for the Vaccine Scheduler POC — skeleton only, steps to be enabled later.

# 1. sf org create scratch -f config/project-scratch-def.json
# 2. sf project deploy start
# 3. run seed-data scripts
#
# MANUAL STEP (A-007 / D-* pre-build sign-off): per-facility public group membership is NOT automated
# in the POC. After deploy + seed, manually add each facility-staff user to their facility's public
# group (staff↔facility association) so facility-scoped sharing (VS-20, REQ-053) resolves correctly.
# Automating membership sync (Flow/Apex on user provisioning) is deferred beyond the pilot.
