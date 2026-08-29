/*============================================================================
 * Premium-OS :: web/routes/api.js
 * REST API — pure Node implementation over the shared ~/.premium-os data dir.
 * Endpoints (all JSON):
 *   GET/POST           /api/profiles
 *   GET/PUT/DELETE     /api/profiles/:id        POST /api/profiles/:id/switch
 *   GET/POST           /api/themes              GET/DELETE /api/themes/:id
 *   GET                /api/performance         /api/performance/history
 *   POST               /api/backup              GET /api/backups
 *   POST               /api/restore
 *   GET/POST           /api/snippets
 *   PUT/DELETE         /api/snippets/:id
 *   GET/POST           /api/hotkeys             DELETE /api/hotkeys/:id
 *   GET/PUT            /api/settings
 *   GET/POST           /api/plugins             DELETE /api/plugins/:id
 *   GET                /api/health
 *==========================================================================*/
'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFile } = require('child_process');

const POS_HOME = process.env.POS_HOME || path.join(os.homedir(), '.premium-os');
const REPO_ROOT = path.resolve(__dirname, '..', '..');
const BUILTIN_THEMES_DIR = path.join(REPO_ROOT, 'config', 'themes');

//------------------------------------------------------------
// Helpers
//------------------------------------------------------------
function readJSON(file, fallback) {
    try { return JSON.parse(fs.readFileSync(file, 'utf8')); }
    catch { return fallback; }
}
function writeJSON(file, obj) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, JSON.stringify(obj, null, 2) + '\n', { mode: 0o600 });
    try { fs.chmodSync(file, 0o600); } catch {}
}
function isSafeName(name) {
    return typeof name === 'string' && /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(name);
}
function send(res, code, obj) {
    const body = JSON.stringify(obj);
    res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(body);
}
function notFound(res, msg = 'not found') { send(res, 404, { error: msg }); }
function badReq(res, msg) { send(res, 400, { error: msg }); }

function readBody(req) {
    return new Promise((resolve, reject) => {
        let data = '';
        req.on('data', (chunk) => {
            data += chunk;
            if (data.length > 1e6) { reject(new Error('payload too large')); req.destroy(); }
        });
        req.on('end', () => {
            if (!data) return resolve({});
            try { resolve(JSON.parse(data)); } catch { reject(new Error('invalid JSON')); }
        });
        req.on('error', reject);
    });
}

function dotGet(obj, dotted) {
    return dotted.split('.').reduce((o, k) => (o && o[k] !== undefined) ? o[k] : undefined, obj);
}
function dotSet(obj, dotted, value) {
    const keys = dotted.split('.');
    const last = keys.pop();
    const target = keys.reduce((o, k) => {
        if (typeof o[k] !== 'object' || o[k] === null) o[k] = {};
        return o[k];
    }, obj);
    target[last] = value;
    return obj;
}

//------------------------------------------------------------
// Profiles
//------------------------------------------------------------
const profilesDir = () => path.join(POS_HOME, 'profiles');
const settingsFile = () => path.join(POS_HOME, 'settings.json');

function listProfiles() {
    try {
        return fs.readdirSync(profilesDir())
            .filter((f) => f.endsWith('.json'))
            .map((f) => {
                const p = readJSON(path.join(profilesDir(), f), {});
                return { id: path.basename(f, '.json'), name: p.name || path.basename(f, '.json'),
                         theme: dotGet(p, 'theme.name'), shell: p.shell };
            });
    } catch { return []; }
}

function routeProfiles(req, res, parts, body) {
    const [id, sub] = parts;
    if (!id) {
        if (req.method === 'GET') return send(res, 200, listProfiles());
        if (req.method === 'POST') {
            if (!isSafeName(body.name)) return badReq(res, 'invalid profile name');
            const file = path.join(profilesDir(), body.name + '.json');
            if (fs.existsSync(file)) return badReq(res, 'profile exists');
            const template = readJSON(path.join(profilesDir(), 'default.json'), {});
            const profile = Object.assign({}, template, body, { name: body.name,
                created: new Date().toISOString() });
            writeJSON(file, profile);
            return send(res, 201, { ok: true, id: body.name });
        }
    }
    const file = path.join(profilesDir(), (id || '') + '.json');
    if (id && !fs.existsSync(file)) return notFound(res, 'profile not found');

    if (sub === 'switch' && req.method === 'POST') {
        const s = readJSON(settingsFile(), {});
        s.active_profile = id;
        writeJSON(settingsFile(), s);
        broadcast('profile:switched', { id });
        return send(res, 200, { ok: true, active: id });
    }
    switch (req.method) {
        case 'GET':    return send(res, 200, readJSON(file, {}));
        case 'PUT':    return body && typeof body === 'object'
            ? (writeJSON(file, Object.assign({}, readJSON(file, {}), body, { name: id })),
               send(res, 200, { ok: true }))
            : badReq(res, 'object body required');
        case 'DELETE':
            if (id === 'default') return badReq(res, 'default profile is protected');
            fs.unlinkSync(file);
            return send(res, 200, { ok: true });
    }
    return badReq(res, 'unsupported method');
}

