#!/usr/bin/env bash
set -euo pipefail
script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/package_release.sh"
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
export KUGO_VERSION=0.1.0 KUGO_BUILD_NUMBER=42
export GITHUB_SHA=1111111111111111111111111111111111111111
export GITHUB_REPOSITORY=fixture/repository GITHUB_RUN_ID=123 GITHUB_SERVER_URL=https://github.com
checksum() {
  local platform
  for platform in android windows; do
    (cd "$1/$platform"; find . -type f ! -name SHA256SUMS.txt -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS.txt)
  done
}
fixture() {
  local input="$1"
  mkdir -p "$input/android" "$input/windows/portable/data/flutter_assets" "$input/windows/installer" "$root/apk"
  printf 'synthetic manifest\n' > "$root/apk/AndroidManifest.xml"
  for abi in armeabi-v7a arm64-v8a x86_64; do
    (cd "$root/apk"; zip -q "$input/android/kugo-0.1.0-android-$abi.apk" AndroidManifest.xml)
    printf 'abi=%s signer-sha256=%064d\n' "$abi" 1 >> "$input/android/SIGNING.txt"
  done
  for file in kugo.exe flutter_windows.dll libmpv-2.dll data/app.so data/icudtl.dat data/flutter_assets/AssetManifest.bin; do
    printf 'synthetic Windows fixture\n' > "$input/windows/portable/$file"
  done
  printf 'MZsynthetic installer; never publish\n' > "$input/windows/installer/kugo-0.1.0-windows-x64-setup.exe"
  for platform in android windows; do
    printf 'version=0.1.0\nbuild=42\ncommit=%s\nrun=https://github.com/fixture/repository/actions/runs/123\n' "$GITHUB_SHA" > "$input/$platform/BUILD-INFO.txt"
  done
  printf 'signing=production\n' >> "$input/android/BUILD-INFO.txt"
  cp "$input/windows/BUILD-INFO.txt" "$input/windows/portable/BUILD-INFO.txt"
  printf 'PASS migration\nPASS cleanup\nPASS replacement\nPASS logout\nPASS delete\n' > "$input/windows/portable/NATIVE-CREDENTIALS.txt"
  printf 'PASS install files and installed app startup\nPASS uninstall\n' > "$input/windows/INSTALLER-TEST.txt"
  checksum "$input"
}
reject() {
  if bash "$script" "$1" "$root/rejected-output" > "$root/rejected.log" 2>&1; then
    echo "FAIL expected rejection: $2" >&2; exit 1
  fi
  echo "PASS rejection: $2"
}
fixture "$root/valid"
bash "$script" "$root/valid" "$root/output" > "$root/valid.log"
test "$(find "$root/output" -maxdepth 1 -name '*.apk' | wc -l)" -eq 3
test -s "$root/output/kugo-0.1.0-windows-x64-setup.exe"
unzip -p "$root/output/kugo-0.1.0-windows-x64-portable.zip" kugo.exe | cmp - "$root/valid/windows/portable/kugo.exe"
(cd "$root/output"; sha256sum --strict -c SHA256SUMS.txt >/dev/null)
echo "PASS all three APKs, installer and full portable ZIP"
for case in missing-abi tampered-apk tampered-installer wrong-version wrong-build wrong-commit wrong-run debug-signing mixed-signers missing-installer missing-runtime missing-probe failed-install uncovered-file wrong-portable-identity invalid-installer invalid-apk invalid-version invalid-build; do
  input="$root/$case"
  fixture "$input"
  case "$case" in
    missing-abi) rm "$input/android/kugo-0.1.0-android-x86_64.apk" ;;
    tampered-apk) printf tamper >> "$input/android/kugo-0.1.0-android-arm64-v8a.apk" ;;
    tampered-installer) printf tamper >> "$input/windows/installer/kugo-0.1.0-windows-x64-setup.exe" ;;
    wrong-version) sed -i 's/version=0.1.0/version=0.2.0/' "$input/android/BUILD-INFO.txt" ;;
    wrong-build) sed -i 's/build=42/build=43/' "$input/windows/BUILD-INFO.txt" ;;
    wrong-commit) sed -i 's/commit=.*/commit=2222222222222222222222222222222222222222/' "$input/windows/BUILD-INFO.txt" ;;
    wrong-run) sed -i 's@runs/123@runs/999@' "$input/android/BUILD-INFO.txt" ;;
    debug-signing) sed -i 's/signing=production/signing=debug/' "$input/android/BUILD-INFO.txt"; checksum "$input" ;;
    mixed-signers) sed -i 's/abi=x86_64 signer-sha256=.*/abi=x86_64 signer-sha256=2222222222222222222222222222222222222222222222222222222222222222/' "$input/android/SIGNING.txt"; checksum "$input" ;;
    missing-installer) rm "$input/windows/installer/kugo-0.1.0-windows-x64-setup.exe" ;;
    missing-runtime) rm "$input/windows/portable/flutter_windows.dll" ;;
    missing-probe) printf 'PASS migration\n' > "$input/windows/portable/NATIVE-CREDENTIALS.txt"; checksum "$input" ;;
    failed-install) printf 'PASS install files and installed app startup\n' > "$input/windows/INSTALLER-TEST.txt"; checksum "$input" ;;
    uncovered-file) sed -i '/installer\/kugo-/d' "$input/windows/SHA256SUMS.txt" ;;
    wrong-portable-identity) sed -i 's/build=42/build=43/' "$input/windows/portable/BUILD-INFO.txt"; checksum "$input" ;;
    invalid-installer) printf 'not an EXE\n' > "$input/windows/installer/kugo-0.1.0-windows-x64-setup.exe"; checksum "$input" ;;
    invalid-apk) printf 'not an APK\n' > "$input/android/kugo-0.1.0-android-arm64-v8a.apk"; checksum "$input" ;;
    invalid-version) export KUGO_VERSION='../bad' ;;
    invalid-build) export KUGO_BUILD_NUMBER=0 ;;
  esac
  reject "$input" "$case"
  export KUGO_VERSION=0.1.0 KUGO_BUILD_NUMBER=42
