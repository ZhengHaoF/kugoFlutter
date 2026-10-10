// Exercise the production lyric child, using synthetic snapshots and a real
// underlying X11 window. Run through run_x11_lyric_probe.sh.
import net from 'node:net';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawn, execFileSync} from 'node:child_process';

const [binary, output, fixtureBinary] = process.argv.slice(2);
const out = path.resolve(output);
fs.mkdirSync(out, {recursive: true});
const token = crypto.randomBytes(32).toString('base64url');
const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
const command = (file, args) => execFileSync(file, args, {
  encoding: 'utf8', stdio:['ignore','pipe','pipe']
}).trim();
const scale = +(process.env.GDK_SCALE || 1);
function check(ok, name) {
  if (!ok) throw new Error(name);
  console.log(`PASS ${name}`);
}
async function until(condition, name, milliseconds = 8000) {
  const end = Date.now() + milliseconds;
  while (!(await condition())) {
    if (Date.now() >= end) throw new Error(`Timeout: ${name}`);
    await wait(100);
  }
}
function windows(pid, visible = true) {
  try {
    return command('xdotool', ['search', ...(visible ? ['--onlyvisible'] : []),
      '--pid', `${pid}`]).split('\n').filter(Boolean);
  } catch { return []; }
}
function geometry(id) {
  const values = Object.fromEntries(command('xdotool',
    ['getwindowgeometry', '--shell', id]).split('\n')
    .map(line => line.split('=')));
  return Object.fromEntries(['X','Y','WIDTH','HEIGHT'].map(key => [key, +values[key]]));
}
function screenshot(name) {
  const file = path.join(out, `${name}.png`);
  command('import', ['-window', 'root', file]);
  return file;
}
function pixel(file, x, y) {
  return command('convert', [file, '-format', `%[pixel:p{${x},${y}}]`, 'info:']);
}
const fixture = spawn(fixtureBinary, [], {stdio: ['ignore', 'pipe', 'pipe']});
let clicks = 0;
fixture.stdout.on('data', bytes => { clicks += bytes.toString().split('CLICK').length - 1; });
const childLog = fs.createWriteStream(path.join(out, 'child.log'));
let child, socket, ready = false, authenticated = false, toggleCount = 0, boundsCount = 0;
let state = {positionMs: 0, isPlaying: false, locked: false};
const lyrics = [
  {t:0, e:3000, x:'X11 透明歌词验收', c:[
    {x:'X11 ',s:0,e:800}, {x:'透明歌词',s:800,e:2400}, {x:'验收',s:2400,e:3000}
  ]},
  {t:3000,e:6000,x:'暂停定位与下一行',c:[],tr:'Offline test fixture'},
];
function snapshot(changes = {}) {
  state = {...state, ...changes};
  socket.write(JSON.stringify({t:'snapshot',d:{
    trackId:'offline-fixture', title:'X11 离线测试', artist:'Linux probe',
    durationMs:6000, lyrics, lyricsReady:true, lyricHash:42, revision:1,
    translation:true, romanization:false, fontScale:1, offsetMs:0,
    ...state
  }})+'\n');
}
const server = net.createServer(client => {
  socket = client;
  let buffer = '';
  client.on('data', bytes => {
    buffer += bytes.toString();
    for (;;) {
      const split = buffer.indexOf('\n');
      if (split < 0) break;
      const message = JSON.parse(buffer.slice(0, split));
      buffer = buffer.slice(split + 1);
      if (message.m === 'hello') {
        authenticated = message.d?.token === token;
      } else if (message.m === 'ready') {
        ready = true;
        snapshot();
      } else if (message.m === 'toggleLock') {
        toggleCount++;
        snapshot({locked: false});
      } else if (message.m === 'bounds') {
        boundsCount++;
      }
    }
  });
});
let exitCode = 0;
try {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  await until(() => windows(fixture.pid).length > 0, 'underlying window');
  const under = geometry(windows(fixture.pid)[0]);
  await wait(500);
  command('xdotool', ['windowactivate', windows(fixture.pid)[0],
    'mousemove', `${under.X+300}`, `${under.Y+100}`, 'click', '1']);
  await wait(300);
  check(clicks > 0, 'underlying click fixture records actual X11 events');
  const baseline = screenshot('baseline');
  child = spawn(path.resolve(binary),
    ['desktop_lyric', `--ipc-port=${server.address().port}`], {
      env: {...process.env, KUGO_LYRIC_PROCESS:'1', KUGO_LYRIC_IPC_TOKEN:token},
      stdio:['ignore', 'pipe', 'pipe']
    });
  child.stdout.pipe(childLog, {end:false});
  child.stderr.pipe(childLog, {end:false});
  await until(() => ready && windows(child.pid).length > 0, 'lyric ready');
  check(authenticated, 'production child authenticates before ready');
  const id = windows(child.pid)[0];
  const initial = geometry(id);
  const properties = command('xprop', ['-id', id, '_NET_WM_STATE']);
  check(properties.includes('_NET_WM_STATE_ABOVE'), 'X11 window is above');
  check(properties.includes('_NET_WM_STATE_SKIP_TASKBAR'), 'lyric skips taskbar');
  command('xdotool', ['windowmove', id, `${under.X + 100}`, `${under.Y + 70}`]);
  await wait(500);
  let g = geometry(id);
  command('xdotool', ['mousemove', '20', '700']);
  await wait(300);
  const rendered = screenshot('transparent-lyrics');
  const sample = [g.X + g.WIDTH - 10, g.Y + 10];
  const clear = pixel(baseline, ...sample) === pixel(rendered, ...sample);
  check(clear === (process.env.KUGO_COMPOSITOR !== '0'),
    clear ? 'transparent pixels reveal underlying window' : 'no-compositor card fallback');
  snapshot({isPlaying:true, positionMs:500});
  await wait(1000);
  screenshot('karaoke-progress');
  snapshot({isPlaying:false, positionMs:3500});
  await wait(300);
  screenshot('paused-seek');
  check(child.exitCode === null, 'playing and paused seek snapshots accepted');
  snapshot({style:{fontScale:2}});
  await until(() => geometry(id).HEIGHT >= 170 * scale, 'large font resize');
  screenshot('large-font');
  snapshot({style:{fontScale:1}});
  await until(() => geometry(id).HEIGHT <= 100 * scale, 'normal font restore');
  g = geometry(id);
  // Unlocked window should consume this click rather than the underlay.
  const x = g.X + 60 * scale, y = g.Y + 18 * scale;
  command('xdotool', ['mousemove', `${x}`, `${y}`, 'click', '1']);
  await wait(300);
  const before = clicks;
  snapshot({locked:true});
  command('xdotool', ['mousemove', '20', '700']);
  await wait(400);
  command('xdotool', ['windowactivate', windows(fixture.pid)[0]]);
  check(command(fixtureBinary, [id]).startsWith('0\n'),
    'locked native client has an empty X11 input region');
  command('xdotool', ['mousemove', `${x}`, `${y}`, 'click', '1']);
  await wait(300);
  check(clicks > before, 'locked lyric clicks reach actual underlying window');
  // Hover-only recovery button becomes interactive through cursor polling.
  command('xdotool', ['mousemove', `${g.X + g.WIDTH - 40*scale}`, `${g.Y + g.HEIGHT - 20*scale}`]);
  await wait(400);
  command('xdotool', ['click', '1']);
  await until(() => toggleCount > 0, 'unlock button');
  check(!state.locked, 'click-through can be unlocked from lyric control');
  command('xdotool', ['mousemove', `${x}`, `${y}`, 'mousedown', '1']);
  await wait(100);
  command('xdotool', ['mousemove', `${x + 120}`, `${y + 40}`]);
  await wait(300);
  command('xdotool', ['mouseup', '1']);
  await wait(300);
  g = geometry(id);
  check(g.X !== under.X + 100 || g.Y !== under.Y + 70, 'native drag moves lyric window');
  check(boundsCount > 0, 'native configure events report position to parent');
  socket.write('{"t":"reposition"}\n');
  await wait(300);
  g = geometry(id);
  check(Math.abs(g.X-initial.X) < 8 && Math.abs(g.Y-initial.Y) < 8,
    'reset returns lyric window to visible work area');
  socket.write('{"t":"hide"}\n');
  await until(() => windows(child.pid).length === 0, 'hide');
  socket.write('{"t":"show"}\n');
  await until(() => windows(child.pid).length > 0, 'show');
  check(child.exitCode === null, 'hide/show reuses the same lyric process');
  screenshot('final-lyrics');
  socket.destroy();
  await until(() => child.exitCode !== null, 'orphan exit', 4000);
  check(child.exitCode === 0, 'IPC disconnect exits lyric child without orphan');
  console.log('ALL_X11_LYRIC_CHECKS_PASSED');
} catch (error) {
  screenshot('failure');
  console.error(`FAIL ${error.stack}`);
  exitCode = 1;
} finally {
  socket?.destroy();
  server.close();
  child?.kill();
  fixture.kill();
  childLog.end();
}
process.exitCode = exitCode;
