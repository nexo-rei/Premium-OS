/*============================================================================
 * Premium-OS :: app.js — dashboard frontend (vanilla JS, no frameworks)
 *==========================================================================*/
'use strict';

/*──────── REST helpers ────────*/
const api = {
    async req(method, path, body) {
        const init = { method, headers: { 'Content-Type': 'application/json' } };
        if (body !== undefined) init.body = JSON.stringify(body);
        const res = await fetch('/api' + path, init);
        const data = await res.json().catch(() => ({}));
        if (!res.ok) throw new Error(data.error || res.statusText);
        return data;
    },
    get: (p) => api.req('GET', p),
    post: (p, b) => api.req('POST', p, b),
    put: (p, b) => api.req('PUT', p, b),
    del: (p) => api.req('DELETE', p)
};

/*──────── Toasts ────────*/
function toast(msg, type = 'ok', ms = 3200) {
    const box = document.getElementById('toasts');
    const el = document.createElement('div');
    el.className = `toast ${type === 'ok' ? '' : type}`;
    el.textContent = msg;
    box.appendChild(el);
    setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 320); }, ms);
}

/*──────── SPA navigation ────────*/
function goto(view) {
    document.querySelectorAll('.view').forEach((v) => v.classList.toggle('active', v.id === `view-${view}`));
    document.querySelectorAll('.nav-item').forEach((n) => n.classList.toggle('active', n.dataset.view === view));
    document.querySelectorAll('.bn-item').forEach((n) => n.classList.toggle('active', n.dataset.view === view));
    window.scrollTo({ top: 0, behavior: 'smooth' });
    loadView(view);
}
document.querySelectorAll('[data-view]').forEach((b) => b.addEventListener('click', () => goto(b.dataset.view)));
document.querySelectorAll('[data-goto]').forEach((b) => b.addEventListener('click', () => goto(b.dataset.goto)));

/*──────── WebSocket (live updates with reconnect) ────────*/
const perfSeries = { cpu: [], ram: [] };
const SERIES_MAX = 120;
let wsOk = false;

function connectWS() {
    const proto = location.protocol === 'https:' ? 'wss' : 'ws';
    const ws = new WebSocket(`${proto}://${location.host}/ws`);
    const chip = document.getElementById('hdr-ws');

    ws.onopen = () => {
        wsOk = true;
        chip.textContent = '● live';
        chip.classList.remove('off');
        ws.send(JSON.stringify({ type: 'subscribe', channel: 'performance' }));
    };
    ws.onclose = () => {
        wsOk = false;
        chip.textContent = '○ offline';
        chip.classList.add('off');
        setTimeout(connectWS, 3000); // graceful reconnect
    };
    ws.onerror = () => ws.close();
    ws.onmessage = (ev) => {
        let msg; try { msg = JSON.parse(ev.data); } catch { return; }
        switch (msg.event) {
            case 'performance:update': onPerf(msg.data); break;
            case 'profile:switched':
                toast(`Profile switched → ${msg.data.id}`);
                refreshProfileChip(); break;
            case 'backup:created': toast(`Backup created: ${msg.data.file}`); loadBackups(); break;
            case 'restore:complete': toast(`Restored: ${msg.data.file}`, 'warn'); break;
            case 'plugin:installed': toast(`Plugin installed: ${msg.data.id}`); loadPlugins(); break;
        }
    };
}

function onPerf(p) {
    const cpu = p.cpu ?? 0;
    const ramPct = p.ram?.percent ?? 0;
    setGauge('gauge-cpu', cpu);
    setGauge('gauge-ram', ramPct);
    document.getElementById('ram-detail').textContent =
        p.ram ? `${p.ram.usedMB} / ${p.ram.totalMB} MB` : '—';
    document.getElementById('procs-val').textContent = p.processes ?? '—';
    document.getElementById('uptime-val').textContent = fmtUptime(p.uptime?.session);
    document.getElementById('uptime-sys').textContent = `system ${fmtUptime(p.uptime?.system)}`;
    pushSeries(perfSeries.cpu, cpu);
    pushSeries(perfSeries.ram, ramPct);
    drawChart('chart-live', perfSeries);
    drawChart('chart-perf', perfSeries);
}

function pushSeries(arr, v) { arr.push(v); if (arr.length > SERIES_MAX) arr.shift(); }
function fmtUptime(sec) {
    if (sec == null) return '—';
    const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60);
    return `${h}h ${String(m).padStart(2, '0')}m`;
}

