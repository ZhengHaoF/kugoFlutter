#!/usr/bin/env bash
set -euo pipefail
: "${KUGO_VERSION:?Missing version}"
: "${KUGO_BUILD_NUMBER:?Missing build number}"
: "${GITHUB_SHA:?Missing commit}"
: "${GITHUB_SERVER_URL:?Missing server}"
: "${GITHUB_REPOSITORY:?Missing repository}"
: "${GITHUB_RUN_ID:?Missing run}"
: "${ANDROID_HOME:?Missing Android SDK}"
[[ "$KUGO_VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || exit 1
tools="$(find "$ANDROID_HOME/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)"
[[ -x "$tools/apksigner" ]] || { echo "Missing apksigner" >&2; exit 1; }
out=build/deliverables/android
mkdir -p "$out"
: > "$out/SIGNING.txt"
for abi in armeabi-v7a arm64-v8a x86_64; do
  apk="build/app/outputs/flutter-apk/app-$abi-release.apk"
  [[ -s "$apk" ]] || { echo "Missing ABI APK: $abi" >&2; exit 1; }
  if ! report="$("$tools/apksigner" verify --verbose --print-certs "$apk" 2>&1)"; then
    echo "apksigner verification failed: $abi" >&2
    exit 1
  fi
  if printf '%s\n' "$report" | grep -Eiq 'CN[[:space:]]*=[[:space:]]*Android Debug'; then
    echo "Rejecting Android Debug signed APK: $abi" >&2
    exit 1
  fi
  # SDK-range labels are used by v3.1, not just the older "Signer #1".
  # Accept repeated ranges only when they all name the same certificate.
  fingerprint="$(printf '%s\n' "$report" | awk '
    /^Signer .* certificate SHA-256 digest:/ {
      sub(/^.* certificate SHA-256 digest:[[:space:]]*/, "");
      sub(/[[:space:]]*$/, "");
      print tolower($0)
    }' | sort -u)"
  [[ "$fingerprint" =~ ^[a-f0-9]{64}$ ]] || {
    echo "Missing or multiple distinct signer fingerprints: $abi" >&2; exit 1;
  }
  printf 'abi=%s signer-sha256=%s\n' "$abi" "${fingerprint,,}" >> "$out/SIGNING.txt"
  cp "$apk" "$out/kugo-$KUGO_VERSION-android-$abi.apk"
done
[[ "$(sed 's/.*signer-sha256=//' "$out/SIGNING.txt" | sort -u | wc -l)" -eq 1 ]] || {
  echo "ABI APKs have different signers" >&2; exit 1;
}
printf 'kugo Android Release\nversion=%s\nbuild=%s\ncommit=%s\nrun=%s/%s/actions/runs/%s\nsigning=production\n' \
  "$KUGO_VERSION" "$KUGO_BUILD_NUMBER" "$GITHUB_SHA" "$GITHUB_SERVER_URL" "$GITHUB_REPOSITORY" "$GITHUB_RUN_ID" \
  > "$out/BUILD-INFO.txt"
(
  cd "$out"
  sha256sum ./*.apk SIGNING.txt BUILD-INFO.txt > SHA256SUMS.txt
)