done
# Preparing signing must fail without secrets, without creating a key.
if env -u ANDROID_KEYSTORE_BASE64 -u KUGO_STORE_PASSWORD -u KUGO_KEY_ALIAS -u KUGO_KEY_PASSWORD \
  bash "$(dirname "$script")/prepare_android_signing.sh" > "$root/signing.log" 2>&1; then
  echo "FAIL signing accepted missing secrets" >&2; exit 1
fi
echo "PASS missing production signing fails closed"

# Exercise the APK verification wrapper with an explicitly synthetic verifier.
# These fixtures test control flow, not cryptographic validity.
mkdir -p "$root/android-wrapper/build/app/outputs/flutter-apk" "$root/sdk/build-tools/35.0.0"
cp "$(dirname "$script")/fixtures/mock_apksigner.sh" "$root/sdk/build-tools/35.0.0/apksigner"
chmod +x "$root/sdk/build-tools/35.0.0/apksigner"
export ANDROID_HOME="$root/sdk"
for abi in armeabi-v7a arm64-v8a x86_64; do
  cp "$root/valid/android/kugo-0.1.0-android-$abi.apk" \
    "$root/android-wrapper/build/app/outputs/flutter-apk/app-$abi-release.apk"
done
(
  cd "$root/android-wrapper"
  bash "$(dirname "$script")/package_android_release.sh"
)
echo "PASS APK verifier wrapper packages all ABIs"
for scenario in debug mixed reject missing; do
  if [[ "$scenario" == missing ]]; then
    rm "$root/android-wrapper/build/app/outputs/flutter-apk/app-x86_64-release.apk"
  fi
  if (cd "$root/android-wrapper"; MOCK_SIGNER_CASE="$scenario" bash "$(dirname "$script")/package_android_release.sh") \
    > "$root/verifier.log" 2>&1; then
    echo "FAIL verifier wrapper accepted: $scenario" >&2; exit 1
  fi
  echo "PASS APK verifier wrapper rejects $scenario"
done
echo "ALL_PRODUCTION_RELEASE_CHECKS_PASSED"