/*──────── Gauges ────────*/
function setGauge(id, pct) {
    const g = document.getElementById(id);
    if (!g) return;
    g.style.setProperty('--pct', pct);
    g.dataset.pct = String(pct);
    g.classList.toggle('warm', pct >= 60 && pct < 85);
    g.classList.toggle('hot', pct >= 85);
    g.querySelector('.gauge-num').textContent = `${pct}%`;
}

/*──────── Canvas charts (gradient lines, zero lib) ────────*/
function drawChart(canvasId, series) {
    const c = document.getElementById(canvasId);
    if (!c || !c.offsetParent) return;
    const ctx = c.getContext('2d');
    const W = (c.width = c.clientWidth * devicePixelRatio);
    const H = (c.height = c.clientHeight * devicePixelRatio);
    ctx.clearRect(0, 0, W, H);

    const drawLine = (data, color, fill) => {
        if (data.length < 2) return;
        const step = W / (SERIES_MAX - 1);
        const off = SERIES_MAX - data.length;
        ctx.beginPath();
        data.forEach((v, i) => {
            const x = (i + off) * step, y = H - (v / 100) * (H - 8) - 4;
            i ? ctx.lineTo(x, y) : ctx.moveTo(x, y);
        });
        ctx.strokeStyle = color; ctx.lineWidth = 2 * devicePixelRatio; ctx.stroke();
        if (fill) {
            ctx.lineTo((data.length - 1 + off) * step, H); ctx.lineTo(off * step, H); ctx.closePath();
            const grad = ctx.createLinearGradient(0, 0, 0, H);
            grad.addColorStop(0, color + '44'); grad.addColorStop(1, color + '00');
            ctx.fillStyle = grad; ctx.fill();
        }
    };
    // grid
    ctx.strokeStyle = 'rgba(255,255,255,.05)'; ctx.lineWidth = 1;
    for (let y = 1; y < 4; y++) {
        ctx.beginPath(); ctx.moveTo(0, H * y / 4); ctx.lineTo(W, H * y / 4); ctx.stroke();
    }
    drawLine(series.cpu, '#00D9FF', true);
    drawLine(series.ram, '#00FF41', true);
}

/*──────── Profile chip ────────*/
async function refreshProfileChip() {
    try {
        const s = await api.get('/settings');
        const chip = document.getElementById('hdr-profile');
        chip.textContent = `● ${s.active_profile || 'default'}`;
    } catch {}
}

/*──────── View loaders ────────*/
async function loadView(view) {
    try {
        switch (view) {
            case 'profiles': return loadProfiles();
            case 'themes': return loadThemes();
            case 'backups': return loadBackups();
            case 'snippets': return loadSnippets();
            case 'hotkeys': return loadHotkeys();
            case 'plugins': return loadPlugins();
            case 'settings': return loadSettings();
        }
    } catch (e) { toast(e.message, 'err'); }
}

/*──────── Profiles ────────*/
async function loadProfiles() {
    const [profiles, settings] = await Promise.all([api.get('/profiles'), api.get('/settings')]);
    const active = settings.active_profile || 'default';
    const box = document.getElementById('profiles-list');
    box.innerHTML = '';
    profiles.forEach((p) => {
        const el = document.createElement('article');
        el.className = 'card glass tile fade-in' + (p.id === active ? ' active-tile' : '');
        el.innerHTML = `
            ${p.id === active ? '<span class="badge-active">active</span>' : ''}
            <h3>${esc(p.name)}</h3>
            <p class="muted">theme: ${esc(p.theme || '?')} · shell: ${esc(p.shell || '?')}</p>
            <div class="btn-row">
                ${p.id !== active ? `<button class="btn primary" data-act="switch">Switch</button>` : ''}
                <button class="btn" data-act="dup">Duplicate</button>
                ${p.id !== 'default' ? `<button class="btn danger" data-act="del">Delete</button>` : ''}
            </div>`;
        el.addEventListener('click', async (e) => {
            const act = e.target.dataset.act; if (!act) return;
            try {
                if (act === 'switch') { await api.post(`/profiles/${p.id}/switch`); toast(`Switched to ${p.id}`); }
                if (act === 'dup') {
                    const name = prompt('Duplicate as:', p.id + '-copy');
                    if (!name) return;
                    const full = await api.get(`/profiles/${p.id}`);
                    full.name = name; await api.post('/profiles', full);
                }
                if (act === 'del' && confirm(`Delete profile "${p.id}"?`)) await api.del(`/profiles/${p.id}`);
                loadProfiles(); refreshProfileChip();
            } catch (err) { toast(err.message, 'err'); }
        });
        box.appendChild(el);
    });
}
document.getElementById('profile-create').addEventListener('click', async () => {
    const name = document.getElementById('profile-new').value.trim();
    if (!name) return toast('Enter a profile name', 'warn');
    try { await api.post('/profiles', { name }); toast(`Profile "${name}" created`); loadProfiles(); }
    catch (e) { toast(e.message, 'err'); }
});

