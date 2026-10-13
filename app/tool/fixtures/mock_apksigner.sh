#!/usr/bin/env bash
# Offline fixture only. Never used by the workflow or for real signature checks.
set -euo pipefail
if [[ "${MOCK_SIGNER_CASE:-}" == reject ]]; then exit 1; fi
if [[ "${MOCK_SIGNER_CASE:-}" == stderr ]]; then exec 1>&2; fi
owner='CN=overtone release fixture'
fingerprint=1111111111111111111111111111111111111111111111111111111111111111
if [[ "${MOCK_SIGNER_CASE:-}" == debug ]]; then owner='CN=Android Debug,O=Android,C=US'; fi
if [[ "${MOCK_SIGNER_CASE:-}" == mixed && "${*: -1}" == *x86_64* ]]; then
  fingerprint=2222222222222222222222222222222222222222222222222222222222222222
fi
case "${MOCK_SIGNER_CASE:-}" in
  schemes)
    printf 'Verifies\nV2 Signer: certificate DN: %s\n' "$owner"
    printf 'V2 Signer: certificate SHA-256 digest: %s\n' "$fingerprint"
    printf 'V3 Signer: certificate SHA-256 digest: %s\n' "$fingerprint"
    ;;
  schemes-mixed)
    printf 'V2 Signer: certificate SHA-256 digest: %s\n' "$fingerprint"
    printf 'V3 Signer: certificate SHA-256 digest: %064d\n' 2
    ;;
  runner)
    # Observed runner label with a synthetic mixed hexadecimal digest.
    printf 'V2 Signer: certificate SHA-256 digest: abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789\n'
    ;;
  ranges)
    printf 'Verifies\nSigner (minSdkVersion=33, maxSdkVersion=2147483647) certificate DN: %s\n' "$owner"
    printf 'Signer (minSdkVersion=33, maxSdkVersion=2147483647) certificate SHA-256 digest: %s\n' "$fingerprint"
    printf 'Signer (minSdkVersion=24, maxSdkVersion=32) certificate SHA-256 digest: %s\n' "$fingerprint"
    ;;
  rotated)
    printf 'Signer (minSdkVersion=33, maxSdkVersion=2147483647) certificate SHA-256 digest: %s\n' "$fingerprint"
    printf 'Signer (minSdkVersion=24, maxSdkVersion=32) certificate SHA-256 digest: %064d\n' 2
    ;;
  crlf)
    printf 'Verifies\r\nSigner #1 certificate DN: %s\r\nSigner #1 certificate SHA-256 digest: %s\r\n' "$owner" "$fingerprint"
    ;;
  *)
    printf 'Verifies\nSigner #1 certificate DN: %s\nSigner #1 certificate SHA-256 digest: %s\n' "$owner" "$fingerprint"
    ;;
esac
