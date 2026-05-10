#!/usr/bin/env bash
# Project verify shim. Agents call ONLY this script — never a hardcoded
# build tool. Replace or extend the body for your stack (npm test,
# pytest, cargo test, mvn verify, etc.).
#
# Current checks:
# - scripts/version.sh must emit exactly 7 lowercase hex chars + newline
#   (a short Git SHA followed by a single LF).

set -euo pipefail

# Capture byte-exactly: append 'x' so a missing trailing newline is
# detectable through command substitution (which strips trailing \n).
out=$(scripts/version.sh; printf x)
raw="${out%x}"

# Short-circuiting checks. Length first — without it, slice operations
# below could produce confusing secondary errors on a too-short raw.

if [[ ${#raw} -ne 8 ]]; then
  echo "ERROR: scripts/version.sh output has wrong byte count: expected 8, got ${#raw}" >&2
  exit 1
fi

# NB: the space in `${raw: -1}` is required — `${raw:-1}` is the
# default-value operator, not slicing.
if [[ "${raw: -1}" != $'\n' ]]; then
  echo "ERROR: scripts/version.sh output is missing a trailing newline" >&2
  exit 1
fi

prefix="${raw:0:7}"
if [[ ! "$prefix" =~ ^[0-9a-f]{7}$ ]]; then
  echo "ERROR: scripts/version.sh output is not 7 lowercase hex characters: '$prefix'" >&2
  exit 1
fi

exit 0
