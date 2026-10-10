#!/usr/bin/env bash
set -euo pipefail

# Package already-validated Android/Windows artifacts. No compilation, signing
# or credential access happens here; source identity and checksums are required.
if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <artifact-input-directory> <release-output-directory>" >&2
  exit 64
fi
: "${GITHUB_SHA:?Missing source commit}"
: "${GITHUB_REPOSITORY:?Missing repository}"
: "${GITHUB_RUN_ID:?Missing workflow run}"
: "${GITHUB_SERVER_URL:?Missing GitHub server URL}"
[[ "$GITHUB_SHA" =~ ^[a-f0-9]{40}$ ]] || {
  echo "Invalid source commit" >&2
  exit 1
}
input="$(cd "$1" && pwd)"
mkdir -p "$2"
output="$(cd "$2" && pwd)"
short="${GITHUB_SHA:0:7}"
run_url="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"

for file in \
  android/kugo-android-test-only.apk android/SHA256SUMS.txt android/BUILD-INFO.txt \
  windows/kugo.exe windows/flutter_windows.dll windows/libmpv-2.dll \
  windows/data/app.so windows/data/icudtl.dat windows/data/flutter_assets/AssetManifest.bin windows/SHA256SUMS.txt \
  windows/BUILD-INFO.txt windows/NATIVE-CREDENTIALS.txt; do
  [[ -s "$input/$file" ]] || {
    echo "Missing or empty release input: $file" >&2
    exit 1
  }
done
[[ -d "$input/windows/data/flutter_assets" ]] || {
  echo "Missing Windows Flutter assets" >&2
  exit 1
}

for platform in android windows; do
  tr -d '\r' < "$input/$platform/BUILD-INFO.txt" |
    rg -Fx "commit=$GITHUB_SHA" > /dev/null || {
      echo "Artifact commit does not match the release source: $platform" >&2
      exit 1
    }
  tr -d '\r' < "$input/$platform/BUILD-INFO.txt" |
    rg -Fx "run=$run_url" > /dev/null || {
      echo "Artifact run does not match the release source: $platform" >&2
      exit 1
    }
  (
    cd "$input/$platform"
    sed 's@\\@/@g' SHA256SUMS.txt | sha256sum --strict -c -
  )
done
if [[ "$(rg -c '^PASS ' "$input/windows/NATIVE-CREDENTIALS.txt" || true)" != 5 ]] ||
  rg -q '^FAIL' "$input/windows/NATIVE-CREDENTIALS.txt"; then
  echo "Incomplete Windows native credential evidence" >&2
  exit 1
fi

apk="kugo-android-$short-test-only.apk"
windows_zip="kugo-windows-x64-$short-portable-test-only.zip"
cp "$input/android/kugo-android-test-only.apk" "$output/$apk"
(
  cd "$input/windows"
  zip -q -r "$output/$windows_zip" .
)
unzip -tq "$output/$windows_zip"

printf '%s\n' \
  "kugo TEST-ONLY release" \
  "commit=$GITHUB_SHA" \
  "run=$run_url" \
  "Android: release-mode APK with an Android Debug test certificate; API 24+." \
  "Windows: complete x64 portable bundle, unsigned." \
  "Real-account, physical-device and long-duration playback acceptance is pending." \
  > "$output/BUILD-INFO.txt"
(
  cd "$output"
  sha256sum "$apk" "$windows_zip" BUILD-INFO.txt > SHA256SUMS.txt
  sha256sum --strict -c SHA256SUMS.txt
)

cat <<EOF > "$output/RELEASE-NOTES.md"
# kugo 测试版

这是开发测试包，不是正式签名发布版本。构建源码为 \`$GITHUB_SHA\`，两端构建、质量门禁及 Windows 原生凭据探针通过后才发布。

## 下载与安装

- **Android**：下载 \`$apk\`，支持 Android 7.0 / API 24 及以上；也可用 \`adb install -r $apk\` 安装。
- **Windows x64**：下载 \`$windows_zip\`，完整解压后运行 \`kugo.exe\`；保留所有 DLL 与 \`data/\`，不要只复制 EXE。
- **校验**：下载 \`SHA256SUMS.txt\` 与相应文件，在同一目录核对 SHA-256；\`BUILD-INFO.txt\` 记录构建来源和签名边界。

## 测试版边界

- Android 使用 CI 生成的 **Android Debug 测试签名**，不是正式发布签名；不同运行的密钥可能不同，不保证覆盖安装，勿贸然卸载有数据的旧应用。
- Windows **未做 Authenticode 签名**，不是 MSI 安装器；缺运行库时安装 Microsoft Visual C++ 2015–2022 x64 Redistributable。
- 真实账号、物理设备、蓝牙/扬声器及长时播放仍待验收；runner 探针和编译成功不替代这些验收。
- 不包含 Linux 应用包，P2 与新的 Wayland 专项仍暂缓。

[构建与验收记录]($run_url)。GitHub Actions 的原始制品也继续保留，Releases 的附件没有设置 Actions 的 30 天自动到期策略。
EOF
echo "Validated release assets: $output"
