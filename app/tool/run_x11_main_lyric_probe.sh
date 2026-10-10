#!/usr/bin/env bash
# Production main -> production child, with isolated persisted preferences.
# Run inside xvfb-run (1440x1000), dbus-run-session. No real accounts.
set -euo pipefail
binary=$(realpath "${1:?production binary required}")
out=$(realpath -m "${2:?output required}")
mkdir -p "$out"
work=$(mktemp -d)
export XDG_RUNTIME_DIR="$work/run" XDG_DATA_HOME="$work/data" XDG_CONFIG_HOME="$work/config"
mkdir -m700 -p "$XDG_RUNTIME_DIR" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME"
export LIBGL_ALWAYS_SOFTWARE=1 NO_AT_BRIDGE=1
main= wm= compositor=
trap 'kill ${main:-} ${compositor:-} ${wm:-} 2>/dev/null || true; rm -rf "$work"' EXIT
openbox > "$out/wm.log" 2>&1 & wm=$!
picom --config /dev/null --backend xrender > "$out/compositor.log" 2>&1 & compositor=$!
sleep 1
"$binary" > "$out/main.log" 2>&1 & main=$!
sleep 25
# Default main-window layout on this fixed virtual screen.
xdotool mousemove 157 772 click 1
sleep 2
import -window root "$out/settings.png"
xdotool mousemove 1126 661 click 1
sleep 3
lyric=$(xdotool search --onlyvisible --name '^kugo X11 lyrics$' | head -1)
node - "$out/main.log" <<'JS'
const fs=require('fs'),net=require('net');
const log=fs.readFileSync(process.argv[2],'utf8');
const port=+log.match(/spawn lyric process:.* port=(\d+)/)[1];
const socket=net.connect(port,'127.0.0.1',()=>{
  socket.write('{"t":"cmd","m":"hello","d":{"token":"invalid-probe-token"}}\n');
});
const timeout=setTimeout(()=>{socket.destroy();throw Error('Invalid IPC peer was not rejected');},4000);
socket.on('error',()=>{});
socket.on('close',()=>{
  clearTimeout(timeout);
  console.log('PASS production parent rejects invalid IPC token');
});
JS
[[ "$(xdotool search --onlyvisible --name '^kugo X11 lyrics$' | head -1)" == "$lyric" ]]
echo 'PASS invalid peer does not replace the existing lyric window'
eval "$(xdotool getwindowgeometry --shell "$lyric")"
xdotool mousemove "$((X+60))" "$((Y+20))" mousedown 1
sleep .2
xdotool mousemove "$((X+260))" "$((Y+220))"
sleep .4
xdotool mouseup 1
sleep 1
eval "$(xdotool getwindowgeometry --shell "$lyric")"
old_x=$X old_y=$Y
preferences="$XDG_DATA_HOME/com.kugo.kugo/shared_preferences.json"
node - "$preferences" "$old_x" "$old_y" <<'JS'
const fs=require('fs');
const p=JSON.parse(fs.readFileSync(process.argv[2]));
const x=+process.argv[3],y=+process.argv[4];
const key=s=>Object.keys(p).find(k=>k.endsWith(s));
if(Math.abs(p[key('desktopLyric.bounds.x')]-x)>3 ||
   Math.abs(p[key('desktopLyric.bounds.y')]-y)>3)
  throw new Error('Native drag position not persisted');
console.log('PASS production parent persists native drag position');
JS
import -window root "$out/main-with-lyrics.png"
# Parent termination must close IPC and remove the child, not leave an orphan.
kill "$main"; wait "$main" || true; main=
sleep 2
if xdotool search --onlyvisible --name '^kugo X11 lyrics$' >/dev/null 2>&1; then
  echo 'FAIL child survived parent'; exit 1
fi
echo 'PASS production child exits when parent stops'
"$binary" > "$out/restarted-main.log" 2>&1 & main=$!
sleep 25
lyric=$(xdotool search --onlyvisible --name '^kugo X11 lyrics$' | head -1)
eval "$(xdotool getwindowgeometry --shell "$lyric")"
[[ "$X" == "$old_x" && "$Y" == "$old_y" ]]
echo 'PASS production restart restores saved lyric position and enabled setting'
import -window root "$out/restarted-main.png"
child_pid=$(xprop -id "$lyric" _NET_WM_PID | awk '{print $NF}')
kill "$child_pid"
sleep 2
node - "$preferences" <<'JS'
const fs=require('fs');
const p=JSON.parse(fs.readFileSync(process.argv[2]));
const key=Object.keys(p).find(k=>k.endsWith('settings.desktopLyricEnabled'));
if(p[key]!==false)throw Error('Child failure left enabled setting true');
console.log('PASS production child failure resets enabled setting');
JS
echo 'ALL_MAIN_LYRIC_CHECKS_PASSED'
