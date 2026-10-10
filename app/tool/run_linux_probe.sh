#!/usr/bin/env bash
# Run inside: xvfb-run -a dbus-run-session -- bash tool/run_linux_probe.sh BIN OUT
# Test-only synthetic audio/video; not a physical speaker or real-account test.
set -euo pipefail
binary=$(realpath "${1:?binary path required}")
out=$(realpath -m "${2:?output directory required}")
mkdir -p "$out"
work=$(mktemp -d)
export XDG_RUNTIME_DIR="$work/runtime"
export XDG_DATA_HOME="$work/data" XDG_CONFIG_HOME="$work/config"
mkdir -m 700 -p "$XDG_RUNTIME_DIR" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME"
export LIBGL_ALWAYS_SOFTWARE=1 NO_AT_BRIDGE=1
export PULSE_SERVER="unix:$XDG_RUNTIME_DIR/pulse/native"
pulse= wm= compositor= record= app=
cleanup() {
  for pid in "$app" "$record" "$pulse" "$compositor" "$wm"; do
    if [[ -n "$pid" ]]; then kill "$pid" 2>/dev/null || true; fi
  done
  rm -rf "$work"
}
trap cleanup EXIT
openbox > "$out/window-manager.log" 2>&1 & wm=$!
if [[ "${KUGO_PROBE_BACKEND:-x11}" == wayland ]]; then
  weston --backend=x11-backend.so --width=1440 --height=1000 \
    --socket=kugo-probe --idle-time=0 > "$out/weston.log" 2>&1 & compositor=$!
  for _ in {1..100}; do
    [[ -S "$XDG_RUNTIME_DIR/kugo-probe" ]] && break
    sleep .1
  done
  [[ -S "$XDG_RUNTIME_DIR/kugo-probe" ]]
  export WAYLAND_DISPLAY=kugo-probe GDK_BACKEND=wayland
fi
pulseaudio --daemonize=no --exit-idle-time=-1 > "$out/pulse.log" 2>&1 & pulse=$!
for _ in {1..50}; do
  if pactl info > /dev/null 2>&1; then break; fi
  sleep .1
done
pactl load-module module-null-sink sink_name=kugo_test > "$out/sink-module.txt"
pactl set-default-sink kugo_test
ffmpeg -nostdin -v error -f lavfi -i testsrc=size=320x180:rate=20 \
  -t 6 -pix_fmt yuv420p -c:v mpeg4 -y "$out/fixture.mp4"
export KUGO_PROBE_VIDEO="$out/fixture.mp4"
parec --device=kugo_test.monitor --format=s16le --rate=48000 --channels=2 \
  > "$out/audio.raw" 2> "$out/record.log" & record=$!
timeout 100 "$binary" > "$out/probe.log" 2>&1 & app=$!
for _ in {1..900}; do
  if ! kill -0 "$app" 2>/dev/null; then break; fi
  if [[ -f "$out/probe.log" ]] && rg -q 'SCREENSHOT_READY' "$out/probe.log"; then
    import -window root "$out/probe.png"
    break
  fi
  sleep .1
done
wait "$app"
app=
kill "$record" 2>/dev/null || true
wait "$record" 2>/dev/null || true
record=
rg 'PASS|FAIL|ALL_CHECKS_PASSED|backend=' "$out/probe.log"
rg -q 'ALL_CHECKS_PASSED' "$out/probe.log"
node - "$out/audio.raw" <<'JS'
const fs = require('fs');
const b = fs.readFileSync(process.argv[2]);
let peak = 0, nonzero = 0;
for (let i = 0; i + 1 < b.length; i += 2) {
  const v = Math.abs(b.readInt16LE(i));
  peak = Math.max(peak, v);
  if (v > 10) nonzero++;
}
if (peak < 100 || nonzero < 1000) {
  throw new Error(`No decoded samples in PulseAudio monitor: peak=${peak}, n=${nonzero}`);
}
console.log(`PASS virtual audio output: peak=${peak}, nonzeroSamples=${nonzero}`);
JS
