const { WebSocketServer } = require('ws');
const http = require('http');

// ════════════════════════════════════════════════════════════════
// HTTP SERVER — Render health check + cold start wake
// ════════════════════════════════════════════════════════════════
const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({
    status: 'ok',
    activeSessions: Object.keys(sessions).length,
    uptime: Math.floor(process.uptime()),
  }));
});

const wss = new WebSocketServer({ server });
const sessions = {};

// ════════════════════════════════════════════════════════════════
// HELPERS
// ════════════════════════════════════════════════════════════════

function generateCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let code, attempts = 0;
  do {
    code = Array.from({ length: 6 }, () =>
      chars[Math.floor(Math.random() * chars.length)]).join('');
    attempts++;
    if (attempts > 100) break;
  } while (sessions[code]);
  return code;
}

function safeSend(ws, data) {
  if (ws && ws.readyState === 1) {
    try {
      ws.send(JSON.stringify(data));
    } catch (err) {
      console.error('[safeSend] Error:', err.message);
    }
  }
}

function forwardToOpponent(playerCode, playerRole, payload) {
  const session = sessions[playerCode];
  if (!session) {
    console.warn(`[${playerCode}] forwardToOpponent: no session`);
    return false;
  }
  const opponent = playerRole === 'host' ? session.guest : session.host;
  if (!opponent) {
    console.warn(`[${playerCode}] forwardToOpponent: opponent not connected`);
    return false;
  }
  safeSend(opponent, payload);
  return true;
}

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
  console.log(`[WS] New connection — ${new Date().toISOString()}`);

  let playerCode = null;
  let playerRole = null;

  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });

  ws.on('message', (raw) => {
    let data;
    try {
      data = JSON.parse(raw.toString());
    } catch {
      console.error('[WS] Invalid JSON');
      return;
    }

    console.log(`[${playerCode ?? 'NEW'}] type=${data.type}`);

    // ── CREATE ───────────────────────────────────────────────
    if (data.type === 'create') {
      if (playerCode && sessions[playerCode]) {
        removeSession(playerCode, 'host created new session');
      }
      const code = generateCode();
      playerCode = code;
      playerRole = 'host';

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
        return safeSend(ws, { type: 'error', message: `No game for "${code}".` });
      }
      if (session.guest) {
        return safeSend(ws, { type: 'error', message: 'Game is already full.' });
      }
      if (!session.host || session.host.readyState !== 1) {
        removeSession(code, 'host gone before guest joined');
        return safeSend(ws, { type: 'error', message: 'Host disconnected.' });
      }

      playerCode = code;
      playerRole = 'guest';
      session.guest = ws;
      session.guestName = data.playerName ?? 'Player 2';
      clearTimeout(session.timer);

      safeSend(ws, {
        type: 'joined', code,
        hostName: session.hostName,
        guestName: session.guestName,
      });
      safeSend(session.host, {
        type: 'start',
        hostName: session.hostName,
        guestName: session.guestName,
      });

      console.log(`[${code}] "${data.playerName}" joined`);
    }

    // ── MOVE ─────────────────────────────────────────────────
    else if (data.type === 'move') {
      forwardToOpponent(playerCode, playerRole, {
        type: 'move',
        index: data.index,
      });
    }

    // ── EMOJI ─────────────────────────────────────────────────
    // Accepts {type:'emoji', emoji:'😂'}
    // Also accepts {type:'message', messageType:'emoji', content:'😂'}
    // Always forwards as {type:'emoji', emoji:'...'} — one schema, no confusion
    else if (data.type === 'emoji') {
      const emoji = data.emoji ?? data.content ?? '👏';
      const ok = forwardToOpponent(playerCode, playerRole, {
        type: 'emoji',
        emoji,
      });
      console.log(`[${playerCode}] emoji="${emoji}" forwarded=${ok}`);
    }

    // ── UNIFIED MESSAGE (handles messageType routing) ─────────
    else if (data.type === 'message') {
      if (data.messageType === 'emoji') {
        forwardToOpponent(playerCode, playerRole, {
          type: 'emoji',
          emoji: data.content ?? '👏',
        });
      } else {
        forwardToOpponent(playerCode, playerRole, {
          type: 'message',
          messageType: 'text',
          content: data.content ?? '',
          sender: data.sender ?? playerRole,
        });
      }
    }

    // ── NAME UPDATE ──────────────────────────────────────────
    else if (data.type === 'name_update') {
      const session = sessions[playerCode];
      if (!session) return;
      if (playerRole === 'host') {
        session.hostName = data.name ?? session.hostName;
      } else {
        session.guestName = data.name ?? session.guestName;
      }
      forwardToOpponent(playerCode, playerRole, {
        type: 'name_update',
        player: data.player,
        name: data.name,
      });
    }

    // ── PING ─────────────────────────────────────────────────
    else if (data.type === 'ping') {
      safeSend(ws, { type: 'pong' });
    }

    // ── UNKNOWN ──────────────────────────────────────────────
    else {
      console.warn(`[${playerCode ?? 'NEW'}] Unknown type: "${data.type}"`);
    }
  });

  // ── CLOSE ────────────────────────────────────────────────────
  ws.on('close', () => {
    console.log(`[${playerCode ?? 'UNKNOWN'}] Disconnected`);
    if (!playerCode || !sessions[playerCode]) return;

    const session = sessions[playerCode];
    const opponent = playerRole === 'host' ? session.guest : session.host;
    if (opponent) safeSend(opponent, { type: 'opponent_left' });

    if (playerRole === 'host' && !session.guest) {
      removeSession(playerCode, 'host left before guest joined');
      return;
    }
    removeSession(playerCode, 'player disconnected');
  });

  ws.on('error', (err) => {
    console.error(`[${playerCode ?? 'UNKNOWN'}] Error: ${err.message}`);
  });
});

// ════════════════════════════════════════════════════════════════
// HEARTBEAT — kill dead sockets every 30s
// ════════════════════════════════════════════════════════════════
const pingInterval = setInterval(() => {
  wss.clients.forEach((ws) => {
    if (!ws.isAlive) return ws.terminate();
    ws.isAlive = false;
    ws.ping();
  });
}, 30000);

wss.on('close', () => clearInterval(pingInterval));

// ════════════════════════════════════════════════════════════════
// START
// ════════════════════════════════════════════════════════════════
const PORT = process.env.PORT || 3000;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`[Server] Running on port ${PORT}`);
  console.log(`[Server] Started at ${new Date().toISOString()}`);
});