/*──────── Themes ────────*/
async function loadThemes() {
    const [themes, settings] = await Promise.all([api.get('/themes'), api.get('/settings')]);
    const current = (settings.ui && settings.ui.theme) || 'dark';
    const box = document.getElementById('themes-list');
    box.innerHTML = '';
    themes.forEach((t) => {
        const el = document.createElement('article');
        el.className = 'card glass tile fade-in' + (t.id === current ? ' active-tile' : '');
        const sw = ['primary', 'secondary', 'accent', 'background']
            .map((k) => `<span class="swatch" style="background:${(t.colors && t.colors[k]) || '#333'}"></span>`).join('');
        el.innerHTML = `
            ${t.id === current ? '<span class="badge-active">current</span>' : ''}
            <h3>${esc(t.name)}${t.custom ? ' · custom' : ''}</h3>
            <div class="swatches">${sw}</div>
            <p class="muted">${esc((t.font && t.font.family) || '')} · ${esc(t.gradient || '')}</p>
            <div class="btn-row">
                <button class="btn primary" data-act="apply">Apply</button>
                ${t.custom ? `<button class="btn danger" data-act="del">Delete</button>` : ''}
            </div>`;
        el.addEventListener('click', async (e) => {
            const act = e.target.dataset.act; if (!act) return;
            try {
                if (act === 'apply') {
                    await api.put('/settings', { set: 'ui.theme', value: t.id });
                    toast(`Theme "${t.name}" applied`);
                    loadThemes();
                }
                if (act === 'del' && confirm(`Delete theme "${t.name}"?`)) {
                    await api.del(`/themes/${t.id}`); loadThemes();
                }
            } catch (err) { toast(err.message, 'err'); }
        });
        box.appendChild(el);
    });
}

/*──── Theme creator (live preview) ────*/
const tcFields = ['name', 'primary', 'secondary', 'accent', 'bg', 'font'];
function tcState() {
    return {
        name: document.getElementById('tc-name').value.trim() || 'my-theme',
        primary: document.getElementById('tc-primary').value,
        secondary: document.getElementById('tc-secondary').value,
        accent: document.getElementById('tc-accent').value,
        bg: document.getElementById('tc-bg').value,
        font: document.getElementById('tc-font').value
    };
}
function tcRender() {
    const s = tcState();
    const p = document.getElementById('tc-preview');
    p.style.background = s.bg;
    p.querySelector('.tp-user').style.color = s.primary;
    p.querySelector('.tp-prompt').style.color = s.secondary;
    p.querySelector('.tp-ok').style.color = s.accent;
    document.getElementById('tc-harmony').textContent =
        `harmony → complementary: ${complementary(s.primary)}`;
}
tcFields.forEach((id) => document.getElementById(`tc-${id}`).addEventListener('input', tcRender));
document.getElementById('tc-save').addEventListener('click', async () => {
    const s = tcState();
    try {
        await api.post('/themes', {
            name: s.name, author: 'web-dashboard',
            colors: { primary: s.primary, secondary: s.secondary, accent: s.accent,
                      background: s.bg, foreground: '#FFFFFF', warning: '#FFD700', danger: '#FF006E' },
            font: { family: s.font, size: 14 }, gradient: 'linear'
        });
        toast(`Theme "${s.name}" saved`);
        document.getElementById('tc-apply').disabled = false;
        loadThemes();
    } catch (e) { toast(e.message, 'err'); }
});
document.getElementById('tc-apply').addEventListener('click', async () => {
    const s = tcState();
    await api.put('/settings', { set: 'ui.theme', value: s.name });
    toast(`Theme "${s.name}" applied`); loadThemes();
});
document.getElementById('tc-copy').addEventListener('click', () => {
    const s = tcState();
    const code = `POS_PRIMARY="${s.primary}"\nPOS_SECONDARY="${s.secondary}"\nPOS_ACCENT="${s.accent}"\nPOS_BG="${s.bg}"`;
    navigator.clipboard?.writeText(code).then(() => toast('Theme code copied'));
});

