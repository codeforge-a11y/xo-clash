const { WebSocketServer } = require('ws');
const http = require('http');

// ════════════════════════════════════════════════════════════════
// HTTP SERVER (for Render health check + cold start wake)
// ════════════════════════════════════════════════════════════════
const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({
    status: 'ok',
    activeSessions: Object.keys(sessions).length,
    uptime: Math.floor(process.uptime()),
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

// Generate unique 6-char code
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

// Safe send — only sends if socket is open
function safeSend(ws, data) {
  if (ws && ws.readyState === 1) {
    try {
      ws.send(JSON.stringify(data));
    } catch (err) {
      console.error('[safeSend] Error:', err.message);
    }
  }
}

// Remove session and clear its timer
function removeSession(code, reason) {
  if (!sessions[code]) return;
  clearTimeout(sessions[code].timer);
  delete sessions[code];
  console.log(`[${code}] Session removed — ${reason}`);
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

  // ── MESSAGE ──────────────────────────────────────────────────
  ws.on('message', (raw) => {
    let data;

    try {
      data = JSON.parse(raw.toString());
    } catch {
      console.error('[WS] Invalid JSON:', raw);
      return;
    }

    console.log(`[${playerCode ?? 'NEW'}] type=${data.type}`);

    // ── CREATE ───────────────────────────────────────────────
    if (data.type === 'create') {

      // Clean up any previous session this socket owned
      if (playerCode && sessions[playerCode]) {
        removeSession(playerCode, 'host created new session');
      }

      const code = generateCode();
      playerCode = code;
      playerRole = 'host';

      // Auto-expire lobby after 10 minutes if no guest joins
      const timer = setTimeout(() => {
        if (sessions[code] && !sessions[code].guest) {
          safeSend(sessions[code].host, {
            type: 'error',
            message: 'Session expired. No one joined in time.',
          });
          removeSession(code, 'lobby timeout');
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

      console.log(`[${code}] Created by "${data.playerName}"`);
    }

    // ── JOIN ─────────────────────────────────────────────────
    else if (data.type === 'join') {
      const code = (data.code ?? '').toUpperCase().trim();
      const session = sessions[code];

      if (!session) {
        safeSend(ws, {
          type: 'error',
          message: `Invalid code! No game found for "${code}".`,
        });
        return;
      }

      if (session.guest) {
        safeSend(ws, {
          type: 'error',
          message: 'Game is already full!',
        });
        return;
      }

      if (!session.host || session.host.readyState !== 1) {
        safeSend(ws, {
          type: 'error',
          message: 'Host has disconnected.',
        });
        removeSession(code, 'host disconnected before guest joined');
        return;
      }

      playerCode = code;
      playerRole = 'guest';

      session.guest = ws;
      session.guestName = data.playerName ?? 'Player 2';

      // Stop the lobby expiry timer since guest joined
      clearTimeout(session.timer);

      // Tell guest they joined successfully
      safeSend(ws, {
        type: 'joined',
        code,
        hostName: session.hostName,
        guestName: session.guestName,
      });

      // Tell host that guest joined — game can start
      safeSend(session.host, {
        type: 'start',
        hostName: session.hostName,
        guestName: session.guestName,
      });

      console.log(`[${code}] "${data.playerName}" joined`);
    }

    // ── MOVE ─────────────────────────────────────────────────
    else if (data.type === 'move') {
      const session = sessions[playerCode];
      if (!session) return;

      const opponent = playerRole === 'host' ? session.guest : session.host;

      if (opponent) {
        safeSend(opponent, {
          type: 'move',
          index: data.index,
        });
      }
    }

    // ── EMOJI ────────────────────────────────────────────────
    else if (data.type === 'emoji') {
      const session = sessions[playerCode];
      if (!session) return;

      const players = [session.host, session.guest];

      players.forEach(player => {
        if (player) {
          safeSend(player, {
            type: 'emoji',
            emoji: data.emoji,
            sender: playerRole, // IMPORTANT
          });
        }
      });
    }

    // ── NAME UPDATE ──────────────────────────────────────────
    else if (data.type === 'name_update') {
      const session = sessions[playerCode];
      if (!session) return;

      const opponent = playerRole === 'host' ? session.guest : session.host;

      // Update stored name in session
      if (playerRole === 'host') {
        session.hostName = data.name ?? session.hostName;
      } else {
        session.guestName = data.name ?? session.guestName;
      }

      // Forward to opponent so their UI updates live
      if (opponent) {
        safeSend(opponent, {
          type: 'name_update',
          player: data.player,
          name: data.name,
        });
      }
    }

    // ── REMATCH ──────────────────────────────────────────────
    else if (data.type === 'rematch') {
      const session = sessions[playerCode];
      if (!session) return;

      const opponent = playerRole === 'host' ? session.guest : session.host;

      if (opponent) {
        safeSend(opponent, { type: 'rematch' });
      }
    }

    // ── REMATCH ACCEPTED ─────────────────────────────────────
    else if (data.type === 'rematch_accepted') {
      const session = sessions[playerCode];
      if (!session) return;

      const opponent = playerRole === 'host' ? session.guest : session.host;

      if (opponent) {
        safeSend(opponent, { type: 'rematch_accepted' });
      }
    }

    // ── PING ─────────────────────────────────────────────────
    else if (data.type === 'ping') {
      safeSend(ws, { type: 'pong' });
    }

    // ── UNKNOWN ──────────────────────────────────────────────
    else {
      console.warn(`[${playerCode ?? 'NEW'}] Unknown message type: "${data.type}"`);
    }
  });

  // ── CLOSE ────────────────────────────────────────────────────
  ws.on('close', () => {
    console.log(`[${playerCode ?? 'UNKNOWN'}] Connection closed`);

    if (!playerCode || !sessions[playerCode]) return;

    const session = sessions[playerCode];
    const opponent = playerRole === 'host' ? session.guest : session.host;

    // Notify opponent that the other player left
    if (opponent) {
      safeSend(opponent, { type: 'opponent_left' });
    }

    // If host leaves before anyone joined, clean up immediately
    if (playerRole === 'host' && !session.guest) {
      removeSession(playerCode, 'host left before guest joined');
      return;
    }

    removeSession(playerCode, 'player disconnected');
  });

  // ── ERROR ────────────────────────────────────────────────────
  ws.on('error', (err) => {
    console.error(`[${playerCode ?? 'UNKNOWN'}] Socket error: ${err.message}`);
  });
});

// ════════════════════════════════════════════════════════════════
// GLOBAL PING — detect and terminate dead clients every 30s
// ════════════════════════════════════════════════════════════════
const pingInterval = setInterval(() => {
  wss.clients.forEach((ws) => {
    if (!ws.isAlive) {
      console.log('[WS] Terminating dead client');
      return ws.terminate();
    }
    ws.isAlive = false;
    ws.ping();
  });
}, 30000);

wss.on('close', () => {
  clearInterval(pingInterval);
});

// ════════════════════════════════════════════════════════════════
// START SERVER
// ════════════════════════════════════════════════════════════════
const PORT = process.env.PORT || 3000;

server.listen(PORT, '0.0.0.0', () => {
  console.log(`[Server] Running on port ${PORT}`);
  console.log(`[Server] Started at ${new Date().toISOString()}`);
});