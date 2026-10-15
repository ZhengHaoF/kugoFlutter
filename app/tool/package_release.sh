#!/usr/bin/env bash
set -euo pipefail
[[ $# -eq 2 ]] || { echo "Usage: $0 <artifact-input-directory> <release-output-directory>" >&2; exit 64; }
: "${OVERTONE_VERSION:?Missing release version}"
: "${OVERTONE_BUILD_NUMBER:?Missing build number}"
: "${GITHUB_SHA:?Missing source commit}"
: "${GITHUB_REPOSITORY:?Missing repository}"
: "${GITHUB_RUN_ID:?Missing workflow run}"
: "${GITHUB_SERVER_URL:?Missing server}"
[[ "$OVERTONE_VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || { echo "Invalid release version" >&2; exit 1; }
[[ "$OVERTONE_BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || { echo "Invalid build number" >&2; exit 1; }
[[ "$GITHUB_SHA" =~ ^[a-f0-9]{40}$ ]] || { echo "Invalid commit" >&2; exit 1; }
input="$(cd "$1" && pwd)"
mkdir -p "$2"
output="$(cd "$2" && pwd)"
run_url="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
installer="overtone-$OVERTONE_VERSION-windows-x64-setup.exe"
portable="overtone-$OVERTONE_VERSION-windows-x64-portable.zip"
android_files=()
required=(
  android/SIGNING.txt android/BUILD-INFO.txt
  windows/BUILD-INFO.txt windows/INSTALLER-TEST.txt
  "windows/installer/$installer"
  windows/portable/overtone.exe windows/portable/flutter_windows.dll windows/portable/libmpv-2.dll
  windows/portable/data/app.so windows/portable/data/icudtl.dat
  windows/portable/data/flutter_assets/AssetManifest.bin
  windows/portable/BUILD-INFO.txt windows/portable/NATIVE-CREDENTIALS.txt
)
for abi in armeabi-v7a arm64-v8a x86_64; do
  apk="overtone-$OVERTONE_VERSION-android-$abi.apk"
  android_files+=("$apk")
  required+=("android/$apk")
done
for file in "${required[@]}"; do
  [[ -s "$input/$file" ]] || { echo "Missing release input: $file" >&2; exit 1; }
done
for platform in android windows; do
  [[ -s "$input/$platform/SHA256SUMS.txt" ]] || { echo "Missing checksums: $platform" >&2; exit 1; }
  info="$input/$platform/BUILD-INFO.txt"
  for line in "version=$OVERTONE_VERSION" "build=$OVERTONE_BUILD_NUMBER" "commit=$GITHUB_SHA" "run=$run_url"; do
    tr -d '\r' < "$info" | rg -Fx "$line" >/dev/null || { echo "Artifact identity mismatch: $platform ($line)" >&2; exit 1; }
  done
  (
    cd "$input/$platform"
    sed 's/\r$//; s@\\@/@g' SHA256SUMS.txt | sha256sum --strict -c -
    # Required files must be covered, not just whatever a manifest happens to list.
    for file in "${required[@]}"; do
      [[ "$file" == "$platform/"* ]] || continue
      relative="${file#"$platform/"}"
      checksum="$(sha256sum "$relative")"
      sed 's/\r$//; s@\\@/@g; s@  \./@  @' SHA256SUMS.txt | rg -Fx "$checksum" >/dev/null || {
        echo "Required file is not covered by checksums: $file" >&2; exit 1;
      }
    done
  )
done
cmp "$input/windows/BUILD-INFO.txt" "$input/windows/portable/BUILD-INFO.txt" >/dev/null || {
  echo "Portable bundle source identity differs from Windows artifact" >&2; exit 1;
}
rg -Fx 'signing=production' "$input/android/BUILD-INFO.txt" >/dev/null || { echo "Android signing is not production" >&2; exit 1; }
[[ "$(wc -l < "$input/android/SIGNING.txt")" -eq 3 ]] || { echo "Missing ABI signature evidence" >&2; exit 1; }
for abi in armeabi-v7a arm64-v8a x86_64; do
  rg -q "^abi=$abi signer-sha256=[a-f0-9]{64}$" "$input/android/SIGNING.txt" || exit 1
done
[[ "$(sed 's/.*signer-sha256=//' "$input/android/SIGNING.txt" | sort -u | wc -l)" -eq 1 ]] || {
  echo "ABI signers differ" >&2; exit 1;
}
[[ "$(rg -c '^PASS ' "$input/windows/portable/NATIVE-CREDENTIALS.txt" || true)" == 5 ]] &&
  ! rg -q '^FAIL' "$input/windows/portable/NATIVE-CREDENTIALS.txt" || { echo "Incomplete native credential evidence" >&2; exit 1; }
tr -d '\r' < "$input/windows/INSTALLER-TEST.txt" | rg -Fx 'PASS install files and installed app startup' >/dev/null &&
  tr -d '\r' < "$input/windows/INSTALLER-TEST.txt" | rg -Fx 'PASS uninstall' >/dev/null || { echo "Installer acceptance incomplete" >&2; exit 1; }
[[ "$(head -c 2 "$input/windows/installer/$installer")" == MZ ]] || { echo "Installer is not a Windows executable" >&2; exit 1; }
for apk in "${android_files[@]}"; do
  unzip -tq "$input/android/$apk" >/dev/null
  unzip -Z1 "$input/android/$apk" | rg -Fx AndroidManifest.xml >/dev/null || { echo "APK manifest missing" >&2; exit 1; }
  cp "$input/android/$apk" "$output/$apk"
done
cp "$input/windows/installer/$installer" "$output/$installer"
cp "$input/android/SIGNING.txt" "$output/ANDROID-SIGNING.txt"
(
  cd "$input/windows/portable"
  zip -q -r "$output/$portable" .
)
unzip -tq "$output/$portable"
printf 'overtone Release\nversion=%s\nbuild=%s\ncommit=%s\nrun=%s\nAndroid: production key, armeabi-v7a/arm64-v8a/x86_64.\nWindows: x64 installer and portable bundle; Authenticode unsigned.\nActual-device and real-account acceptance remains pending.\n' \
  "$OVERTONE_VERSION" "$OVERTONE_BUILD_NUMBER" "$GITHUB_SHA" "$run_url" > "$output/BUILD-INFO.txt"
(
  cd "$output"
  sha256sum "${android_files[@]}" "$installer" "$portable" ANDROID-SIGNING.txt BUILD-INFO.txt > SHA256SUMS.txt
  sha256sum --strict -c SHA256SUMS.txt
)
cat <<EOF > "$output/RELEASE-NOTES.md"
# overtone $OVERTONE_VERSION

Release 模式发布包，构建编号 $OVERTONE_BUILD_NUMBER，源码 \`$GITHUB_SHA\`。

- Android：按设备 CPU 下载 \`armeabi-v7a\`（ARM 32 位）、\`arm64-v8a\`（ARM 64 位）或 \`x86_64\` APK。最低 Android 7.0 / API 24。所有 APK 经过签名验证，使用同一正式密钥，证书指纹见 ANDROID-SIGNING.txt；架构与拆包规则见 [Flutter 官方文档](https://docs.flutter.dev/deployment/android)。
- Windows x64：\`$installer\` 为当前用户安装程序，含快捷方式及卸载；\`$portable\` 为完整绿色目录，解压后运行 overtone.exe，不要丢弃 DLL 和 data/。
- Windows 安装程序及程序目前没有 Authenticode 代码签名，可能出现 SmartScreen 提示；Release 模式不等于已取得代码签名或商店认证，提示机制见 [Microsoft 说明](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation)。
- 请使用 SHA256SUMS.txt 核对下载文件。旧测试版 Android 的 debug 签名与正式签名不同，可能无法覆盖安装，不要为安装新包贸然卸载有数据的旧应用。
- 真实账号、设备播放、长时运行仍需验收；CI 安装和原生探针不等同于真机验收。不提供 Linux 包。

[构建与验收记录]($run_url)。
EOF
echo "Validated production release assets: $output"
