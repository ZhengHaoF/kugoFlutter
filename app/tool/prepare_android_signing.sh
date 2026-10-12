#!/usr/bin/env bash
set -euo pipefail
for name in ANDROID_KEYSTORE_BASE64 KUGO_STORE_PASSWORD KUGO_KEY_ALIAS KUGO_KEY_PASSWORD; do
  if [[ -z "${!name:-}" ]]; then
    echo "Missing production Android signing configuration: $name. Configure repository Actions Secrets; no debug fallback is permitted." >&2
    exit 1
  fi
done
: "${RUNNER_TEMP:?Missing runner temporary directory}"
: "${GITHUB_ENV:?Missing Actions environment file}"
umask 077
keystore="$RUNNER_TEMP/kugo-release-keystore.jks"
trap 'rm -f "$keystore"' ERR
printf '%s' "$ANDROID_KEYSTORE_BASE64" | base64 --decode > "$keystore"
[[ -s "$keystore" ]] || { echo "Empty decoded keystore" >&2; exit 1; }
printf 'KUGO_KEYSTORE_FILE=%s\n' "$keystore" >> "$GITHUB_ENV"
echo "Production Android keystore prepared; passwords are supplied only through the environment."
