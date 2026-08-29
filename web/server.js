#!/usr/bin/env node
/*============================================================================
 * Premium-OS :: web/server.js
 * Zero-dependency dashboard server (Node.js built-ins only).
 *   - Serves static files from public/
 *   - REST API at /api/*            (routes/api.js)
 *   - WebSocket at /ws              (routes/websocket.js)
 *
 * Zero deps = light setup mode: works on Termux with just `pkg install nodejs`.
 * package.json lists optionalDeps for reference; none are required.
 *==========================================================================*/
'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const url = require('url');

const apiRouter = require('./routes/api');
const wsHandler = require('./routes/websocket');

const PORT = parseInt(process.env.PORT || '8080', 10);
const HOST = process.env.HOST || '0.0.0.0';
const PUBLIC_DIR = path.join(__dirname, 'public');

const MIME = {
    '.html': 'text/html; charset=utf-8',
    '.css': 'text/css; charset=utf-8',
    '.js': 'text/javascript; charset=utf-8',
    '.json': 'application/json; charset=utf-8',
    '.svg': 'image/svg+xml',
    '.png': 'image/png',
    '.ico': 'image/x-icon',
    '.webmanifest': 'application/manifest+json'
};

//------------------------------------------------------------
// Static file serving (with path-traversal protection)
//------------------------------------------------------------
function serveStatic(req, res, pathname) {
    let rel = decodeURIComponent(pathname);
    if (rel === '/' || rel === '') rel = '/index.html';
    const filePath = path.normalize(path.join(PUBLIC_DIR, rel));
    if (!filePath.startsWith(PUBLIC_DIR)) {
        res.writeHead(403, { 'Content-Type': 'text/plain' });
        return res.end('Forbidden');
    }
    fs.readFile(filePath, (err, data) => {
        if (err) {
            // SPA fallback: unknown non-file paths get index.html
            if (!path.extname(rel)) {
                return fs.readFile(path.join(PUBLIC_DIR, 'index.html'), (e2, html) => {
                    if (e2) { res.writeHead(404); return res.end('Not found'); }
                    res.writeHead(200, { 'Content-Type': MIME['.html'] });
                    res.end(html);
                });
            }
            res.writeHead(404, { 'Content-Type': 'text/plain' });
            return res.end('404 Not Found');
        }
        const ext = path.extname(filePath).toLowerCase();
        res.writeHead(200, {
            'Content-Type': MIME[ext] || 'application/octet-stream',
            'Cache-Control': ext === '.html' ? 'no-cache' : 'max-age=300'
        });
        res.end(data);
    });
}

//------------------------------------------------------------
// HTTP request entry
//------------------------------------------------------------
const server = http.createServer((req, res) => {
    const parsed = url.parse(req.url, true);
    const pathname = parsed.pathname;

    // Lightweight CORS for same-device tooling (no credentials used)
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,DELETE,OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
    if (req.method === 'OPTIONS') { res.writeHead(204); return res.end(); }

    if (pathname.startsWith('/api/')) {
        return apiRouter(req, res, parsed);
    }
    serveStatic(req, res, pathname);
});

//------------------------------------------------------------
// WebSocket upgrade
//------------------------------------------------------------
server.on('upgrade', (req, socket, head) => {
    if (req.url === '/ws' || req.url.startsWith('/ws?')) {
        wsHandler.accept(req, socket, head);
    } else {
        socket.destroy();
    }
});

//------------------------------------------------------------
// Error page helpers (500)
//------------------------------------------------------------
process.on('uncaughtException', (err) => {
    console.error('[pos-web] uncaught:', err.message);
});

server.listen(PORT, HOST, () => {
    console.log(`◢◤ Premium-OS dashboard → http://localhost:${PORT}`);
    console.log(`   serving ${PUBLIC_DIR}`);
    console.log(`   data dir ${apiRouter.POS_HOME}`);
});

module.exports = server;
