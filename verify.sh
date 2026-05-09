#!/usr/bin/env bash
# Project verify shim. Agents call ONLY this script — never a hardcoded
# build tool. Replace the body below with real tests/build for your stack
# (npm test, pytest, cargo test, mvn verify, etc.).
#
# The default body prints a WARN line so the no-op stays visible in run
# logs and never silently masks a missing test setup.

set -euo pipefail

echo "WARN: verify.sh is the no-op default; replace with real tests/build" >&2
exit 0
