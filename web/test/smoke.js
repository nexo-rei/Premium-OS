#!/usr/bin/env node
/*============================================================================
 * Premium-OS :: web/test/smoke.js
 * End-to-end dashboard smoke test: REST + WebSocket, zero deps.
 *   node test/smoke.js        (spawns the server on a random port)
 *==========================================================================*/
'use strict';

const { spawn } = require('child_process');
const http = require('http');
const crypto = require('crypto');
const net = require('net');
const os = require('os');
const fs = require('fs');
const path = require('path');

const PORT = 8090 + Math.floor(Math.random() * 500);
const POS_HOME = fs.mkdtempSync(path.join(os.tmpdir(), 'pos-web-test-'));

let passed = 0, failed = 0;
const ok = (cond, name) => {
    if (cond) { passed++; console.log(`  ✔ ${name}`); }
    else { failed++; console.error(`  ✖ ${name}`); }
};

function request(method, pathName, body) {
    return new Promise((resolve, reject) => {
        const data = body ? JSON.stringify(body) : null;
        const req = http.request({
            host: '127.0.0.1', port: PORT, path: pathName, method,
            headers: { 'Content-Type': 'application/json',
                       ...(data ? { 'Content-Length': Buffer.byteLength(data) } : {}) }
        }, (res) => {
            let buf = '';
            res.on('data', (c) => buf += c);
            res.on('end', () => {
                let json = null;
                try { json = JSON.parse(buf); } catch {}
                resolve({ status: res.statusCode, body: json, raw: buf });
            });
        });
        req.on('error', reject);
        if (data) req.write(data);
        req.end();
    });
}

/*──────── WebSocket client (handshake + text frames) ────────*/
function wsCollect(frames, ms) {
    return new Promise((resolve, reject) => {
        const key = crypto.randomBytes(16).toString('base64');
        const sock = net.connect(PORT, '127.0.0.1', () => {
            sock.write(
                `GET /ws HTTP/1.1\r\nHost: 127.0.0.1:${PORT}\r\n` +
                `Upgrade: websocket\r\nConnection: Upgrade\r\n` +
                `Sec-WebSocket-Key: ${key}\r\nSec-WebSocket-Version: 13\r\n\r\n`
            );
        });
        let shook = false;
        const got = [];
        sock.on('data', (buf) => {
            if (!shook) {
                const text = buf.toString('utf8');
                const idx = text.indexOf('\r\n\r\n');
                if (idx !== -1) {
                    shook = text.startsWith('HTTP/1.1 101');
                    buf = buf.slice(idx + 4);
                    if (!buf.length) return;
                } else return;
            }
            // parse text frames (server frames are unmasked)
            let off = 0;
            while (off + 2 <= buf.length) {
                const len = buf[off + 1] & 0x7f;
                // tests only receive small/126 frames; handle both
                let header = 2, realLen = len;
                if (len === 126) { if (off + 4 > buf.length) break; realLen = buf.readUInt16BE(off + 2); header = 4; }
                if (off + header + realLen > buf.length) break;
                const payload = buf.slice(off + header, off + header + realLen).toString('utf8');
                try { got.push(JSON.parse(payload)); } catch {}
                off += header + realLen;
            }
        });
        sock.on('error', reject);
        setTimeout(() => { sock.destroy(); resolve({ shook, got }); }, ms);
    });
}

