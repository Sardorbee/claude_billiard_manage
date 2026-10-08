#!/bin/sh
# Checks the security rules, then runs the end-to-end flow tests in Chrome.
# Each part gets its own fresh, seeded emulators.
set -e
cd "$(dirname "$0")/.."
emulators() {
  firebase emulators:exec --only auth,firestore,database,storage \
    --project billiard-manage "python3 tool/seed_emulator.py && $1"
}
emulators "python3 tool/check_rules.py"
emulators "flutter test --platform chrome test/emulator_flow_test.dart --reporter expanded"
