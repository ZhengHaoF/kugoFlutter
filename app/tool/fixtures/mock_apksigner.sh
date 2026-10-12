#!/usr/bin/env bash
# Offline fixture only. Never used by the workflow or for real signature checks.
set -euo pipefail
if [[ "${MOCK_SIGNER_CASE:-}" == reject ]]; then exit 1; fi
owner='CN=kugo release fixture'
fingerprint=1111111111111111111111111111111111111111111111111111111111111111
if [[ "${MOCK_SIGNER_CASE:-}" == debug ]]; then owner='CN=Android Debug,O=Android,C=US'; fi
if [[ "${MOCK_SIGNER_CASE:-}" == mixed && "${*: -1}" == *x86_64* ]]; then
  fingerprint=2222222222222222222222222222222222222222222222222222222222222222
fi
printf 'Verifies\nSigner #1 certificate DN: %s\nSigner #1 certificate SHA-256 digest: %s\n' "$owner" "$fingerprint"