//------------------------------------------------------------
// Themes (read-only built-ins + writable user themes)
//------------------------------------------------------------
function themeDirs() {
    return [BUILTIN_THEMES_DIR, path.join(POS_HOME, 'themes')];
}
function listThemes() {
    const out = [];
    for (const dir of themeDirs()) {
        try {
            for (const f of fs.readdirSync(dir)) {
                if (!f.endsWith('.json')) continue;
                const t = readJSON(path.join(dir, f), null);
                if (t && t.name) out.push({
                    id: path.basename(f, '.json'), name: t.name,
                    custom: dir !== BUILTIN_THEMES_DIR,
                    colors: t.colors, font: t.font, gradient: t.gradient
                });
            }
        } catch {}
    }
    return out;
}
function findThemeFile(id) {
    if (!isSafeName(id)) return null;
    for (const dir of themeDirs()) {
        const f = path.join(dir, id + '.json');
        if (fs.existsSync(f)) return f;
    }
    return null;
}

function routeThemes(req, res, parts, body) {
    const id = parts[0];
    if (!id) {
        if (req.method === 'GET') return send(res, 200, listThemes());
        if (req.method === 'POST') {
            if (!isSafeName(body.name)) return badReq(res, 'invalid theme name');
            const file = path.join(POS_HOME, 'themes', body.name + '.json');
            writeJSON(file, body);
            return send(res, 201, { ok: true, id: body.name });
        }
    }
    const file = findThemeFile(id);
    if (!file) return notFound(res, 'theme not found');
    if (req.method === 'GET') return send(res, 200, readJSON(file, {}));
    if (req.method === 'DELETE') {
        if (!file.startsWith(POS_HOME)) return badReq(res, 'built-in themes are read-only');
        fs.unlinkSync(file);
        return send(res, 200, { ok: true });
    }
    return badReq(res, 'unsupported method');
}

//------------------------------------------------------------
// Performance — direct /proc reads, no shell dependency
//------------------------------------------------------------
let prevCpu = null;
function cpuPercent() {
    try {
        const line = fs.readFileSync('/proc/stat', 'utf8').split('\n')[0];
        const parts = line.trim().split(/\s+/).slice(1).map(Number);
        const idle = parts[3] + parts[4];
        const total = parts.reduce((a, b) => a + b, 0);
        if (prevCpu) {
            const dIdle = idle - prevCpu.idle, dTotal = total - prevCpu.total;
            prevCpu = { idle, total };
            if (dTotal > 0) return Math.round((1 - dIdle / dTotal) * 100);
        }
        prevCpu = { idle, total };
        return null; // first sample — percentage needs two reads
    } catch { return 0; }
}
function memInfo() {
    try {
        const raw = fs.readFileSync('/proc/meminfo', 'utf8');
        const total = Number((raw.match(/MemTotal:\s+(\d+)/) || [])[1] || 0) / 1024;
        const avail = Number((raw.match(/MemAvailable:\s+(\d+)/) || [])[1] || 0) / 1024;
        return { totalMB: Math.round(total), usedMB: Math.round(total - avail),
                 percent: total ? Math.round((total - avail) * 100 / total) : 0 };
    } catch { return { totalMB: 0, usedMB: 0, percent: 0 }; }
}
function processCount() {
    try { return fs.readdirSync('/proc').filter((e) => /^\d+$/.test(e)).length; }
    catch { return 0; }
}
function readPerf() {
    const mem = memInfo();
    let upSession = Math.round(process.uptime());
    let upSystem = 0;
    try { upSystem = Math.round(Number(fs.readFileSync('/proc/uptime', 'utf8').split(' ')[0])); } catch {}
    return {
        cpu: cpuPercent(),          // may be null on very first poll
        ram: mem,
        processes: processCount(),
        uptime: { session: upSession, system: upSystem },
        timestamp: Date.now()
    };
}

