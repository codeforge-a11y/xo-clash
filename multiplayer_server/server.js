const WebSocket = require('ws');
const http = require('http');

// ════════════════════════════════════════════════════════════════
// HTTP SERVER (required for Render)
// ════════════════════════════════════════════════════════════════
const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end('Tic Tac Toe Server Running ✓');
});

// ════════════════════════════════════════════════════════════════
// WEBSOCKET SERVER
// ════════════════════════════════════════════════════════════════
const wss = new WebSocket.Server({ server });

// Active sessions stored in memory
// { code: { host, hostName, guest, guestName, timer } }
const sessions = {};

// ════════════════════════════════════════════════════════════════
// HELPERS
// ════════════════════════════════════════════════════════════════

// Generate unique 6-char code
function generateCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let code = '';
  let attempts = 0;
  do {
    code = '';
    for (let i = 0; i < 6; i++) {
      code += chars[Math.floor(Math.random() * chars.length)];
    }
    attempts++;
    // Safety: if somehow all codes taken, expand length
    if (attempts > 100) {
      console.warn('Too many collisions, something is wrong');
      break;
    }
  } while (sessions[code]); // regenerate if code already exists
  return code;
}

// Safe send — only sends if socket is open
function safeSend(ws, data) {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(data));
  }
}

// Remove session cleanly
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
  console.log('New connection');

  let playerCode = null;
  let playerRole = null; // 'host' or 'guest'

  // ── PING/PONG keep-alive ────────────────────
  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });

  // ── MESSAGE HANDLER ─────────────────────────
  ws.on('message', (raw) => {
    let data;
    try {
      data = JSON.parse(raw);
    } catch (e) {
      console.error('Invalid JSON:', raw);
      return;
    }

    console.log(`[${playerCode ?? 'NEW'}] Message: ${data.type}`);

    // ── CREATE GAME ────────────────────────────
    if (data.type === 'create') {
      const code = generateCode();
      playerCode = code;
      playerRole = 'host';

      // Auto-expire session after 10 minutes if no guest joins
      const timer = setTimeout(() => {
        if (sessions[code] && !sessions[code].guest) {
          safeSend(sessions[code].host, {
            type: 'error',
            message: 'Session expired. No one joined in 10 minutes.',
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

      safeSend(ws, {
        type: 'created',
        code,
      });

      console.log(`[${code}] Created by ${data.playerName}`);
    }

    // ── JOIN GAME ──────────────────────────────
    else if (data.type === 'join') {
      const code = (data.code ?? '').toUpperCase().trim();
      const session = sessions[code];

      // Validate code exists
      if (!session) {
        safeSend(ws, {
          type: 'error',
          message: 'Invalid code! No game found for "$code".',
        });
        return;
      }

      // Validate not already full
      if (session.guest) {
        safeSend(ws, {
          type: 'error',
          message: 'This game is already full!',
        });
        return;
      }

      // Validate host still connected
      if (!session.host || session.host.readyState !== WebSocket.OPEN) {
        safeSend(ws, {
          type: 'error',
          message: 'Host disconnected. Game no longer available.',
        });
        removeSession(code, 'host disconnected before join');
        return;
      }

      // All good — join session
      playerCode = code;
      playerRole = 'guest';
      session.guest = ws;
      session.guestName = data.playerName ?? 'Player 2';

      // Cancel auto-expire timer since guest joined
      clearTimeout(session.timer);

      // Tell GUEST — joined successfully
      safeSend(ws, {
        type: 'joined',
        code,
        hostName: session.hostName,
        guestName: session.guestName,
      });

      // Tell HOST — guest joined, start game
      safeSend(session.host, {
        type: 'start',
        hostName: session.hostName,
        guestName: session.guestName,
      });

      console.log(`[${code}] ${data.playerName} joined ${session.hostName}'s game`);
    }

    // ── GAME MOVE ──────────────────────────────
    else if (data.type === 'move') {
      const session = sessions[playerCode];
      if (!session) return;

      const opponent = playerRole === 'host' ? session.guest : session.host;
      safeSend(opponent, {
        type: 'move',
        index: data.index,
      });
    }

    // ── REMATCH REQUEST ────────────────────────
    else if (data.type === 'rematch') {
      const session = sessions[playerCode];
      if (!session) return;

      const opponent = playerRole === 'host' ? session.guest : session.host;
      safeSend(opponent, { type: 'rematch' });
    }

    // ── PING (keep alive from client) ──────────
    else if (data.type === 'ping') {
      safeSend(ws, { type: 'pong' });
    }
  });

  // ── DISCONNECT HANDLER ───────────────────────
  ws.on('close', () => {
    console.log(`[${playerCode ?? 'UNKNOWN'}] Disconnected (${playerRole})`);
    if (!playerCode || !sessions[playerCode]) return;

    const session = sessions[playerCode];
    const opponent = playerRole === 'host' ? session.guest : session.host;

    // Notify opponent
    safeSend(opponent, {
      type: 'opponent_left',
      message: 'Your opponent disconnected.',
    });

    // Clean up session
    removeSession(playerCode, `${playerRole} disconnected`);
  });

  // ── ERROR HANDLER ────────────────────────────
  ws.on('error', (err) => {
    console.error(`[${playerCode ?? 'UNKNOWN'}] Error:`, err.message);
  });
});

// ════════════════════════════════════════════════════════════════
// PING ALL CLIENTS EVERY 30s — detect dead connections
// ════════════════════════════════════════════════════════════════
const pingInterval = setInterval(() => {
  wss.clients.forEach((ws) => {
    if (!ws.isAlive) {
      ws.terminate();
      return;
    }
    ws.isAlive = false;
    ws.ping();
  });
}, 30000);

wss.on('close', () => clearInterval(pingInterval));

// ════════════════════════════════════════════════════════════════
// START SERVER
// ════════════════════════════════════════════════════════════════
const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`Tic Tac Toe server running on port ${PORT}`);
  console.log(`WebSocket ready at ws://localhost:${PORT}`);
});