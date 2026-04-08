const { WebSocketServer } = require('ws');
const http = require('http');

// ════════════════════════════════════════════════════════════════
// HTTP SERVER (for Render health check)
// ════════════════════════════════════════════════════════════════
const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({
    status: 'ok',
    activeSessions: Object.keys(sessions).length,
  }));
});

// ════════════════════════════════════════════════════════════════
// WEBSOCKET SERVER
// ════════════════════════════════════════════════════════════════
const wss = new WebSocketServer({ server });

// Active sessions
const sessions = {};

// ════════════════════════════════════════════════════════════════
// HELPERS
// ════════════════════════════════════════════════════════════════

// Generate unique code
function generateCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let code;
  let attempts = 0;

  do {
    code = '';
    for (let i = 0; i < 6; i++) {
      code += chars[Math.floor(Math.random() * chars.length)];
    }
    attempts++;
    if (attempts > 100) break;
  } while (sessions[code]);

  return code;
}

// Safe send
function safeSend(ws, data) {
  if (ws && ws.readyState === 1) {
    ws.send(JSON.stringify(data));
  }
}

// Remove session
function removeSession(code, reason) {
  if (!sessions[code]) return;
  clearTimeout(sessions[code].timer);
  delete sessions[code];
  console.log(`[${code}] Removed — ${reason}`);
}

// ════════════════════════════════════════════════════════════════
// CONNECTION HANDLER
// ════════════════════════════════════════════════════════════════
wss.on('connection', (ws) => {
  console.log(`[WS] New connection at ${new Date().toISOString()}`);

  let playerCode = null;
  let playerRole = null;

  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });

  // ── MESSAGE ────────────────────────────────
  ws.on('message', (raw) => {
    let data;

    try {
      data = JSON.parse(raw.toString()); // ✅ FIXED
    } catch {
      console.error('Invalid JSON:', raw);
      return;
    }

    console.log(`[${playerCode ?? 'NEW'}] ${data.type}`);

    // ── CREATE ───────────────────────────────
    if (data.type === 'create') {
      const code = generateCode();

      playerCode = code;
      playerRole = 'host';

      const timer = setTimeout(() => {
        if (sessions[code] && !sessions[code].guest) {
          safeSend(sessions[code].host, {
            type: 'error',
            message: 'Session expired. No one joined.',
          });
          removeSession(code, 'expired');
        }
      }, 10 * 60 * 1000);

      sessions[code] = {
        host: ws,
        hostName: data.playerName ?? 'Player 1',
        guest: null,
        guestName: null,
        timer,
      };

      safeSend(ws, { type: 'created', code });

      console.log(`[${code}] Created by ${data.playerName}`);
    }

    // ── JOIN ────────────────────────────────
    else if (data.type === 'join') {
      const code = (data.code ?? '').toUpperCase().trim();
      const session = sessions[code];

      if (!session) {
        safeSend(ws, {
          type: 'error',
          message: `Invalid code! No game found for "${code}".`, // ✅ FIXED
        });
        return;
      }

      if (session.guest) {
        safeSend(ws, {
          type: 'error',
          message: 'Game already full!',
        });
        return;
      }

      if (!session.host || session.host.readyState !== 1) {
        safeSend(ws, {
          type: 'error',
          message: 'Host disconnected.',
        });
        removeSession(code, 'host disconnected');
        return;
      }

      playerCode = code;
      playerRole = 'guest';

      session.guest = ws;
      session.guestName = data.playerName ?? 'Player 2';

      clearTimeout(session.timer);

      safeSend(ws, {
        type: 'joined',
        code,
        hostName: session.hostName,
        guestName: session.guestName,
      });

      safeSend(session.host, {
        type: 'start',
        hostName: session.hostName,
        guestName: session.guestName,
      });

      console.log(`[${code}] ${data.playerName} joined`);
    }

    // ── MOVE ────────────────────────────────
    else if (data.type === 'move') {
      const session = sessions[playerCode];
      if (!session) return;

      const opponent =
        playerRole === 'host' ? session.guest : session.host;

      if (opponent) {
        safeSend(opponent, {
          type: 'move',
          index: data.index,
        });
      }
    }

    // ── REMATCH ─────────────────────────────
    else if (data.type === 'rematch') {
      const session = sessions[playerCode];
      if (!session) return;

      const opponent =
        playerRole === 'host' ? session.guest : session.host;

      if (opponent) {
        safeSend(opponent, { type: 'rematch' });
      }
    }

    // ── PING ────────────────────────────────
    else if (data.type === 'ping') {
      safeSend(ws, { type: 'pong' });
    }
  });

  // ── CLOSE ────────────────────────────────
  ws.on('close', () => {
    console.log(`[${playerCode ?? 'UNKNOWN'}] Disconnected`);

    if (!playerCode || !sessions[playerCode]) return;

    const session = sessions[playerCode];
    const opponent =
      playerRole === 'host' ? session.guest : session.host;

    if (opponent) {
      safeSend(opponent, {
        type: 'opponent_left',
      });
    }

    removeSession(playerCode, 'disconnect');
  });

  ws.on('error', (err) => {
    console.error(`[WS] Error: ${err.message}`);
  });
});

// ════════════════════════════════════════════════════════════════
// GLOBAL PING (detect dead clients)
// ════════════════════════════════════════════════════════════════
const interval = setInterval(() => {
  wss.clients.forEach((ws) => {
    if (!ws.isAlive) return ws.terminate();

    ws.isAlive = false;
    ws.ping();
  });
}, 30000);

wss.on('close', () => clearInterval(interval));

// ════════════════════════════════════════════════════════════════
// START SERVER
// ════════════════════════════════════════════════════════════════
const PORT = process.env.PORT || 3000;

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running on port ${PORT}`);
});