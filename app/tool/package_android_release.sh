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
  report="$("$tools/apksigner" verify --verbose --print-certs "$apk")"
  if printf '%s\n' "$report" | rg -qi 'CN\s*=\s*Android Debug'; then
    echo "Rejecting Android Debug signed APK: $abi" >&2
    exit 1
  fi
  fingerprint="$(printf '%s\n' "$report" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p')"
  [[ "$fingerprint" =~ ^[a-fA-F0-9]{64}$ ]] || { echo "Missing signer fingerprint: $abi" >&2; exit 1; }
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
