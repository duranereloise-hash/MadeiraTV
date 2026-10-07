// SPDX-License-Identifier: GPL-3.0-or-later
//
// Self-contained control panel served at /panel. No CDN, no frameworks:
// inline CSS + JS, dark theme, LAN browser tooling.

import Foundation

enum RemotePanelHTML {
    static let source = """
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>MadeiraTV Console</title>
<style>
  :root { color-scheme: dark; --bg:#0b0d10; --card:#161a20; --line:#262c35;
          --txt:#e6eaf0; --dim:#8b94a3; --acc:#4f8cff; --ok:#34c759; --warn:#ff9f0a; --err:#ff453a; }
  * { box-sizing:border-box; margin:0; padding:0; }
  body { background:var(--bg); color:var(--txt); font:14px/1.5 -apple-system,Segoe UI,Roboto,sans-serif; padding:20px; }
  h1 { font-size:20px; margin-bottom:4px; }
  .sub { color:var(--dim); margin-bottom:18px; }
  .grid { display:grid; grid-template-columns: repeat(auto-fit,minmax(320px,1fr)); gap:14px; }
  .card { background:var(--card); border:1px solid var(--line); border-radius:12px; padding:14px; }
  .card h2 { font-size:13px; text-transform:uppercase; letter-spacing:.8px; color:var(--dim); margin-bottom:10px; }
  .row { display:flex; justify-content:space-between; align-items:center; padding:5px 0; border-bottom:1px solid var(--line); }
  .row:last-child { border-bottom:none; }
  .row .k { color:var(--dim); }
  .badge { font-variant-numeric:tabular-nums; font-weight:600; }
  .ok { color:var(--ok); } .warn { color:var(--warn); } .err { color:var(--err); }
  button { background:var(--acc); color:#fff; border:none; border-radius:8px; padding:8px 12px;
           font-weight:600; cursor:pointer; }
  button.sec { background:transparent; border:1px solid var(--line); color:var(--txt); }
  button.warn-b { background:var(--warn); }
  button.err-b { background:var(--err); }
  .actions { display:flex; flex-wrap:wrap; gap:8px; margin-top:6px; }
  .toggle { display:flex; justify-content:space-between; align-items:center; padding:5px 0; }
  .toggle label { color:var(--dim); }
  textarea { width:100%; height:260px; background:#0d0f13; color:var(--txt); border:1px solid var(--line);
             border-radius:8px; padding:8px; font:12px/1.4 ui-monospace,Menlo,Consolas,monospace; resize:vertical; }
  input[type=text],select { background:#0d0f13; color:var(--txt); border:1px solid var(--line); border-radius:6px; padding:6px; }
  .btn-row { display:flex; gap:8px; margin-top:8px; align-items:center; }
  .dot { display:inline-block; width:10px; height:10px; border-radius:50%; margin-right:6px; }
</style>
</head>
<body>
<h1>🎮 MadeiraTV Console</h1>
<div class="sub" id="ip">Loading…</div>

<div class="grid">
  <div class="card">
    <h2>Status</h2>
    <div class="row"><span class="k">Process</span><span class="badge ok" id="st-health">?</span></div>
    <div class="row"><span class="k">JIT</span><span class="badge" id="st-jit">?</span></div>
    <div class="row"><span class="k">Wineserver</span><span class="badge" id="st-ws">?</span></div>
    <div class="row"><span class="k">Wine</span><span class="badge" id="st-wine">?</span></div>
    <div class="row"><span class="k">Presents (DXMT)</span><span class="badge" id="st-present">?</span></div>
    <div class="row"><span class="k">Uptime</span><span class="badge" id="st-uptime">?</span></div>
    <div class="row"><span class="k">Available mem</span><span class="badge" id="st-mem">?</span></div>
    <div class="row"><span class="k">Session</span><span class="badge" id="st-session">?</span></div>
  </div>

  <div class="card">
    <h2>Actions</h2>
    <div class="actions">
      <button onclick="act('rearm-jit')">Re-arm JIT</button>
      <button onclick="act('restart-wineserver')">Restart wineserver</button>
      <button class="warn-b" onclick="act('stop')">Stop game</button>
      <button class="sec" onclick="act('dump-vm')">Dump VM stats</button>
      <button class="sec" onclick="act('snapshot')">Snapshot logs</button>
      <button class="err-b" onclick="act('reboot-app')">Reboot app</button>
    </div>
    <div class="toggle"><label>JIT pool MB (next restart)</label>
      <select id="pool-mb"><option value="512">512</option><option value="1024">1024</option><option value="2048">2048</option></select>
    </div>
    <div class="toggle"><label>Quiet logs</label><input type="checkbox" id="quiet" onchange="saveEnv()"></div>
    <div class="toggle"><label>Verbose Wine logs</label><input type="checkbox" id="verbose" onchange="saveEnv()"></div>
    <div class="btn-row">
      <input type="text" id="appid" placeholder="Steam AppID" style="flex:1">
      <button onclick="launchByID()">Launch</button>
    </div>
  </div>

  <div class="card" style="grid-column:1/-1">
    <h2>Live log tail (/all)</h2>
    <textarea id="log" readonly spellcheck="false"></textarea>
    <div class="btn-row">
      <button class="sec" onclick="fetchLog(true)">Reload</button>
      <span class="sub" id="log-ts"></span>
    </div>
  </div>

  <div class="card" style="grid-column:1/-1">
    <h2>Crash log / Journal</h2>
    <textarea id="crash" readonly spellcheck="false" style="height:160px"></textarea>
    <div class="btn-row">
      <button class="sec" onclick="fetchCrash()">Reload crash.log</button>
      <button class="sec" onclick="fetchJournal()">Reload journal</button>
    </div>
  </div>
</div>

<script>
const API = location.origin;
let appIDs = [];

function fmt(n) { return n == null ? '-' : String(n); }
function $(id) { return document.getElementById(id); }

async function jget(path) {
  const r = await fetch(path);
  return r.json();
}

async function refreshStatus() {
  try {
    const s = await jget('/status');
    $('ip').textContent = 'Device: ' + (s.ip || '?') + ' · ' + (s.gameCount ?? '?') + ' games';
    $('st-health').textContent = s.health ? 'alive' : 'dead';
    $('st-health').className = 'badge ' + (s.health ? 'ok' : 'err');
    $('st-jit').textContent = s.jitEnabled ? 'on (offset ' + s.jitOffset + ')' : 'off';
    $('st-jit').className = 'badge ' + (s.jitEnabled ? 'ok' : 'err');
    $('st-ws').textContent = s.wineserverRunning ? 'running' : 'stopped';
    $('st-ws').className = 'badge ' + (s.wineserverRunning ? 'ok' : '');
    $('st-wine').textContent = s.wineRunning ? 'running' : 'stopped';
    $('st-wine').className = 'badge ' + (s.wineRunning ? 'ok' : '');
    $('st-present').textContent = fmt(s.presentCount);
    $('st-uptime').textContent = (s.uptimeS/60).toFixed(1) + ' min';
    $('st-mem').textContent = s.availableMemoryBytes ? Math.round(s.availableMemoryBytes/1048576) + ' MB' : '-';
    $('st-session').textContent = s.sessionActive ? 'active' : '-';

    const env = s.envOverrides || {};
    $('pool-mb').value = env['MADEIRA_JIT_POOL_MB'] || '512';
    $('quiet').checked = env['MADEIRA_QUIET'] === '1';
    $('verbose').checked = env['MADEIRA_DEBUG_VERBOSE'] === '1';
  } catch (e) { $('ip').textContent = 'offline: ' + e; }
}

async function fetchLog(force) {
  try {
    const t0 = performance.now();
    const r = await fetch('/all?ts=' + Math.random());
    const t = await r.text();
    $('log').value = t;
    $('log').scrollTop = $('log').scrollHeight;
    $('log-ts').textContent = 'updated ' + Math.round(performance.now()-t0) + 'ms';
  } catch (e) { $('log-ts').textContent = 'fetch failed'; }
}

async function fetchCrash() {
  try {
    const r = await fetch('/crash?ts=' + Math.random());
    $('crash').value = await r.text();
  } catch (e) { $('crash').value = 'failed: ' + e; }
}

async function fetchJournal() {
  try {
    const j = await jget('/journal');
    $('crash').value = JSON.stringify(j, null, 2);
  } catch (e) { $('crash').value = 'failed: ' + e; }
}

async function post(obj) {
  const r = await fetch('/action', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(obj)
  });
  return r.text();
}

function act(action) {
  post({ action }).then(t => { $('log-ts').textContent = action + ': ' + t; refreshStatus(); });
}

function launchByID() {
  const id = $('appid').value.trim();
  if (!id) return;
  post({ action: 'launch', app: Number(id) }).then(t => { $('log-ts').textContent = 'launch: ' + t; refreshStatus(); });
}

function saveEnv() {
  const env = {};
  env['MADEIRA_JIT_POOL_MB'] = $('pool-mb').value;
  env['MADEIRA_QUIET'] = $('quiet').checked ? '1' : '0';
  env['MADEIRA_DEBUG_VERBOSE'] = $('verbose').checked ? '1' : '0';
  post({ action: 'set-env', env }).then(t => $('log-ts').textContent = 'set-env: ' + t);
}

refreshStatus();
fetchLog();
fetchCrash();
setInterval(refreshStatus, 2000);
setInterval(() => fetchLog(), 2000);
</script>
</body>
</html>
"""
}