function routePerformance(req, res, parts) {
    if (parts[0] === 'history') {
        const histFile = path.join(POS_HOME, 'history', 'perf',
            new Date().toISOString().slice(0, 10) + '.csv');
        let rows = [];
        try {
            rows = fs.readFileSync(histFile, 'utf8').trim().split('\n')
                .map((l) => l.split(',').map(Number))
                .filter((r) => r.length >= 3)
                .map(([epoch, cpu, ram]) => ({ epoch, cpu, ram }));
        } catch {}
        return send(res, 200, rows.slice(-1000));
    }
    const cur = readPerf();
    // Guarantee a real cpu% by sampling twice if the first was null
    if (cur.cpu === null) {
        const t0 = process.hrtime.bigint();
        while (Number(process.hrtime.bigint() - t0) / 1e6 < 60) {} // 60ms spin (dashboard-local)
        cur.cpu = cpuPercent();
    }
    return send(res, 200, cur);
}

//------------------------------------------------------------
// Backups — delegate to tar for container compatibility with .poz
//------------------------------------------------------------
function listBackups() {
    const dir = path.join(POS_HOME, 'backups');
    try {
        return fs.readdirSync(dir).filter((f) => f.endsWith('.poz'))
            .map((f) => {
                const st = fs.statSync(path.join(dir, f));
                return { file: f, size: st.size, mtime: st.mtime.toISOString() };
            })
            .sort((a, b) => b.mtime.localeCompare(a.mtime));
    } catch { return []; }
}
function runTar(args, cwd) {
    return new Promise((resolve, reject) => {
        execFile('tar', args, { cwd, timeout: 30000 },
            (err) => err ? reject(err) : resolve());
    });
}

async function routeBackups(req, res, parts, body) {
    const backupsDir = path.join(POS_HOME, 'backups');
    fs.mkdirSync(backupsDir, { recursive: true });

    if (parts[0] === 'restore' && req.method === 'POST') {
        const file = body && body.file;
        if (typeof file !== 'string' || file.includes('/') || !file.endsWith('.poz'))
            return badReq(res, 'invalid file');
        const full = path.join(backupsDir, file);
        if (!fs.existsSync(full)) return notFound(res, 'backup not found');
        const stage = path.join(POS_HOME, 'tmp', 'restore-' + Date.now());
        fs.mkdirSync(stage, { recursive: true });
        try {
            await runTar(['-xzf', full, '-C', stage]);
            const dataDir = path.join(stage, 'data');
            if (fs.existsSync(dataDir)) {
                for (const entry of fs.readdirSync(dataDir)) {
                    fs.cpSync(path.join(dataDir, entry), path.join(POS_HOME, entry), { recursive: true });
                }
            }
            broadcast('restore:complete', { file });
            return send(res, 200, { ok: true });
        } catch (e) {
            return send(res, 500, { error: 'restore failed: ' + e.message });
        } finally {
            fs.rmSync(stage, { recursive: true, force: true });
        }
    }

    if (req.method === 'GET') return send(res, 200, listBackups());

    if (req.method === 'POST') {
        const ts = new Date().toISOString().replace(/[:T]/g, '-').replace(/\..+/, '');
        const stage = path.join(POS_HOME, 'tmp', 'bundle-' + Date.now());
        fs.mkdirSync(path.join(stage, 'data'), { recursive: true });
        try {
            fs.writeFileSync(path.join(stage, 'manifest.json'), JSON.stringify({
                format: 'poz', poz_version: 1, created: new Date().toISOString(),
                encrypted: false
            }, null, 2));
            for (const item of ['profiles', 'themes']) {
                const src = path.join(POS_HOME, item);
                if (fs.existsSync(src)) fs.cpSync(src, path.join(stage, 'data', item), { recursive: true });
            }
            for (const item of ['settings.json', 'snippets.json', 'hotkeys.conf']) {
                const src = path.join(POS_HOME, item);
                if (fs.existsSync(src)) fs.copyFileSync(src, path.join(stage, 'data', item));
            }
            const out = path.join(backupsDir, `backup-${ts}.poz`);
            await runTar(['-czf', out, '-C', stage, '.']);
            broadcast('backup:created', { file: path.basename(out) });
            return send(res, 201, { ok: true, file: path.basename(out) });
        } catch (e) {
            return send(res, 500, { error: 'backup failed: ' + e.message });
        } finally {
            fs.rmSync(stage, { recursive: true, force: true });
        }
    }
    return badReq(res, 'unsupported method');
}