/*──────── Backups ────────*/
async function loadBackups() {
    const backups = await api.get('/backups');
    const box = document.getElementById('backups-list');
    box.innerHTML = backups.length ? '' : '<p class="muted">No backups yet.</p>';
    backups.forEach((b) => {
        const el = document.createElement('div');
        el.className = 'list-item';
        el.innerHTML = `
            <div class="meta">
                <div class="title">${esc(b.file)}</div>
                <div class="sub">${(b.size / 1024).toFixed(1)} KB · ${new Date(b.mtime).toLocaleString()}</div>
            </div>
            <div class="btn-row">
                <button class="btn primary" data-act="restore">Restore</button>
            </div>`;
        el.querySelector('[data-act="restore"]').addEventListener('click', async () => {
            if (!confirm(`Restore ${b.file}? Current config becomes the rollback point.`)) return;
            try { await api.post('/restore', { file: b.file }); toast('Restored'); }
            catch (e) { toast(e.message, 'err'); }
        });
        box.appendChild(el);
    });
}
document.getElementById('backup-create').addEventListener('click', async (e) => {
    e.target.disabled = true;
    try { const r = await api.post('/backup', {}); toast(`Backup: ${r.file}`); loadBackups(); }
    catch (err) { toast(err.message, 'err'); }
    e.target.disabled = false;
});
document.getElementById('qa-backup').addEventListener('click',
    () => document.getElementById('backup-create').click());

/*──────── Snippets ────────*/
let snipCache = [];
async function loadSnippets() {
    snipCache = await api.get('/snippets');
    renderSnippets(snipCache);
}
function renderSnippets(list) {
    const box = document.getElementById('snippets-list');
    box.innerHTML = list.length ? '' : '<p class="muted">No snippets.</p>';
    list.forEach((s) => {
        const el = document.createElement('div');
        el.className = 'list-item';
        el.innerHTML = `
            <div class="meta">
                <div class="title">[${esc(s.category)}] ${esc(s.name)}</div>
                <div class="sub mono">$ ${esc(s.command)}</div>
            </div>
            <div class="btn-row">
                <button class="btn" data-act="copy">Copy</button>
                <button class="btn danger" data-act="del">Delete</button>
            </div>`;
        el.addEventListener('click', async (e) => {
            const act = e.target.dataset.act; if (!act) return;
            if (act === 'copy') {
                navigator.clipboard?.writeText(s.command).then(() => toast('Copied'));
            }
            if (act === 'del' && confirm(`Delete snippet "${s.name}"?`)) {
                await api.del(`/snippets/${s.id}`); loadSnippets();
            }
        });
        box.appendChild(el);
    });
}
document.getElementById('snip-search').addEventListener('input', (e) => {
    const q = e.target.value.toLowerCase();
    renderSnippets(snipCache.filter((s) =>
        s.name.toLowerCase().includes(q) || s.command.toLowerCase().includes(q)));
});
document.getElementById('snip-add').addEventListener('click', async () => {
    const cat = document.getElementById('snip-cat').value.trim() || 'General';
    const name = document.getElementById('snip-name').value.trim();
    const cmd = document.getElementById('snip-cmd').value.trim();
    if (!name || !cmd) return toast('Name and command required', 'warn');
    try {
        await api.post('/snippets', { category: cat, name, command: cmd });
        toast('Snippet added'); loadSnippets();
    } catch (e) { toast(e.message, 'err'); }
});

/*──────── Hotkeys ────────*/
async function loadHotkeys() {
    const list = await api.get('/hotkeys');
    const box = document.getElementById('hotkeys-list');
    box.innerHTML = list.length ? '' : '<p class="muted">No hotkeys bound.</p>';
    list.forEach((h) => {
        const el = document.createElement('div');
        el.className = 'list-item';
        el.innerHTML = `
            <div class="meta">
                <div class="title">${esc(h.key)}</div>
                <div class="sub mono">${esc(h.command)}</div>
            </div>
            <button class="btn danger">Remove</button>`;
        el.querySelector('.btn').addEventListener('click', async () => {
            await api.del(`/hotkeys/${encodeURIComponent(h.key)}`);
            loadHotkeys();
        });
        box.appendChild(el);
    });
}
document.getElementById('hk-add').addEventListener('click', async () => {
    const key = document.getElementById('hk-key').value.trim();
    const cmd = document.getElementById('hk-cmd').value.trim();
    if (!key || !cmd) return toast('Key and command required', 'warn');
    try { await api.post('/hotkeys', { key, command: cmd }); toast('Hotkey bound'); loadHotkeys(); }
    catch (e) { toast(e.message, 'err'); }
});

