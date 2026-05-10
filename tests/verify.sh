#!/usr/bin/env bash
# verify.sh for the smurf plugin's own development repo. Runs the hook
# smoke tests. End users do NOT call this — they ship their own verify.sh
# in their project (created by /smurf:init).
set -euo pipefail
cd "$(dirname "$0")/.."
bash tests/test-hooks.sh
