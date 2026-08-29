/*============================================================================
 * Premium-OS :: web/routes/websocket.js
 * Minimal RFC 6455 WebSocket implementation (text frames only) — zero deps.
 *
 * Events server → client (JSON):
 *   performance:update   every 2 seconds
 *   profile:switched / theme:applied / backup:created / system:optimized
 *   plugin:installed / update:available  (via REST-layer broadcast)
 *==========================================================================*/
'use strict';

const crypto = require('crypto');
const apiRouter = require('./api');

const WS_MAGIC = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
const clients = new Set();
let perfTimer = null;

//------------------------------------------------------------
// Handshake + frame codec
//------------------------------------------------------------
function accept(req, socket) {
    const key = req.headers['sec-websocket-key'];
    if (!key) return socket.destroy();
    const acceptKey = crypto.createHash('sha1')
        .update(key + WS_MAGIC).digest('base64');
    socket.write(
        'HTTP/1.1 101 Switching Protocols\r\n' +
        'Upgrade: websocket\r\n' +
        'Connection: Upgrade\r\n' +
        `Sec-WebSocket-Accept: ${acceptKey}\r\n\r\n`
    );
    socket.setNoDelay(true);

    const client = { socket, alive: true };
    clients.add(client);

    socket.on('data', (buf) => handleFrames(client, buf));
    socket.on('close', () => drop(client));
    socket.on('error', () => drop(client));

    sendTo(client, 'connected', { ok: true, clients: clients.size });
    ensurePerfLoop();
}

function drop(client) {
    client.alive = false;
    clients.delete(client);
    try { client.socket.destroy(); } catch {}
    if (clients.size === 0 && perfTimer) { clearInterval(perfTimer); perfTimer = null; }
}

//------------------------------------------------------------
// Frame parsing: supports continuation-less text/ping/pong/close,
// 7/16/64-bit lengths, masked client frames.
//------------------------------------------------------------
function handleFrames(client, buf) {
    let offset = 0;
    // buffer leftover partial frames per client
    if (client.pending) {
        buf = Buffer.concat([client.pending, buf]);
        client.pending = null;
    }
    while (offset + 2 <= buf.length) {
        const b0 = buf[offset], b1 = buf[offset + 1];
        const opcode = b0 & 0x0f;
        const masked = (b1 & 0x80) !== 0;
        let len = b1 & 0x7f;
        let header = 2;
        if (len === 126) {
            if (offset + 4 > buf.length) break;
            len = buf.readUInt16BE(offset + 2); header = 4;
        } else if (len === 127) {
            if (offset + 10 > buf.length) break;
            len = Number(buf.readBigUInt64BE(offset + 2)); header = 10;
        }
        const maskLen = masked ? 4 : 0;
        if (offset + header + maskLen + len > buf.length) break; // wait for more data
        let payload = buf.slice(offset + header + maskLen, offset + header + maskLen + len);
        if (masked) {
            const mask = buf.slice(offset + header, offset + header + 4);
            payload = Buffer.from(payload.map((b, i) => b ^ mask[i % 4]));
        }
        offset += header + maskLen + len;

        switch (opcode) {
            case 0x8: // close
                sendFrame(client.socket, Buffer.alloc(0), 0x8);
                return drop(client);
            case 0x9: // ping → pong
                sendFrame(client.socket, payload, 0xA);
                break;
            case 0xA: // pong
                break;
            case 0x1: // text — client controls
                try {
                    const msg = JSON.parse(payload.toString('utf8'));
                    handleClientMessage(client, msg);
                } catch {}
                break;
        }
    }
    if (offset < buf.length) client.pending = buf.slice(offset);
}

function sendFrame(socket, payload, opcode = 0x1) {
    const len = payload.length;
    let header;
    if (len < 126) {
        header = Buffer.from([0x80 | opcode, len]);
    } else if (len < 65536) {
        header = Buffer.alloc(4);
        header[0] = 0x80 | opcode; header[1] = 126;
        header.writeUInt16BE(len, 2);
    } else {
        header = Buffer.alloc(10);
        header[0] = 0x80 | opcode; header[1] = 127;
        header.writeBigUInt64BE(BigInt(len), 2);
    }
    try { socket.write(Buffer.concat([header, payload])); } catch {}
}

//------------------------------------------------------------
// Messaging
//------------------------------------------------------------
function sendTo(client, event, data) {
    if (!client.alive) return;
    sendFrame(client.socket, Buffer.from(JSON.stringify({ event, data })), 0x1);
}

function broadcast(event, data) {
    for (const c of clients) sendTo(c, event, data);
}

function handleClientMessage(client, msg) {
    if (msg && msg.type === 'ping') sendTo(client, 'pong', { t: Date.now() });
    if (msg && msg.type === 'subscribe' && msg.channel === 'performance') {
        sendTo(client, 'performance:update', apiRouter.readPerf());
    }
}

//------------------------------------------------------------
// performance:update broadcaster — every 2s while clients present
//------------------------------------------------------------
function ensurePerfLoop() {
    if (perfTimer) return;
    perfTimer = setInterval(() => {
        if (clients.size === 0) return;
        let perf = apiRouter.readPerf();
        if (perf.cpu === null) {
            // keep history-friendly: skip until second sample exists
            perf = Object.assign({}, perf, { cpu: 0 });
        }
        broadcast('performance:update', perf);
    }, 2000);
    perfTimer.unref();
}

// Wire REST-layer events → WebSocket clients
apiRouter.setBroadcaster(broadcast);

module.exports = { accept, broadcast };