//------------------------------------------------------------
// Snippets
//------------------------------------------------------------
const snippetsFile = () => path.join(POS_HOME, 'snippets.json');
function routeSnippets(req, res, parts, body) {
    const store = readJSON(snippetsFile(), { snippets: [] });
    const id = parts[0] ? Number(parts[0]) : null;

    if (id === null || Number.isNaN(id)) {
        if (req.method === 'GET') return send(res, 200, store.snippets || []);
        if (req.method === 'POST') {
            if (!body.name || !body.command) return badReq(res, 'name and command required');
            const nextId = (store.snippets || []).reduce((m, s) => Math.max(m, s.id || 0), 0) + 1;
            const snip = { id: nextId, category: body.category || 'General',
                           name: body.name, command: body.command };
            store.snippets = store.snippets || [];
            store.snippets.push(snip);
            writeJSON(snippetsFile(), store);
            return send(res, 201, snip);
        }
    }
    const idx = (store.snippets || []).findIndex((s) => s.id === id);
    if (idx === -1) return notFound(res, 'snippet not found');

    if (req.method === 'PUT') {
        store.snippets[idx] = Object.assign({}, store.snippets[idx], body, { id });
        writeJSON(snippetsFile(), store);
        return send(res, 200, store.snippets[idx]);
    }
    if (req.method === 'DELETE') {
        store.snippets.splice(idx, 1);
        writeJSON(snippetsFile(), store);
        return send(res, 200, { ok: true });
    }
    return badReq(res, 'unsupported method');
}

//------------------------------------------------------------
// Hotkeys
//------------------------------------------------------------
const hotkeysFile = () => path.join(POS_HOME, 'hotkeys.conf');
function readHotkeys() {
    const map = [];
    try {
        for (const line of fs.readFileSync(hotkeysFile(), 'utf8').split('\n')) {
            if (!line || line.startsWith('#') || !line.includes('=')) continue;
            const i = line.indexOf('=');
            map.push({ key: line.slice(0, i), command: line.slice(i + 1) });
        }
    } catch {}
    return map;
}
function writeHotkeys(list) {
    const data = '# Premium-OS hotkey bindings\n' +
        list.map((h) => `${h.key}=${h.command}`).join('\n') + '\n';
    fs.mkdirSync(path.dirname(hotkeysFile()), { recursive: true });
    fs.writeFileSync(hotkeysFile(), data, { mode: 0o600 });
}

function routeHotkeys(req, res, parts, body) {
    const list = readHotkeys();
    const id = decodeURIComponent(parts[0] || '');
    if (!id) {
        if (req.method === 'GET') return send(res, 200, list);
        if (req.method === 'POST') {
            if (!body.key || !body.command) return badReq(res, 'key and command required');
            if (list.some((h) => h.key === body.key))
                return badReq(res, `conflict: ${body.key} already bound`);
            list.push({ key: body.key, command: body.command });
            writeHotkeys(list);
            return send(res, 201, { ok: true });
        }
    }
    const idx = list.findIndex((h) => h.key === id);
    if (idx === -1) return notFound(res, 'hotkey not found');
    if (req.method === 'DELETE') {
        list.splice(idx, 1);
        writeHotkeys(list);
        return send(res, 200, { ok: true });
    }
    return badReq(res, 'unsupported method');
}

//------------------------------------------------------------
// Settings
//------------------------------------------------------------
function routeSettings(req, res, body) {
    if (req.method === 'GET') return send(res, 200, readJSON(settingsFile(), {}));
    if (req.method === 'PUT') {
        if (!body || typeof body !== 'object') return badReq(res, 'object body required');
        const cur = readJSON(settingsFile(), {});
        if (body.set && body.value !== undefined) {
            // {set:"ui.animations", value:false} surgical update
            dotSet(cur, body.set, body.value);
        } else {
            // shallow merge
            Object.assign(cur, body);
        }
        writeJSON(settingsFile(), cur);
        return send(res, 200, { ok: true });
    }
    return badReq(res, 'unsupported method');
}