(async () => {
    console.log('◢◤ Premium-OS web smoke test');
    console.log(`  POS_HOME=${POS_HOME} PORT=${PORT}`);

    // Seed data dir like pos_init would
    fs.mkdirSync(path.join(POS_HOME, 'profiles'), { recursive: true });
    fs.writeFileSync(path.join(POS_HOME, 'profiles', 'default.json'),
        JSON.stringify({ name: 'default', theme: { name: 'dark' }, shell: 'bash' }));

    const srv = spawn(process.execPath, [path.join(__dirname, '..', 'server.js')], {
        env: { ...process.env, PORT: String(PORT), HOST: '127.0.0.1', POS_HOME },
        stdio: ['ignore', 'pipe', 'pipe']
    });
    srv.stderr.on('data', (d) => process.stderr.write(`[srv] ${d}`));
    await new Promise((r) => setTimeout(r, 800));

    try {
        const health = await request('GET', '/api/health');
        ok(health.status === 200 && health.body.ok, 'GET /api/health');

        const prof = await request('GET', '/api/profiles');
        ok(Array.isArray(prof.body) && prof.body.length >= 1, 'GET /api/profiles');

        const create = await request('POST', '/api/profiles', { name: 'smoke' });
        ok(create.status === 201, 'POST /api/profiles');

        const badName = await request('POST', '/api/profiles', { name: '../evil' });
        ok(badName.status === 400, 'POST /api/profiles rejects traversal name');

        const sw = await request('POST', '/api/profiles/smoke/switch');
        ok(sw.body.active === 'smoke', 'POST /api/profiles/:id/switch');

        const themes = await request('GET', '/api/themes');
        ok(Array.isArray(themes.body) && themes.body.length >= 5, 'GET /api/themes (5 presets)');

        const perf = await request('GET', '/api/performance');
        ok(typeof perf.body.ram.percent === 'number', 'GET /api/performance');

        const snip = await request('POST', '/api/snippets', { name: 's1', command: 'echo hi' });
        ok(snip.status === 201 && snip.body.id >= 1, 'POST /api/snippets');

        const snipPut = await request('PUT', `/api/snippets/${snip.body.id}`, { name: 's1-renamed' });
        ok(snipPut.body.name === 's1-renamed', 'PUT /api/snippets/:id');

        const hk = await request('POST', '/api/hotkeys', { key: 'Ctrl+Alt+Z', command: 'zzz' });
        ok(hk.status === 201, 'POST /api/hotkeys');
        const hkDup = await request('POST', '/api/hotkeys', { key: 'Ctrl+Alt+Z', command: 'dup' });
        ok(hkDup.status === 400, 'hotkey conflict rejected');
        const hkDel = await request('DELETE', `/api/hotkeys/${encodeURIComponent('Ctrl+Alt+Z')}`);
        ok(hkDel.status === 200, 'DELETE /api/hotkeys/:id');

        const setRes = await request('PUT', '/api/settings', { set: 'ui.animations', value: false });
        ok(setRes.status === 200, 'PUT /api/settings (dot-set)');
        const getSet = await request('GET', '/api/settings');
        ok(getSet.body.ui.animations === false, 'settings persisted');

        const plug = await request('POST', '/api/plugins', {
            manifest: { name: 'smoke-plugin', version: '1.0.0', author: 't',
                        description: 't', hooks: [], permissions: [] },
            plugin: 'plugin_on_event() { :; }'
        });
        ok(plug.status === 201, 'POST /api/plugins (inline install)');
        const plugDel = await request('DELETE', '/api/plugins/smoke-plugin');
        ok(plugDel.status === 200, 'DELETE /api/plugins/:id');

        const danger = await request('POST', '/api/plugins', {
            manifest: { name: 'bad', version: '1', author: 't', description: 't' },
            plugin: 'rm -rf /'
        });
        ok(danger.status === 400, 'dangerous plugin rejected');

        const backup = await request('POST', '/api/backup', {});
        ok(backup.status === 201 && backup.body.file.endsWith('.poz'), 'POST /api/backup');
        const backups = await request('GET', '/api/backups');
        ok(backups.body.length >= 1, 'GET /api/backups');

        const index = await request('GET', '/');
        ok(index.status === 200 && index.raw.includes('Premium-OS'), 'GET / serves dashboard');
        const css = await request('GET', '/styles.css');
        ok(css.status === 200, 'GET /styles.css');
        const trav = await request('GET', '/%2e%2e/%2e%2e/etc/passwd');
        ok(trav.status !== 200 || !String(trav.raw).includes('root:'), 'path traversal blocked');

        // WebSocket: expect connected + at least one performance:update
        const ws = await wsCollect(3, 2800);
        ok(ws.shook, 'WebSocket handshake 101');
        ok(ws.got.some((m) => m.event === 'connected'), 'WS connected event');
        ok(ws.got.some((m) => m.event === 'performance:update'), 'WS performance:update broadcast');
    } catch (e) {
        failed++;
        console.error('  ✖ unexpected:', e.message);
    } finally {
        srv.kill();
        fs.rmSync(POS_HOME, { recursive: true, force: true });
    }

    console.log(`\n  ${passed} passed · ${failed} failed`);
    process.exit(failed === 0 ? 0 : 1);
})();
