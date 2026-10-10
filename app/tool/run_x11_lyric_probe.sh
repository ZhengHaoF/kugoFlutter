#!/usr/bin/env bash
# Run inside xvfb-run -a dbus-run-session. The compositor is test-only.
set -euo pipefail
binary=$(realpath "${1:?production binary required}")
out=$(realpath -m "${2:?output required}")
mkdir -p "$out"
work=$(mktemp -d)
export XDG_RUNTIME_DIR="$work/run" XDG_DATA_HOME="$work/data" XDG_CONFIG_HOME="$work/config"
mkdir -m700 -p "$XDG_RUNTIME_DIR" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME"
export LIBGL_ALWAYS_SOFTWARE=1 NO_AT_BRIDGE=1
wm= compositor=
trap 'kill ${compositor:-} ${wm:-} 2>/dev/null || true; rm -rf "$work"' EXIT
openbox > "$out/wm.log" 2>&1 & wm=$!
if [[ "${KUGO_COMPOSITOR:-1}" == 1 ]]; then
  picom --config /dev/null --backend xrender > "$out/compositor.log" 2>&1 &
  compositor=$!
fi
g++ tool/x11_input_fixture.cc -lX11 -lXext -o "$work/underlay"
sleep 1
node tool/x11_lyric_probe.mjs "$binary" "$out" "$work/underlay" | tee "$out/probe.log"
