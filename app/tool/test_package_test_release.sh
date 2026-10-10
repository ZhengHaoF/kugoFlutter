#!/usr/bin/env bash
set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/package_test_release.sh"
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
export GITHUB_SHA=1111111111111111111111111111111111111111
export GITHUB_REPOSITORY=fixture/repository
export GITHUB_RUN_ID=123
export GITHUB_SERVER_URL=https://github.com

checksum_windows() {
  local input="$1"
  local manifest
  manifest="$(mktemp "$root/checksums.XXXXXX")"
  (
    cd "$input/windows"
    find . -type f ! -name SHA256SUMS.txt -print0 | sort -z |
      xargs -0 sha256sum | sed 's@/@\\@g' > "$manifest"
  )
  mv "$manifest" "$input/windows/SHA256SUMS.txt"
}

fixture() {
  local input="$1"
  mkdir -p "$input/android" "$input/windows/data/flutter_assets"
  printf 'synthetic APK fixture, never publish\n' > "$input/android/kugo-android-test-only.apk"
  for file in kugo.exe flutter_windows.dll libmpv-2.dll data/app.so data/icudtl.dat data/flutter_assets/AssetManifest.bin; do
    printf 'synthetic Windows fixture, never publish\n' > "$input/windows/$file"
  done
  for platform in android windows; do
    printf 'commit=%s\nrun=%s/%s/actions/runs/%s\n' \
      "$GITHUB_SHA" "$GITHUB_SERVER_URL" "$GITHUB_REPOSITORY" "$GITHUB_RUN_ID" \
      > "$input/$platform/BUILD-INFO.txt"
  done
  printf 'PASS migration\nPASS plaintext cleanup\nPASS replacement\nPASS logout\nPASS native delete\n' \
    > "$input/windows/NATIVE-CREDENTIALS.txt"
  (
    cd "$input/android"
    sha256sum kugo-android-test-only.apk > SHA256SUMS.txt
  )
  checksum_windows "$input"
}

reject() {
  if bash "$script" "$1" "$2" > "$root/rejected.log" 2>&1; then
    echo "FAIL: expected packaging rejection: $3" >&2
    exit 1
  fi
  echo "PASS rejection: $3"
}

fixture "$root/valid"
bash "$script" "$root/valid" "$root/valid-output" > "$root/valid.log"
test -s "$root/valid-output/kugo-android-1111111-test-only.apk"
test -s "$root/valid-output/kugo-windows-x64-1111111-portable-test-only.zip"
(
  cd "$root/valid-output"
  sha256sum --strict -c SHA256SUMS.txt > /dev/null
)
unzip -p "$root/valid-output/kugo-windows-x64-1111111-portable-test-only.zip" kugo.exe |
  cmp - "$root/valid/windows/kugo.exe"
echo "PASS complete test release packaging"

fixture "$root/tampered"
printf 'tampered\n' >> "$root/tampered/android/kugo-android-test-only.apk"
reject "$root/tampered" "$root/tampered-output" "APK checksum mismatch"

fixture "$root/tampered-windows"
printf 'tampered\n' >> "$root/tampered-windows/windows/libmpv-2.dll"
reject "$root/tampered-windows" "$root/tampered-windows-output" "Windows checksum mismatch"

fixture "$root/wrong-commit"
printf 'commit=2222222222222222222222222222222222222222\n' > "$root/wrong-commit/windows/BUILD-INFO.txt"
reject "$root/wrong-commit" "$root/wrong-commit-output" "mismatched source commit"

fixture "$root/missing-runtime"
rm "$root/missing-runtime/windows/flutter_windows.dll"
reject "$root/missing-runtime" "$root/missing-runtime-output" "missing Windows runtime"

fixture "$root/incomplete-probe"
printf 'PASS migration\n' > "$root/incomplete-probe/windows/NATIVE-CREDENTIALS.txt"
checksum_windows "$root/incomplete-probe"
reject "$root/incomplete-probe" "$root/incomplete-probe-output" "incomplete native evidence"

fixture "$root/wrong-run"
printf 'commit=%s\nrun=https://github.com/fixture/repository/actions/runs/999\n' "$GITHUB_SHA" \
  > "$root/wrong-run/android/BUILD-INFO.txt"
reject "$root/wrong-run" "$root/wrong-run-output" "mismatched workflow run"
echo "ALL_RELEASE_PACKAGING_CHECKS_PASSED"
