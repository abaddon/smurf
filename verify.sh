#!/usr/bin/env bash
# Repo-root verify.sh — required by the smurf plugin's pre-commit-verify hook
# when committing inside the smurf source repo itself. Delegates to the real
# suite under tests/.
set -euo pipefail
cd "$(dirname "$0")"
exec bash tests/verify.sh "$@"