/*──────── Plugins ────────*/
async function loadPlugins() {
    const plugins = await api.get('/plugins');
    const box = document.getElementById('plugins-list');
    box.innerHTML = plugins.length ? '' : '<p class="muted">No plugins installed. Use the CLI: bash main.sh plugin install …</p>';
    plugins.forEach((p) => {
        const el = document.createElement('article');
        el.className = 'card glass tile fade-in';
        el.innerHTML = `
            <h3>${esc(p.name)} <span class="muted">v${esc(p.version)}</span></h3>
            <p class="muted">${esc(p.description)}</p>
            <div class="btn-row">
                <span class="stat-chip ${p.enabled ? '' : 'off'}">${p.enabled ? 'enabled' : 'disabled'}</span>
                <button class="btn danger">Uninstall</button>
            </div>`;
        el.querySelector('.btn').addEventListener('click', async () => {
            if (!confirm(`Uninstall "${p.name}"?`)) return;
            await api.del(`/plugins/${p.id}`); loadPlugins();
        });
        box.appendChild(el);
    });
}

/*──────── Settings ────────*/
async function loadSettings() {
    const s = await api.get('/settings');
    document.querySelectorAll('[data-setting]').forEach((sw) => {
        const pathParts = sw.dataset.setting.split('.');
        let cur = s;
        for (const k of pathParts) cur = cur ? cur[k] : undefined;
        sw.classList.toggle('on', cur === true);
    });
    const mb = document.getElementById('set-max-backups');
    mb.value = (s.backup && s.backup.max_backups) || 10;
}
document.querySelectorAll('[data-setting]').forEach((sw) => {
    sw.addEventListener('click', async () => {
        const next = !sw.classList.contains('on');
        try {
            await api.put('/settings', { set: sw.dataset.setting, value: next });
            sw.classList.toggle('on', next);
            toast('Setting saved');
        } catch (e) { toast(e.message, 'err'); }
    });
});
document.getElementById('set-max-backups').addEventListener('change', async (e) => {
    await api.put('/settings', { set: 'backup.max_backups', value: Number(e.target.value) });
    toast('Saved');
});

/*──────── Performance CSV ────────*/
document.getElementById('perf-csv').addEventListener('click', async () => {
    const rows = await api.get('/performance/history');
    const csv = 'epoch,cpu,ram\n' + rows.map((r) => `${r.epoch},${r.cpu},${r.ram}`).join('\n');
    const blob = new Blob([csv], { type: 'text/csv' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = `perf-history-${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(a.href);
});

/*──────── Misc UI ────────*/
document.getElementById('theme-toggle').addEventListener('click', () => {
    const html = document.documentElement;
    const cur = html.dataset.theme === 'light' ? '' : 'light';
    html.dataset.theme = cur;
    localStorage.setItem('pos-theme', cur);
});
document.documentElement.dataset.theme = localStorage.getItem('pos-theme') || '';

const scrollBtn = document.getElementById('scroll-top');
window.addEventListener('scroll', () => scrollBtn.classList.toggle('show', scrollY > 400));
scrollBtn.addEventListener('click', () => scrollTo({ top: 0, behavior: 'smooth' }));

/*──────── Helpers ────────*/
function esc(s) {
    return String(s ?? '').replace(/[&<>"']/g, (c) =>
        ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

/*──────── Init ────────*/
(async function init() {
    tcRender();
    refreshProfileChip();
    connectWS();
    try {
        const h = await api.get('/health');
        const v = document.getElementById('hdr-version');
        if (v && h.version) v.textContent = 'v' + h.version;
    } catch {}
    // PWA (best-effort)
    if ('serviceWorker' in navigator && location.protocol !== 'file:') {
        navigator.serviceWorker.register('/sw.js').catch(() => {});
    }
})();
