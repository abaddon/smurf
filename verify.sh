#!/usr/bin/env bash
# Project verify shim. Agents call ONLY this script — never a hardcoded
# build tool. Replace the body below with real tests/build for your stack
# (npm test, pytest, cargo test, mvn verify, etc.).
#
# The default body prints a WARN line so the no-op stays visible in run
# logs and never silently masks a missing test setup.

set -euo pipefail

echo "WARN: verify.sh is the no-op default; replace with real tests/build" >&2

# ── Check: scripts/version.sh must emit exactly 7 lowercase hex chars + newline ──
# Capture output byte-exactly: append 'x' so a missing trailing newline is detectable.
out=$(scripts/version.sh; printf x)
# Strip the sentinel 'x' we appended — what remains is the raw output of version.sh.
raw="${out%x}"

# Check for trailing newline: if raw ends with \n, stripping it via ${raw%?} should
# differ from raw (or we can check the sentinel position more directly).
# Approach: the captured string before 'x' must be exactly "<7 hex chars>\n".
# Strip the trailing newline from raw to get just the SHA part.
sha="${raw%$'\n'}"

# Detect missing trailing newline: if raw == sha, there was no newline.
if [[ "${raw}" == "${sha}" ]]; then
  echo "ERROR: scripts/version.sh output is missing a trailing newline" >&2
  exit 1
fi

# Check length: sha must be exactly 7 characters.
if [[ ${#sha} -ne 7 ]]; then
  echo "ERROR: scripts/version.sh output has wrong length: expected 7, got ${#sha} (value: '${sha}')" >&2
  exit 1
fi

# Check that sha contains only lowercase hex characters.
if [[ ! "${sha}" =~ ^[0-9a-f]{7}$ ]]; then
  echo "ERROR: scripts/version.sh output is not 7 lowercase hex characters: '${sha}'" >&2
  exit 1
fi

exit 0