//------------------------------------------------------------
// Plugins
//------------------------------------------------------------
function routePlugins(req, res, parts, body) {
    const dir = path.join(POS_HOME, 'plugins');
    const id = parts[0];
    if (!id) {
        if (req.method === 'GET') {
            const out = [];
            try {
                for (const d of fs.readdirSync(dir)) {
                    const mf = path.join(dir, d, 'manifest.json');
                    if (!fs.existsSync(mf)) continue;
                    const m = readJSON(mf, {});
                    out.push({ id: d, name: m.name || d, version: m.version || '?',
                               description: m.description || '',
                               enabled: !fs.existsSync(path.join(dir, d, '.disabled')) });
                }
            } catch {}
            return send(res, 200, out);
        }
        if (req.method === 'POST') {
            // body = {manifest:{...}, plugin:"source code"} — simple inline install
            if (!body.manifest || !body.plugin) return badReq(res, 'manifest and plugin required');
            const name = String(body.manifest.name || '')
                .toLowerCase().replace(/[^a-z0-9-]+/g, '-');
            if (!isSafeName(name)) return badReq(res, 'invalid plugin name');
            const dest = path.join(dir, name);
            if (fs.existsSync(dest)) return badReq(res, 'plugin exists');
            const dangerous = ['rm -rf /', 'rm -rf ~', 'mkfs', 'dd if=', ':(){ :|:& };:'];
            if (dangerous.some((p) => String(body.plugin).includes(p)))
                return badReq(res, 'plugin rejected: dangerous code pattern');
            fs.mkdirSync(dest, { recursive: true });
            writeJSON(path.join(dest, 'manifest.json'), body.manifest);
            fs.writeFileSync(path.join(dest, 'plugin.sh'), String(body.plugin));
            broadcast('plugin:installed', { id: name });
            return send(res, 201, { ok: true, id: name });
        }
    }
    if (id) {
        const dest = path.join(dir, id);
        if (!id.includes('..') && fs.existsSync(dest)) {
            if (req.method === 'DELETE') {
                fs.rmSync(dest, { recursive: true, force: true });
                return send(res, 200, { ok: true });
            }
        }
        return notFound(res, 'plugin not found');
    }
    return badReq(res, 'unsupported method');
}

//------------------------------------------------------------
// WebSocket broadcast hook (wired by routes/websocket.js)
//------------------------------------------------------------
let broadcast = () => {};
function setBroadcaster(fn) { broadcast = fn; }

//------------------------------------------------------------
// Top-level router
//------------------------------------------------------------
async function apiRouter(req, res, parsed) {
    const parts = parsed.pathname.replace(/^\/api\//, '').split('/').filter(Boolean);
    const seg = parts[0];
    let body = {};
    if (['POST', 'PUT', 'PATCH', 'DELETE'].includes(req.method)) {
        try { body = await readBody(req); }
        catch (e) { return badReq(res, e.message); }
    }
    try {
        switch (seg) {
            case 'health':      return send(res, 200, { ok: true, version: '1.0.0' });
            case 'profiles':    return routeProfiles(req, res, parts.slice(1), body);
            case 'themes':      return routeThemes(req, res, parts.slice(1), body);
            case 'performance': return routePerformance(req, res, parts.slice(1));
            case 'backup':      return routeBackups(req, res, ['backup'], body);
            case 'backups':     return routeBackups(req, res, [], body);
            case 'restore':     return routeBackups(req, res, ['restore'], body);
            case 'snippets':    return routeSnippets(req, res, parts.slice(1), body);
            case 'hotkeys':     return routeHotkeys(req, res, parts.slice(1), body);
            case 'settings':    return routeSettings(req, res, body);
            case 'plugins':     return routePlugins(req, res, parts.slice(1), body);
            default:            return notFound(res, 'unknown endpoint');
        }
    } catch (e) {
        send(res, 500, { error: 'internal: ' + e.message });
    }
}

apiRouter.POS_HOME = POS_HOME;
apiRouter.readPerf = readPerf;
apiRouter.setBroadcaster = setBroadcaster;
module.exports = apiRouter;
